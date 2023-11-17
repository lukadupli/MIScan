import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'edit_page.dart';
import 'gallery_export.dart';
import 'helpers.dart';

class ImagePage extends StatelessWidget{
  const ImagePage({super.key, required this.imageFile});
  final permission = Permission.manageExternalStorage;

  final File imageFile;

  @override
  Widget build(BuildContext context) {
    String name = removeExtension(getName(imageFile.path));

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(name)
      ),
      body: SafeArea(
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Center(
                child: Image.file(imageFile),
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
                    onPressed: () => Share.shareXFiles([XFile(imageFile.path)])
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit), 
                    tooltip: "Edit", 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditPage(imageFile: imageFile)))),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app), 
                    tooltip: "Export to gallery",
                    onPressed: () => GalleryExport.export(context: context, file: imageFile),
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