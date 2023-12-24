import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:external_path/external_path.dart';

class Locations{
  /// Name of album in external gallery where images are exported
  static const String galleryAlbumName = "MIScan";

  /// Returns the directory where images are internally saved
  /// 
  /// The returned directory's path is *{applicationDocumentsDirectory}/Scans*
  /// 
  /// /// If the directory doesn't exist, it is created
  static Future<Directory> getAppInternalSaveDirectory() async{
    final path = "${(await getApplicationDocumentsDirectory()).path}/Scans";
    final dir = Directory(path);
    if(!await dir.exists()) await dir.create();
    return dir;
  }

  /// Returns the directory where images are externally saved
  /// 
  /// The returned directory's path is *{pathToExternalGallery}/[galleryAlbumName]*
  /// 
  /// If the directory doesn't exist, it is created
  static Future<Directory> getGallerySaveDirectory() async{
    final path = "${await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_PICTURES)}/$galleryAlbumName";
    final dir = Directory(path);
    if(!await dir.exists()) await dir.create();
    return dir;
  }
}