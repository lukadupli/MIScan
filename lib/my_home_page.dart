import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:straighten/transform_page.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'helpers.dart';
import 'loading_page.dart';
import 'listview_image.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final picker = ImagePicker();
  List<(File, DateTime)>? files;

  Future<ui.Image> crossFileToImage(XFile xfile) async{
    final raw = await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
    return await bytesToImage(raw);
  }

  Future<List<(File, DateTime)>> _getImageFiles() async{
    final appDir = await getApplicationDocumentsDirectory();

    final entities = appDir.listSync();
    var files = List<(File, DateTime)>.empty(growable: true);
    for(final item in entities){
      if(item is File){
        if(["jpg", "jpeg"].contains(getExtension(item.path))){
          files.add((item, FileStat.statSync(item.path).modified));
        }
      }
    }

    files.sort((a, b) => b.$2.compareTo(a.$2));
    return files;
  }

  @override
  Widget build(BuildContext context){
    _getImageFiles().then((result) => setState(() => files = result));
    late Widget body;
    if(files == null){
      body = const Center(child: SizedBox(width: 60.0, height: 60.0, child: CircularProgressIndicator()));
    }
    else if(files!.isEmpty){
      body = const Center(child: Text("No recent scans!"));
    }
    else{
      body = ListView.separated(
        itemBuilder: (context, index){
          if(index == 0) return const SizedBox(height: 100, child: Center(child: Text("Recent scans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30))));
          return ListViewImage(imageFile: files![index - 1].$1, time: files![index - 1].$2, height: 130, index: index - 1, 
            onDeletion: (deleted){
              showDialog(
                context: context,
                builder: (context) => AlertDialog.adaptive(
                  title: const Text("Confirm deletion"),
                  content: Text("Are you sure you want to delete ${getName(files![deleted].$1.path)}?"),
                  actions: [
                    TextButton(child: const Text("Yes"), onPressed: (){
                      files![deleted].$1.delete();
                      files!.removeAt(deleted);
                      Navigator.of(context).pop();
                      setState((){});
                    }),
                    TextButton(child: const Text("No"), onPressed: () => Navigator.of(context).pop()),
                  ]
                )
              );
            }
          );
        },
        separatorBuilder: (context, index){
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Container(height: 2, color: Colors.black26));
        },
        itemCount: files!.length + 1,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: RichText(
          text: TextSpan(
            children: [
              const WidgetSpan(child: Icon(Icons.home)),
              TextSpan(text: " Home", style: Theme.of(context).textTheme.titleLarge),
            ]
          )
        )
      ),
      body: SafeArea(
        child: body,
      ),
      persistentFooterAlignment: AlignmentDirectional.bottomCenter,
      persistentFooterButtons: [
        importImageButton(context, source: ImageSource.camera, child: const Icon(Icons.camera_alt),),
        importImageButton(context, source: ImageSource.gallery, child: const Icon(Icons.image),)
      ]
    );
  }

  TextButton importImageButton(BuildContext context, {required ImageSource source, required Widget child}) {
    return TextButton(
        onPressed: () {
          picker.pickImage(source: source).then((xfile) {
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
        child: child,
      );
  }
}
