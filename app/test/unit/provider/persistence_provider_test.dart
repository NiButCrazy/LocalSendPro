import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/persistence/history_direction_filter.dart';
import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PersistenceService background mode', () {
    setUp(() {
      // Pre-fill everything initialize() would otherwise generate (including the Rust security context).
      SharedPreferences.setMockInitialValues({
        'ls_version': 4,
        'ls_locale': 'en',
        'ls_show_token': 'test-token',
        'ls_alias': 'test-alias',
        'ls_security_context': '{}',
        'ls_color': 'localsend',
      });
    });

    test('defaults to disabled', () async {
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.isBackgroundMode(), isFalse);
    });

    test('persists the enabled state', () async {
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      await persistence.setBackgroundMode(true);
      expect(persistence.isBackgroundMode(), isTrue);
    });
  });

  group('PersistenceService frameless window', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'ls_version': 4,
        'ls_locale': 'en',
        'ls_show_token': 'test-token',
        'ls_alias': 'test-alias',
        'ls_security_context': '{}',
        'ls_color': 'localsend',
      });
    });

    test('defaults to disabled', () async {
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.isFramelessWindow(), isFalse);
    });

    test('persists the enabled state', () async {
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      await persistence.setFramelessWindow(true);
      expect(persistence.isFramelessWindow(), isTrue);
    });
  });

  group('PersistenceService history default filter', () {
    void mockPrefs([Map<String, Object> extra = const {}]) {
      SharedPreferences.setMockInitialValues({
        'ls_version': 4,
        'ls_locale': 'en',
        'ls_show_token': 'test-token',
        'ls_alias': 'test-alias',
        'ls_security_context': '{}',
        'ls_color': 'localsend',
        ...extra,
      });
    }

    test('defaults to all', () async {
      mockPrefs();
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.getHistoryDefaultFilter(), HistoryDirectionFilter.all);
    });

    test('persists the selected filter', () async {
      mockPrefs();
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      await persistence.setHistoryDefaultFilter(HistoryDirectionFilter.send);
      expect(persistence.getHistoryDefaultFilter(), HistoryDirectionFilter.send);
    });

    test('falls back to all for unknown values', () async {
      mockPrefs({'ls_history_default_filter': 'unknown'});
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.getHistoryDefaultFilter(), HistoryDirectionFilter.all);
    });
  });

  group('PersistenceService history default layer', () {
    void mockPrefs([Map<String, Object> extra = const {}]) {
      SharedPreferences.setMockInitialValues({
        'ls_version': 4,
        'ls_locale': 'en',
        'ls_show_token': 'test-token',
        'ls_alias': 'test-alias',
        'ls_security_context': '{}',
        'ls_color': 'localsend',
        ...extra,
      });
    }

    test('defaults to runtime', () async {
      mockPrefs();
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.getHistoryDefaultLayer(), HistoryLayer.runtime);
    });

    test('persists the selected layer', () async {
      mockPrefs();
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      await persistence.setHistoryDefaultLayer(HistoryLayer.persistent);
      expect(persistence.getHistoryDefaultLayer(), HistoryLayer.persistent);
    });

    test('falls back to runtime for unknown values', () async {
      mockPrefs({'ls_history_default_layer': 'unknown'});
      final persistence = await PersistenceService.initialize(supportsDynamicColors: false);
      expect(persistence.getHistoryDefaultLayer(), HistoryLayer.runtime);
    });
  });
}
