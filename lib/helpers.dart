import 'dart:ui' as ui;
import 'dart:typed_data';

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