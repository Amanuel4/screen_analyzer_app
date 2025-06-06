import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // For ui.Image for the overlay

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import 'services/analysis_service.dart'; // Your analysis service
import 'widgets/drawing_overlay.dart'; // Your drawing overlay widget

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI Screen Assistant',
        theme: ThemeData(
          primarySwatch: Colors.green, // Primary green color
          scaffoldBackgroundColor: Colors.grey[100],
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const AnalyzerHomePage(),
      ),
    );
  }
}

class AnalyzerHomePage extends StatefulWidget {
  const AnalyzerHomePage({super.key});

  @override
  State<AnalyzerHomePage> createState() => _AnalyzerHomePageState();
}

class _AnalyzerHomePageState extends State<AnalyzerHomePage> {
  final AnalysisService _analysisService = AnalysisService();
  String _chatInputText = "";
  String _aiResponseText =
      "Welcome! How can I help you with your screen today?";
  bool _isProcessing = false; // For loading indicators

  // For image/screen display
  Image? _currentDisplayImage; // Holds either camera frame or screenshot
  ui.Image? _uiImageForOverlay; // For CustomPainter
  Size _displayedImageSize = const Size(300, 200); // Default or actual
  List<DetectedObject> _detectedObjectsForOverlay = [];

  // Screen Capture Simulation (using image_picker)
  final ImagePicker _picker = ImagePicker();
  Uint8List? _lastImageBytes;

  // Speech to Text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _sttText = '';

  // Text to Speech
  late FlutterTts _flutterTts;

  @override
  void initState() {
    super.initState();
    _initSpeechToText();
    _initTextToSpeech();
  }

  void _initSpeechToText() async {
    _speech = stt.SpeechToText();
    // Request microphone permission early
    await Permission.microphone.request();
  }

