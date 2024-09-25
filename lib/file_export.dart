import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'helpers.dart';
import 'main.dart';

class FileExport{
  /// Exports a file [file] to a directory [directory] which can be public
  /// 
  /// Shows a confirmation dialog and warns user when there is already a file with the same name
  /// 
  /// Will ask for external storage management permission if [askForPermission] is set to true,
  /// but I think that the permission isn't necessary since other similar apps do not ask for it when exporting
  /// 
  /// If you wish to ask for permission, make sure to add it to *AndroidManifest.xml* file
  static Future export(File file, Directory directory, 
  {
    required String exportConfirmTitle, 
    required String exportConfirmDescription,
    required String exportConfirmation,
    bool askForPermission = false,
    Future Function(String, String)? saveFunction,
  }) async {
    return await showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text(exportConfirmTitle),
        content: Text(exportConfirmDescription),
        actions: [
          TextButton(
            child: Text(AppLocalizations.of(context)!.yes), 
            onPressed: () {
              Navigator.of(context).pop(); 
              if(askForPermission) {
                _exportWithPermission(file, directory, exportConfirmation, saveFunction);
              } else {
                _export(file, directory, exportConfirmation, saveFunction);
              }
            }
          ),
          TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () => Navigator.of(context).pop()),
        ]
      )
    );
  }

  static const permission = Permission.manageExternalStorage;
  static Future _exportWithPermission(File file, Directory dir, String confirmation, Future Function(String, String)? saveFunction) async{
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

    _export(file, dir, confirmation, saveFunction);
  }

  static Future _export(File file, Directory dir, String confirmation, Future Function(String, String)? saveFunction) async{
    final name = getName(file.path);
    final newPath = "${dir.path}/$name";

    if(await File(newPath).exists()){
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.fileExistsTitle),
          content: Text(AppLocalizations.of(context)!.fileExistsContent(name)),
          actions: [
            TextButton(child: Text(AppLocalizations.of(context)!.yes), onPressed: () {Navigator.of(context).pop(); _copyWithMessage(file, newPath, confirmation, saveFunction);}),
            TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () => Navigator.of(context).pop()),
          ]
        )
      );
    }
    else{
      _copyWithMessage(file, newPath, confirmation, saveFunction);
    }
  }

  static void _copyWithMessage(File file, String newPath, String exportConfirmation, Future Function(String, String)? saveFunction) {
    if(saveFunction == null){
      final dst = File(newPath);
      if(!dst.existsSync()) dst.createSync();
      dst.writeAsBytesSync(file.readAsBytesSync());
      
      final context = navigatorKey.currentContext!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exportConfirmation)) 
      );
    }
    else{
      saveFunction(file.path, newPath).then((_) {
        final context = navigatorKey.currentContext!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exportConfirmation)) 
        );
      });
    }
  }
}