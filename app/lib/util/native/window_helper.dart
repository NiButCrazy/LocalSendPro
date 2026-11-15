import 'package:localsend_app/util/native/platform_check.dart';
import 'package:window_manager/window_manager.dart';

/// Hides or restores the native title bar.
///
/// Requires [WindowManager.ensureInitialized] to have completed.
/// No-op on platforms that do not support the in-app title bar.
Future<void> applyFramelessWindow(bool frameless) async {
  if (!checkPlatformSupportsFramelessWindow()) {
    return;
  }

  await windowManager.setTitleBarStyle(
    frameless ? TitleBarStyle.hidden : TitleBarStyle.normal,
    windowButtonVisibility: false,
  );
}
