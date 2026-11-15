import 'package:flutter_test/flutter_test.dart';
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
}
