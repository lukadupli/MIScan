import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

import 'edit_page.dart';
import 'gallery_export.dart';
import 'helpers.dart';

class ImagePage extends StatefulWidget{
  const ImagePage({super.key, required this.imageFile});

  final File imageFile;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  late File imageFile;

  @override initState(){
    super.initState();
    imageFile = widget.imageFile;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(imageFile.path);
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: TextFormField(
          initialValue: removeExtension(getName(imageFile.path)),
          onFieldSubmitted: (value){
            if(value == removeExtension(getName(imageFile.path))) return;

            final newPath = "${widget.imageFile.parent.path}/$value.jpg";
            if(File(newPath).existsSync()){
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("File already exists"),
                  content: Text("File with the name '$value' already exists. Do you want to replace it?"),
                  actions: [
                    TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); setState(() => imageFile = imageFile.renameSync(newPath));}),
                    TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
                  ]
                )
              );
            }
            else{
              setState(() => imageFile = imageFile.renameSync(newPath));
            }
          },
          style: Theme.of(context).textTheme.titleLarge,
          decoration: const InputDecoration(suffixIcon: Icon(Icons.edit))
        ),
      ),
      body: SafeArea(
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Center(
                child: ClipRRect(
                  child: PhotoView(
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    imageProvider: FileImage(widget.imageFile),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 5,
                  ),
                )
              ),
            ),
            SizedBox(
              height: MediaQuery.orientationOf(context) == Orientation.portrait ? 80.0 : null,
              width: MediaQuery.orientationOf(context) == Orientation.landscape ? 80.0 : null,
              child: Flex(
                direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share), 
                    tooltip: "Share",
                    onPressed: () => Share.shareXFiles([XFile(widget.imageFile.path)])
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit), 
                    tooltip: "Edit", 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditPage(imageFile: imageFile)))),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app), 
                    tooltip: "Export to gallery",
                    onPressed: () => GalleryExport.export(widget.imageFile),
                  ),
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}