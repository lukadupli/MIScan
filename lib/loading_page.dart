import 'package:flutter/material.dart';
import 'package:miscan/l10n/app_localizations.dart';

class LoadingPage extends StatelessWidget{
  /// Creates a simple loading page with [CircularProgressIndicator] and a localized loading message
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 60.0, height: 60.0, child: CircularProgressIndicator()),
            Padding(padding: const EdgeInsets.all(10.0), child: Text(AppLocalizations.of(context)!.loading)),
          ],
        ),
      )
    );
  }
}