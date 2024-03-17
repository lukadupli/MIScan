import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'cubic_spline.dart';

final DynamicLibrary dll = Platform.isAndroid ? DynamicLibrary.open("libstraighten.so") : DynamicLibrary.process();

final _prepare = dll.lookupFunction<Void Function(Bool, Bool), void Function(bool, bool)>("Prepare");

final _canTransform = dll.lookupFunction<
Bool Function(Double, Double, Double, Double, Double, Double, Double, Double), 
bool Function(double, double, double, double, double, double, double, double)>
("CanTransform");

final _loadCoordinates = dll.lookupFunction<
Bool Function(Double, Double, Double, Double, Double, Double, Double, Double), 
bool Function(double, double, double, double, double, double, double, double)>
("LoadCoordinates");

final _getWidth = dll.lookupFunction<Int32 Function(), int Function()>("GetWidth");
final _getHeight = dll.lookupFunction<Int32 Function(), int Function()>("GetHeight");
final _getRequiredDstSize = dll.lookupFunction<Int32 Function(Int32), int Function(int)>("GetRequiredDstSize");

final _process = dll.lookupFunction<
Void Function(Pointer<Uint8>, Int32, Int32, Int32, Pointer<Uint8>), 
void Function(Pointer<Uint8>, int, int, int, Pointer<Uint8>)>
("Process");

final _bookLoadCoordinates = dll.lookupFunction<
Bool Function(Pointer<Double>, Pointer<Double>, Int32, Pointer<Double>, Pointer<Double>, Bool),
bool Function(Pointer<Double>, Pointer<Double>, int, Pointer<Double>, Pointer<Double>, bool)>
("BookLoadCoordinates");

final _bookProcess = dll.lookupFunction<
Void Function(Pointer<Uint8>, Int32, Int32, Int32, Pointer<Uint8>), 
void Function(Pointer<Uint8>, int, int, int, Pointer<Uint8>)>
("BookProcess");

class QuadTransform{
  static Bitmap? _transform(Uint8List srcList, int width, int height, Offset a, Offset b, Offset c, Offset d){
    _prepare(false, false); // is input padded and is output padded
    if(!_loadCoordinates(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy, d.dx, d.dy)) return null;

    final src = malloc.allocate<Uint8>(srcList.length);
    src.asTypedList(srcList.length).setAll(0, srcList);

    int size = _getRequiredDstSize(4); //RGBA - 4 bytes per pixel
    final dst = malloc.allocate<Uint8>(size);

    _process(src, width, height, 4, dst);

    final dstList = dst.asTypedList(size);
    final result = Bitmap.fromHeadless(_getWidth(), _getHeight(), Uint8List.fromList(dstList));

    malloc.free(src);
    malloc.free(dst);

    return result;
  }

  /// Checks if these coordinates can be linearly transformed to make a rectangle
  /// 
  /// The coordinates are given in counterclockwise order, starting from bottom left coordinate
  static bool canTransform(Offset a, Offset b, Offset c, Offset d) => _canTransform(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy, d.dx, d.dy);

  /// Linearly transforms [image] so that the coordinates given form a rectangular border of the new image,
  /// i.e. performs a quadrilateral transformation of an image
  /// 
  /// The coordinates are given in counterclockwise order, starting from bottom left coordinate
  /// 
  /// Throws a [FormatException] if the coordinates cannot be uniquely transformed to make a rectangle
  static Future<Bitmap> transform(ui.Image image, Offset a, Offset b, Offset c, Offset d) async{
    final byteData = (await image.toByteData())!;

    transform((Uint8List, int, int, Offset, Offset, Offset, Offset) data) => _transform(data.$1, data.$2, data.$3, data.$4, data.$5, data.$6, data.$7);
    final raw = await compute(transform, (byteData.buffer.asUint8List(), image.width, image.height, a, b, c, d));
    if(raw == null) throw const FormatException("Cannot uniquely transform from these points");

    return raw;
  }
}

