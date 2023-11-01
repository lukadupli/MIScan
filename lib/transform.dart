import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'helpers.dart';

final DynamicLibrary dll = Platform.isAndroid ? DynamicLibrary.open("libstraighten.so") : DynamicLibrary.process();

final _loadCornerCoordinates = 
dll.lookupFunction<Bool Function(Double, Double, Double, Double, Double, Double, Double, Double), bool Function(double, double, double, double, double, double, double, double)>("LoadCornerCoordinates");

final _getWidth = dll.lookupFunction<Uint32 Function(), int Function()>("GetWidth");
final _getHeight = dll.lookupFunction<Uint32 Function(), int Function()>("GetHeight");

final _processBitmapData = 
dll.lookupFunction<
  Void Function(Pointer<Uint8>, Uint32, Uint32, Uint32, Pointer<Uint8>, Bool), 
  void Function(Pointer<Uint8>, int, int, int, Pointer<Uint8>, bool)>
("ProcessBitmapData");

final _canTransform = 
dll.lookupFunction<Bool Function(Double, Double, Double, Double, Double, Double, Double, Double), bool Function(double, double, double, double, double, double, double, double)>("CanTransform");

bool canTransform(Offset a, Offset b, Offset c, Offset d) => _canTransform(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy, d.dx, d.dy);

Uint8List? _transform(List<dynamic> list){
  final srcList = list[0] as Uint8List;
  final width = list[1] as int;
  final height = list[2] as int;
  final a = list[3] as Offset;
  final b = list[4] as Offset;
  final c = list[5] as Offset;
  final d = list[6] as Offset;

  if(!_loadCornerCoordinates(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy, d.dx, d.dy)) return null;

  final src = malloc.allocate<Uint8>(srcList.length);
  src.asTypedList(srcList.length).setAll(0, srcList);

  int neww = _getWidth(), newh = _getHeight();
  final dst = malloc.allocate<Uint8>(neww * newh * 4); //RGBA

  _processBitmapData(src, width, height, 4, dst, true);

  final dstList = dst.asTypedList(neww * newh * 4);
  
  final resultBmp = Bitmap.fromHeadless(neww, newh, dstList);
  final result = resultBmp.buildHeaded();

  malloc.free(src);
  malloc.free(dst);

  return result;
}

Future<ui.Image> transform(ui.Image image, Offset a, Offset b, Offset c, Offset d) async{
  final byteData = (await image.toByteData())!;

  final raw = await compute(_transform, [byteData.buffer.asUint8List(), image.width, image.height, a, b, c, d]);
  if(raw == null) throw const FormatException("Cannot uniquely transform from these points");

  return await bytesToImage(raw);
}