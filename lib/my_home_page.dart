import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:miscan/l10n/app_localizations.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'helpers.dart';
import 'transform_page.dart';
import 'loading_page.dart';
import 'listview_image.dart';
import 'locations.dart';

class MyHomePage extends StatefulWidget {
  /// App's home page
  /// 
  /// Previous scans are shown in a [ListView] as [ListViewImage]s
  /// 
  /// New image can be imported from camera or from gallery using a [FloatingActionButton]
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<(File, DateTime)>? files;

  Future<ui.Image> crossFileToImage(XFile xfile) async{
    final raw = await (await FlutterExifRotation.rotateImage(path: xfile.path)).readAsBytes();
    return await bytesToImage(raw);
  }

  Future<List<(File, DateTime)>> _getImageFiles() async{
    final dir = await Locations.getAppInternalSaveDirectory();

    final entities = dir.listSync();
    final files = [for(final item in entities) (item as File, (await FileStat.stat(item.path)).modified)];

    // sort files by last modification time
    files.sort((a, b) => b.$2.compareTo(a.$2));
    return files;
  }

  @override
  Widget build(BuildContext context){
    final apploc = AppLocalizations.of(context)!;
    _getImageFiles().then((result) => setState(() => files = result));
    late Widget body;
    if(files == null){
      body = const Center(child: SizedBox(width: 60.0, height: 60.0, child: CircularProgressIndicator()));
    }
    else if(files!.isEmpty){
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Center(child: Text(apploc.noScansYet)), Center(child: Text(apploc.tipForCreatingScans))]
      );
    }
    else{
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.all(8.0), child: Text(apploc.scanListTitle, style: Theme.of(context).textTheme.titleLarge)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0), 
              child: ListView.separated(
                itemBuilder: (context, index){
                  return ListViewImage(
                    key: ValueKey(files![index].$2), // forces rebuild when image is modified
                    imageFile: files![index].$1, 
                    time: files![index].$2, 
                    height: MediaQuery.orientationOf(context) == Orientation.portrait ? 100 : 150, 
                    index: index, 
                    onDeletion: (deleted){
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog.adaptive(
                          title: Text(apploc.confirmDeletionTitle),
                          content: Text(apploc.confirmDeletionContent(getName(files![deleted].$1.path))),
                          actions: [
                            TextButton(child: Text(apploc.yes), onPressed: (){
                              files![deleted].$1.deleteSync();
                              files!.removeAt(deleted);
                              Navigator.of(context).pop();
                              setState((){});
                            }),
                            TextButton(child: Text(apploc.cancel), onPressed: () => Navigator.of(context).pop()),
                          ]
                        )
                      );
                    }
                  );
                },
                separatorBuilder: (context, index){
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Container(height: 1, color: Colors.black12));
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
              TextSpan(text: " ${apploc.homePageTitle}", style: Theme.of(context).textTheme.titleLarge),
            ]
          )
        )
      ),
      body: SafeArea(
        child: body,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getImage,
        tooltip: apploc.newScanTooltip,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  void _getImage(){
    final apploc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(apploc.chooseSourceTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            importImageButton(source: ImageSource.camera, icon: const Icon(Icons.camera_alt), label: apploc.imageSource("camera")),
            importImageButton(source: ImageSource.gallery, icon: const Icon(Icons.image), label: apploc.imageSource("gallery"))
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
        ImagePicker().pickImage(source: source).then((xfile) {
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
