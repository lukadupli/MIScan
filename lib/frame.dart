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
      canvas.drawLine(points[i] + add, points[(i + 1) % points.length] + add, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

double ccw(Offset a, Offset b, Offset c){
  return a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy);
}

class FrameController{
  bool initialized = false;
  Size childSize = Size.zero;
  final corners = <Offset>[Offset.zero, Offset.zero, Offset.zero, Offset.zero];

  bool isConvex(){
    for(int i = 0; i < 4; i++){
      if(ccw(corners[i], corners[(i + 1) % 4], corners[(i + 2) % 4]) >= 0) return false;
    }
    return true;
  }
}

class Frame extends StatefulWidget{
  final FrameController controller;
  final double cornerSize, cornerLineThickness;
  final Color color;
  final EdgeInsets margin;
  final void Function()? whenLoaded;
  final void Function(int)? onDragStart;
  final void Function(int)? onPositionChange;
  final void Function(int)? onDragEnd;
  final Widget child;

  const Frame({
    super.key, 
    required this.controller, 
    this.cornerSize = 30.0, 
    this.cornerLineThickness = 3.0, 
    this.color = Colors.black, 
    this.margin = EdgeInsets.zero,
    this.whenLoaded,
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
        widget.controller.corners[1] = Offset(0, newBound.height);
        widget.controller.corners[2] = Offset(newBound.width, newBound.height);
        widget.controller.corners[3] = Offset(newBound.width, 0);
      }
      else{
        for(int i = 0; i < 4; i++){
          widget.controller.corners[i] = Offset(
            scale(widget.controller.corners[i].dx, 0, boundary.height, 0, newBound.height),
            scale(widget.controller.corners[i].dy, 0, boundary.width, 0, newBound.width),
          );
        }
      }

      widget.controller.childSize = newBound.size;
      if(widget.whenLoaded != null) widget.whenLoaded!();

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