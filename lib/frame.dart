import 'glider.dart';
import 'helpers.dart';
import 'package:flutter/material.dart';

/// Corner-circle diameter shared between the corner editor's [Frame] and the
/// scanner's live overlay ([ScanCameraPage]), so the two visually match.
const double kFrameCornerVisualSize = 28.0;

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

  /// Where the corners start, as fractions of the child's size -- top left,
  /// top right, bottom right, bottom left on screen, e.g. a detected page.
  /// Applied at the first layout, once the child's size is known. Null, or
  /// anything but four finite points, starts from the child's edges instead.
  final List<Offset>? initialCorners;

  FrameController({List<Offset>? initialCorners})
      : initialCorners = initialCorners == null ? null : List.unmodifiable(initialCorners);
  FrameController.from(FrameController other) : initialCorners = other.initialCorners {
    initialized = other.initialized;
    childSize = other.childSize;
    boundary = other.boundary;
    corners = List<Offset>.from(other.corners);
  }

  /// Corners for a child of [size] that has not been laid out before:
  /// [initialCorners] clamped onto the child if they are usable, else the
  /// child's own corners.
  List<Offset> startingCorners(Size size){
    final start = initialCorners;
    final usable = start != null && start.length == 4 &&
        start.every((p) => p.dx.isFinite && p.dy.isFinite);
    if(!usable){
      return [Offset.zero, Offset(size.width, 0), Offset(size.width, size.height), Offset(0, size.height)];
    }
    return [
      for(final p in start) Offset(p.dx.clamp(0.0, 1.0) * size.width, p.dy.clamp(0.0, 1.0) * size.height),
    ];
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

  /// Diameter of each corner's draggable hit area. Defaults to [cornerSize],
  /// but can be set larger so a corner stays easy to grab even when its
  /// drawn circle ([cornerSize]) is small.
  final double? hitboxSize;
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
    this.hitboxSize,
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
      final controller = widget.controller;
      if(!controller.initialized){
        controller.initialized = true;
        controller.corners = controller.startingCorners(newBound.size);
      }
      else if(!controller.boundary.isEmpty){
        // Scale from the size the corners were placed for, which the
        // controller knows. This State's own [boundary] is empty when the
        // controller comes laid out from elsewhere, and scaling from an empty
        // size divides by zero.
        final old = controller.boundary;
        for(int i = 0; i < 4; i++){
          controller.corners[i] = Offset(
            scale(controller.corners[i].dx, 0, old.width, 0, newBound.width),
            scale(controller.corners[i].dy, 0, old.height, 0, newBound.height),
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
    final hitbox = widget.hitboxSize ?? widget.cornerSize;
    final size = Size(boundary.right + widget.margin.right, boundary.bottom + widget.margin.bottom);

    return Glider(
      key: GlobalKey(),
      startPosition: widget.controller.corners[index],
      positionOffset: Offset(hitbox / 2, hitbox / 2),
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
        width: hitbox,
        height: hitbox,
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