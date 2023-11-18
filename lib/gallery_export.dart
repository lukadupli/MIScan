import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'helpers.dart';
import 'locations.dart';
import 'main.dart';

class GalleryExport{
  static const permission = Permission.manageExternalStorage;

  static void export(File file){
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text("Confirm export"),
        content: Text("Are you sure you want to export file '${getName(file.path)}' to gallery?"),
        actions: [
          TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); _exportWithPermission(file);}),
          TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
        ]
      )
    );
  }

  static Future _exportWithPermission(File file) async{
    var status = await permission.request();
    bool cancelled = false;
    
    while(status != PermissionStatus.granted){
      if(status == PermissionStatus.permanentlyDenied){
        bool flag = true;
        await showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text("Unable to export"),
            content: const Text("App needs the permission to manage external storage in order to export this file"),
            actions: [
              TextButton(child: const Text("Go to settings"), onPressed: () {flag = false; openAppSettings().then((_) => flag = true); Navigator.of(context).pop();}),
              TextButton(child: const Text("Cancel"), onPressed: () {Navigator.of(context).pop(); cancelled = true;}),
            ],
          ),
          barrierDismissible: false,
        );
        while(!flag){}
      }
      else{
        await showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text("Unable to export"),
            content: const Text("App needs the permission to manage external storage in order to export this file"),
            actions: [
              TextButton(child: const Text("Try again"), onPressed: () => Navigator.of(context).pop()),
              TextButton(child: const Text("Cancel"), onPressed: () {Navigator.of(context).pop(); cancelled = true;}),
            ]
          ),
          barrierDismissible: false,
        ); 
      }

      if(cancelled) return;
      status = await permission.request();
    }

    final name = getName(file.path);
    final newPath = await _getGalleryCopyPath(name);

    if(File(newPath).existsSync()){
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text("File already exists"),
          content: Text("File with the name '$name' already exists in gallery. Do you want to replace it?"),
          actions: [
            TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); _copyWithMessage(file, newPath);}),
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
          ]
        )
      );
    }
    else{
      _copyWithMessage(file, newPath);
    }
  }

  static Future<String> _getGalleryCopyPath(String name) async{
    return "${(await Locations.getGallerySaveDirectory()).path}/$name";
  }
  static void _copyWithMessage(File file, String newPath){
    file.copySync(newPath);
    showDialog(
      context: navigatorKey.currentContext!,
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