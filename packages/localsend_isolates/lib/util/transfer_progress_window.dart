import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('TransferProgressWindow');

/// Drives the native always-on-top progress window on Windows.
///
/// The window is created and painted by the Windows runner; this class only forwards the
/// aggregated transfer state over a method channel.
class TransferProgressWindow {
  TransferProgressWindow._();

  static const _channel = MethodChannel('org.localsend.localsend_app/transfer_progress');

  /// The native window interpolates between updates, so it can follow the transfer much more
  /// closely than the Android notification, which stays throttled by [ForegroundService].
  static const _updateInterval = Duration(milliseconds: 100);

  static bool _visible = false;
  static DateTime? _lastUpdate;
  static String? _lastTitle;
  static String? _lastText;
  static int? _lastProgress;
  static bool _dark = false;
  static int _background = 0xFFF5F5F5;
  static int _foreground = 0xFF1F1F1F;
  static int _accent = 0xFF0078D4;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Updates the colors used by the native window. Call this whenever the app theme changes.
  static void setTheme({
    required bool dark,
    required int background,
    required int foreground,
    required int accent,
  }) {
    _dark = dark;
    _background = background;
    _foreground = foreground;
    _accent = accent;
  }

  static Map<String, dynamic> _themeArguments() => {
    'dark': _dark,
    'background': _background,
    'foreground': _foreground,
    'accent': _accent,
  };

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.windows;

  static void Function(String action)? _actionHandler;
  static void Function()? _hideHandler;
  static void Function(List<String> args)? _secondInstanceHandler;

  /// 正在等待原生 PIN 输入框的结果。
  static Completer<String?>? _pinCompleter;

  /// 正在等待原生设备选择器的结果（选中项下标；null = 取消）。
  static Completer<int?>? _pickerCompleter;

  /// Registers the handler for the native window actions (`accept`, `decline`, `open`, `hide`).
  static void setActionHandler(void Function(String action)? handler) {
    _actionHandler = handler;
    _syncMethodCallHandler();
  }

  /// Registers a callback invoked whenever the native close button hides the card.
  ///
  /// Kept separate from [setActionHandler] so the receive flow can handle
  /// accept/decline while pending quick-send states are still cleared on close.
  static void setHideHandler(void Function()? handler) {
    _hideHandler = handler;
    _syncMethodCallHandler();
  }

  /// Registers the handler for a second launch forwarded by the Windows runner.
  ///
  /// This covers double-clicking the exe and picking LocalSend in the Windows
  /// Share menu while an instance is already running: the native runner hands
  /// the command line over without starting a second Flutter engine.
  static void setSecondInstanceHandler(void Function(List<String> args)? handler) {
    _secondInstanceHandler = handler;
    _syncMethodCallHandler();
  }

