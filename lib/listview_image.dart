import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:io';
import 'gallery_export.dart';
import 'helpers.dart';
import 'image_page.dart';

class ListViewImage extends StatelessWidget{
  final File imageFile;
  final DateTime time;
  final double height;
  final int index;
  final void Function(int) onDeletion;

  const ListViewImage({super.key, required this.imageFile, required this.height, required this.time, required this.index, required this.onDeletion});

  @override
  Widget build(BuildContext context) {
    final apploc = AppLocalizations.of(context)!;

    return SizedBox(
      height: height,
      child: InkWell(
        onTap: () => Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (context) => ImagePage(imageFile: imageFile),
          )
        ),
        child: Row(
          children: [
            Container(
              width: height, 
              height: height, 
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                image: DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover)
              )
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(removeExtension(getName(imageFile.path))),
                      subtitle: Text(_formatDateTime(apploc, time)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(icon: const Icon(Icons.share), tooltip: apploc.shareTooltip, onPressed: () => Share.shareXFiles([XFile(imageFile.path)])),
                      IconButton(icon: const Icon(Icons.delete), tooltip: apploc.deleteTooltip, onPressed: () => onDeletion(index)),
                      IconButton(icon: const Icon(Icons.exit_to_app), tooltip: apploc.exportTooltip, onPressed: () => 
                      GalleryExport.export(imageFile)),
                    ],
                  )
                ]
              ),
            )
          ]
        ),
      )
    );
  }

  String _formatDateTime(AppLocalizations apploc, DateTime time){
    final date = DateTime(time.year, time.month, time.day);

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    if(date == today) return "${apploc.today}, ${DateFormat.jm(apploc.localeName).format(time)}";
    if(date == yesterday) return "${apploc.yesterday}, ${DateFormat.jm(apploc.localeName).format(time)}";
    return DateFormat.yMMMd(apploc.localeName).format(time);
  }
}