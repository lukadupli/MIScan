import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:straighten/transform_page.dart';

import 'loading_page.dart';

class MyHomePage extends StatelessWidget {
  MyHomePage({super.key, required this.title});

  final String title;
  final picker = ImagePicker();
  
  Future<Uint8List?> pickImageData(ImageSource source) async{
    final xfile = await picker.pickImage(source: source);
    if(xfile == null) return null;

    return await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
  }
  Future<Uint8List?> crossFileToImageData(XFile? xfile) async{
    if(xfile == null) return null;
    return await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
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
            picker.pickImage(source: ImageSource.camera).then((xfile) => Navigator.push(context, 
                MaterialPageRoute(
                  builder: (context) => FutureBuilder(
                    future: crossFileToImageData(xfile),
                    builder: (context, snapshot) => snapshot.hasData ? TransformPage(imageData: snapshot.data!) : const LoadingPage(),
                  )
                )
              )
            );
          },
          tooltip: "Take a photo",
          child: const Icon(Icons.camera_alt),
        ),
        FloatingActionButton(
          heroTag: "2",
          onPressed: () {
            picker.pickImage(source: ImageSource.gallery).then((xfile) => Navigator.push(context, 
                MaterialPageRoute(
                  builder: (context) => FutureBuilder(
                    future: crossFileToImageData(xfile),
                    builder: (context, snapshot) => snapshot.hasData ? TransformPage(imageData: snapshot.data!) : const LoadingPage(),
                  )
                )
              )
            );
          },
          tooltip: "From gallery",
          child: const Icon(Icons.camera_alt),
        ),
      ]
    );
  }
}