class BookTransform{
  static Bitmap? _transform(Uint8List srcList, int width, int height, List<Offset> corners, List<Offset> curve, bool curvePosition){
    if(corners.length != 4) throw const FormatException("Corners have to contain 4 elements - the corners of the paper");
    if(curve.length < 2) throw const FormatException("Curve has to contain its endpoints so the minimum length of curve is 2");

    _prepare(false, false); // is input padded and is output padded

    final cornersXPtr = malloc.allocate<Double>(4 * sizeOf<Double>());
    final cornersYPtr = malloc.allocate<Double>(4 * sizeOf<Double>());
    for(int i = 0; i < 4; i++){
      cornersXPtr[i] = corners[i].dx;
      cornersYPtr[i] = corners[i].dy;
    }

    final curveXPtr = malloc.allocate<Double>(curve.length * sizeOf<Double>());
    final curveYPtr = malloc.allocate<Double>(curve.length * sizeOf<Double>());
    for(int i = 0; i < curve.length; i++){
      curveXPtr[i] = curve[i].dx;
      curveYPtr[i] = curve[i].dy;
    }

    if(!_bookLoadCoordinates(cornersXPtr, cornersYPtr, curve.length, curveXPtr, curveYPtr, curvePosition)) return null;

    malloc.free(cornersXPtr);
    malloc.free(cornersYPtr);
    malloc.free(curveXPtr);
    malloc.free(curveYPtr);

    final src = malloc.allocate<Uint8>(srcList.length);
    src.asTypedList(srcList.length).setAll(0, srcList);

    int size = _getRequiredDstSize(4); //RGBA - 4 bytes per pixel
    final dst = malloc.allocate<Uint8>(size);

    _bookProcess(src, width, height, 4, dst);

    final dstList = dst.asTypedList(size);
    final result = Bitmap.fromHeadless(_getWidth(), _getHeight(), Uint8List.fromList(dstList));

    malloc.free(src);
    malloc.free(dst);

    return result;
  }
  static Bitmap? _transformFromSpline(Uint8List srcList, int width, int height, List<Offset> corners, CubicSpline spline, bool curvePosition, {double ratio = 1.0}){
    final points = <Offset>[];
    if(!curvePosition){
      for(double x = corners[0].dx; x <= corners[1].dx; x++){
        points.add(Offset(x, spline.compute(x / ratio) * ratio));
      }
    }
    else{
      for(double x = corners[3].dx; x <= corners[2].dx; x++){
        points.add(Offset(x, spline.compute(x / ratio) * ratio));
      }
    }

    return _transform(srcList, width, height, corners, points, curvePosition);
  }

  static bool canTransform(List<Offset> corners) => _canTransform(corners[0].dx, corners[0].dy, corners[1].dx, corners[1].dy, corners[2].dx, corners[2].dy, corners[3].dx, corners[3].dy);

  /// Transforms [image] so that the book page whose corners are given by [corners] so that it appears straight
  /// Points in [curve] represent the curvature of the page, it has to contain its endpoints
  /// [curvePosition] false means that the curve is between bottom-left and bottom-right corner points
  /// [curvePosition] true means that the curve is between top-left and top-right corner points
  /// 
  /// The coordinates are given in counterclockwise order, starting from bottom left coordinate
  /// 
  /// Throws a [FormatException] if the coordinates cannot be uniquely transformed to make a rectangle
  static Future<Bitmap> transform(ui.Image image, List<Offset> corners, List<Offset> curve, bool curvePosition) async{
    final byteData = (await image.toByteData())!;

    transform((Uint8List, int, int, List<Offset>, List<Offset>, bool) data) => _transform(data.$1, data.$2, data.$3, data.$4, data.$5, data.$6);
    final raw = await compute(transform, (byteData.buffer.asUint8List(), image.width, image.height, corners, curve, curvePosition));
    if(raw == null) throw const FormatException("Cannot uniquely transform from these points");

    return raw;
  }

  /// corners have to be ratioed, ratio is applied only on spline
  static Future<Bitmap> transformFromSpline(ui.Image image, List<Offset> corners, CubicSpline spline, bool curvePosition, {double ratio = 1.0}) async{
    final byteData = (await image.toByteData())!;

    transform((Uint8List, int, int, List<Offset>, CubicSpline, bool, double) data) => _transformFromSpline(data.$1, data.$2, data.$3, data.$4, data.$5, data.$6, ratio: data.$7);
    final raw = await compute(transform, (byteData.buffer.asUint8List(), image.width, image.height, corners, spline, curvePosition, ratio));
    if(raw == null) throw const FormatException("Cannot uniquely transform from these points");

    return raw;
  }
}