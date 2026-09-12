import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:miscan/l10n/app_localizations.dart';

import 'dart:io';

import 'debug/benchmark_page.dart';
import 'debug/live_preview_page.dart';
import 'helpers.dart';
import 'main.dart' show routeObserver;
import 'scan_camera_page.dart';
import 'scan_input.dart';
import 'transform_page.dart';
import 'loading_page.dart';
import 'listview_image.dart';
import 'locations.dart';

class MyHomePage extends StatefulWidget {
  /// App's home page
  /// 
  /// Previous scans are shown in a [ListView] as [ListViewImage]s
  /// 
  /// New image can be imported from camera or from gallery using a [FloatingActionButton]
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with RouteAware {
  List<(File, DateTime)>? files;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  // Scans are created, edited and renamed on pages pushed above this one, so
  // coming back here is when the list can have changed. Listing it from
  // build() instead re-listed on every frame: each listing's setState asked
  // for another build, which started another listing, for as long as the
  // page existed -- including while hidden under other pages.
  @override
  void didPopNext() => _refresh();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final result = await _getImageFiles();
    if (mounted) setState(() => files = result);
  }

  Future<List<(File, DateTime)>> _getImageFiles() async{
    final dir = await Locations.getAppInternalSaveDirectory();

    final entities = dir.listSync();
    final files = [for(final item in entities) (item as File, (await FileStat.stat(item.path)).modified)];

    // sort files by last modification time
    files.sort((a, b) => b.$2.compareTo(a.$2));
    return files;
  }

  @override
  Widget build(BuildContext context){
    final apploc = AppLocalizations.of(context)!;
    late Widget body;
    if(files == null){
      body = const Center(child: SizedBox(width: 60.0, height: 60.0, child: CircularProgressIndicator()));
    }
    else if(files!.isEmpty){
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Center(child: Text(apploc.noScansYet)), Center(child: Text(apploc.tipForCreatingScans))]
      );
    }
    else{
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.all(8.0), child: Text(apploc.scanListTitle, style: Theme.of(context).textTheme.titleLarge)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0), 
              child: ListView.separated(
                itemBuilder: (context, index){
                  return ListViewImage(
                    key: ValueKey(files![index].$2), // forces rebuild when image is modified
                    imageFile: files![index].$1, 
                    time: files![index].$2, 
                    height: MediaQuery.orientationOf(context) == Orientation.portrait ? 100 : 150, 
                    index: index, 
                    onDeletion: (deleted){
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog.adaptive(
                          title: Text(apploc.confirmDeletionTitle),
                          content: Text(apploc.confirmDeletionContent(getName(files![deleted].$1.path))),
                          actions: [
                            TextButton(child: Text(apploc.yes), onPressed: (){
                              files![deleted].$1.deleteSync();
                              files!.removeAt(deleted);
                              Navigator.of(context).pop();
                              setState((){});
                            }),
                            TextButton(child: Text(apploc.cancel), onPressed: () => Navigator.of(context).pop()),
                          ]
                        )
                      );
                    }
                  );
                },
                separatorBuilder: (context, index){
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Container(height: 1, color: Colors.black12));
                },
                itemCount: files!.length,
              ),
            )
          ),
        ]
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: RichText(
          text: TextSpan(
            children: [
              const WidgetSpan(child: Icon(Icons.home)),
              TextSpan(text: " ${apploc.homePageTitle}", style: Theme.of(context).textTheme.titleLarge),
            ]
          )
        ),
        actions: [
          // Dev tooling. Hidden only in release: profile builds need these too,
          // since debug-mode Dart runs unoptimised and gives misleading timings.
          if (!kReleaseMode) ...[
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Execution providers (debug)',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BenchmarkPage())),
            ),
            IconButton(
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Live corner preview (debug)',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LivePreviewPage())),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: body,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newScan,
        tooltip: apploc.newScanTooltip,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  void _newScan(){
    final apploc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(apploc.newScanTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _newScanOptionButton(
              icon: const Icon(Icons.camera_alt),
              label: apploc.scannerOption,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ScanCameraPage()));
              },
            ),
            _newScanOptionButton(
              icon: const Icon(Icons.image),
              label: apploc.galleryOption,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _pickFromGallery();
              },
            ),
          ]
        )
      ),
    );
  }

  Widget _newScanOptionButton({required Icon icon, required String label, required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      icon: icon,
      label: Text(label),
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
      onPressed: onPressed,
    );
  }

  Future<void> _pickFromGallery() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => LoadingThen<ScanInput>(
        future: prepareScanInput(xfile.path),
        builder: (context, input) => TransformPage(image: input.image, initialCorners: input.corners),
      ),
    ));
  }
}
