import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/window_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('hides the native title bar', () async {
    await applyFramelessWindow(true);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setTitleBarStyle');
    expect(calls.single.arguments, {'titleBarStyle': 'hidden', 'windowButtonVisibility': false});
  });

  test('restores the native title bar', () async {
    await applyFramelessWindow(false);

    expect(calls, hasLength(1));
    expect(calls.single.arguments, {'titleBarStyle': 'normal', 'windowButtonVisibility': false});
  });

  test('is a no-op on unsupported platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await applyFramelessWindow(true);

    expect(calls, isEmpty);
  });
}
