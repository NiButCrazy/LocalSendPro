import 'dart:async';

import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:localsend_isolates/util/file_speed_helper.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_progress_window.dart';

/// A transfer only becomes fast enough to measure after a while; the first chunks are not
/// representative. Same threshold as `ProgressPage`.
const _minBytesForSpeed = 500 * 1024;

/// How a transfer ended. Drives the text kept on screen until the window hides.
enum TransferOutcome {
  completed,
  failed,
  canceled,
}

/// Drives the single foreground service notification on behalf of all running transfers.
///
/// There is one notification but there can be several transfers: receiving is limited to one
/// session, sending is not, and both directions can run at the same time. So the service is
/// reference counted here - it starts with the first transfer, ends with the last one, and the
/// notification shows the sum of everything in flight.
class TransferNotification {
  TransferNotification._();

  static final _transfers = <String, _Transfer>{};
  static NotificationStrings? _strings;

  /// How long the Windows window keeps showing the completion state before hiding.
  static Duration _completionDisplayDuration = const Duration(seconds: 3);
  static Timer? _completionTimer;

  /// Injects the translated strings. Must be called before the first transfer starts.
  /// The locale is pinned on app start, so one call is enough.
  static void init(
    NotificationStrings strings, {
    Duration completionDisplayDuration = const Duration(seconds: 3),
  }) {
    _strings = strings;
    _completionDisplayDuration = completionDisplayDuration;
  }

  /// Updates how long the native window keeps showing the completion state.
  static void setCompletionDisplayDuration(Duration duration) {
    _completionDisplayDuration = duration;
  }

  /// Only for tests: forgets every registered transfer.
  static void resetForTest() {
    _transfers.clear();
    _cancelCompletionTimer();
  }

  /// Whether [update] would reach the notification, so that callers can skip summing up the
  /// progress of every file for an update that gets throttled away.
  ///
  /// While several transfers run, they take turns passing this check, which means each of them
  /// refreshes its share of the total a bit less often. The numbers stay close enough: every
  /// running transfer reports progress continuously.
  static bool get shouldUpdate => ForegroundService.shouldUpdateNotification || TransferProgressWindow.shouldUpdate;

  /// Registers a transfer, starting the service if it is the first one.
  ///
  /// Must be called while the app is in the foreground: Android 12+ rejects starting a foreground
  /// service from the background.
  static void start({required String sessionId, required bool receiving}) {
    if (_transfers.containsKey(sessionId)) {
      return;
    }

    final isFirst = _transfers.isEmpty;
    _transfers[sessionId] = _Transfer(receiving: receiving);

    if (isFirst) {
      _cancelCompletionTimer();
      final snapshot = _snapshot();
      ForegroundService.start(
        channelName: _requiredStrings.titleReceiving,
        title: snapshot.title,
        text: snapshot.text,
        progress: snapshot.percentage,
      );
      TransferProgressWindow.show(title: snapshot.windowTitle, text: snapshot.windowText, percentage: snapshot.percentage);
    }
  }

  /// Reports the progress of a single transfer and refreshes the notification.
  /// Unknown sessions are ignored, so a late progress event cannot revive a finished transfer.
  static void update({
    required String sessionId,
    required int currentBytes,
    required int totalBytes,
    required int finishedFiles,
    required int totalFiles,
    required int? startTime,
    required int? endTime,
  }) {
    final transfer = _transfers[sessionId];
    if (transfer == null) {
      return;
    }

    transfer.currentBytes = currentBytes;
    transfer.totalBytes = totalBytes;
    transfer.finishedFiles = finishedFiles;
    transfer.totalFiles = totalFiles;
    transfer.speedInBytes = _speed(currentBytes: currentBytes, startTime: startTime, endTime: endTime);

    final snapshot = _snapshot();
    ForegroundService.updateNotification(title: snapshot.title, text: snapshot.text, progress: snapshot.percentage);
    TransferProgressWindow.update(title: snapshot.windowTitle, text: snapshot.windowText, percentage: snapshot.percentage);
  }

  /// Unregisters a transfer, stopping the service once the last one is gone.
  ///
  /// [outcome] keeps the Windows window visible for the configured duration and
  /// shows the matching text instead of hiding it immediately. Without an outcome
  /// (e.g. the user closing the progress page) the window hides right away.
  static void stop(String sessionId, {TransferOutcome? outcome}) {
    final transfer = _transfers.remove(sessionId);
    if (transfer == null) {
      return;
    }

    if (_transfers.isEmpty) {
      ForegroundService.stop();
      if (outcome != null) {
        _showOutcome(transfer, outcome);
      } else {
        _cancelCompletionTimer();
        TransferProgressWindow.hide();
      }
    } else {
      final snapshot = _snapshot();
      ForegroundService.updateNotification(title: snapshot.title, text: snapshot.text, progress: snapshot.percentage);
      TransferProgressWindow.update(title: snapshot.windowTitle, text: snapshot.windowText, percentage: snapshot.percentage);
    }
  }