  void _initTextToSpeech() {
    _flutterTts = FlutterTts();
    // Optional: Set language, pitch, rate
    _flutterTts.setLanguage("en-US");
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          print('STT status: $val');
          if (val == 'notListening' || val == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (val) {
          print('STT error: $val');
          if (mounted) {
            setState(() => _isListening = false);
            _updateAiResponse("Speech recognition error. Please try typing.");
          }
        },
      );
      if (available) {
        if (mounted) setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _sttText = val.recognizedWords;
            if (val.finalResult) {
              _chatInputText = _sttText;
              _sendChatInput(); // Send recognized text
            }
          }),
          listenFor: const Duration(seconds: 10), // Adjust listening duration
          pauseFor: const Duration(seconds: 3), // Pause after speech ends
        );
      } else {
        if (mounted) setState(() => _isListening = false);
        _updateAiResponse("Speech recognition not available on this device.");
      }
    } else {
      if (mounted) setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // Combined handler for both simulated screen capture and screenshot upload
  Future<void> _captureOrPickScreen(ImageSource source, String taskKey) async {
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _aiResponseText = (source == ImageSource.camera)
          ? "Attempting to capture screen (simulated)..."
          : "Please select a screenshot...";
      _currentDisplayImage = null;
      _uiImageForOverlay = null;
      _detectedObjectsForOverlay = [];
    });

    XFile? imageFile;
    if (source == ImageSource.camera) {
      // Simulate full screen capture by picking from gallery
      // In a real app with native code, this would be MediaProjection.
      // For this demo, we use image picker as a stand-in.
      imageFile = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
      if (imageFile != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text("Simulating full screen capture with selected image.")));
      }
    } else {
      // ImageSource.gallery
      imageFile = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70);
    }

    if (imageFile != null) {
      _lastImageBytes = await File(imageFile.path).readAsBytes();
      final decodedImage = await decodeImageFromList(_lastImageBytes!);

      if (mounted) {
        setState(() {
          _currentDisplayImage = Image.memory(_lastImageBytes!);
          _uiImageForOverlay = decodedImage; // For CustomPainter
          _displayedImageSize = Size(
              decodedImage.width.toDouble(), decodedImage.height.toDouble());
          _aiResponseText = "Image ready. Analyzing...";
        });
      }
      await _analyzeImageWithGemini(_lastImageBytes!, taskKey);
    } else {
      if (mounted) {
        setState(() {
          _aiResponseText = (source == ImageSource.camera)
              ? "Screen capture cancelled or failed."
              : "Screenshot selection cancelled.";
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _analyzeImageWithGemini(
      Uint8List imageBytes, String taskKeyOrCustomPrompt) async {
    String geminiTaskPrompt = "";
    // Construct prompt based on taskKeyOrCustomPrompt
    if (taskKeyOrCustomPrompt == "data_usage") {
      geminiTaskPrompt =
          "This is an image from a smartphone screen. User wants to understand data usage. Analyze to identify: 1. Total data used & period. 2. Top apps by usage. 3. Data limits/warnings. Summarize. If info isn't visible, state that clearly.";
    } else if (taskKeyOrCustomPrompt == "data_saver") {
      geminiTaskPrompt =
          "This is an image from a smartphone screen. User wants to find 'Data Saver' settings. 1. Is it visible? 2. ON/OFF? 3. Based ONLY on what's visible, suggest how to navigate/toggle. If not visible, suggest common locations.";
    } else if (taskKeyOrCustomPrompt == "generic_what_is_this") {
      geminiTaskPrompt =
          "This is an image from a smartphone screen. Describe main elements, likely app/page, and its primary purpose based on visual content.";
    } else {
      // Assume it's a custom prompt
      geminiTaskPrompt = taskKeyOrCustomPrompt;
    }

    final result = await _analysisService.analyzeScreenImage(
        imageBytes: imageBytes, taskPrompt: geminiTaskPrompt);

    if (!mounted) return;

    if (result['error'] != null) {
      _updateAiResponse("Analysis Error: ${result['error']}");
    } else if (result['analysis_text'] != null) {
      _updateAiResponse(result['analysis_text']);
      _parseAnalysisForDrawing(
          result['analysis_text']); // Try to find elements to draw
    } else {
      _updateAiResponse(
          "Received an empty or unexpected response from analysis.");
    }
    setState(() => _isProcessing = false);
  }

  void _updateAiResponse(String text) {
    setState(() {
      _aiResponseText = text;
    });
    _speak(text);
  }

  // Simplified parsing and drawing logic
  void _parseAnalysisForDrawing(String analysisText) {
    // This is a very basic example. Real parsing would need NLP or structured output from Gemini.
    List<DetectedObject> newObjects = [];
    // Example: If Gemini says "The data saver toggle is located at coordinates (100,200,50,50)"
    // Or "The 'Data Saver' text is clearly visible."
    // Or if Gemini could return bounding boxes directly (ideal but requires specific prompting and model capability)

    // Simple keyword-based highlighting (very rudimentary)
    if (analysisText.toLowerCase().contains("data saver")) {
      // Placeholder: Draw a box around an arbitrary area if "data saver" is mentioned
      // In a real app, Gemini would ideally return coordinates, or you'd do client-side text OCR + search
      newObjects.add(DetectedObject(
          boundingBox: const Rect.fromLTWH(0.2, 0.3, 0.6,
              0.1), // Example: 20% from left, 30% from top, 60% width, 10% height
          label: "Data Saver Area (Example)",
          color: Colors.orangeAccent));
    }
    if (analysisText.toLowerCase().contains("data usage is") &&
        analysisText.toLowerCase().contains("gb")) {
      newObjects.add(DetectedObject(
          boundingBox: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.2),
          label: "Data Usage Info (Example)",
          color: Colors.blueAccent));
    }

    if (mounted) setState(() => _detectedObjectsForOverlay = newObjects);
  }

  void _sendChatInput() {
    // This will be used for triggering analysis based on text for now
    final text = _chatInputText.trim();
    if (text.isEmpty) return;

    setState(() {
      _aiResponseText = "Thinking..."; // Placeholder while processing command
      // Add user message to a conceptual chat log (not fully implemented here)
    });

    // Simple command parsing (not using Rasa for this isolated example)
    if (text.toLowerCase().contains("check data usage")) {
      // Prompt to either share screen or upload
      _showActionChoiceDialog("data_usage");
    } else if (text.toLowerCase().contains("data saver")) {
      _showActionChoiceDialog("data_saver");
    } else if (text.toLowerCase().contains("analyze screen") ||
        text.toLowerCase().contains("what is this")) {
      _showActionChoiceDialog("generic_what_is_this");
    } else {
      _updateAiResponse(
          "I can help analyze your screen for tasks like 'check data usage' or 'find data saver'. Please share or upload your screen.");
    }
    _chatInputText = ""; // Clear input
  }

  void _showActionChoiceDialog(String taskKey) {
    if (_lastImageBytes != null && _currentDisplayImage != null) {
      // If an image is already loaded (e.g., from a previous upload), analyze it directly
      _analyzeImageWithGemini(_lastImageBytes!, taskKey);
      return;
    }
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Choose Action"),
            content:
                const Text("How would you like to provide the screen content?"),
            actions: <Widget>[
              TextButton(
                child: const Text("Live Screen Capture (Simulated)"),
                onPressed: () {
                  Navigator.of(context).pop();
                  _captureOrPickScreen(
                      ImageSource.camera, taskKey); // Simulates live capture
                },
              ),
              TextButton(
                child: const Text("Upload Screenshot"),
                onPressed: () {
                  Navigator.of(context).pop();
                  _captureOrPickScreen(ImageSource.gallery, taskKey);
                },
              ),
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        });
  }

  void _showStreamOptions() {
    // This modal would replace the direct "Capture Full Screen" and "Upload Screenshot" buttons
    // It would offer "Device Camera (for AR)" and "Share Phone Screen (for Analysis)"
    // For now, we are keeping separate buttons for clarity in this isolated example.
    // In a combined app, this function would be triggered by the video icon.
    print("Stream options icon clicked - integrate modal here if needed.");
    // For this example, let's use the main buttons directly.
    // If you had a single video icon, this would show a choice.
    // Here, we can simulate it with an alert dialog or directly call.
    _showActionChoiceDialog(
        "generic_what_is_this"); // Default task if icon clicked
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Screen Assistant'),
        actions: [
          // Video Icon to choose stream type (conceptual - main buttons used for now)
          // IconButton(icon: Icon(Icons.videocam_outlined), onPressed: _showStreamOptions)
        ],
      ),
      body: SingleChildScrollView(
        child: SizedBox(
          height: 800.h,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Display Area for Camera Feed or Screenshot Preview
                Container(
                  height: 250, // Fixed height for display area
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    border:
                        Border.all(color: Theme.of(context).primaryColorDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _currentDisplayImage != null &&
                          _uiImageForOverlay != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: DrawingOverlay(
                            // Use the CustomPaint widget
                            backgroundImage: _uiImageForOverlay!,
                            detectedObjects: _detectedObjectsForOverlay,
                            imageSize: _displayedImageSize,
                          ))
                      : Center(
                          child: Text("Share or upload screen to see preview",
                              style: TextStyle(color: Colors.white54))),
                ),
                const SizedBox(height: 16),

                // Controls for starting streams
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.screen_share),
                      label: const Text("Share Screen"), // Simplified
                      onPressed: _isProcessing
                          ? null
                          : () =>
                              _showActionChoiceDialog("generic_what_is_this"),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: const Text("Upload Image"),
                      onPressed: _isProcessing
                          ? null
                          : () => _captureOrPickScreen(
                              ImageSource.gallery, "generic_what_is_this"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Chat Input Area (Simplified for this example)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _chatInputText),
                        onChanged: (value) => _chatInputText = value,
                        onSubmitted: (_) => _sendChatInput(),
                        decoration: const InputDecoration(
                          hintText:
                              "Type command (e.g., 'check data usage')...",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                      color: Theme.of(context).primaryColor,
                      onPressed: _listen,
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      color: Theme.of(context).primaryColor,
                      onPressed: _sendChatInput,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // AI Response Area
                Text(
                  'AI Assistant:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 2),
                          )
                        ]),
                    child: _isProcessing
                        ? const Center(child: CircularProgressIndicator())
                        : SelectableText(_aiResponseText,
                            textAlign: TextAlign.left),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
