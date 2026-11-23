import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('QuickSend');

/// 解析 `--send-to <fingerprint>` 的目标设备指纹。
///
/// 参数缺失或为空时返回 null，调用方按普通启动处理。
@visibleForTesting
String? sendToFingerprint(List<String> args) {
  final index = args.indexOf('--send-to');
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  final value = args[index + 1].trim();
  return value.isEmpty ? null : value;
}

final quickSendCoordinatorProvider = Provider<QuickSendCoordinator>((ref) => QuickSendCoordinator(ref));

/// 处理右键菜单的快速发送：合并多选文件、等待设备被发现、直接开始会话。
class QuickSendCoordinator {
  QuickSendCoordinator(this._ref);

  final Ref _ref;

  /// 多选时 Explorer 会为每个选中项各启动一次进程，用防抖把它们合并成一个会话。
  static const _debounce = Duration(milliseconds: 500);

  /// 设备不在发现列表时最多等待多久。
  static const _deviceTimeout = Duration(seconds: 10);
  static const _pollInterval = Duration(milliseconds: 200);

  final Map<String, Timer> _timers = {};

  /// 已开始收集文件、尚未发送的批次（按指纹）。
  final Set<String> _batches = {};

  Future<void> handle(List<String> args) async {
    final fingerprint = sendToFingerprint(args);
    if (fingerprint == null) {
      // 普通启动：保持原有行为。
      final filesAdded = await _ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
      if (filesAdded) {
        _ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
      }
      return;
    }

    if (_batches.add(fingerprint)) {
      // 新一批：先清掉上一轮普通发送或上一次快速发送残留的文件。
      _ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    }

    final filesAdded = await _ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
    if (!filesAdded) {
      // 这一批里没有可发送的文件：撤回批次标记，不显示查找通知。
      _batches.remove(fingerprint);
      _timers.remove(fingerprint)?.cancel();
      return;
    }

    TransferNotification.startPending(
      sessionId: _searchSessionId(fingerprint),
      title: t.progressPage.titleSending,
      text: t.contextMenuPage.searching,
      forceWindow: true,
    );

    _timers.remove(fingerprint)?.cancel();
    _timers[fingerprint] = Timer(_debounce, () => unawaited(_sendBatch(fingerprint)));
  }

  Future<void> _sendBatch(String fingerprint) async {
    _timers.remove(fingerprint);
    // 读取文件后立刻结束这一批，下一次点击会重新清空旧选择。
    _batches.remove(fingerprint);

    final files = List<CrossFile>.of(_ref.read(selectedSendingFilesProvider));
    final sessionId = _searchSessionId(fingerprint);
    if (files.isEmpty) {
      TransferNotification.stop(sessionId);
      _fallBackToSendPage();
      return;
    }

    var target = _findDevice(fingerprint);
    if (target == null) {
      _ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
      final deadline = DateTime.now().add(_deviceTimeout);
      while (target == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(_pollInterval);
        target = _findDevice(fingerprint);
      }
    }

    if (target == null) {
      _logger.info('Device $fingerprint was not found in time.');
      TransferNotification.stop(sessionId);
      _fallBackToSendPage();
      return;
    }

    TransferNotification.stop(sessionId);
    await _ref
        .notifier(sendProvider)
        .startSession(
          target: target,
          files: files,
          background: true,
          notifyWhileWaiting: true,
        );
  }

  /// 只有当前可直连的设备才算找到：通过信令发现的设备没有 IP。
  Device? _findDevice(String fingerprint) {
    final device = _ref.read(nearbyDevicesProvider).allDevices[fingerprint];
    if (device == null || device.ip == null || device.download) {
      return null;
    }
    return device;
  }

  void _fallBackToSendPage() {
    unawaited(showFromTray());
    _ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
    Routerino.context.showSnackBar(t.contextMenuPage.deviceUnavailable);
  }

  static String _searchSessionId(String fingerprint) => 'search:$fingerprint';
}

/// 应用启动参数入口：普通启动与右键菜单快速发送共用。
class HandleSendArgumentsAction extends AsyncGlobalAction {
  final List<String> args;

  HandleSendArgumentsAction({required this.args});

  @override
  Future<void> reduce() async {
    await ref.read(quickSendCoordinatorProvider).handle(args);
  }
}
