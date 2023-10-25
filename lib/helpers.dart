import 'dart:ui' as ui;
import 'dart:typed_data';

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