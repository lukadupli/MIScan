import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'helpers.dart';
import 'dart:ui' as ui;

class ShowcasePainter extends CustomPainter{
  ui.Image? image;
  final Size imageSegmentSize;
  final Size size;
  final ValueNotifier<Offset> position;

  ShowcasePainter(Uint8List imageData, {required this.size, required this.imageSegmentSize, required this.position}) : super(repaint: position){
    bytesToImage(imageData).then((value) => image = value);
  }

  @override
  void paint(Canvas canvas, Size size){
    if(image == null) return;
    final src = Offset(position.value.dx - imageSegmentSize.width / 2, position.value.dy - imageSegmentSize.height / 2) & imageSegmentSize;
    canvas.drawImageRect(image!, src, Offset.zero & size, Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CornerShowcase extends StatelessWidget {
  const CornerShowcase({
    super.key,
    required this.size,
    required this.imageData,
    required this.imageSegmentSize,
    required this.positionNotifier,
  });

  final Uint8List imageData;
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
          painter: ShowcasePainter(imageData, size: size, imageSegmentSize: imageSegmentSize, position: positionNotifier),
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