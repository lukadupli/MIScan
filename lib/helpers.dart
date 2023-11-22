import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:core';

double scale(double value, double oldMin, double oldMax, double newMin, double newMax){
  return (value - oldMin) * (newMax - newMin) / (oldMax - oldMin) + newMin;
}
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
String generateImageName({required String format}){
  final now = DateTime.now();
  return "Scan_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.$format";
}

String getExtension(String path){
  final splitted = path.split('.');
  if(splitted.length == 1) return "";
  return splitted.last;
}

String getName(String path){
  return path.split('/').last;
}

String removeExtension(String name){
  return name.split('.').first;
}