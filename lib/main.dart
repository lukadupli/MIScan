import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'my_home_page.dart';

/// Used for creating [AlertDialog]s
final navigatorKey = GlobalKey<NavigatorState>();
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Supported locales are English ('en') and Croatian ('hr')
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIScan',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(),
      ),
      home: const MyHomePage(),
      navigatorKey: navigatorKey,
    );
  }
}
