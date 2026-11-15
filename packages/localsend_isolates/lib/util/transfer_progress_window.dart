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

  /// Same interval as [ForegroundService]: the native window does not need more repaints.
  static const _updateInterval = Duration(milliseconds: 500);

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

  /// Registers the handler for the native window actions (`accept`, `decline`, `open`, `hide`).
  static void setActionHandler(void Function(String action)? handler) {
    _actionHandler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onWindowAction') {
      return null;
    }
    final arguments = call.arguments;
    if (arguments is Map && arguments['action'] is String) {
      _actionHandler?.call(arguments['action'] as String);
    }
    return null;
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

  static void show({required String title, required String text, required int percentage}) {
    if (!isSupported) {
      return;
    }

    _visible = true;
    _lastUpdate = now();
    _lastTitle = title;
    _lastText = text;
    _lastProgress = percentage;
    unawaited(_invoke('showProgress', {'title': title, 'text': text, 'progress': percentage / 100, ..._themeArguments()}));
  }

  static void update({required String title, required String text, required int percentage}) {
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
    unawaited(_invoke('updateProgress', {'title': title, 'text': text, 'progress': percentage / 100, ..._themeArguments()}));
  }

  static void hide() {
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
      unawaited(_invoke('hideProgress', const {}));
    }
  }

  @visibleForTesting
  static void resetForTest() {
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
