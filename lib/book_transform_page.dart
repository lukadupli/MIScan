import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:ui' as ui;

import 'book_frame.dart';
import 'frame.dart';

class BookTransformPage extends StatefulWidget{
  final ui.Image image;
  late final BookFrameController controller;

  BookTransformPage({super.key, required this.image, required FrameController fController}){
    controller = BookFrameController(splinePoints: 2, corners: fController.corners, boundary: fController.boundary);
  }

  @override
  State<StatefulWidget> createState() => _BookTransformPageState();
}

class _BookTransformPageState extends State<BookTransformPage>{
  late double ratio;

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(apploc.transformPageTitle),
      ), 
      body: SafeArea(
        child: Center(
          child: BookFrame(
            controller: widget.controller,
            margin: const EdgeInsets.all(12.5),
            whenResized: () => ratio = widget.image.width / widget.controller.childSize.width,
            child: RawImage(image: widget.image),
          ),
        ),
      ),
    );
  }
}