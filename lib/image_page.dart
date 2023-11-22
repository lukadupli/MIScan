import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'edit_page.dart';
import 'gallery_export.dart';
import 'helpers.dart';

class ImagePage extends StatefulWidget{
  const ImagePage({super.key, required this.imageFile});

  final File imageFile;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  late File imageFile;

  @override initState(){
    super.initState();
    imageFile = widget.imageFile;
  }

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: TextFormField(
          initialValue: removeExtension(getName(imageFile.path)),
          onFieldSubmitted: (value){
            if(value == removeExtension(getName(imageFile.path))) return;

            final newPath = "${widget.imageFile.parent.path}/$value.jpg";
            if(File(newPath).existsSync()){
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(apploc.fileExistsTitle),
                  content: Text(apploc.fileExistsContent(value)),
                  actions: [
                    TextButton(child: Text(apploc.yes), onPressed: () {Navigator.of(context).pop(); setState(() => imageFile = imageFile.renameSync(newPath));}),
                    TextButton(child: Text(apploc.cancel), onPressed: () => Navigator.of(context).pop()),
                  ]
                )
              );
            }
            else{
              setState(() => imageFile = imageFile.renameSync(newPath));
            }
          },
          style: Theme.of(context).textTheme.titleLarge,
          decoration: const InputDecoration(suffixIcon: Icon(Icons.edit))
        ),
      ),
      body: SafeArea(
        child: Flex(
          direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Center(
                child: ClipRRect(
                  child: PhotoView(
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    imageProvider: FileImage(widget.imageFile),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 5,
                  ),
                )
              ),
            ),
            SizedBox(
              height: MediaQuery.orientationOf(context) == Orientation.portrait ? 80.0 : null,
              width: MediaQuery.orientationOf(context) == Orientation.landscape ? 80.0 : null,
              child: Flex(
                direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share), 
                    tooltip: apploc.shareTooltip,
                    onPressed: () => Share.shareXFiles([XFile(widget.imageFile.path)])
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit), 
                    tooltip: apploc.editTooltip, 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditPage(imageFile: imageFile)))),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app), 
                    tooltip: apploc.exportTooltip,
                    onPressed: () => GalleryExport.export(widget.imageFile),
                  ),
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}