import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';

final DynamicLibrary dll = Platform.isAndroid ? DynamicLibrary.open("libimage_processing.so") : DynamicLibrary.process();
final _processJpg = dll.lookupFunction<Bool Function(Pointer<Utf8>, Pointer<Utf8>, Double, Double), 
  bool Function(Pointer<Utf8>, Pointer<Utf8>, double, double)>("processJpg");

class JpgProcess{
  /// Synchronously processes JPEG image at [srcPath] and saves the result at [dstPath] in JPEG format
  /// 
  /// for each pixel color x, it's new value is [contrast] * (x - 128) + 128 + [brightness]
  /// if [contrast] is 1.0 and [brightness] is 0.0, copies file at srcPath to dstPath, if the paths are same it does nothing, returns true
  /// returns if JPEG decoding/encoding succeeded
  static bool processSync(String srcPath, String dstPath, {double contrast = 1.0, double brightness = 0.0}){
    if(contrast == 1.0 && brightness == 0.0){
      if(srcPath != dstPath) File(srcPath).copySync(dstPath);
      return true;
    }
    final srcPathPtr = srcPath.toNativeUtf8();
    final dstPathPtr = dstPath.toNativeUtf8();

    final result = _processJpg(srcPathPtr, dstPathPtr, contrast, brightness);

    malloc.free(srcPathPtr);
    malloc.free(dstPathPtr);

    return result;
  }

  /// Asynchronously, in an isolate processes JPEG image at [srcPath] and saves the result at [dstPath] in JPEG format
  /// 
  /// for each pixel color x, its new value is [contrast] * (x - 128) + 128 + [brightness]
  /// if [contrast] is 1.0 and [brightness] is 0.0, copies file at srcPath to dstPath, if the paths are same it does nothing, returns true
  /// returns if JPEG decoding/encoding succeeded
  static Future<bool> process(String srcPath, String dstPath, {double contrast = 1.0, double brightness = 0.0}) async{
    if(contrast == 1.0 && brightness == 0.0){
      if(srcPath != dstPath) await File(srcPath).copy(dstPath);
      return true;
    }
    bool proc((String, String, double, double) data) => processSync(data.$1, data.$2, contrast: data.$3, brightness: data.$4);
    return await compute(proc, (srcPath, dstPath, contrast, brightness));
  }
}