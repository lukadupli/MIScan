import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class Glider extends StatefulHookWidget {
  final Widget child;
  final Offset startPosition;
  final Offset positionOffset;
  final Size size;
  final Rect boundary;
  final void Function(Offset)? onDragStart;
  final void Function(Offset)? onPositionChange;
  final void Function()? onDragEnd;

  const Glider({
    super.key, 
    required this.child, 
    this.startPosition = Offset.zero, 
    this.positionOffset = Offset.zero,
    required this.size,
    required this.boundary,
    this.onDragStart,
    this.onPositionChange, 
    this.onDragEnd,
  });

  @override
  State<Glider> createState() => _GliderState();
}

class _GliderState extends State<Glider>{
  @override
  Widget build(BuildContext context) {
    final position = useState(widget.startPosition + widget.boundary.topLeft - widget.positionOffset);
    final delta = useState(Offset.zero);

    return GestureDetector(
      onPanDown:(details) {
        delta.value = details.globalPosition - position.value - widget.positionOffset;
      },
      onPanStart: (details){
        if(widget.onDragStart != null) widget.onDragStart!(details.globalPosition);
      },
      onPanUpdate:(details) {
        var t = details.globalPosition - delta.value;
        Offset temp = Offset(
          t.dx.clamp(widget.boundary.topLeft.dx, widget.boundary.bottomRight.dx), 
          t.dy.clamp(widget.boundary.topLeft.dy, widget.boundary.bottomRight.dy)
        );

        if(widget.onPositionChange != null) widget.onPositionChange!(temp - widget.boundary.topLeft);
        position.value = temp - widget.positionOffset;
      },
      onPanEnd: (details){
        if(widget.onDragEnd != null) widget.onDragEnd!();
      },
      child: SizedBox(
        width: widget.size.width,
        height: widget.size.height,
        child: Stack(
          children: [
            Positioned(
              left: position.value.dx,
              top: position.value.dy,
              child: widget.child,
            )
          ],
        ),
      ),
    );
  }
}