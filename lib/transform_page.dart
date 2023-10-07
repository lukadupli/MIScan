import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'frame.dart';
import 'transform.dart';
import 'package:image_size_getter/image_size_getter.dart' as isg;
import 'dart:typed_data';
import 'post_transform_page.dart';
import 'dart:ui' as ui;

Future<ui.Image> bytesToImage(Uint8List imgBytes) async{
  ui.Codec codec = await ui.instantiateImageCodec(imgBytes);
  ui.FrameInfo frame;
  try {
    frame = await codec.getNextFrame();
  } finally {
    codec.dispose();
  }
  return frame.image;
}


class TransformPage extends StatefulWidget{
  final Uint8List imageData;

  const TransformPage({super.key, required this.imageData});

  @override
  State<TransformPage> createState() => _TransformPageState();
}

class _TransformPageState extends State<TransformPage> {
  final fController = FrameController();
  late final isg.Size imageSize;
  late final List<ValueNotifier<Offset>> notifiers;

  static const double frameCornerDimension = 50.0;
  static const double showcaseDimension = 60.0;

  Widget buildShowcase(int index){
    return CornerShowcase(
      size: const Size(showcaseDimension, showcaseDimension),
      imageData: widget.imageData,
      imageSegmentSize: const Size(showcaseDimension, showcaseDimension),
      positionNotifier: notifiers[index],
    );
  }

  @override
  void initState(){
    imageSize = isg.ImageSizeGetter.getSize(isg.MemoryInput(widget.imageData));
    notifiers = <ValueNotifier<Offset>>[
      ValueNotifier<Offset>(Offset.zero),
      ValueNotifier<Offset>(Offset(0, imageSize.height.toDouble())),
      ValueNotifier<Offset>(Offset(imageSize.width.toDouble(), imageSize.height.toDouble())),
      ValueNotifier<Offset>(Offset(imageSize.width.toDouble(), 0)),
    ];
    super.initState();
  }

  @override
  Widget build(BuildContext context){
    EasyLoading.show();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Transformator"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for(int i = 0; i < 4; i++) buildShowcase(i),
            ],
          ),
          Frame(
            controller: fController,
            cornerSize: frameCornerDimension,
            margin: const EdgeInsets.symmetric(vertical: frameCornerDimension / 2),
            whenLoaded: (){
              double ratio = imageSize.width / fController.childSize.width;
              EasyLoading.dismiss();
              for(int i = 0; i < 4; i++){
                notifiers[i].value = fController.corners[i] * ratio;
              }
            },
            onPositionChange: (index) {
              double ratio = imageSize.width / fController.childSize.width;
              notifiers[index].value = fController.corners[index] * ratio;
            },
            child: Image.memory(widget.imageData)
          ),
          IconButton(icon: const Icon(Icons.transform), onPressed: () {
            double ratio = imageSize.width / fController.childSize.width;
            EasyLoading.show();
            transform(
              widget.imageData, 
              fController.corners[0] * ratio, 
              fController.corners[1] * ratio, 
              fController.corners[2] * ratio,
              fController.corners[3] * ratio,
            )
            .then((result) {
              EasyLoading.dismiss();
              Navigator.push(context, MaterialPageRoute(builder: (context) => PostTransformPage(imageData: result!)));
            });
          })
        ]
      ),
    );
  }
}

class CornerPainter extends CustomPainter{
  ui.Image? image;
  final Size cornerSize;
  final ValueNotifier<Offset> position;

  CornerPainter(Uint8List imageData, {required this.cornerSize, required this.position}) : super(repaint: position){
    bytesToImage(imageData).then((value) => image = value);
  }

  @override
  void paint(Canvas canvas, Size size){
    if(image == null) return;
    final src = Offset(position.value.dx - cornerSize.width / 2, position.value.dy - cornerSize.height / 2) & cornerSize;
    canvas.drawImageRect(image!, src, Offset.zero & cornerSize, Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CornerShowcase extends StatelessWidget {
  const CornerShowcase({
    super.key,
    required this.size,
    required this.imageData,
    required this.imageSegmentSize,
    required this.positionNotifier,
  });

  final Uint8List imageData;
  final Size imageSegmentSize;
  final Size size;
  final ValueNotifier<Offset> positionNotifier;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: CornerPainter(imageData, cornerSize: imageSegmentSize, position: positionNotifier),
          child: SizedBox(
            width: size.width,
            height: size.height, 
            child: const Center(child: Text("+", style: TextStyle(color: Colors.black54)))
          ),
        ),
      ),
    );
  }
}