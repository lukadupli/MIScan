import 'package:flutter/material.dart';
import 'package:miscan/l10n/app_localizations.dart';

import 'main.dart';

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

/// Shows [LoadingPage] while [future] runs, then replaces itself with the
/// page [builder] returns for the result.
///
/// On error, pops back to whoever pushed this page and shows a SnackBar
/// instead of the result page -- without this, a decode error left
/// [LoadingPage] up forever, because the pages this replaces built their
/// loading state with a [FutureBuilder] that just never left the "waiting"
/// branch.
class LoadingThen<T> extends StatefulWidget{
  final Future<T> future;
  final Widget Function(BuildContext context, T value) builder;

  const LoadingThen({super.key, required this.future, required this.builder});

  @override
  State<LoadingThen<T>> createState() => _LoadingThenState<T>();
}

class _LoadingThenState<T> extends State<LoadingThen<T>>{
  @override
  void initState(){
    super.initState();
    widget.future.then(_onSuccess, onError: _onError);
  }

  void _onSuccess(T value){
    if(!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => widget.builder(context, value)),
    );
  }

  void _onError(Object error){
    if(!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(navigatorKey.currentContext!)!.imageLoadFailed)),
    );
  }

  @override
  Widget build(BuildContext context) => const LoadingPage();
}