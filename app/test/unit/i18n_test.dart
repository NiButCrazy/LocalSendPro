import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:test/test.dart';

void main() {
  group('i18n', () {
    test('Should compile', () {
      // The following test will fail if the i18n file is either not compiled
      // or there are compile-time errors.
      expect(AppLocale.en.translations.general.accept, 'Accept');
      expect(AppLocale.en.translations.settingsTab.general.backgroundMode, isNotEmpty);
      expect(AppLocale.en.translations.settingsTab.general.backgroundModeDescription, isNotEmpty);
      expect(AppLocale.en.translations.settingsTab.general.framelessWindow, isNotEmpty);
    });

    test('All locales should be supported by Flutter', () {
      for (final locale in AppLocale.values) {
        expect(kMaterialSupportedLanguages, contains(locale.languageCode));
      }
    });
  });
}
