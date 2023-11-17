import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:straighten/transform_page.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'helpers.dart';
import 'loading_page.dart';
import 'listview_image.dart';
import 'locations.dart';

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
    final dir = await Locations.getAppInternalSaveDirectory();

    final entities = dir.listSync();
    final files = [for(final item in entities) (item as File, (await FileStat.stat(item.path)).modified)];

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
      body = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text("No recent scans!"), Text("Create a new scan by clicking on the button below!")]
      );
    }
    else{
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.all(8.0), child: Text("Recent scans", style: Theme.of(context).textTheme.titleLarge)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0), 
              child: ListView.separated(
                itemBuilder: (context, index){
                  return ListViewImage(imageFile: files![index].$1, time: files![index].$2, height: MediaQuery.orientationOf(context) == Orientation.portrait ? 100 : 150, index: index, 
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
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Container(height: 1, color: Colors.black26));
                },
                itemCount: files!.length,
              ),
            )
          ),
        ]
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
      floatingActionButton: FloatingActionButton(
        onPressed: _getImage,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  void _getImage(){
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import from: "),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            importImageButton(source: ImageSource.camera, icon: const Icon(Icons.camera_alt), label: "Camera"),
            importImageButton(source: ImageSource.gallery, icon: const Icon(Icons.image), label: "Gallery")
          ]
        )
      ),
    );
  }

  Widget importImageButton({required ImageSource source, required Icon icon, required String label}) {
    return ElevatedButton.icon(
      icon: icon,
      label: Text(label),
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
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
    );
  }
}
