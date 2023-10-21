import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class ShowcasePainter extends CustomPainter{
  final ui.Image image;
  final Size imageSegmentSize;
  final Size size;
  final ValueNotifier<Offset> position;

  ShowcasePainter(this.image, {required this.size, required this.imageSegmentSize, required this.position}) : super(repaint: position);

  @override
  void paint(Canvas canvas, Size size){
    final src = Offset(position.value.dx - imageSegmentSize.width / 2, position.value.dy - imageSegmentSize.height / 2) & imageSegmentSize;
    canvas.drawImageRect(image, src, Offset.zero & size, Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CornerShowcase extends StatelessWidget {
  const CornerShowcase({
    super.key,
    required this.size,
    required this.image,
    required this.imageSegmentSize,
    required this.positionNotifier,
  });

  final ui.Image image;
  final Size imageSegmentSize;
  final Size size;
  final ValueNotifier<Offset> positionNotifier;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: ShowcasePainter(image, size: size, imageSegmentSize: imageSegmentSize, position: positionNotifier),
          child: SizedBox(
            width: size.width,
            height: size.height, 
            child: const Center(child: Text("+", style: TextStyle(color: Colors.black54)))
          ),
        ),
      ),
    );
  }
}