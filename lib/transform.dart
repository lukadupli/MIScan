import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'helpers.dart';

final DynamicLibrary dll = Platform.isAndroid ? DynamicLibrary.open("libstraighten.so") : DynamicLibrary.process();

final bool Function(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3) loadCornerCoordinates = 
dll.lookupFunction<Bool Function(Double, Double, Double, Double, Double, Double, Double, Double), bool Function(double, double, double, double, double, double, double, double)>("LoadCornerCoordinates");

final int Function() getWidth = dll.lookupFunction<Uint32 Function(), int Function()>("GetWidth");
final int Function() getHeight = dll.lookupFunction<Uint32 Function(), int Function()>("GetHeight");

final void Function(Pointer<Uint8> src, int srcWidth, int srcHeight, int srcChannels, Pointer<Uint8> dst, bool assureStrideDivBy4) processBitmapData = 
dll.lookupFunction<
  Void Function(Pointer<Uint8>, Uint32, Uint32, Uint32, Pointer<Uint8>, Bool), 
  void Function(Pointer<Uint8>, int, int, int, Pointer<Uint8>, bool)>
("ProcessBitmapData");

Uint8List? _transform(List<dynamic> list){
  final srcList = list[0] as Uint8List;
  final width = list[1] as int;
  final height = list[2] as int;
  final a = list[3] as Offset;
  final b = list[4] as Offset;
  final c = list[5] as Offset;
  final d = list[6] as Offset;

  if(!loadCornerCoordinates(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy, d.dx, d.dy)) return null;

  final src = malloc.allocate<Uint8>(srcList.length);
  src.asTypedList(srcList.length).setAll(0, srcList);

  int neww = getWidth(), newh = getHeight();
  final dst = malloc.allocate<Uint8>(neww * newh * 4); //RGBA

  processBitmapData(src, width, height, 4, dst, true);

  final dstList = dst.asTypedList(neww * newh * 4);
  final resultBmp = Bitmap.fromHeadless(neww, newh, dstList);
  final result = resultBmp.buildHeaded();

  malloc.free(src);
  malloc.free(dst);

  return result;
}

Future<ui.Image?> transform(ui.Image image, Offset a, Offset b, Offset c, Offset d) async{
  final byteData = await image.toByteData();
  if(byteData == null) return null;

  final raw = await compute(_transform, [byteData.buffer.asUint8List(), image.width, image.height, a, b, c, d]);

  if(raw == null) return null;
  return await bytesToImage(raw);
}