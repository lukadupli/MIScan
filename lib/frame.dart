import 'glider.dart';
import 'package:flutter/material.dart';

class BorderPainter extends CustomPainter{
  final Color color;
  final List<Offset> points;
  final Offset? delta;
  ValueNotifier<bool> notifier;

  BorderPainter({required this.color, required this.points, this.delta, required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    Offset add = delta == null ? Offset.zero : delta!;
    for(int i = 0; i < points.length; i++){
      canvas.drawLine(points[i] + add, points[(i + 1) % points.length] + add, paint);
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

  bool convexCheck(){
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
  Rect? boundary;
  final notifier = ValueNotifier<bool>(false);
  final childKey = GlobalKey();

  Widget buildCorner(int index){
    final bound = boundary == null ? Rect.zero : boundary!;
    final size = Size(bound.right + widget.margin.right, bound.bottom + widget.margin.bottom);

    return Glider(
      key: GlobalKey(),
      startPosition: widget.controller.corners[index],
      positionOffset: Offset(widget.cornerSize / 2, widget.cornerSize / 2),
      size: size,
      boundary: bound,
      onDragStart: (pos){
        if(widget.onDragStart != null) widget.onDragStart!(index);
      },
      onPositionChange: (pos){
        final temp = widget.controller.corners[index];
        widget.controller.corners[index] = pos;

        if(widget.controller.convexCheck()){
          widget.controller.corners[index] = pos;
          if(widget.onPositionChange != null) widget.onPositionChange!(index);
          notifier.value = !notifier.value;
        }
        else {
          widget.controller.corners[index] = temp;
        }
      },
      onDragEnd: (){
        if(widget.onDragEnd != null) widget.onDragEnd!(index);
      },
      child: Container(
        width: widget.cornerSize,
        height: widget.cornerSize, 
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: widget.cornerLineThickness))
      )
    );
  }

  @override
  Widget build(BuildContext context){
    if(boundary == null || boundary!.size == Size.zero){
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        final childBox = childKey.currentContext!.findRenderObject()! as RenderBox;

        setState((){
          boundary = widget.margin.topLeft & childBox.size;
        });
      });
    }
    else if(!widget.controller.initialized){
      widget.controller.initialized = true;
      widget.controller.childSize = boundary!.size;

      widget.controller.corners[0] = Offset.zero;
      widget.controller.corners[1] = Offset(0, boundary!.height);
      widget.controller.corners[2] = Offset(boundary!.width, boundary!.height);
      widget.controller.corners[3] = Offset(boundary!.width, 0);

      if(widget.whenLoaded != null) widget.whenLoaded!();
    }

    return CustomPaint(
      foregroundPainter: BorderPainter(color: widget.color, points: widget.controller.corners, delta: boundary?.topLeft, notifier: notifier),
      child: Stack(
        children:[
          Container(
            margin: widget.margin,
            child: Container(key: childKey, child: widget.child),
          ),
          for(int i = 0; i < 4; i++) buildCorner(i),
        ]
      ),
    );
  }               
}