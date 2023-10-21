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
  late final List<ValueNotifier<Offset>> notifiers;
  late final double ratio;
  final activeIndex = ValueNotifier<int>(-1);

  static const double frameCornerDimension = 50.0;
  static const double showcaseSizeDimension = 60.0;
  static const double showcaseSegmentDimension = 200.0;

  Widget buildShowcase(int index){
    if(index < 0 || index > 3) return const SizedBox.shrink();
    return CornerShowcase(
      size: const Size(showcaseSizeDimension, showcaseSizeDimension),
      image: widget.image,
      imageSegmentSize: const Size(showcaseSegmentDimension, showcaseSegmentDimension),
      positionNotifier: notifiers[index],
    );
  }

  @override
  void initState(){
    notifiers = <ValueNotifier<Offset>>[
      ValueNotifier<Offset>(Offset.zero),
      ValueNotifier<Offset>(Offset(0, widget.image.height.toDouble())),
      ValueNotifier<Offset>(Offset(widget.image.width.toDouble(), widget.image.height.toDouble())),
      ValueNotifier<Offset>(Offset(widget.image.width.toDouble(), 0)),
    ];
    super.initState();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Transformator"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:[
          Stack(
            children: [
              Frame(
                controller: fController,
                cornerSize: frameCornerDimension,
                margin: const EdgeInsets.fromLTRB(frameCornerDimension / 4, frameCornerDimension / 2, frameCornerDimension / 4, frameCornerDimension / 2),
                whenLoaded: (){
                  ratio = widget.image.width / fController.childSize.width;
                  for(int i = 0; i < 4; i++){
                    notifiers[i].value = fController.corners[i] * ratio;
                  }
                },
                onDragStart: (index){
                  if(activeIndex.value == -1) activeIndex.value = index;
                },
                onPositionChange: (index) {
                  notifiers[index].value = fController.corners[index] * ratio;
                },
                onDragEnd: () => activeIndex.value = -1,
                child: RawImage(image: widget.image),
              ),
              ValueListenableBuilder<int>(
                valueListenable: activeIndex,
                builder: (context, index, child) => buildShowcase(index),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.transform), onPressed: () {
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
          })
        ]
      ),
    );
  }
}
