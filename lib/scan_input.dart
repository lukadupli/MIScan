import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Offset;

import 'detection/document_model.dart';
import 'helpers.dart';

/// A decoded scan photo, plus where ML detection thinks the page is.
class ScanInput {
  final ui.Image image;

  /// Detected corners normalised to [image], TL/TR/BR/BL, or null when no
  /// page was found -- including a model failure or a timeout. [TransformPage]
  /// treats null the same as "no detection ran": it starts from the image's
  /// own corners.
  final List<Offset>? corners;

  const ScanInput(this.image, this.corners);
}

/// A few seconds is generous next to the ~215-233 ms detection measured on a
/// photo (see HANDOFF-document-detection.md); it only matters on a much
/// slower device or a cold model load.
const _detectionTimeout = Duration(seconds: 5);

/// Loads the image at [path] and runs document detection on it, for the
/// scanner camera and the gallery import alike.
///
/// Any detection failure or timeout is swallowed -- there is no page-not-found
/// UI, so a slow or missing model should look exactly like "no page found".
/// When [deleteFile], the file at [path] is removed once it has been decoded
/// (a scanner capture is a temp file nothing else points at; a gallery pick
/// is not, so callers leave it alone).
Future<ScanInput> prepareScanInput(String path, {bool deleteFile = false}) async{
  final image = await loadImageFile(path);
  if(deleteFile){
    try {
      await File(path).delete();
    } catch (_) {}
  }

  List<Offset>? corners;
  try {
    final model = await DocumentModel.shared();
    corners = await model.detectImage(image).timeout(_detectionTimeout);
  } catch (_) {
    corners = null;
  }
  return ScanInput(image, corners);
}
