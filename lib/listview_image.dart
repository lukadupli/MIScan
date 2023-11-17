import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'gallery_export.dart';
import 'helpers.dart';
import 'image_page.dart';

class ListViewImage extends StatelessWidget{
  final File imageFile;
  final DateTime time;
  final double height;
  final int index;
  final void Function(int) onDeletion;

  const ListViewImage({super.key, required this.imageFile, required this.height, required this.time, required this.index, required this.onDeletion});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: InkWell(
        onTap: () => Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (context) => ImagePage(imageFile: imageFile),
          )
        ),
        child: Row(
          children: [
            Container(
              width: height, 
              height: height, 
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                image: DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover)
              )
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(removeExtension(getName(imageFile.path))),
                      subtitle: Text(formatDateTime(time)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(icon: const Icon(Icons.share), tooltip: "Share", onPressed: () => Share.shareXFiles([XFile(imageFile.path)])),
                      IconButton(icon: const Icon(Icons.delete), tooltip: "Delete", onPressed: () => onDeletion(index)),
                      IconButton(icon: const Icon(Icons.exit_to_app), tooltip: "Export to gallery", onPressed: () => 
                      GalleryExport.export(context: context, file: imageFile)),
                    ],
                  )
                ]
              ),
            )
          ]
        ),
      )
    );
  }
}