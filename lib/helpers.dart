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

String formatDateTime(DateTime time){
  final strTime = time.toString();
  final hourMinute = strTime.substring(11, 16);
  
  final date = DateTime(time.year, time.month, time.day);

  final now = DateTime.now();

  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);

  final weekAgo = DateTime(now.year, now.month, now.day - 7);

  if(date == today) return "Today, $hourMinute";
  if(date == yesterday) return "Yesterday, $hourMinute";
  if(date.isAfter(weekAgo)) return "${["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][date.weekday - 1]}, $hourMinute";
  return strTime.substring(0, 16);
}