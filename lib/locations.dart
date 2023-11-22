import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';

class Locations{
  static const String galleryAlbumName = "MIScan exports";

  static Future<Directory> getAppInternalSaveDirectory() async{
    final path = "${(await getApplicationDocumentsDirectory()).path}/Scans";
    final dir = Directory(path);
    if(!await dir.exists()) await dir.create();
    return dir;
  }
  static Future<Directory> getGallerySaveDirectory() async{
    final path = "${await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_PICTURES)}/$galleryAlbumName";
    final dir = Directory(path);
    if(!await dir.exists()) await dir.create();
    return dir;
  }
}