  static void _showOutcome(_Transfer transfer, TransferOutcome outcome) {
    _cancelCompletionTimer();

    var remainingSeconds = _completionDisplayDuration.inSeconds;
    if (remainingSeconds <= 0) {
      TransferProgressWindow.hide();
      return;
    }

    final title = _outcomeTitle(transfer, outcome);
    final percentage = _outcomePercentage(transfer, outcome);
    TransferProgressWindow.show(
      title: title,
      text: _outcomeText(transfer, outcome, remainingSeconds: remainingSeconds),
      percentage: percentage,
    );

    _completionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remainingSeconds--;
      if (remainingSeconds <= 0) {
        timer.cancel();
        _completionTimer = null;
        TransferProgressWindow.hide();
        return;
      }
      TransferProgressWindow.update(
        title: title,
        text: _outcomeText(transfer, outcome, remainingSeconds: remainingSeconds),
        percentage: percentage,
      );
    });
  }

  /// The outcome title keeps the file counter of a multi-file transfer.
  static String _outcomeTitle(_Transfer transfer, TransferOutcome outcome) {
    final strings = _requiredStrings;
    final title = switch (outcome) {
      TransferOutcome.completed => strings.titleCompleted,
      TransferOutcome.failed => strings.titleFailed,
      TransferOutcome.canceled => strings.titleCanceled,
    };
    final filesCount = transfer.totalFiles > 1 ? '${transfer.finishedFiles}/${transfer.totalFiles}' : null;
    return filesCount != null ? '$title\u0001$filesCount' : title;
  }

  static int _outcomePercentage(_Transfer transfer, TransferOutcome outcome) {
    if (outcome == TransferOutcome.completed) {
      return 100;
    }
    return transfer.totalBytes == 0 ? 0 : (100 * transfer.currentBytes / transfer.totalBytes).floor();
  }

  /// The outcome body keeps the percentage and sizes, and replaces the remaining
  /// time with the countdown until the window disappears.
  static String _outcomeText(
    _Transfer transfer,
    TransferOutcome outcome, {
    required int remainingSeconds,
  }) {
    final strings = _requiredStrings;
    final percentage = _outcomePercentage(transfer, outcome);
    final readableCurrent = transfer.currentBytes.asReadableFileSize;
    final readableTotal = transfer.totalBytes.asReadableFileSize;
    final text = StringBuffer('$percentage%\t$readableCurrent / $readableTotal');

    final countdown = strings.completionCountdown(seconds: remainingSeconds);
    final speed = transfer.speedInBytes;
    if (speed != null) {
      text.write('\n$countdown\t${speed.asReadableFileSize}/s');
    } else {
      text.write('\n$countdown');
    }

    return text.toString();
  }

  static void _cancelCompletionTimer() {
    _completionTimer?.cancel();
    _completionTimer = null;
  }

  /// The transfer speed in bytes per second, or null while it cannot be measured yet.
  static int? _speed({required int currentBytes, required int? startTime, required int? endTime}) {
    if (startTime == null || currentBytes < _minBytesForSpeed) {
      return null;
    }

    final end = endTime ?? DateTime.now().millisecondsSinceEpoch;
    if (end <= startTime) {
      // guards the division in [getFileSpeed]
      return null;
    }

    return getFileSpeed(start: startTime, end: end, bytes: currentBytes);
  }

  static NotificationStrings get _requiredStrings {
    final strings = _strings;
    if (strings == null) {
      throw StateError('TransferNotification.init() must be called before a transfer starts');
    }
    return strings;
  }

  static String _title() {
    final receiving = _transfers.values.any((transfer) => transfer.receiving);
    final sending = _transfers.values.any((transfer) => !transfer.receiving);
    final strings = _requiredStrings;

    if (receiving && sending) {
      return '${strings.titleReceiving} · ${strings.titleSending}';
    }
    return receiving ? strings.titleReceiving : strings.titleSending;
  }

  /// The combined progress of all running transfers:
  /// 42% (1.2 MB / 3.4 MB)
  /// 0:45 · 1.2 MB/s
  static ({String title, String windowTitle, String text, String windowText, int percentage}) _snapshot() {
    int currentBytes = 0;
    int totalBytes = 0;
    int finishedFiles = 0;
    int totalFiles = 0;
    int? speedInBytes;
    for (final transfer in _transfers.values) {
      currentBytes += transfer.currentBytes;
      totalBytes += transfer.totalBytes;
      finishedFiles += transfer.finishedFiles;
      totalFiles += transfer.totalFiles;
      final speed = transfer.speedInBytes;
      if (speed != null) {
        speedInBytes = (speedInBytes ?? 0) + speed;
      }
    }

    final percentage = totalBytes == 0 ? 0 : (100 * currentBytes / totalBytes).floor();
    final readableCurrent = currentBytes.asReadableFileSize;
    final readableTotal = totalBytes.asReadableFileSize;
    // Show the file currently being worked on (1-based), not the number already finished.
    final currentFile = finishedFiles < totalFiles ? finishedFiles + 1 : finishedFiles;
    final filesCount = totalFiles > 1 ? '$currentFile/$totalFiles' : null;
    final title = _title();
    final text = StringBuffer('$percentage% ($readableCurrent / $readableTotal)');
    // The Windows window draws the part after the tab on the right edge. A control
    // character in the title starts a muted, smaller file counter.
    final windowTitle = filesCount != null ? '$title\u0001$filesCount' : title;
    final windowText = StringBuffer('$percentage%\t$readableCurrent / $readableTotal');

    if (speedInBytes != null) {
      final remaining = getRemainingTime(bytesPerSeconds: speedInBytes, remainingBytes: totalBytes - currentBytes, strings: _requiredStrings);
      text.write('\n$remaining · ${speedInBytes.asReadableFileSize}/s');
      windowText.write('\n$remaining\t${speedInBytes.asReadableFileSize}/s');
    } else if (filesCount != null) {
      text.write('\n$filesCount');
    }

    return (title: title, windowTitle: windowTitle, text: text.toString(), windowText: windowText.toString(), percentage: percentage);
  }
}

class _Transfer {
  final bool receiving;
  int currentBytes = 0;
  int totalBytes = 0;
  int finishedFiles = 0;
  int totalFiles = 0;
  int? speedInBytes;

  _Transfer({required this.receiving});
}
