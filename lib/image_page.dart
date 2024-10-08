import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'edit_page.dart';
import 'file_export.dart';
import 'helpers.dart';
import 'locations.dart';

import 'package:pdf/widgets.dart' as pw;

class ImagePage extends StatefulWidget{
  /// Creates a widget for showing the image from [imageFile]
  /// 
  /// Image can be renamed, exported, edited or shared
  /// 
  /// Cases when image has the same name as some other image are handled with [AlertDialog]
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

            final newPath = "${imageFile.parent.path}/$value.${getExtension(imageFile.path)}";
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
              imageFile = imageFile.renameSync(newPath);
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
                    imageProvider: FileImage(imageFile),
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
                    onPressed: () => Share.shareXFiles([XFile(imageFile.path)])
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit), 
                    tooltip: apploc.editTooltip, 
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditPage(imageFile: imageFile)))),
                  IconButton(
                    icon: const Icon(Icons.photo_library), 
                    tooltip: apploc.galleryExportTooltip,
                    onPressed: () async => await FileExport.export(imageFile, await Locations.getGallerySaveDirectory(),
                      exportConfirmTitle: apploc.exportConfirmTitle,
                      exportConfirmDescription: apploc.galleryExportConfirmContent(getName(imageFile.path)),
                      exportConfirmation: apploc.galleryExportConfirmation(getName(imageFile.path)),
                      warnIfExists: false,
                      saveFunction: (path1, path2) async{
                        await SaverGallery.saveFile(
                          file: path1, 
                          name: getName(path2), 
                          androidRelativePath: "Pictures/${Locations.galleryAlbumName}",
                          androidExistNotSave: false,
                        );
                      }
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    tooltip: apploc.pdfTooltip,
                    onPressed: () async{
                      final pdfName = removeExtension(getName(imageFile.path));
                      final pdf = pw.Document(title: pdfName);
                      final imageBytes = imageFile.readAsBytesSync();
                      pdf.addPage(pw.Page(pageFormat: PdfPageFormat.undefined, build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(imageBytes)))));

                      final pdfBytes = await pdf.save();
                      final tempFile = File("${(await getApplicationDocumentsDirectory()).path}/$pdfName.pdf");
                      tempFile.writeAsBytesSync(pdfBytes);

                      await FileExport.export(tempFile, await Locations.getDownloadsSaveDirectory(),
                        exportConfirmTitle: apploc.exportConfirmTitle,
                        exportConfirmDescription: apploc.downloadsExportConfirmContent("$pdfName.pdf"),
                        exportConfirmation: apploc.downloadsExportConfirmation("$pdfName.pdf"),
                      );
                    }
                  )
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}