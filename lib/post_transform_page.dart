import 'dart:ui' as ui;
import 'package:image_gallery_saver/image_gallery_saver.dart';

import 'package:flutter/material.dart';

class PostTransformPage extends StatefulWidget{
  final ui.Image image;
  const PostTransformPage({super.key, required this.image});

  @override
  State<PostTransformPage> createState() => _PostTransformPageState();
}

class _PostTransformPageState extends State<PostTransformPage> {
  int turns = 0;

  Future save() async{
    final bytes = await widget.image.toByteData(format: ui.ImageByteFormat.png);
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
        child: Center(
          child: RotatedBox(
            quarterTurns: turns,
            child: RawImage(image: widget.image)
          )
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Icons.rotate_left ), onPressed: () => setState(() => turns = (turns + 3) % 4)),
            IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setState(() => turns = (turns + 1) % 4)),
            IconButton(icon: const Icon(Icons.save), onPressed: () => save()),
          ]
        )
      ),
    );
  }
}