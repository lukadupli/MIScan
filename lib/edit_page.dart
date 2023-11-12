import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'helpers.dart';
import 'image_page.dart';
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
    name = getName(widget.imageFile.path);
  }

  img.Image _rotate(img.Image image, int turns){
    if(turns == 0) return image;
    return img.copyRotate(image, angle: turns * 90);
  }
  Future<Uint8List> _editAndEncodeImage() async{
    var image = img.decodeImage(await widget.imageFile.readAsBytes())!;
    image = _rotate(image, turns);

    return img.encodeJpg(image);
  }
  void _saveAndPop(BuildContext context, File file, Uint8List bytes){
    file.writeAsBytesSync(bytes, flush: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => ImagePage(imageFile: file)));
  }
  void _save(BuildContext context) {
    _editAndEncodeImage().then(
      (bytes) => Locations.getAppInternalSaveDirectory().then(
        (dir){
          final file = File("${dir.path}/$name");
          if(file.existsSync()){
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("File already exists"),
                content: Text("File with the name '$name' already exists. Do you want to replace it?"),
                actions: [
                  TextButton(child: const Text("Yes"), onPressed: () {Navigator.of(context).pop(); FileImage(file).evict(); _saveAndPop(context, file, bytes);}),
                  TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
                ]
              )
            );
          }
          else{
            _saveAndPop(context, file, bytes);
          }
        }
      )
    );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: TextFormField(initialValue: removeExtension(name), onFieldSubmitted: (value) => name = "$value.jpg", style: Theme.of(context).textTheme.titleLarge),
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
                  IconButton(icon: const Icon(Icons.done), onPressed: () => _save(context)),
                ]
              ),
            )
          ]
        ),
      ),
    );
  }
}