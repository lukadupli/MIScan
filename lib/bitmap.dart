import 'dart:typed_data';

class Bitmap{
  late final int width, height;
  late final Uint8List content;

  Bitmap.fromHeadless(this.width, this.height, this.content);
}