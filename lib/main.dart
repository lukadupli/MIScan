import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'transform_page.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(),
      ),
      home: MyHomePage(title: 'Home'),
    );
  }
}

class MyHomePage extends StatelessWidget {
  MyHomePage({super.key, required this.title});

  final String title;
  final picker = ImagePicker();

  Future<Uint8List?> pickImageData() async{
    final xfile = await picker.pickImage(source: ImageSource.camera);
    if(xfile == null) return null;

    return await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          pickImageData().then(
            (data) {
              if(data == null) return;
              Navigator.push(context, MaterialPageRoute(builder: (context) => TransformPage(imageData: data)));
            },
            onError: (e) => debugPrint("Couldn't pick image! $e"),
          );
        }
      ),
    );
  }
}
