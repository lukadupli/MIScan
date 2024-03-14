// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'helpers.dart';
import 'corner_showcase.dart';
import 'frame.dart';
import 'loading_page.dart';
import 'transform.dart';
import 'edit_page.dart';
import 'jpg_encode.dart';
import 'dart:ui' as ui;

class TransformPage extends StatefulWidget{
  final ui.Image image;

  /// Creates a page which uses a [Frame] to select the corners to quadrilateraly transform an [image] and save it in JPEG format
  const TransformPage({super.key, required this.image});

  @override
  State<TransformPage> createState() => _TransformPageState();
}

class _TransformPageState extends State<TransformPage> {
  final fController = FrameController();
  late double ratio;
  
  int active = 0;
  final showcaseAlignment = ValueNotifier<bool?>(null);
  final showcasePosition = ValueNotifier<Offset>(Offset.zero);

  static const double frameCornerDimension = 50.0;
  static const double showcaseSizeDimension = 100.0;
  static const double showcaseSegmentDimension = 200.0;

  bool getAlignment(Offset position, Size imageSize){
    return position.dx < imageSize.width / 2 && position.dy < imageSize.height / 2;
  }

  Widget buildShowcase(){
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: CornerShowcase(
        size: const Size(showcaseSizeDimension, showcaseSizeDimension),
        image: widget.image,
        imageSegmentSize: const Size(showcaseSegmentDimension, showcaseSegmentDimension),
        positionNotifier: showcasePosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context){
    final apploc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(apploc.transformPageTitle),
      ),
      body: SafeArea(
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              child: Center(
                child: Stack(
                  children: [
                    Frame(
                      controller: fController,
                      cornerSize: frameCornerDimension,
                      margin: const EdgeInsets.all(frameCornerDimension / 4),
                      whenResized: () => ratio = widget.image.width / fController.childSize.width,
                      onDragStart: (index){
                        active++;
                        if(active == 2) showcaseAlignment.value = null;
                      },
                      onPositionChange: (index) {
                        if(active != 1) return;
                    
                        final properAlignment = getAlignment(fController.corners[index], fController.childSize);
                        if(showcaseAlignment.value != properAlignment) showcaseAlignment.value = properAlignment;
                        
                        showcasePosition.value = fController.corners[index] * ratio;
                      },
                      onDragEnd: (index) {
                        active--;
                        if(active == 0) showcaseAlignment.value = null;
                      }, 
                      child: RawImage(image: widget.image),
                    ),
                    ValueListenableBuilder(
                      valueListenable: showcaseAlignment,
                      builder: (context, alignment, child) => alignment != null ? Positioned.fill(
                        child: Align(
                          alignment: alignment ? Alignment.topRight : Alignment.topLeft,
                          child: child,
                        ),
                      ) : const SizedBox.shrink(),
                      child: buildShowcase(),
                    ),
                  ],
                ),
              ),
            ),
            OutlinedButton(
              child: const Icon(Icons.check),
              onPressed: () {
                if(!QuadTransform.canTransform(
                  fController.corners[0] * ratio, 
                  fController.corners[1] * ratio, 
                  fController.corners[2] * ratio,
                  fController.corners[3] * ratio,
                )){
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
                  future: _transformAndSaveToTemporary(),
                  builder: (context, snapshot) => snapshot.hasData ? EditPage(imageFile: snapshot.data!) : const LoadingPage(),
                )));
              }
            ),
          ]
        ),
      ),
    );
  }

  Future<File> _transformAndSaveToTemporary() async{
    final transformed = await QuadTransform.transform(
      widget.image, 
      fController.corners[0] * ratio, 
      fController.corners[1] * ratio, 
      fController.corners[2] * ratio,
      fController.corners[3] * ratio,
    );

    final path = "${(await getTemporaryDirectory()).path}/${generateImageName(format: "jpg")}";
    final file = File(path);

    await JpgEncode.encodeToFile(file.path, transformed.content, transformed.width, transformed.height, 4); // 4 channels - RGBA

    return file;
  }
}
