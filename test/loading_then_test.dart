import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miscan/l10n/app_localizations.dart';
import 'package:miscan/l10n/app_localizations_en.dart';
import 'package:miscan/loading_page.dart';
import 'package:miscan/main.dart' show navigatorKey;

void main() {
  // LoadingThen relies on the app's global navigatorKey (see loading_page.dart)
  // to show a SnackBar after popping itself, so tests wire up a real
  // MaterialApp with that same key rather than a bare Navigator.
  Widget app(Widget home) => MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  testWidgets('success replaces the loading page with the result page', (tester) async {
    final completer = Completer<int>();
    await tester.pumpWidget(app(
      LoadingThen<int>(
        future: completer.future,
        builder: (context, value) => Scaffold(body: Text('result: $value')),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('result: 42'), findsNothing);

    completer.complete(42);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('result: 42'), findsOneWidget);
  });

  testWidgets('error pops back to the caller and shows a SnackBar', (tester) async {
    final completer = Completer<int>();
    await tester.pumpWidget(app(
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (context) => LoadingThen<int>(
                future: completer.future,
                builder: (context, value) => Scaffold(body: Text('result: $value')),
              ),
            )),
            child: const Text('start'),
          ),
        ),
      ),
    ));

    // Not pumpAndSettle: LoadingPage's CircularProgressIndicator is
    // indeterminate, so it never stops scheduling frames on its own.
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // let the push transition finish
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.completeError(Exception('decode failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300)); // let the pop + SnackBar entrance finish

    // Back on the caller's page, not stuck on LoadingPage or the result page.
    expect(find.text('start'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('result: 42'), findsNothing);
    expect(find.text(AppLocalizationsEn().imageLoadFailed), findsOneWidget);
  });
}
