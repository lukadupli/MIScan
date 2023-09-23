import 'dart:typed_data';

import 'package:flutter/material.dart';

class PostTransformPage extends StatelessWidget{
  final Uint8List imageData;
  const PostTransformPage({super.key, required this.imageData});

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
      )
    );
  }
}