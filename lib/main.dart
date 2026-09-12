import 'package:flutter/material.dart';
import 'package:miscan/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'my_home_page.dart';
import 'first_launch_page.dart';

/// Used for creating [AlertDialog]s
final navigatorKey = GlobalKey<NavigatorState>();

/// Tells pages when a route above them has been popped, so they can refresh
/// what they show on the way back (see MyHomePage).
final routeObserver = RouteObserver<ModalRoute<void>>();

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
      home: const FirstLaunchChecker(),
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
    );
  }
}

class FirstLaunchChecker extends StatefulWidget {
  const FirstLaunchChecker({super.key});

  @override
  State<FirstLaunchChecker> createState() => _FirstLaunchCheckerState();
}

class _FirstLaunchCheckerState extends State<FirstLaunchChecker> {
  bool isFirstLaunch = false;

  @override
  void initState() {
    super.initState();
    checkFirstLaunch();
  }

  Future<void> checkFirstLaunch() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isFirstLaunch_ = prefs.getBool('isFirstLaunch') ?? true;

    if (isFirstLaunch_) {
      await prefs.setBool('isFirstLaunch', false);
    }

    setState(() {
      isFirstLaunch = isFirstLaunch_;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isFirstLaunch) {
      return const FirstLaunchPage();
    } else {
      return const MyHomePage();
    }
  }
}
