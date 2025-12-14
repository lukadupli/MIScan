import 'dart:io';

import 'package:flutter/material.dart';
import 'package:miscan/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;

import 'book_frame.dart';
import 'edit_page.dart';
import 'frame.dart';
import 'helpers.dart';
import 'jpg_encode.dart';
import 'loading_page.dart';
import 'main.dart';
import 'transform.dart';

class BookTransformPage extends StatefulWidget{
  final ui.Image image;
  late final BookFrameController controller;

  /// Page for performing book transform
  /// 
  /// This is only called from [TransformPage] and [fController] is a copy of [TransformPage]'s [FrameController]
  BookTransformPage({super.key, required this.image, required FrameController fController}){
    controller = BookFrameController(splinePoints: 4, corners: fController.corners, boundary: fController.boundary);
  }

  @override
  State<StatefulWidget> createState() => _BookTransformPageState();
}

class _BookTransformPageState extends State<BookTransformPage>{
  late double ratio;
  _BookTransformPageState();

  @override
  void initState(){
    super.initState();
    ratio = widget.image.width / widget.controller.childSize.width;
  }

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;
    final orient = MediaQuery.orientationOf(context);

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(apploc.bookTransformPageTitle),
      ), 
      body: SafeArea(
        child: Flex(
          direction: orient == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              child: Center(
                child: BookFrame(
                  controller: widget.controller,
                  margin: const EdgeInsets.all(12.5),
                  whenResized: () => ratio = widget.image.width / widget.controller.childSize.width,
                  child: RawImage(image: widget.image),
                ),
              ),
            ),
            OutlinedButton(
              child: const Icon(Icons.check),
              onPressed: () {
                final corners = List<Offset>.generate(4, (i) => widget.controller.corners[i] * ratio);

                if(!BookTransform.canTransform(corners)){
                  cannotTransformDialog(context, apploc);
                  return;
                }

                Navigator.push(context, MaterialPageRoute(builder: (context) => FutureBuilder(
                  future: _transformAndSaveToTemporary(corners),
                  builder: (context, snapshot) => snapshot.hasData ? EditPage(imageFile: snapshot.data!) : const LoadingPage(),
                )));
              }
            ),
          ]
        ),
      ),
    );
  }

  Future<File?> _transformAndSaveToTemporary(List<Offset> corners) async{
    try{
      final transformed = await BookTransform.transformFromSpline(
        widget.image, 
        corners,
        widget.controller.curveUp,
        false,
        ratio: ratio
      );

      final path = "${(await getTemporaryDirectory()).path}/${generateImageName(format: "jpg")}";
      final file = File(path);

      await JpgEncode.encodeToFile(file.path, transformed.content, transformed.width, transformed.height, 4); // 4 channels - RGBA

      return file;
    } on FormatException {
      cannotTransformDialog(navigatorKey.currentContext!, AppLocalizations.of(navigatorKey.currentContext!)!).then(
        (_) => Navigator.of(navigatorKey.currentContext!).pop() // pop future builder
      );
    }
    return null;
  }
}