import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'helpers.dart';
import 'locations.dart';
import 'main.dart';

class GalleryExport{
  static const permission = Permission.manageExternalStorage;

  /// Exports a file [file] to gallery folder
  /// 
  /// Shows confirmation dialogs and asks for permission to manage external storage (needed for storing in external memory)
  static void export(File file){
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.exportConfirmTitle),
        content: Text(AppLocalizations.of(context)!.exportConfirmContent(getName(file.path))),
        actions: [
          TextButton(child: Text(AppLocalizations.of(context)!.yes), onPressed: () {Navigator.of(context).pop(); _exportWithPermission(file);}),
          TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () => Navigator.of(context).pop()),
        ]
      )
    );
  }

  static Future _exportWithPermission(File file) async{
    var status = await permission.request();
    bool cancelled = false;
    
    while(status != PermissionStatus.granted){
      if(status == PermissionStatus.permanentlyDenied){
        await showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.exportPermissionTitle),
            content: Text(AppLocalizations.of(context)!.exportPermissionContent),
            actions: [
              TextButton(child: Text(AppLocalizations.of(context)!.openSettings), onPressed: () => openAppSettings().then((_) => Navigator.of(context).pop())),
              TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () {Navigator.of(context).pop(); cancelled = true;}),
            ],
          ),
          barrierDismissible: false,
        );
      }
      else{
        await showDialog(
          context: navigatorKey.currentContext!,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.exportPermissionTitle),
            content: Text(AppLocalizations.of(context)!.exportPermissionContent),
            actions: [
              TextButton(child: Text(AppLocalizations.of(context)!.tryAgain), onPressed: () => Navigator.of(context).pop()),
              TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () {Navigator.of(context).pop(); cancelled = true;}),
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
          title: Text(AppLocalizations.of(context)!.fileExistsTitle),
          content: Text(AppLocalizations.of(context)!.fileExistsContent(name)),
          actions: [
            TextButton(child: Text(AppLocalizations.of(context)!.yes), onPressed: () {Navigator.of(context).pop(); _copyWithMessage(file, newPath);}),
            TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () => Navigator.of(context).pop()),
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
    final context = navigatorKey.currentContext!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.exportConfirmation(getName(newPath)))) 
    );
  }
}