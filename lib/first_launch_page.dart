import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'my_home_page.dart';

class FirstLaunchPage extends StatelessWidget{
  const FirstLaunchPage({super.key});

  @override
  Widget build(BuildContext context){
    final apploc = AppLocalizations.of(context)!;
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: apploc.welcome,
          image: Image.asset("assets/MISiconTransparent.png"),
          body: apploc.aboutApp,
          decoration: const PageDecoration(
            imagePadding: EdgeInsets.all(40.0),
            imageFlex: 3
          )
        ),
        PageViewModel(
          title: apploc.documentScanningTitle,
          image: SafeArea(child: Image.asset("assets/paper0tap.jpg")),
          body: apploc.documentScanningContent,
          decoration: const PageDecoration(
            imagePadding: EdgeInsets.only(top: 10.0), 
            imageFlex: 3
          ),
        ),
        PageViewModel(
          title: "${apploc.bookPageScanningTitle} 1/2",
          image: SafeArea(child: Image.asset("assets/book0tap.jpg")),
          body: apploc.bookPageScanningContent1,
          decoration: const PageDecoration(
            imagePadding: EdgeInsets.only(top: 10.0), 
            imageFlex: 3
          ),
        ),
        PageViewModel(
          title: "${apploc.bookPageScanningTitle} 2/2",
          image: SafeArea(child: Image.asset("assets/book1tap.jpg")),
          body: apploc.bookPageScanningContent2,
          decoration: const PageDecoration(
            imagePadding: EdgeInsets.only(top: 10.0), 
            imageFlex: 3
          ),
        ),
      ],
      next: Text(apploc.next),
      done: Text(apploc.done),
      onDone: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (context) => const MyHomePage()));
      }
    );
  }
}