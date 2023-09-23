import 'dart:typed_data';

import 'glider.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

class BorderPainter extends CustomPainter{
  Color color;
  List<Offset> points;

  BorderPainter({required this.color, required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    for(int i = 0; i < points.length; i++){
      canvas.drawLine(points[i], points[(i + 1) % points.length], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    final oldThis = oldDelegate as BorderPainter;
    return oldThis.color != color || oldThis.points != points;
  }
}

double ccw(Offset a, Offset b, Offset c){
  return a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy);
}

class FrameController{
  final corners = List<Offset>.filled(4, Offset.zero);
  final scControllers = <ScreenshotController>[ScreenshotController(), ScreenshotController(), ScreenshotController(), ScreenshotController()];

  bool convexCheck(){
    for(int i = 0; i < 4; i++){
      if(ccw(corners[i], corners[(i + 1) % 4], corners[(i + 2) % 4]) >= 0) return false;
    }
    return true;
  }

  Future<Uint8List?> capture(int index) async{
    return await scControllers[index].capture();
  }
}

class Frame extends StatefulWidget{
  final FrameController controller;
  final double cornerSize, cornerLineThickness;
  final Color color;
  final void Function(int)? onPositionChange;

  const Frame({super.key, required this.controller, this.cornerSize = 30.0, this.cornerLineThickness = 3.0, this.color = Colors.black, this.onPositionChange});

  @override
  State<Frame> createState() => _FrameState();
}

class _FrameState extends State<Frame>{
  Widget buildCorner(int index){
    return Screenshot(
      controller: widget.controller.scControllers[index],
      child: Glider(
        key: GlobalKey(),
        startPosition: widget.controller.corners[index],
        positionOffset: Offset(widget.cornerSize / 2, widget.cornerSize / 2),
        onPositionChange: (pos){
          final temp = widget.controller.corners[index];
          widget.controller.corners[index] = pos;

          if(widget.controller.convexCheck()){
            widget.controller.corners[index] = pos;
            if(widget.onPositionChange != null) widget.onPositionChange!(index);
          }
          else {
            widget.controller.corners[index] = temp;
          }
        },
        child: Container(
          width: widget.cornerSize,
          height: widget.cornerSize, 
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: widget.cornerLineThickness))
        )
      ),
    );
  }

  @override
  Widget build(BuildContext context){
    return LayoutBuilder(
      builder: (context, constraints){
        widget.controller.corners[0] = Offset.zero;
        widget.controller.corners[1] = Offset(0, constraints.maxHeight);
        widget.controller.corners[2] = Offset(constraints.maxWidth, constraints.maxHeight);
        widget.controller.corners[3] = Offset(constraints.maxWidth, 0);

        return CustomPaint(
          painter: BorderPainter(color: widget.color, points: widget.controller.corners),
          child: Stack(
            children:[
              for(int i = 0; i < 4; i++) buildCorner(i)
            ]
          )
        );
      }
    );
  }               
}