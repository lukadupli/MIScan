import 'dart:math';

import 'package:flutter/material.dart';
import 'frame.dart';
import 'transform.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'dart:typed_data';
import 'post_transform_page.dart';
import 'package:exif/exif.dart';

Size _exifedSize(int? orient, Size size){
  if(orient == null) return size;

  if(orient <= 4) return size;
  return Size(size.height, size.width);
}

class TransformPage extends StatefulWidget{
  final Uint8List imageData;

  const TransformPage({super.key, required this.imageData});

  @override
  State<TransformPage> createState() => _TransformPageState();
}

class _TransformPageState extends State<TransformPage> {
  final fController = FrameController();
  double ratio = 1.0;
  int? orient;

  @override
  Widget build(BuildContext context){
    if(orient == null){
      readExifFromBytes(widget.imageData).then((exif){
        if(exif["Image Orientation"] == null){
          setState(() => orient = 1);
        }
        else{
          setState(() => orient = (exif["Image Orientation"]!.values as IfdInts).firstAsInt());
        }
      });
    } 

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Transformator"),
      ),
      body: Column(
        children:[
          Container(height: 50, color: Theme.of(context).focusColor,
            child: IconButton(icon: const Icon(Icons.transform), onPressed: () {
              transform(widget.imageData, fController.corners[0] * ratio, fController.corners[1] * ratio, fController.corners[2] * ratio, fController.corners[3] * ratio)
              .then((result) => Navigator.push(context, MaterialPageRoute(builder: (context) => PostTransformPage(imageData: result!))));
            })
          ),
          Container(
            margin: const EdgeInsets.all(10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                late double x, y;
                final realSize = ImageSizeGetter.getSize(MemoryInput(widget.imageData));

                final size = _exifedSize(orient, realSize);

                if(size.height > size.width){
                  x = min(constraints.maxWidth, size.width.toDouble());
                  y = x * (size.height / size.width);
                }
                else{
                  y = min(constraints.maxHeight, size.height.toDouble());
                  x = y * (size.width / size.height);
                }
                ratio = size.width / x;
          
                return SizedBox(
                  width: x,
                  height: y,
                  child: Stack(
                    children:[
                      Image.memory(widget.imageData),
                      Frame(controller: fController, cornerSize: 50),
                    ]
                  )
                );
              }
            ),
          ),
        ]
      ),
    );
  }
}