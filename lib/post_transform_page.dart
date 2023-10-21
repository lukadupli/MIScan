import 'dart:ui' as ui;
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'package:flutter/material.dart';

class PostTransformPage extends StatelessWidget{
  final ui.Image image;
  const PostTransformPage({super.key, required this.image});

  Future save() async{
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if(bytes == null) return;

    await ImageGallerySaver.saveImage(bytes.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Save and Edit")
      ),
      body: Container(
        margin: const EdgeInsets.all(10.0),
        child: RawImage(image: image),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => save(),
      ),
    );
  }
}