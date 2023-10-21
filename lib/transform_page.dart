import 'package:flutter/material.dart';
import 'corner_showcase.dart';
import 'frame.dart';
import 'loading_page.dart';
import 'transform.dart';
import 'package:image_size_getter/image_size_getter.dart' as isg;
import 'dart:typed_data';
import 'post_transform_page.dart';

class TransformPage extends StatefulWidget{
  final Uint8List imageData;

  const TransformPage({super.key, required this.imageData});

  @override
  State<TransformPage> createState() => _TransformPageState();
}

class _TransformPageState extends State<TransformPage> {
  final fController = FrameController();
  late final isg.Size imageSize;
  late final List<ValueNotifier<Offset>> notifiers;
  late final double ratio;

  static const double frameCornerDimension = 50.0;
  static const double showcaseSizeDimension = 60.0;
  static const double showcaseSegmentDimension = 200.0;

  Widget buildShowcase(int index){
    return CornerShowcase(
      size: const Size(showcaseSizeDimension, showcaseSizeDimension),
      imageData: widget.imageData,
      imageSegmentSize: const Size(showcaseSegmentDimension, showcaseSegmentDimension),
      positionNotifier: notifiers[index],
    );
  }

  @override
  void initState(){
    imageSize = isg.ImageSizeGetter.getSize(isg.MemoryInput(widget.imageData));
    notifiers = <ValueNotifier<Offset>>[
      ValueNotifier<Offset>(Offset.zero),
      ValueNotifier<Offset>(Offset(0, imageSize.height.toDouble())),
      ValueNotifier<Offset>(Offset(imageSize.width.toDouble(), imageSize.height.toDouble())),
      ValueNotifier<Offset>(Offset(imageSize.width.toDouble(), 0)),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for(int i = 0; i < 4; i++) buildShowcase(i),
            ],
          ),
          Frame(
            controller: fController,
            cornerSize: frameCornerDimension,
            margin: const EdgeInsets.fromLTRB(frameCornerDimension / 4, frameCornerDimension / 2, frameCornerDimension / 4, frameCornerDimension / 2),
            whenLoaded: (){
              ratio = imageSize.width / fController.childSize.width;
              for(int i = 0; i < 4; i++){
                notifiers[i].value = fController.corners[i] * ratio;
              }
            },
            onPositionChange: (index) {
              notifiers[index].value = fController.corners[index] * ratio;
            },
            child: Image.memory(widget.imageData)
          ),
          IconButton(icon: const Icon(Icons.transform), onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => FutureBuilder(
              future: transform(
                widget.imageData, 
                fController.corners[0] * ratio, 
                fController.corners[1] * ratio, 
                fController.corners[2] * ratio,
                fController.corners[3] * ratio,
              ),
              builder: (context, snapshot) => snapshot.hasData ? PostTransformPage(imageData: snapshot.data!) : const LoadingPage(),
            )));
          })
        ]
      ),
    );
  }
}
