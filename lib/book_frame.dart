import 'package:flutter/material.dart';
import 'cubic_spline.dart';
import 'glider.dart';
import 'helpers.dart';

class BookFrameController {
  final int splinePoints;
  final List<Offset> corners;
  late final List<Offset> curvePointsUp;
  late final List<Offset> curvePointsDown;
  final notifier = ValueNotifier<bool>(true);

  Rect boundary;
  Size get childSize => boundary.size;

  static const polyDegree = 7;

  BookFrameController({required this.splinePoints, required this.corners, required this.boundary}){
    double dx = (corners[1].dx - corners[0].dx) / (splinePoints + 1);
    double dy = (corners[1].dy - corners[0].dy) / (splinePoints + 1);
    curvePointsUp = List<Offset>.generate(splinePoints, (int index) => Offset(corners[0].dx + (index + 1) * dx, corners[0].dy + (index + 1) * dy));

    dx = (corners[2].dx - corners[3].dx) / (splinePoints + 1);
    dy = (corners[2].dy - corners[3].dy) / (splinePoints + 1);
    curvePointsDown = List<Offset>.generate(splinePoints, (int index) => Offset(corners[3].dx + (index + 1) * dx, corners[3].dy + (index + 1) * dy)); 
  }

  CubicSpline get curveUp => CubicSpline([corners[0], for(final p in curvePointsUp) p, corners[1]]);
  CubicSpline get curveDown => CubicSpline([corners[3], for(final p in curvePointsDown) p, corners[2]]);

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
  final Color splineSelectorEdgeColor;
  final Color splineSelectorFillColor;
  final Color splineLineColor;
  final Offset offset;
  
  BookFramePainter({
    required this.controller, 
    required this.cornerSize, 
    required this.cornerThickness,
    required this.mainFrameColor, 
    required this.splineSelectorSize, 
    required this.splineSelectorEdgeColor,
    required this.splineSelectorFillColor,
    required this.splineLineColor,
    this.offset = const Offset(0, 0)}) : super(repaint: controller.notifier);

  @override
  void paint(Canvas canvas, Size size) {
    for(final p in controller.corners){
      canvas.drawCircle(p + offset, cornerSize / 2, Paint()..style = PaintingStyle.stroke..color = mainFrameColor..strokeWidth = cornerThickness);
    }
    canvas.drawLine(controller.corners[1] + offset, controller.corners[2] + offset, Paint()..color = mainFrameColor..strokeWidth = 1);
    canvas.drawLine(controller.corners[3] + offset, controller.corners[0] + offset, Paint()..color = mainFrameColor.. strokeWidth = 1);

    for(final p in controller.curvePointsUp){
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorEdgeColor..style = PaintingStyle.stroke);
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorFillColor..style = PaintingStyle.fill);
    }
    for(final p in controller.curvePointsDown){
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorEdgeColor..style = PaintingStyle.stroke);
      canvas.drawCircle(p + offset, splineSelectorSize / 2, Paint()..color = splineSelectorFillColor..style = PaintingStyle.fill);
    }

    // spline approximation
    const int pixelsPerPoint = 4;

    int approxSize = ((controller.corners[1].dx - controller.corners[0].dx) / pixelsPerPoint).round(); // 3 pixels per point
    final dxUp = (controller.corners[1].dx - controller.corners[0].dx) / approxSize;
    for(int i = 0; i < approxSize; i++){
      final nx = controller.corners[0].dx + i * dxUp;
      final p1 = Offset(nx, controller.curveUp.compute(nx));
      final p2 = Offset(nx + dxUp, controller.curveUp.compute(nx + dxUp));

      canvas.drawLine(p1 + offset, p2 + offset, Paint()..color = splineLineColor..strokeWidth = 1);
    }

    approxSize = ((controller.corners[2].dx - controller.corners[3].dx) / pixelsPerPoint).round();
    final dxDown = (controller.corners[2].dx - controller.corners[3].dx) / approxSize;
    for(int i = 0; i < approxSize; i++){
      final nx = controller.corners[3].dx + i * dxDown;
      final p1 = Offset(nx, controller.curveDown.compute(nx));
      final p2 = Offset(nx + dxDown, controller.curveDown.compute(nx + dxDown));

      canvas.drawLine(p1 + offset, p2 + offset, Paint()..color = splineLineColor..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => this != (oldDelegate as BookFramePainter);
}

class BookFrame extends StatefulWidget{
  final BookFrameController controller;
  final EdgeInsets margin;
  final void Function()? whenResized;

  final double cornerSize;
  final double cornerThickness;
  final Color mainFrameColor;
  final double splineSelectorSize;
  final Color splineSelectorEdgeColor;
  final Color splineSelectorFillColor;
  final Color splineLineColor;

  final Widget child;

  const BookFrame({
    super.key, 
    required this.controller, 
    this.margin = EdgeInsets.zero, 
    this.whenResized, 
    this.cornerSize = 50.0,
    this.cornerThickness = 3.0,
    this.mainFrameColor = Colors.black, 
    this.splineSelectorSize = 30.0, 
    this.splineSelectorEdgeColor = Colors.black,
    this.splineSelectorFillColor = Colors.white24,
    this.splineLineColor = Colors.black,
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
    const hitboxMul = 1.5;

    return Glider(
      key: GlobalKey(),
      startPosition: !curve ? widget.controller.curvePointsUp[index] : widget.controller.curvePointsDown[index],
      positionOffset: Offset(widget.splineSelectorSize / 2, widget.splineSelectorSize / 2) * hitboxMul,
      size: size,
      boundary: widget.controller.boundary,
      onPositionChange: (pos){
        if(!curve) {
          widget.controller.setCurvePointUp(index, pos);
        } else {
          widget.controller.setCurvePointDown(index, pos);
        }
      },
      child: Container(
        width: widget.splineSelectorSize * hitboxMul,
        height: widget.splineSelectorSize * hitboxMul, 
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
          splineSelectorEdgeColor: widget.splineSelectorEdgeColor,
          splineSelectorFillColor: widget.splineSelectorFillColor,
          splineLineColor: widget.splineLineColor,
          offset: widget.controller.boundary.topLeft,
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