import 'package:flutter/material.dart';
import 'frame.dart';
import 'transform.dart';
import 'package:image_size_getter/image_size_getter.dart';
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
  late Size imageSize;
  final fTargetKey = GlobalKey();

  Image? show;

  @override
  void initState(){
    imageSize = ImageSizeGetter.getSize(MemoryInput(widget.imageData));
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
        children:[
          Container(height: 50, color: Theme.of(context).focusColor, child: show),
          Frame(
            controller: fController,
            cornerSize: 50.0,
            margin: const EdgeInsets.all(25.0),
            child: Image.memory(widget.imageData)
          ),
          IconButton(icon: const Icon(Icons.transform), onPressed: () {
            double ratio = imageSize.width / fController.childSize.width;

            transform(widget.imageData, fController.corners[0] * ratio, fController.corners[1] * ratio, fController.corners[2] * ratio, fController.corners[3] * ratio)
            .then((result) => Navigator.push(context, MaterialPageRoute(builder: (context) => PostTransformPage(imageData: result!))));
          })
        ]
      ),
    );
  }
}