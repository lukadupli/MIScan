import 'glider.dart';
import 'helpers.dart';
import 'package:flutter/material.dart';

class BorderPainter extends CustomPainter{
  final Color color;
  final List<Offset> points;
  final double cornerSize;
  final double cornerLineThickness;
  final Offset? delta;
  ValueNotifier<bool> notifier;

  BorderPainter({
    required this.color, 
    required this.cornerSize, 
    required this.cornerLineThickness, 
    required this.points, 
    this.delta, 
    required this.notifier
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    Offset add = delta == null ? Offset.zero : delta!;
    for(int i = 0; i < points.length; i++){
      canvas.drawCircle(points[i] + add, cornerSize / 2, Paint()..style = PaintingStyle.stroke..color = color..strokeWidth = cornerLineThickness);
      canvas.drawLine(points[i] + add, points[(i + 1) % points.length] + add, Paint()..color = color..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Returns double the size of area of a triangle given by points [a], [b] and [c]
/// 
/// If the given points are in counterclockwise order, the area is positive,
/// if they are in clockwise order, the area is negative
double ccw(Offset a, Offset b, Offset c){
  return a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy);
}

/// Class which provides information about a [Frame].
/// 
/// Corners are indexed in counterclockwise order starting from bottom left
/// (note that on the screen they are actually in clockwise order starting from top left 
/// because (0, 0) coordinate is in screen's upper left corner)
/// 
/// Provides a function to check if the corners form a convex quadrilateral
class FrameController{
  bool initialized = false;
  Size childSize = Size.zero;
  Rect boundary = Rect.zero;
  var corners = <Offset>[Offset.zero, Offset.zero, Offset.zero, Offset.zero];

  FrameController();
  FrameController.from(FrameController other){
    initialized = other.initialized;
    childSize = other.childSize;
    boundary = other.boundary;
    corners = List<Offset>.from(other.corners);
  }

  bool isConvex(){
    for(int i = 0; i < 4; i++){
      if(ccw(corners[i], corners[(i + 1) % 4], corners[(i + 2) % 4]) >= 0) return false;
    }
    return true;
  }
}

/// A draggable frame with 4 corners around child widget
class Frame extends StatefulWidget{
  final FrameController controller;
  final double cornerSize, cornerLineThickness;
  final Color color;
  final EdgeInsets margin;
  final void Function()? whenResized;
  final void Function(int)? onDragStart;
  final void Function(int)? onPositionChange;
  final void Function(int)? onDragEnd;
  final Widget child;

  /// Creates a widget which shows a draggable frame with 4 corners around child widget
  /// 
  /// [controller] contains information about corner positions and child's size
  /// 
  /// Corners are indexed in counterclockwise order starting from bottom left 
  /// (note that on the screen they are actually in clockwise order starting from top left because (0, 0) coordinate is in upper left corner)
  /// 
  /// [onDragStart], [onPositionChange], [onDragEnd] are called with an index (from 0 to 3) to the corner whose position was altered
  /// 
  /// [whenResized] is called at first build and when child's size is changed
  const Frame({
    super.key, 
    required this.controller, 
    this.cornerSize = 30.0, 
    this.cornerLineThickness = 3.0, 
    this.color = Colors.black, 
    this.margin = EdgeInsets.zero,
    this.whenResized,
    this.onDragStart,
    this.onPositionChange,
    this.onDragEnd, 
    required this.child,
  });

  @override
  State<Frame> createState() => _FrameState();
}

class _FrameState extends State<Frame>{
  Rect boundary = Rect.zero;
  final notifier = ValueNotifier<bool>(false);
  final childKey = GlobalKey();

  void handleChildSizeChange(){
    final childBox = childKey.currentContext!.findRenderObject()! as RenderBox;
    final newBound = widget.margin.topLeft & childBox.size;

    if(newBound != boundary){
      if(!widget.controller.initialized){
        widget.controller.initialized = true;

        widget.controller.corners[0] = Offset.zero;
        widget.controller.corners[1] = Offset(newBound.width, 0);
        widget.controller.corners[2] = Offset(newBound.width, newBound.height);
        widget.controller.corners[3] = Offset(0, newBound.height);
      }
      else{
        for(int i = 0; i < 4; i++){
          widget.controller.corners[i] = Offset(
            scale(widget.controller.corners[i].dx, 0, boundary.width, 0, newBound.width),
            scale(widget.controller.corners[i].dy, 0, boundary.height, 0, newBound.height),
          );
        }
      }

      widget.controller.childSize = newBound.size;
      widget.controller.boundary = newBound;
      if(widget.whenResized != null) widget.whenResized!();

      setState(() => boundary = newBound);
    }
  }

  Widget buildCorner(int index){
    final size = Size(boundary.right + widget.margin.right, boundary.bottom + widget.margin.bottom);

    return Glider(
      key: GlobalKey(),
      startPosition: widget.controller.corners[index],
      positionOffset: Offset(widget.cornerSize / 2, widget.cornerSize / 2),
      size: size,
      boundary: boundary,
      onDragStart: (pos){
        if(widget.onDragStart != null) widget.onDragStart!(index);
      },
      onPositionChange: (pos){
        widget.controller.corners[index] = pos;
        if(widget.onPositionChange != null) widget.onPositionChange!(index);
        notifier.value = !notifier.value;
      },
      onDragEnd: (){
        if(widget.onDragEnd != null) widget.onDragEnd!(index);
      },
      child: Container(
        width: widget.cornerSize,
        height: widget.cornerSize, 
        decoration: const BoxDecoration(shape: BoxShape.circle)
      )
    );
  }

  @override
  Widget build(BuildContext context){
    WidgetsBinding.instance.addPostFrameCallback((_) => handleChildSizeChange());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (sizeNotification) {
        WidgetsBinding.instance.addPostFrameCallback((_) => handleChildSizeChange());
        return true;
      },
      child: CustomPaint(
        foregroundPainter: BorderPainter(
          color: widget.color, 
          cornerSize: widget.cornerSize,
          cornerLineThickness: widget.cornerLineThickness, 
          points: widget.controller.corners, 
          delta: boundary.topLeft, 
          notifier: notifier
        ),
        child: Stack(
          children:[
            Container(
              margin: widget.margin,
              child: SizeChangedLayoutNotifier(key: childKey, child: widget.child),
            ),
            for(int i = 0; i < 4; i++) buildCorner(i),
          ]
        ),
      ),
    );
  }               
}