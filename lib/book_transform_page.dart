import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;

import 'book_frame.dart';
import 'edit_page.dart';
import 'frame.dart';
import 'helpers.dart';
import 'jpg_encode.dart';
import 'loading_page.dart';
import 'transform.dart';

class BookTransformPage extends StatefulWidget{
  final ui.Image image;
  late final BookFrameController controller;

  BookTransformPage({super.key, required this.image, required FrameController fController}){
    controller = BookFrameController(splinePoints: 2, corners: fController.corners, boundary: fController.boundary);
  }

  @override
  // ignore: no_logic_in_create_state
  State<StatefulWidget> createState() => _BookTransformPageState(ratio: image.width / controller.childSize.width);
}

class _BookTransformPageState extends State<BookTransformPage>{
  double ratio;
  _BookTransformPageState({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;
    final orient = MediaQuery.orientationOf(context);

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(apploc.transformPageTitle),
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
                  showDialog(
                    context: context, 
                    builder: (context) => AlertDialog.adaptive(
                      title: Text(apploc.cannotTransformTitle),
                      content: Text(apploc.cannotTransformContent),
                      actions: [TextButton(child: Text(apploc.ok), onPressed: () => Navigator.of(context).pop())]
                    )
                  );
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
  Future<File> _transformAndSaveToTemporary(List<Offset> corners) async{
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
  }
}