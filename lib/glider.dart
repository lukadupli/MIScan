import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class Glider extends StatefulHookWidget {
  final Widget child;
  final Offset startPosition;
  final Offset positionOffset;
  final void Function(Offset)? onDragStart;
  final void Function(Offset)? onPositionChange;
  final void Function()? onDragEnd;

  const Glider({
    super.key, 
    required this.child, 
    this.startPosition = Offset.zero, 
    this.positionOffset = Offset.zero, 
    this.onDragStart,
    this.onPositionChange, 
    this.onDragEnd,
  });

  @override
  State<Glider> createState() => _GliderState();
}

class _GliderState extends State<Glider>{
  final _globalKey = GlobalKey();
  RenderBox? _renderBox;

@override
void initState(){
  WidgetsBinding.instance.addPostFrameCallback((_) => _renderBox = _globalKey.currentContext!.findRenderObject() as RenderBox);
  super.initState();
}

  @override
  Widget build(BuildContext context) {
    final position = useState(widget.startPosition - widget.positionOffset);
    final delta = useState(Offset.zero);

    Offset bottomRight = Offset.infinite;
    if(_renderBox != null) bottomRight = _renderBox!.size.bottomRight(Offset.zero);

    return GestureDetector(
      key: _globalKey,
      onPanDown:(details) {
        delta.value = details.globalPosition - position.value - widget.positionOffset;
      },
      onPanStart: (details){
        if(widget.onDragStart != null) widget.onDragStart!(details.globalPosition);
      },
      onPanUpdate:(details) {
        var t = details.globalPosition - delta.value;
        Offset temp = Offset(t.dx.clamp(0.0, bottomRight.dx), t.dy.clamp(0.0, bottomRight.dy));

        if(widget.onPositionChange != null) widget.onPositionChange!(temp);
        position.value = temp - widget.positionOffset;
      },
      onPanEnd: (details){
        if(widget.onDragEnd != null) widget.onDragEnd!();
      },
      child: Stack(
        children: [
          Positioned(
            left: position.value.dx,
            top: position.value.dy,
            child: widget.child,
          )
        ],
      ),
    );
  }
}