import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Scales [value] from range [oldMin], [oldMax] to range [newMin], [newMax]
double scale(double value, double oldMin, double oldMax, double newMin, double newMax){
  return (value - oldMin) * (newMax - newMin) / (oldMax - oldMin) + newMin;
}

/// computes square of [value]
double sq(double x) => x * x;

/// computes cube of [value]
double cb(double x) => x * x * x;

/// Creates an [ui.Image] from [Uint8List]
Future<ui.Image> bytesToImage(Uint8List imgBytes) async{
  ui.Codec codec = await ui.instantiateImageCodec(imgBytes);
  ui.FrameInfo frame;
  try {
    frame = await codec.getNextFrame();
  } finally {
    codec.dispose();
  }
  return frame.image;
}

/// Generates an image name in form *Scan_YYYYMMDD_HHMMSS.[format]*
String generateImageName({required String format}){
  final now = DateTime.now();
  return "Scan_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.$format";
}

/// Gets the extension from [path], returns an empty string if there is no extension
String getExtension(String path){
  final splitted = path.split('.');
  if(splitted.length == 1) return "";
  return splitted.last;
}

/// Gets name of the file/directory from [path], including possible extensions
String getName(String path){
  return path.split('/').last;
}

/// Returns the [name] without the extension
String removeExtension(String name){
  final lim = name.lastIndexOf('.');
  if(lim == -1) return name;
  return name.substring(0, lim);
}

Future<dynamic> cannotTransformDialog(BuildContext context, AppLocalizations apploc) {
    return showDialog(
                  context: context, 
                  builder: (context) => AlertDialog.adaptive(
                    title: Text(apploc.cannotTransformTitle),
                    content: Text(apploc.cannotTransformContent),
                    actions: [TextButton(child: Text(apploc.ok), onPressed: () => Navigator.of(context).pop())]
                  )
                );
  }