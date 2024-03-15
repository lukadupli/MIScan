import 'package:equations/equations.dart';
import 'package:flutter/material.dart';
import 'glider.dart';
import 'helpers.dart';

class BookFrameController {
  final int splinePoints;
  final List<Offset> corners;
  late final List<Offset> curvePointsUp;
  late final List<Offset> curvePointsDown;
  final notifier = ValueNotifier<bool>(true);

  Rect boundary;

  BookFrameController({required this.splinePoints, required this.corners, required this.boundary}){
    double dx = (corners[1].dx - corners[0].dx) / splinePoints;
    double dy = (corners[1].dy - corners[0].dy) / splinePoints;
    curvePointsUp = List<Offset>.generate(splinePoints, (int index) => Offset(corners[0].dx + index * dx, corners[0].dy + index * dy));

    dx = (corners[2].dx - corners[3].dx) / splinePoints;
    dy = (corners[2].dy - corners[3].dy) / splinePoints;
    curvePointsDown = List<Offset>.generate(splinePoints, (int index) => Offset(corners[3].dx + index * dx, corners[3].dy + index * dy)); 
  }

  SplineInterpolation get curveUp => SplineInterpolation(nodes: [
    InterpolationNode(x: corners[0].dx, y: corners[0].dy), 
    for(final p in curvePointsUp) InterpolationNode(x: p.dx, y: p.dy), 
    InterpolationNode(x: corners[1].dx, y: corners[1].dy)
  ]);

  SplineInterpolation get curveDown => SplineInterpolation(nodes: [
    InterpolationNode(x: corners[3].dx, y: corners[3].dy),
    for(final p in curvePointsDown) InterpolationNode(x: p.dx, y: p.dy),
    InterpolationNode(x: corners[2].dx, y: corners[2].dx)
  ]);

  void setCurvePointUp(int index, Offset pos){
    curvePointsUp[index] = pos;
    notifier.value = !notifier.value;
  }

  void setCurvePointDown(int index, Offset pos){
    curvePointsDown[index] = pos;
    notifier.value = !notifier.value;
  }
}

class BookFramePainter extends CustomPainter{
  final BookFrameController controller;
  final double cornerSize;
  final double cornerThickness;
  final Color mainFrameColor;
  final double splineSelectorSize;
  final Color splineSelectorColor;
  final Color splineLineColor;
  final Offset offset;
  
  BookFramePainter({
    required this.controller, 
    required this.cornerSize, 
    required this.cornerThickness,
    required this.mainFrameColor, 
    required this.splineSelectorSize, 
    required this.splineSelectorColor,
    required this.splineLineColor,
    this.offset = const Offset(0, 0)}) : super(repaint: controller.notifier);

