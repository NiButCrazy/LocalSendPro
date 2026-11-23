import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:localsend_isolates/util/transfer_progress_window.dart';

/// PIN 输入入口。
///
/// 主窗口隐藏或调用方强制要求时使用原生通知窗口，否则使用应用内对话框。
/// 原生窗口返回 `null` 表示用户取消或窗口被接收请求抢占。
class PinPrompt {
  PinPrompt._();

  static Future<String?> show({
    required BuildContext context,
    required String title,
    required String text,
    required bool invalid,
    required bool forceNative,
  }) async {
    if (TransferProgressWindow.isSupported && (forceNative || !TransferNotification.isMainWindowActive)) {
      return TransferProgressWindow.showPin(
        title: title,
        text: text,
        invalid: invalid,
        confirmLabel: t.general.confirm,
        cancelLabel: t.general.cancel,
      );
    }

    if (!TransferNotification.isMainWindowActive) {
      await showFromTray();
    }
    if (!context.mounted) {
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (_) => PinDialog(
        obscureText: true,
        showInvalidPin: invalid,
      ),
    );
  }
}
