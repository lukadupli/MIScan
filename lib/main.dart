import 'package:flutter/material.dart';
import 'my_home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIScan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(brightness: Brightness.light, seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(),
      ),
      home: const MyHomePage(),
      navigatorKey: navigatorKey,
    );
  }
}
