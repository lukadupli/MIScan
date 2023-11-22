import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'image_page.dart';
import 'loading_page.dart';
import 'helpers.dart';
import 'locations.dart';

import 'package:image/image.dart' as img;

class EditPage extends StatefulWidget{
  final File imageFile;
  const EditPage({super.key, required this.imageFile});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  int turns = 0;
  late String name;

  @override
  void initState(){
    super.initState();
    name = "${removeExtension(getName(widget.imageFile.path))}.jpg";
  }

  static String _editAndSave(List list) {
    final path1 = list[0] as String;
    final path2 = list[1] as String;
    final turns = list[2] as int;
    
    final file1 = File(path1);

    var image = img.decodeNamedImage(path1, file1.readAsBytesSync())!;
    if(turns != 0) image = img.copyRotate(image, angle: turns * 90);
    
    final file2 = File(path2);
    file2.writeAsBytesSync(img.encodeJpg(image));

    return path2;
  }

  void _saveAndPop(File file){
    Navigator.push(context, MaterialPageRoute(builder: (context) => const LoadingPage()));
    compute(_editAndSave, [widget.imageFile.path, file.path, turns]).then(
      (_) => FileImage(file).evict().then((_) {
        Navigator.popUntil(context, (route) => route.isFirst); 
        Navigator.push(context, MaterialPageRoute(builder: (context) => ImagePage(imageFile: file)));
      }),
    );
  }
  void _save() {
    Locations.getAppInternalSaveDirectory().then(
      (dir){
        final file = File("${dir.path}/$name");
        if(file.existsSync()){
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.fileExistsTitle),
              content: Text(AppLocalizations.of(context)!.fileExistsContent(name)),
              actions: [
                TextButton(child: Text(AppLocalizations.of(context)!.yes), onPressed: () {Navigator.of(context).pop(); _saveAndPop(file);}),
                TextButton(child: Text(AppLocalizations.of(context)!.cancel), onPressed: () => Navigator.of(context).pop()),
              ]
            )
          );
        }
        else{
          _saveAndPop(file);
        }
      }
    );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: TextFormField(
          initialValue: removeExtension(name),
          onChanged: (value) => name = "$value.jpg",
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
                child: RotatedBox(
                  quarterTurns: turns,
                  child: Image.file(widget.imageFile),
                ),
              ),
            ),
            SizedBox(
              height: MediaQuery.orientationOf(context) == Orientation.portrait ? 80.0 : null,
              width: MediaQuery.orientationOf(context) == Orientation.landscape ? 80.0 : null,
              child: Flex(
                direction: MediaQuery.orientationOf(context) == Orientation.portrait ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: const Icon(Icons.rotate_left ), onPressed: () => setState(() => turns = (turns + 3) % 4)),
                  IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setState(() => turns = (turns + 1) % 4)),
                  IconButton(icon: const Icon(Icons.done), onPressed: () => _save()),
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}