// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get homePageTitle => 'Home';

  @override
  String get scanListTitle => 'Recent';

  @override
  String get noScansYet => 'No scans yet!';

  @override
  String get tipForCreatingScans =>
      'Click on the button below to create a new scan!';

  @override
  String get confirmDeletionTitle => 'Confirm deletion';

  @override
  String confirmDeletionContent(String filename) {
    return 'Are you sure you want to delete file \'$filename\'?';
  }

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get cancel => 'Cancel';

  @override
  String get newScanTooltip => 'Create a new scan';

  @override
  String get chooseSourceTitle => 'Import from';

  @override
  String imageSource(String source) {
    String _temp0 = intl.Intl.selectLogic(
      source,
      {
        'camera': 'Camera',
        'gallery': 'Gallery',
        'other': 'Other',
      },
    );
    return '$_temp0';
  }

  @override
  String get shareTooltip => 'Share';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get galleryExportTooltip => 'Export to gallery';

  @override
  String get downloadTooltip => 'Download';

  @override
  String get pdfTooltip => 'Create a PDF file';

  @override
  String get editTooltip => 'Edit';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get fileExistsTitle => 'File already exists';

  @override
  String fileExistsContent(String filename) {
    return 'File with the name \'$filename\' already exists. Do you want to replace it?';
  }

  @override
  String get exportConfirmTitle => 'Confirm export';

  @override
  String galleryExportConfirmContent(String filename) {
    return 'Are you sure you want to export file \'$filename\' to gallery?';
  }

  @override
  String downloadsExportConfirmContent(String filename) {
    return 'Are you sure you want to download file \'$filename\'?';
  }

  @override
  String get exportPermissionTitle => 'Unable to export';

  @override
  String get exportPermissionContent =>
      'App needs the permission to manage external storage in order to export files';

  @override
  String get openSettings => 'Open settings';

  @override
  String get tryAgain => 'Try again';

  @override
  String galleryExportConfirmation(String filename) {
    return 'File \'$filename\' exported to gallery';
  }

  @override
  String downloadsExportConfirmation(String filename) {
    return 'File \'$filename\' downloaded';
  }

  @override
  String get exportFailed =>
      'File couldn\'t be exported. Try changing the name of the file.';

  @override
  String get loading => 'Loading';

  @override
  String get transformPageTitle => 'Select corners';

  @override
  String get bookTransformPageTitle => 'Select curve';

  @override
  String get cannotTransformTitle => 'Cannot transform';

  @override
  String get cannotTransformContent =>
      'Image cannot be transformed from selected corners';

  @override
  String get ok => 'OK';

  @override
  String get contrast => 'Contrast';

  @override
  String get brightness => 'Brightness';

  @override
  String get welcome => 'Welcome!';

  @override
  String get aboutApp =>
      'MIScan is a lightweight app for fast scanning of documents and book pages.';

  @override
  String get documentScanningTitle => 'Document scanning';

  @override
  String get documentScanningContent =>
      'To scan a flat piece of paper select its corners by dragging the black circles and press the check button.';

  @override
  String get bookPageScanningTitle => 'Book page scanning';

  @override
  String get bookPageScanningContent1 =>
      'To scan a curved page of paper first select its corners and press the book button ...';

  @override
  String get bookPageScanningContent2 =>
      '... then, by dragging the white circles, fit the curve to match the curvature of the page and press the check button.';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';
}