  static void _syncMethodCallHandler() {
    final hasHandler =
        _actionHandler != null || _hideHandler != null || _secondInstanceHandler != null || _pinCompleter != null || _pickerCompleter != null;
    _channel.setMethodCallHandler(hasHandler ? _handleMethodCall : null);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onWindowAction') {
      final arguments = call.arguments;
      if (arguments is Map && arguments['action'] is String) {
        final action = arguments['action'] as String;
        if (action == 'hide') {
          _hideHandler?.call();
          if (_actionHandler == null) {
            hide();
          }
        }
        _actionHandler?.call(action);
      }
    } else if (call.method == 'onSecondInstance') {
      final arguments = call.arguments;
      if (arguments is List) {
        _secondInstanceHandler?.call(arguments.whereType<String>().toList(growable: false));
      }
    } else if (call.method == 'onPinResult') {
      final arguments = call.arguments;
      String? pin;
      if (arguments is Map) {
        final value = arguments['pin'];
        if (value is String && value.isNotEmpty) {
          pin = value;
        }
      }
      _completePin(pin);
    } else if (call.method == 'onDevicePick') {
      final arguments = call.arguments;
      int? index;
      if (arguments is Map) {
        final value = arguments['index'];
        if (value is int && value >= 0) {
          index = value;
        }
      }
      _completePicker(index);
    }
    return null;
  }

  static void _completePicker(int? index) {
    final completer = _pickerCompleter;
    _pickerCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(index);
    }
    _syncMethodCallHandler();
  }

  static void _completePin(String? pin) {
    final completer = _pinCompleter;
    _pinCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(pin);
    }
    _syncMethodCallHandler();
  }

  /// Shows the waiting state with accept/decline buttons until the transfer starts.
  static void showWaiting({
    required String title,
    required String text,
    required String acceptLabel,
    required String declineLabel,
  }) {
    if (!isSupported) {
      return;
    }

    _visible = true;
    _lastUpdate = now();
    _lastTitle = title;
    _lastText = text;
    _lastProgress = null;
    unawaited(
      _invoke('showWaiting', {
        'title': title,
        'text': text,
        'acceptLabel': acceptLabel,
        'declineLabel': declineLabel,
        ..._themeArguments(),
      }),
    );
  }

  /// Whether [update] would actually forward an update right now.
  /// Lets callers skip summing up the progress of every file for an update that gets throttled away.
  static bool get shouldUpdate {
    if (!isSupported || !_visible) {
      return false;
    }
    final lastUpdate = _lastUpdate;
    return lastUpdate == null || now().difference(lastUpdate) >= _updateInterval;
  }

  static void show({
    required String title,
    required String text,
    required int percentage,
    bool indeterminate = false,
    bool showBar = true,
  }) {
    if (!isSupported) {
      return;
    }

    _visible = true;
    _lastUpdate = now();
    _lastTitle = title;
    _lastText = text;
    _lastProgress = percentage;
    unawaited(
      _invoke('showProgress', {
        'title': title,
        'text': text,
        'progress': percentage / 100,
        'indeterminate': indeterminate,
        'bar': showBar,
        ..._themeArguments(),
      }),
    );
  }

  static void update({required String title, required String text, required int percentage, bool showBar = true}) {
    if (!isSupported || !_visible) {
      return;
    }

    final current = now();
    final lastUpdate = _lastUpdate;
    if (lastUpdate != null && current.difference(lastUpdate) < _updateInterval) {
      return;
    }
    _lastUpdate = current;

    if (title == _lastTitle && text == _lastText && percentage == _lastProgress) {
      return;
    }
    _lastTitle = title;
    _lastText = text;
    _lastProgress = percentage;
    unawaited(
      _invoke('updateProgress', {
        'title': title,
        'text': text,
        'progress': percentage / 100,
        'bar': showBar,
        ..._themeArguments(),
      }),
    );
  }

  static void hide() {
    if (!isSupported) {
      return;
    }

    // Hiding cancels a PIN prompt and the device picker natively; complete them
    // here as well so the caller never waits on a window that is gone.
    _completePin(null);
    _completePicker(null);
    final wasVisible = _visible;
    _visible = false;
    _lastUpdate = null;
    _lastTitle = null;
    _lastText = null;
    _lastProgress = null;
    if (wasVisible) {
      unawaited(_invoke('hideProgress', const {}));
    }
  }

  /// Hides the progress/waiting state but leaves an open PIN prompt alone.
  static void hideProgressOnly() {
    if (!isSupported) {
      return;
    }

    final wasVisible = _visible;
    _visible = false;
    _lastUpdate = null;
    _lastTitle = null;
    _lastText = null;
    _lastProgress = null;
    if (wasVisible) {
      unawaited(_invoke('hideProgressOnly', const {}));
    }
  }

  /// Asks the receiver for a PIN in the native window and waits for the answer.
  ///
  /// The future completes with `null` when the prompt was canceled, hidden, or a
  /// receive request took the window over. A previous prompt is canceled.
  static Future<String?> showPin({
    required String title,
    required String text,
    required bool invalid,
    required String confirmLabel,
    required String cancelLabel,
  }) {
    if (!isSupported) {
      return Future<String?>.value(null);
    }

    _completePin(null);
    _completePicker(null);
    final completer = Completer<String?>();
    _pinCompleter = completer;
    _syncMethodCallHandler();

    _visible = true;
    _lastUpdate = now();
    _lastTitle = title;
    _lastText = text;
    _lastProgress = null;
    unawaited(() async {
      try {
        await _channel.invokeMethod<void>('showPin', {
          'title': title,
          'text': text,
          'invalid': invalid,
          'confirmLabel': confirmLabel,
          'cancelLabel': cancelLabel,
          ..._themeArguments(),
        });
      } catch (e) {
        // 原生窗口不可用时按取消处理，避免发送会话永久等待。
        _logger.warning('Could not show the PIN prompt', e);
        _completePin(null);
      }
    }());
    return completer.future;
  }

  /// Asks the user to pick one of the discovered devices in the native window.
  ///
  /// Returns the selected index or `null` when canceled/hidden. The labels are
  /// shown in the combo box; [infos] is displayed below it for the selection.
  static Future<int?> showDevicePicker({
    required String title,
    required List<String> labels,
    required List<String> infos,
    required String sendLabel,
    required String cancelLabel,
  }) {
    if (!isSupported) {
      return Future<int?>.value(null);
    }

    _completePicker(null);
    _completePin(null);
    final completer = Completer<int?>();
    _pickerCompleter = completer;
    _syncMethodCallHandler();

    _visible = true;
    _lastUpdate = now();
    _lastTitle = title;
    _lastText = null;
    _lastProgress = null;
    unawaited(() async {
      try {
        await _channel.invokeMethod<void>('showDevicePicker', {
          'title': title,
          'text': '',
          'labels': labels,
          'infos': infos,
          'sendLabel': sendLabel,
          'cancelLabel': cancelLabel,
          ..._themeArguments(),
        });
      } catch (e) {
        _logger.warning('Could not show the device picker', e);
        _completePicker(null);
      }
    }());
    return completer.future;
  }

  @visibleForTesting
  static void resetForTest() {
    _completePin(null);
    _completePicker(null);
    _visible = false;
    _lastUpdate = null;
    _lastTitle = null;
    _lastText = null;
    _lastProgress = null;
    now = DateTime.now;
  }

  static Future<void> _invoke(String method, Map<String, dynamic> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      // MissingPluginException in tests, or the channel is gone while the app is shutting down.
      _logger.warning('Transfer progress window call failed', e);
    }
  }
}
