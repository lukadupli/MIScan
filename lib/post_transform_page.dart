import 'dart:ui' as ui;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:flutter/material.dart';
import 'package:bitmap/bitmap.dart';
import 'helpers.dart';

class PostTransformPage extends StatefulWidget{
  final ui.Image image;
  const PostTransformPage({super.key, required this.image});

  @override
  State<PostTransformPage> createState() => _PostTransformPageState();
}

class _PostTransformPageState extends State<PostTransformPage> {
  int turns = 0;

  Future<ui.Image> rotate(ui.Image image, int turns) async{
    if(turns == 0) return image;

    final byteData = (await image.toByteData())!;
    var bmp = Bitmap.fromHeadless(image.width, image.height, byteData.buffer.asUint8List());

    if(turns == 1){
      bmp = bmp.apply(BitmapRotate.rotateClockwise());
    }
    else if(turns == 2){
      bmp = bmp.apply(BitmapRotate.rotate180());
    }
    else if(turns == 3){
      bmp = bmp.apply(BitmapRotate.rotateCounterClockwise());
    }

    return await bytesToImage(bmp.buildHeaded());
  }

  Future save(ui.Image image, int turns) async{
    debugPrint("start save");

    final rotated = await rotate(image, turns);
    final byteData = (await rotated.toByteData(format: ui.ImageByteFormat.png))!;

    await ImageGallerySaver.saveImage(byteData.buffer.asUint8List());
    debugPrint("saved");
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Save and Edit")
      ),
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.orientationOf(context) == Orientation.portrait ? 0.0 : MediaQuery.paddingOf(context).top),
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: RotatedBox(
                    quarterTurns: turns,
                    child: RawImage(image: widget.image)
                  ),
                ),
              ),
            ),
            Container(
              color: Theme.of(context).highlightColor,
              height: MediaQuery.orientationOf(context) == Orientation.portrait ? 80.0 : null,
              width: MediaQuery.orientationOf(context) == Orientation.landscape ? 80.0 : null,
              child: Flex(
                direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: const Icon(Icons.rotate_left ), onPressed: () => setState(() => turns = (turns + 3) % 4)),
                  IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setState(() => turns = (turns + 1) % 4)),
                  IconButton(icon: const Icon(Icons.save), onPressed: () => save(widget.image, turns)),
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}