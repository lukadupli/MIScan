// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'corner_showcase.dart';
import 'frame.dart';
import 'loading_page.dart';
import 'transform.dart';
import 'post_transform_page.dart';
import 'dart:ui' as ui;

class TransformPage extends StatefulWidget{
  final ui.Image image;

  const TransformPage({super.key, required this.image});

  @override
  State<TransformPage> createState() => _TransformPageState();
}

class _TransformPageState extends State<TransformPage> {
  final fController = FrameController();
  late double ratio;
  
  int active = 0;
  final showcaseAlignment = ValueNotifier<bool?>(null);
  final showcasePosition = ValueNotifier<Offset>(Offset.zero);

  static const double frameCornerDimension = 50.0;
  static const double showcaseSizeDimension = 100.0;
  static const double showcaseSegmentDimension = 200.0;

  bool getAlignment(Offset position, Size imageSize){
    return position.dx < imageSize.width / 2 && position.dy < imageSize.height / 2;
  }

  Widget buildShowcase(){
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: CornerShowcase(
        size: const Size(showcaseSizeDimension, showcaseSizeDimension),
        image: widget.image,
        imageSegmentSize: const Size(showcaseSegmentDimension, showcaseSegmentDimension),
        positionNotifier: showcasePosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Transformator"),
      ),
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.orientationOf(context) == Orientation.portrait ? 0.0 : MediaQuery.paddingOf(context).top),
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Frame(
                  controller: fController,
                  cornerSize: frameCornerDimension,
                  margin: EdgeInsets.symmetric(
                    vertical  : frameCornerDimension / (MediaQuery.orientationOf(context) == Orientation.portrait ? 2 : 4),
                    horizontal: frameCornerDimension / (MediaQuery.orientationOf(context) == Orientation.portrait ? 4 : 2),
                  ),
                  whenLoaded: () => ratio = widget.image.width / fController.childSize.width,
                  onDragStart: (index){
                    active++;
                    if(active == 2) showcaseAlignment.value = null;
                  },
                  onPositionChange: (index) {
                    if(active != 1) return;

                    final properAlignment = getAlignment(fController.corners[index], fController.childSize);
                    if(showcaseAlignment.value != properAlignment) showcaseAlignment.value = properAlignment;
                    
                    showcasePosition.value = fController.corners[index] * ratio;
                  },
                  onDragEnd: (index) {
                    active--;
                    if(active == 0) showcaseAlignment.value = null;
                  }, 
                  child: RawImage(image: widget.image),
                ),
                ValueListenableBuilder(
                  valueListenable: showcaseAlignment,
                  builder: (context, alignment, child) => alignment != null ? Positioned.fill(
                    child: Align(
                      alignment: alignment ? Alignment.topRight : Alignment.topLeft,
                      child: child,
                    ),
                  ) : const SizedBox.shrink(),
                  child: buildShowcase(),
                ),
              ],
            ),
            OutlinedButton(child: const Icon(Icons.check), onPressed: () {
              if(!canTransform(
                fController.corners[0] * ratio, 
                fController.corners[1] * ratio, 
                fController.corners[2] * ratio,
                fController.corners[3] * ratio,
              )){
                showDialog(
                  context: context, 
                  builder: (context) => AlertDialog.adaptive(
                    title: const Text("Cannot transform from selected points"),
                    actions: [TextButton(child: const Text("OK"), onPressed: () => Navigator.of(context).pop())]
                  )
                );
                return;
              }

              Navigator.push(context, MaterialPageRoute(builder: (context) => FutureBuilder(
                future: transform(
                  widget.image, 
                  fController.corners[0] * ratio, 
                  fController.corners[1] * ratio, 
                  fController.corners[2] * ratio,
                  fController.corners[3] * ratio,
                ),
                builder: (context, snapshot) => snapshot.hasData ? PostTransformPage(image: snapshot.data!) : const LoadingPage(),
              )));
            }),
          ]
        ),
      ),
    );
  }
}
