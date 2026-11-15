import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/window_title_bar.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<MethodCall> calls;
  bool isMaximized = false;

  setUp(() {
    calls = [];
    isMaximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isMaximized') {
        return isMaximized;
      }
      if (call.method == 'isFullScreen') {
        return false;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Widget app({required bool frameless}) {
    return MaterialApp(
      builder: (context, child) => WindowTitleBarArea(
        framelessWindow: frameless,
        child: child!,
      ),
      home: const Scaffold(body: Text('page')),
    );
  }

  Future<void> withPlatform(TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('shows the bar and offsets the content when enabled', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await tester.pumpWidget(app(frameless: false));
      expect(find.byType(WindowTitleBar), findsNothing);

      await tester.pumpWidget(app(frameless: true));
      await tester.pump();

      expect(find.byType(WindowTitleBar), findsOneWidget);
      expect(tester.getTopLeft(find.text('page')).dy, kWindowTitleBarHeight);
    });
  });

  testWidgets('is hidden on unsupported platforms', (tester) async {
    await withPlatform(TargetPlatform.linux, () async {
      await tester.pumpWidget(app(frameless: true));
      await tester.pump();

      expect(find.byType(WindowTitleBar), findsNothing);
    });
  });

  testWidgets('buttons call window_manager', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await tester.pumpWidget(app(frameless: true));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(calls.map((call) => call.method), contains('minimize'));

      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pump();
      expect(calls.map((call) => call.method), contains('maximize'));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(calls.map((call) => call.method), contains('close'));
      expect(calls.map((call) => call.method), isNot(contains('destroy')));
    });
  });

  testWidgets('reflects maximize events', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await tester.pumpWidget(app(frameless: true));
      await tester.pump();

      for (final listener in windowManager.listeners) {
        listener.onWindowMaximize();
      }
      await tester.pump();
      expect(find.byIcon(Icons.filter_none), findsOneWidget);

      for (final listener in windowManager.listeners) {
        listener.onWindowUnmaximize();
      }
      await tester.pump();
      expect(find.byIcon(Icons.crop_square), findsOneWidget);
    });
  });
}
