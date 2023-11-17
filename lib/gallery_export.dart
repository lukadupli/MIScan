import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'helpers.dart';
import 'locations.dart';

class GalleryExport{
  static const permission = Permission.manageExternalStorage;

  static void export({required BuildContext context, required File file}){
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm export"),
        content: Text("Are you sure you want to export file '${getName(file.path)}' to gallery?"),
        actions: [
          TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); _exportToGalleryWithPermission(context, file);}),
          TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
        ]
      )
    );
  }
  static void _exportToGalleryWithPermission(BuildContext context, File file) {
    final name = getName(file.path);
    permission.request().then(
      (status){
        if(status == PermissionStatus.permanentlyDenied){
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Unable to export"),
              content: const Text("App needs the permission to manage external storage in order to export this file"),
              actions: [
                TextButton(child: const Text("Go to settings"), onPressed: () {openAppSettings(); Navigator.of(context).pop();}),
                TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
              ]
            )
          );
        }
        else if(status != PermissionStatus.granted){
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Unable to export"),
              content: const Text("App needs the permission to manage external storage in order to export this file"),
              actions: [
                TextButton(child: const Text("Try again"), onPressed: () {Navigator.of(context).pop(); 
                _exportToGalleryWithPermission(context, file);}),
                TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
              ]
            )
          );
        }
        else{
          _getGalleryCopyPath(name).then(
            (newPath){
              if(File(newPath).existsSync()){
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("File already exists"),
                    content: Text("File with the name '$name' already exists in gallery. Do you want to replace it?"),
                    actions: [
                      TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); _copyWithMessage(context, file, newPath);}),
                      TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
                    ]
                  )
                );
              }
              else{
                _copyWithMessage(context, file, newPath);
              }
            }
          );
        }
      }
    );
  }
  static Future<String> _getGalleryCopyPath(String name) async{
    return "${(await Locations.getGallerySaveDirectory()).path}/$name";
  }
  static void _copyWithMessage(BuildContext context, File file, String newPath){
    file.copySync(newPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Export complete"),
        content: Text("File '${getName(newPath)}' successfully exported to gallery"),
        actions: [
          TextButton(child: const Text("OK"), onPressed: () => Navigator.of(context).pop()),
        ]
      )
    );
  }
}