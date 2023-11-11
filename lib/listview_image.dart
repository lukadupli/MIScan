import 'package:flutter/material.dart';
import 'dart:io';
import 'helpers.dart';
import 'package:share_plus/share_plus.dart';

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
        onTap: () => debugPrint("Tap"),
        child: Row(
          children: [
            SizedBox(width: MediaQuery.orientationOf(context) == Orientation.portrait ? 100 : 300, child: Image.file(imageFile)),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(getName(imageFile.path)),
                      subtitle: Text(formatDateTime(time)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(icon: const Icon(Icons.share), tooltip: "Share", onPressed: () => Share.shareXFiles([XFile(imageFile.path)])),
                      IconButton(icon: const Icon(Icons.delete), tooltip: "Delete", onPressed: () => onDeletion(index)),
                      IconButton(icon: const Icon(Icons.exit_to_app), tooltip: "Export to gallery", onPressed: (){}),
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