  @override
  void paint(Canvas canvas, Size size) {
    for(final p in controller.corners){
      canvas.drawCircle(p + offset, cornerSize / 2, Paint()..style = PaintingStyle.stroke..color = mainFrameColor..strokeWidth = cornerThickness);
    }
    canvas.drawLine(controller.corners[1] + offset, controller.corners[2] + offset, Paint()..color = mainFrameColor);
    canvas.drawLine(controller.corners[3] + offset, controller.corners[0] + offset, Paint()..color = mainFrameColor);

    for(final p in controller.curvePointsUp){
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorColor..style = PaintingStyle.fill);
    }
    for(final p in controller.curvePointsDown){
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorColor..style = PaintingStyle.fill);
    }

    // spline approximation
    const int approxSize = 1000;
    final dxUp = (controller.corners[1].dx - controller.corners[0].dx) / approxSize;
    for(int i = 0; i < approxSize - 1; i++){
      final p1 = Offset(i * dxUp, controller.curveUp.compute(i * dxUp));
      final p2 = Offset((i + 1) * dxUp, controller.curveUp.compute((i + 1) * dxUp));

      canvas.drawLine(p1 + offset, p2 + offset, Paint()..color = splineLineColor);
    }

    final dxDown = (controller.corners[2].dx - controller.corners[3].dx) / approxSize;
    for(int i = 0; i < approxSize - 1; i++){
      final p1 = Offset(i * dxDown, controller.curveDown.compute(i * dxDown));
      final p2 = Offset((i + 1) * dxDown, controller.curveDown.compute((i + 1) * dxDown));

      canvas.drawLine(p1 + offset, p2 + offset, Paint()..color = splineLineColor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class BookFrame extends StatefulWidget{
  final BookFrameController controller;
  final EdgeInsets margin;
  final void Function()? whenResized;

  final double cornerSize;
  final double cornerThickness;
  final Color mainFrameColor;
  final double splineSelectorSize;
  final Color splineSelectorColor;
  final Color splineLineColor;

  final Widget child;

  const BookFrame({
    super.key, 
    required this.controller, 
    this.margin = EdgeInsets.zero, 
    this.whenResized, 
    this.cornerSize = 30.0,
    this.cornerThickness = 3.0,
    this.mainFrameColor = Colors.black, 
    this.splineSelectorSize = 20.0, 
    this.splineSelectorColor = Colors.white24,
    this.splineLineColor = Colors.lightBlueAccent,
    required this.child, 
  });

  @override
  State<StatefulWidget> createState() => _BookFrameState(); 
}
class _BookFrameState extends State<BookFrame>{
  final childKey = GlobalKey();

  void handleChildSizeChange(){
    final childBox = childKey.currentContext!.findRenderObject()! as RenderBox;
    final newBound = widget.margin.topLeft & childBox.size;

    if(newBound != widget.controller.boundary){
      for(int i = 0; i < 4; i++){
        widget.controller.corners[i] = Offset(
          scale(widget.controller.corners[i].dx, 0, widget.controller.boundary.width, 0, newBound.width),
          scale(widget.controller.corners[i].dy, 0, widget.controller.boundary.height, 0, newBound.height),
        );
      }
      for(int i = 0; i < widget.controller.curvePointsUp.length; i++){
        widget.controller.curvePointsUp[i] = Offset(
          scale(widget.controller.curvePointsUp[i].dx, 0, widget.controller.boundary.width, 0, newBound.width),
          scale(widget.controller.curvePointsUp[i].dy, 0, widget.controller.boundary.height, 0, newBound.height),
        );
      }
      for(int i = 0; i < widget.controller.curvePointsDown.length; i++){
        widget.controller.curvePointsDown[i] = Offset(
          scale(widget.controller.curvePointsDown[i].dx, 0, widget.controller.boundary.width, 0, newBound.width),
          scale(widget.controller.curvePointsDown[i].dy, 0, widget.controller.boundary.height, 0, newBound.height),
        );
      }

      // repaint
      widget.controller.notifier.value = !widget.controller.notifier.value;

      if(widget.whenResized != null) widget.whenResized!();
      setState(() => widget.controller.boundary = newBound);
    }
  }

  Widget buildSplineSelector(int index, bool curve){
    final size = Size(widget.controller.boundary.right + widget.margin.right, widget.controller.boundary.bottom + widget.margin.bottom);

    return Glider(
      key: GlobalKey(),
      startPosition: curve ? widget.controller.curvePointsUp[index] : widget.controller.curvePointsDown[index],
      positionOffset: Offset(widget.splineSelectorSize / 2, widget.splineSelectorSize / 2),
      size: size,
      boundary: widget.controller.boundary,
      onPositionChange: (pos){
        widget.controller.corners[index] = pos;
        if(!curve) {
          widget.controller.setCurvePointUp(index, pos);
        } else {
          widget.controller.setCurvePointDown(index, pos);
        }
      },
      child: Container(
        width: widget.splineSelectorSize,
        height: widget.splineSelectorSize, 
        decoration: const BoxDecoration(shape: BoxShape.circle)
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => handleChildSizeChange());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (sizeNotification) {
        WidgetsBinding.instance.addPostFrameCallback((_) => handleChildSizeChange());
        return true;
      },
      child: CustomPaint(
        foregroundPainter: BookFramePainter(
          controller: widget.controller,
          cornerSize: widget.cornerSize,
          cornerThickness: widget.cornerThickness,
          mainFrameColor: widget.mainFrameColor,
          splineSelectorSize: widget.splineSelectorSize,
          splineSelectorColor: widget.splineSelectorColor,
          splineLineColor: widget.splineLineColor,
        ),
        child: Stack(
          children:[
            Container(
              margin: widget.margin,
              child: SizeChangedLayoutNotifier(key: childKey, child: widget.child),
            ),
            for(int i = 0; i < widget.controller.curvePointsUp.length; i++) buildSplineSelector(i, false),
            for(int i = 0; i < widget.controller.curvePointsDown.length; i++) buildSplineSelector(i, true)
          ]
        ),
      ),
    );
  }
}