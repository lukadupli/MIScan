import 'dart:io';
import 'package:native_exif/native_exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'jpg_process.dart';
import 'loading_page.dart';
import 'main.dart';
import 'image_page.dart';
import 'helpers.dart';
import 'locations.dart';

class EditPage extends StatefulWidget{
  final File imageFile;

  /// Creates a page widget for editing the image from [imageFile]
  /// 
  /// Image can be renamed or rotated 90 degrees
  /// 
  /// Cases when image has the same name as some other image are handled with [AlertDialog]
  const EditPage({super.key, required this.imageFile});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  int turns = 0;
  double contrast = 1.0;
  double brightness = 0.0;
  late String name;

  /// new RGB channel value is [contrast]*(x - 128) + 128 + [brightness]
  static List<double> _getMatrix(double contrast, double brightness){
    return [
      contrast, 0, 0, 0, -128*contrast + 128 + brightness,
      0, contrast, 0, 0, -128*contrast + 128 + brightness,
      0, 0, contrast, 0, -128*contrast + 128 + brightness,
      0, 0, 0, 1, 0,
    ];
  }

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
  static Future<void> _rotate(String path, int turns) async {
    if(turns == 0) return;

    final exif = await Exif.fromPath(path);
    final orient = await exif.getAttribute("Orientation");

    int realTurns = (turns + _orientToTurns(int.parse(orient))) % 4;

    await exif.writeAttribute("Orientation", _turnsToOrient(realTurns).toString());
  }

  static Future<bool> _edit(String srcPath, String dstPath, {int turns = 0, double contrast = 1.0, double brightness = 0.0}) async{
    await JpgProcess.process(srcPath, dstPath, contrast: contrast, brightness: brightness);
    await _rotate(dstPath, turns);
    await FileImage(File(dstPath)).evict();

    return true;
  }

  void _saveAndPop(File file){
    Navigator.popUntil(navigatorKey.currentContext!, (route) => route.isFirst); 
    Navigator.push(navigatorKey.currentContext!, MaterialPageRoute(
      builder: (context) => FutureBuilder(
        future: _edit(widget.imageFile.path, file.path, turns: turns, contrast: contrast, brightness: brightness),
        builder: (context, snapshot) => snapshot.hasData ? ImagePage(imageFile: file) : const LoadingPage()
      )
    ));
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
    final apploc = AppLocalizations.of(context)!;
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
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_getMatrix(contrast, brightness)),
                  child: RotatedBox(
                    quarterTurns: turns,
                    child: Image.file(widget.imageFile),
                  ),
                ),
              ),
            ),
            Container(
              padding: MediaQuery.orientationOf(context) == Orientation.portrait ? const EdgeInsets.only(top: 20.0) : null,
              child: SliderTheme(
                data: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // contrast is between [0.5, 1.5], selected with the ran[-100, 100]
                    Text(apploc.contrast),
                    Slider(
                      value: (contrast - 1) * 200,
                      min: -100,
                      max: 100,
                      label: ((contrast - 1) * 200).round().toString(),
                      onChanged: (value) => setState(() => contrast = value / 200 + 1),
                    ),
                    Text(apploc.brightness),
                    Slider(
                      value: brightness,
                      min: -100,
                      max: 100,
                      label: brightness.round().toString(),
                      onChanged: (value) => setState(() => brightness = value),
                    ),
                  ],
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