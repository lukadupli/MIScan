import 'dart:io';
import 'package:native_exif/native_exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'main.dart';
import 'image_page.dart';
import 'helpers.dart';
import 'locations.dart';

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

  static int _orientToTurns(int orient){
    if(orient == 6) return 1;
    if(orient == 3) return 2;
    if(orient == 8) return 3;
    return 0;
  }
  static int _turnsToOrient(int turns){
    if(turns == 1) return 6;
    if(turns == 2) return 3;
    if(turns == 3) return 8;
    return 1;
  }
  static Future<void> _edit(String path, int turns) async {
    if(turns == 0) return;

    final exif = await Exif.fromPath(path);
    final orient = await exif.getAttribute("Orientation");

    int realTurns = (turns + _orientToTurns(int.parse(orient))) % 4;

    await exif.writeAttribute("Orientation", _turnsToOrient(realTurns).toString());
  }

  Future<void> _saveAndPop(File file) async{
    if(file.path != widget.imageFile.path) await widget.imageFile.copy(file.path);
    await _edit(file.path, turns);

    await FileImage(file).evict();
    Navigator.popUntil(navigatorKey.currentContext!, (route) => route.isFirst); 
    Navigator.push(navigatorKey.currentContext!, MaterialPageRoute(builder: (context) => ImagePage(imageFile: file)));
  }

  Future<void> _save() async{
    final dir = await Locations.getAppInternalSaveDirectory();
    final file = File("${dir.path}/$name");
    if(file.path != widget.imageFile.path && await file.exists()){
      showDialog(
        context: navigatorKey.currentContext!,
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