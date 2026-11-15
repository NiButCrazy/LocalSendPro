import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:localsend_isolates/util/transfer_progress_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.localsend.localsend_app/transfer_progress');
  late List<MethodCall> calls;
  late DateTime now;

  setUp(() {
    calls = [];
    now = DateTime(2026, 1, 1, 12);
    TransferProgressWindow.resetForTest();
    TransferProgressWindow.now = () => now;
    TransferNotification.resetForTest();
    TransferNotification.init(
      const NotificationStrings(
        titleReceiving: 'Receiving files',
        titleSending: 'Sending files',
        remainingTimeMinutes: _remainingMinutes,
        remainingTimeLong: _remainingLong,
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TransferNotification.resetForTest();
    TransferProgressWindow.resetForTest();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('shows the window when the first transfer starts', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    TransferNotification.start(sessionId: 'a', receiving: false);
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'showProgress');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['title'], 'Sending files');
    expect(arguments['progress'], 0.0);
  });

  test('updates the window with aggregated progress', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.start(sessionId: 'a', receiving: false);

    now = now.add(const Duration(seconds: 1));
    TransferNotification.update(
      sessionId: 'a',
      currentBytes: 50,
      totalBytes: 100,
      finishedFiles: 0,
      totalFiles: 1,
      startTime: null,
      endTime: null,
    );
    await Future<void>.delayed(Duration.zero);

    final updates = calls.where((call) => call.method == 'updateProgress').toList();
    expect(updates, hasLength(1));
    final arguments = updates.single.arguments as Map<Object?, Object?>;
    expect(arguments['progress'], 0.5);
    expect(arguments['text'], contains('50%'));
  });

  test('hides only after the last transfer stops', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.start(sessionId: 'a', receiving: false);
    now = now.add(const Duration(seconds: 1));
    TransferNotification.start(sessionId: 'b', receiving: true);

    TransferNotification.stop('a');
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), isNot(contains('hideProgress')));

    now = now.add(const Duration(seconds: 1));
    TransferNotification.stop('b');
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), contains('hideProgress'));
  });

  test('does nothing on non-Windows platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    TransferNotification.start(sessionId: 'a', receiving: false);
    TransferNotification.update(
      sessionId: 'a',
      currentBytes: 50,
      totalBytes: 100,
      finishedFiles: 0,
      totalFiles: 1,
      startTime: null,
      endTime: null,
    );
    TransferNotification.stop('a');
    await Future<void>.delayed(Duration.zero);

    expect(calls, isEmpty);
  });

  test('dispatches native window actions', () async {
    final actions = <String>[];
    TransferProgressWindow.setActionHandler(actions.add);
    addTearDown(() => TransferProgressWindow.setActionHandler(null));

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onWindowAction', {'action': 'accept'}),
      ),
      (_) {},
    );

    expect(actions, ['accept']);
  });
}

String _remainingMinutes({required Object m, required Object ss}) => '$m:$ss';

String _remainingLong({required num h, required num m}) => '${h}h ${m}m';
