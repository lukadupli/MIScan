import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:straighten/transform_page.dart';

import 'dart:ui' as ui;

import 'helpers.dart';
import 'loading_page.dart';

class MyHomePage extends StatelessWidget {
  MyHomePage({super.key, required this.title});

  final String title;
  final picker = ImagePicker();
  
  Future<ui.Image> crossFileToImage(XFile xfile) async{
    final raw = await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
    return await bytesToImage(raw);
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        title: Text(title),
      ),
      persistentFooterAlignment: AlignmentDirectional.bottomCenter,
      persistentFooterButtons: [
        FloatingActionButton(
          heroTag: "1",
          onPressed: () {
            picker.pickImage(source: ImageSource.camera).then((xfile) {
              if(xfile != null) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => FutureBuilder(
                    future: crossFileToImage(xfile),
                    builder: (context, snapshot) => snapshot.hasData ? TransformPage(image: snapshot.data!) : const LoadingPage(),
                  )
                ));
              }
            });
          },
          tooltip: "Take a photo",
          child: const Icon(Icons.camera_alt),
        ),
        FloatingActionButton(
          heroTag: "2",
          onPressed: () {
            picker.pickImage(source: ImageSource.gallery).then((xfile) {
              if(xfile != null) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => FutureBuilder(
                    future: crossFileToImage(xfile),
                    builder: (context, snapshot) => snapshot.hasData ? TransformPage(image: snapshot.data!) : const LoadingPage(),
                  )
                ));
              }
            });
          },
          tooltip: "From gallery",
          child: const Icon(Icons.image),
        ),
      ]
    );
  }
}
