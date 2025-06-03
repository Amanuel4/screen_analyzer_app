import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// Your Gemini Backend URL
const String screenAnalysisApiUrl = 'https://rasa.qemsha.com/analyze_screen/';

class AnalysisService {
  Future<Map<String, dynamic>> analyzeScreenImage({
    required Uint8List imageBytes,
    required String taskPrompt,
    String imageMimeType = 'image/jpeg', // Or 'image/png'
  }) async {
    try {
      String base64Image = "data:$imageMimeType;base64,${base64Encode(imageBytes)}";

      print("Sending image to analysis service. Task: ${taskPrompt.substring(0, (taskPrompt.length > 50) ? 50 : taskPrompt.length)}...");

      final response = await http.post(
        Uri.parse(screenAnalysisApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image, 'task_prompt': taskPrompt}),
      ).timeout(const Duration(seconds: 60)); // Increased timeout for potentially long analysis

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("Analysis service response: $data");
        return data; // Expects {"analysis_text": "...", "error": "..."}
      } else {
        print("Analysis service error: ${response.statusCode} - ${response.body}");
        return {'error': "Server error: ${response.statusCode} - ${response.reasonPhrase}"};
      }
    } catch (e) {
      print("Exception calling analysis service: $e");
      return {'error': "Failed to connect to analysis service: $e"};
    }
  }
}