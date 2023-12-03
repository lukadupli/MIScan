import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';

final DynamicLibrary dll = Platform.isAndroid ? DynamicLibrary.open("libjpg_encode.so") : DynamicLibrary.process();
final _jpgEncodeToFile = dll.lookupFunction<Bool Function(Pointer<Utf8>, Pointer<Uint8>, Int, Int, Int), 
  bool Function(Pointer<Utf8>, Pointer<Uint8>, int, int, int)>("JpgEncodeToFile");

class JpgEncode{
  static bool encodeToFile(String filename, Uint8List imageData, int width, int height, int channels){
    final src = malloc.allocate<Uint8>(imageData.length);
    src.asTypedList(imageData.length).setAll(0, imageData);

    final fnamePtr = filename.toNativeUtf8();

    final result = _jpgEncodeToFile(fnamePtr, src, width, height, channels);

    malloc.free(fnamePtr);
    malloc.free(src);

    return result;
  }
  static Future<bool> encodeToFileAsync(String filename, Uint8List imageData, int width, int height, int channels) async{
    bool encode((String, Uint8List, int, int, int) data) => encodeToFile(data.$1, data.$2, data.$3, data.$4, data.$5);
    return await compute(encode, (filename, imageData, width, height, channels));
  }
}