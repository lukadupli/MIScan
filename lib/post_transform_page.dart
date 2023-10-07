import 'dart:typed_data';
import 'dart:ui' as ui;
import 'transform_page.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'package:flutter/material.dart';

class PostTransformPage extends StatelessWidget{
  final Uint8List imageData;
  const PostTransformPage({super.key, required this.imageData});

  Future save() async{
    final img = await bytesToImage(imageData);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
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
        child: Image.memory(imageData),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => save(),
      ),
    );
  }
}