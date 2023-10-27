import 'package:flutter/material.dart';

class LoadingPage extends StatelessWidget{
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: MediaQuery.orientationOf(context) == Orientation.landscape ? null : AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 60.0, height: 60.0, child: CircularProgressIndicator()),
            Padding(padding: EdgeInsets.all(10.0), child: Text("Loading")),
          ],
        ),
      )
    );
  }
}