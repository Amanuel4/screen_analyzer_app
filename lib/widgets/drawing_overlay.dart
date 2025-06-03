import 'package:flutter/material.dart';
import 'dart:ui' as ui; // For ui.Image

// Define a simple class to hold detected object info for drawing
class DetectedObject {
  final Rect boundingBox; // Relative coordinates (0.0 to 1.0)
  final String label;
  final Color color;

  DetectedObject({required this.boundingBox, required this.label, this.color = Colors.red});
}

class DrawingOverlay extends StatelessWidget {
  final ui.Image? backgroundImage; // The image to draw upon
  final List<DetectedObject> detectedObjects;
  final Size imageSize; // Actual size of the image being displayed

  const DrawingOverlay({
    super.key,
    required this.backgroundImage,
    required this.detectedObjects,
    required this.imageSize,
  });

  @override
  Widget build(BuildContext context) {
    if (backgroundImage == null) {
      return const Center(child: Text("No image to display overlay on."));
    }
    return CustomPaint(
      painter: OverlayPainter(
        backgroundImage: backgroundImage!,
        detectedObjects: detectedObjects,
        imageSize: imageSize,
      ),
      size: imageSize, // Make painter take up the size of the image
    );
  }
}

class OverlayPainter extends CustomPainter {
  final ui.Image backgroundImage;
  final List<DetectedObject> detectedObjects;
  final Size imageSize; // The original size of the image the boxes relate to

  OverlayPainter({
    required this.backgroundImage,
    required this.detectedObjects,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) { // size here is the size of the CustomPaint widget
    // Draw the background image first, scaled to fit the CustomPaint widget
    final paintImage = Paint();
    final srcRect = Rect.fromLTWH(0, 0, backgroundImage.width.toDouble(), backgroundImage.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height); // Draw to fit widget
    canvas.drawImageRect(backgroundImage, srcRect, dstRect, paintImage);

    // Calculate scaling factors if painter size is different from original image size
    // For simplicity, assume detectedObject.boundingBox is relative to backgroundImage dimensions
    // And we scale it to the displayed size (dstRect or size)

    final double scaleX = size.width / imageSize.width; // backgroundImage.width.toDouble();
    final double scaleY = size.height / imageSize.height; // backgroundImage.height.toDouble();


    for (var obj in detectedObjects) {
      final paintRect = Paint()
        ..color = obj.color.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      // Scale bounding box coordinates
      final Rect scaledBox = Rect.fromLTRB(
        obj.boundingBox.left * size.width, // If obj.boundingBox is already 0-1 relative to image
        obj.boundingBox.top * size.height,
        obj.boundingBox.right * size.width,
        obj.boundingBox.bottom * size.height,
      );
      // Or if boundingBox is in absolute pixels of original image:
      // final Rect scaledBox = Rect.fromLTRB(
      //   obj.boundingBox.left * scaleX,
      //   obj.boundingBox.top * scaleY,
      //   obj.boundingBox.right * scaleX,
      //   obj.boundingBox.bottom * scaleY,
      // );

      canvas.drawRect(scaledBox, paintRect);

      final textPainter = TextPainter(
        text: TextSpan(
          text: obj.label,
          style: TextStyle(
            color: obj.color,
            fontSize: 14.0,
            backgroundColor: Colors.black.withOpacity(0.5),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(scaledBox.left, scaledBox.top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Repaint whenever detectedObjects change or image changes
  }
}