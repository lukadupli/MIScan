// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Croatian (`hr`).
class AppLocalizationsHr extends AppLocalizations {
  AppLocalizationsHr([String locale = 'hr']) : super(locale);

  @override
  String get homePageTitle => 'Početna';

  @override
  String get scanListTitle => 'Nedavno';

  @override
  String get noScansYet => 'Nema prijašnjih skenova!';

  @override
  String get tipForCreatingScans =>
      'Pritisnite gumb dolje desno za izradu novog skena.';

  @override
  String get confirmDeletionTitle => 'Potvrdi brisanje';

  @override
  String confirmDeletionContent(String filename) {
    return 'Jeste li sigurni da želite izbrisati datoteku \'$filename\'?';
  }

  @override
  String get yes => 'Da';

  @override
  String get no => 'Ne';

  @override
  String get cancel => 'Otkaži';

  @override
  String get newScanTooltip => 'Izradi novi sken';

  @override
  String get chooseSourceTitle => 'Uvezi iz';

  @override
  String imageSource(String source) {
    String _temp0 = intl.Intl.selectLogic(
      source,
      {
        'camera': 'Kamere',
        'gallery': 'Galerije',
        'other': 'Druga lokacija',
      },
    );
    return '$_temp0';
  }

  @override
  String get shareTooltip => 'Dijeli';

  @override
  String get deleteTooltip => 'Izbriši';

  @override
  String get galleryExportTooltip => 'Izvezi u galeriju';

  @override
  String get downloadTooltip => 'Preuzimanje';

  @override
  String get pdfTooltip => 'Izradi PDF datoteku';

  @override
  String get editTooltip => 'Uredi';

  @override
  String get today => 'Danas';

  @override
  String get yesterday => 'Jučer';

  @override
  String get fileExistsTitle => 'Datoteka već postoji';

  @override
  String fileExistsContent(String filename) {
    return 'Datoteka s imenom \'$filename\' već postoji. Želite li je zamijeniti?';
  }

  @override
  String get exportConfirmTitle => 'Potvrdi izvoz';

  @override
  String galleryExportConfirmContent(String filename) {
    return 'Jeste li sigurni da želite izvesti datoteku \'$filename\' u galeriju?';
  }

  @override
  String downloadsExportConfirmContent(String filename) {
    return 'Jeste li sigurni da želite preuzeti datoteku \'$filename\'?';
  }

  @override
  String get exportPermissionTitle => 'Dopuštenja';

  @override
  String get exportPermissionContent =>
      'Aplikaciji je potrebno dopuštenje upravljanja svim datotekama kako bi mogla izvoditi datoteke';

  @override
  String get openSettings => 'Otvori postavke';

  @override
  String get tryAgain => 'Pokušaj ponovo';

  @override
  String galleryExportConfirmation(String filename) {
    return 'Datoteka \'$filename\' uspješno izvedena u galeriju';
  }

  @override
  String downloadsExportConfirmation(String filename) {
    return 'Datoteka \'$filename\' uspješno preuzeta';
  }

  @override
  String get exportFailed =>
      'Datoteku nije moguće izvesti. Pokušajte promijeniti naziv datoteke.';

  @override
  String get loading => 'Učitavanje';

  @override
  String get transformPageTitle => 'Odaberi vrhove';

  @override
  String get bookTransformPageTitle => 'Odaberi krivulju';

  @override
  String get cannotTransformTitle => 'Transformacija nemoguća';

  @override
  String get cannotTransformContent =>
      'Nemoguće je transformirati sliku iz odabranih vrhova';

  @override
  String get ok => 'OK';

  @override
  String get contrast => 'Kontrast';

  @override
  String get brightness => 'Svjetlina';

  @override
  String get welcome => 'Dobrodošli!';

  @override
  String get aboutApp =>
      'MIScan je aplikacija za brzo i jednostavno skeniranje dokumenata i stranica knjiga.';

  @override
  String get documentScanningTitle => 'Skeniranje dokumenata';

  @override
  String get documentScanningContent =>
      'Kako biste skenirali dokument, povlačenjem crnih krugova odaberite kutove dokumenta te pritisnite gumb s kvačicom.';

  @override
  String get bookPageScanningTitle => 'Skeniranje stranice knjige';

  @override
  String get bookPageScanningContent1 =>
      'Kako biste skenirali stranicu knjige prvo odaberite kutove stranice te pritisnite gumb s ikonom knjige ...';

  @override
  String get bookPageScanningContent2 =>
      '... zatim, povlačeći bijele kružiće, namjestite krivulju tako da se podudara s zakrivljenim rubom stranice te pritisnite gumb s kvačicom.';

  @override
  String get next => 'Sljedeće';

  @override
  String get done => 'Gotovo';
}
