import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hr')
  ];

  /// Home page title
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homePageTitle;

  /// Title of the home page list of previous scans
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get scanListTitle;

  /// Message to display when there are no previous scans
  ///
  /// In en, this message translates to:
  /// **'No scans yet!'**
  String get noScansYet;

  /// Message to display when there are no previous scans to show how to create new scans
  ///
  /// In en, this message translates to:
  /// **'Click on the button below to create a new scan!'**
  String get tipForCreatingScans;

  /// Title of the alert dialog which pops up when the user wants to delete a file
  ///
  /// In en, this message translates to:
  /// **'Confirm deletion'**
  String get confirmDeletionTitle;

  /// Content of the alert dialog which pops up when the user wants to delete a file
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete file \'{filename}\'?'**
  String confirmDeletionContent(String filename);

  /// Yes/No question answer
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Yes/No question answer
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Cancel operation
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Message displayed when new scan button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Create a new scan'**
  String get newScanTooltip;

  /// Title of dialog for choosing how to import an image
  ///
  /// In en, this message translates to:
  /// **'Import from'**
  String get chooseSourceTitle;

  /// Image source options
  ///
  /// In en, this message translates to:
  /// **'{source, select, camera{Camera} gallery{Gallery} other{Other}}'**
  String imageSource(String source);

  /// Message shown when share button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTooltip;

  /// Message shown when delete button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// Message shown when export to gallery button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Export to gallery'**
  String get galleryExportTooltip;

  /// Message shown when download button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadTooltip;

  /// Message shown when PDF button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Create a PDF file'**
  String get pdfTooltip;

  /// Message shown when edit button is long pressed
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editTooltip;

  /// Used for scan modification time
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Used for scan modification time
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Title of a dialog warning user that a file with the same name already exists in the save location
  ///
  /// In en, this message translates to:
  /// **'File already exists'**
  String get fileExistsTitle;

  /// Content of a dialog warning user that a file with the same name already exists in the save location
  ///
  /// In en, this message translates to:
  /// **'File with the name \'{filename}\' already exists. Do you want to replace it?'**
  String fileExistsContent(String filename);

  /// Title of a dialog asking user to confirm export of a file
  ///
  /// In en, this message translates to:
  /// **'Confirm export'**
  String get exportConfirmTitle;

  /// Content of a dialog asking user to confirm export to gallery
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to export file \'{filename}\' to gallery?'**
  String galleryExportConfirmContent(String filename);

  /// Content of a dialog asking user to confirm export to downloads
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to download file \'{filename}\'?'**
  String downloadsExportConfirmContent(String filename);

  /// Title of a dialog asking user to allow the app to manage external storage in order to export a file
  ///
  /// In en, this message translates to:
  /// **'Unable to export'**
  String get exportPermissionTitle;

  /// Content of a dialog asking user to allow the app to manage external storage in order to export a file
  ///
  /// In en, this message translates to:
  /// **'App needs the permission to manage external storage in order to export files'**
  String get exportPermissionContent;

  /// Title of a button leading to phone settings
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// Title of a button for trying again
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Confirmation message when export to gallery is done
  ///
  /// In en, this message translates to:
  /// **'File \'{filename}\' exported to gallery'**
  String galleryExportConfirmation(String filename);

  /// Confirmation message when export to downloads is done
  ///
  /// In en, this message translates to:
  /// **'File \'{filename}\' downloaded'**
  String downloadsExportConfirmation(String filename);

  /// Message shown when export fails.
  ///
  /// In en, this message translates to:
  /// **'File couldn\'t be exported. Try changing the name of the file.'**
  String get exportFailed;

  /// Loading page text
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// Title of transform page
  ///
  /// In en, this message translates to:
  /// **'Select corners'**
  String get transformPageTitle;

  /// Title of book transform page
  ///
  /// In en, this message translates to:
  /// **'Select curve'**
  String get bookTransformPageTitle;

  /// Title of a dialog alerting user that the transformation cannot be made from selected corners
  ///
  /// In en, this message translates to:
  /// **'Cannot transform'**
  String get cannotTransformTitle;

  /// Content of a dialog alerting user that the transformation cannot be made from selected corners
  ///
  /// In en, this message translates to:
  /// **'Image cannot be transformed from selected corners'**
  String get cannotTransformContent;

  /// OK button title
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Contrast in image processing
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// Brightness in image processing
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// Introduction screen greeting
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get welcome;

  /// Short description of the app
  ///
  /// In en, this message translates to:
  /// **'MIScan is a lightweight app for fast scanning of documents and book pages.'**
  String get aboutApp;

  /// Title of an intro screen explaining the document scanning function.
  ///
  /// In en, this message translates to:
  /// **'Document scanning'**
  String get documentScanningTitle;

  /// Content of an intro screen explaining the document scanning function.
  ///
  /// In en, this message translates to:
  /// **'To scan a flat piece of paper select its corners by dragging the black circles and press the check button.'**
  String get documentScanningContent;

  /// Title of intro screens explaining the book page scanning function.
  ///
  /// In en, this message translates to:
  /// **'Book page scanning'**
  String get bookPageScanningTitle;

  /// Content of the first intro screen about book page scanning.
  ///
  /// In en, this message translates to:
  /// **'To scan a curved page of paper first select its corners and press the book button ...'**
  String get bookPageScanningContent1;

  /// Content of the second intro screen about book page scanning.
  ///
  /// In en, this message translates to:
  /// **'... then, by dragging the white circles, fit the curve to match the curvature of the page and press the check button.'**
  String get bookPageScanningContent2;

  /// Intro screen button.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Intro screen button.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hr':
      return AppLocalizationsHr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
