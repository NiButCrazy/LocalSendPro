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
        titleCompleted: 'Transfer complete',
        titleFailed: 'Transfer failed',
        titleCanceled: 'Transfer canceled',
        completionCountdown: _completionCountdown,
        remainingTimeMinutes: _remainingMinutes,
        remainingTimeLong: _remainingLong,
      ),
      completionDisplayDuration: Duration.zero,
    );
    // Most tests exercise the native window, which only appears while the app window is hidden.
    TransferNotification.setMainWindowActive(false);
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

  test('does not show the window while the app window is visible', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.setMainWindowActive(true);

    TransferNotification.start(sessionId: 'a', receiving: false);
    await Future<void>.delayed(Duration.zero);

    expect(calls, isEmpty);
  });

  test('shows the running transfer once the app window is hidden', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.setMainWindowActive(true);
    TransferNotification.start(sessionId: 'a', receiving: false);

    TransferNotification.setMainWindowActive(false);
    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'showProgress');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['title'], 'Sending files');
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

  test('shows the completion text before hiding', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.init(
      const NotificationStrings(
        titleReceiving: 'Receiving files',
        titleSending: 'Sending files',
        titleCompleted: 'Transfer complete',
        titleFailed: 'Transfer failed',
        titleCanceled: 'Transfer canceled',
        completionCountdown: _completionCountdown,
        remainingTimeMinutes: _remainingMinutes,
        remainingTimeLong: _remainingLong,
      ),
      completionDisplayDuration: const Duration(seconds: 1),
    );

    TransferNotification.start(sessionId: 'a', receiving: false);
    TransferNotification.update(
      sessionId: 'a',
      currentBytes: 100,
      totalBytes: 100,
      finishedFiles: 2,
      totalFiles: 2,
      startTime: null,
      endTime: null,
    );
    TransferNotification.stop('a', outcome: TransferOutcome.completed);
    await Future<void>.delayed(Duration.zero);

    final completed = calls.lastWhere((call) => call.method == 'showProgress');
    final arguments = completed.arguments as Map<Object?, Object?>;
    expect(arguments['title'], 'Transfer complete\u00012/2');
    expect(arguments['text'], startsWith('100%'));
    expect(arguments['text'], contains('100 B / 100 B'));
    expect(arguments['text'], contains('1s left'));
    expect(arguments['progress'], 1.0);
    expect(calls.map((call) => call.method), isNot(contains('hideProgress')));

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(calls.map((call) => call.method), contains('hideProgress'));
  });

  test('shows the failure text with the current progress', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TransferNotification.init(
      const NotificationStrings(
        titleReceiving: 'Receiving files',
        titleSending: 'Sending files',
        titleCompleted: 'Transfer complete',
        titleFailed: 'Transfer failed',
        titleCanceled: 'Transfer canceled',
        completionCountdown: _completionCountdown,
        remainingTimeMinutes: _remainingMinutes,
        remainingTimeLong: _remainingLong,
      ),
      completionDisplayDuration: const Duration(seconds: 1),
    );

    TransferNotification.start(sessionId: 'a', receiving: true);
    TransferNotification.update(
      sessionId: 'a',
      currentBytes: 50,
      totalBytes: 100,
      finishedFiles: 1,
      totalFiles: 2,
      startTime: null,
      endTime: null,
    );
    TransferNotification.stop('a', outcome: TransferOutcome.failed);
    await Future<void>.delayed(Duration.zero);

    final failed = calls.lastWhere((call) => call.method == 'showProgress');
    final arguments = failed.arguments as Map<Object?, Object?>;
    expect(arguments['title'], 'Transfer failed\u00011/2');
    expect(arguments['text'], startsWith('50%'));
    expect(arguments['text'], contains('50 B / 100 B'));
    expect(arguments['text'], contains('1s left'));
    expect(arguments['progress'], 0.5);
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

String _completionCountdown({required Object seconds}) => '${seconds}s left';

String _remainingLong({required num h, required num m}) => '${h}h ${m}m';
