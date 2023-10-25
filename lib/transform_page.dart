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
  int quarterTurns = 0;

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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Transformator"),
      ),
      body: Stack(
        children: [
          Center(
            child: Frame(
              controller: fController,
              cornerSize: frameCornerDimension,
              margin: const EdgeInsets.fromLTRB(frameCornerDimension / 4, frameCornerDimension / 2, frameCornerDimension / 4, frameCornerDimension / 2),
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
          ),
          ValueListenableBuilder(
            valueListenable: showcaseAlignment,
            builder: (context, alignment, child) => alignment != null ? Align(
              alignment: alignment ? Alignment.topRight : Alignment.topLeft,
              child: child,
            ) : const SizedBox.shrink(),
            child: buildShowcase(),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: IconButton(icon: const Icon(Icons.check), onPressed: () {
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
      ),
    );
  }

  TextButton simpleButton({required Icon icon, required Text text, required void Function() onPressed}) {
    return TextButton(
      onPressed: onPressed,
      child: Column(
        children: [
          icon,
          text, 
        ]
      ),
    );
  }
}
