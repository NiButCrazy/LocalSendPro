import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/device_presence.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:localsend_isolates/util/transfer_progress_window.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:window_manager/window_manager.dart';

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

  /// 占位项扫描阶段的等待通知 id。
  static const _scanSessionId = 'scan:picker';

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

    // 手机端同一时间只处理一个会话：已有请求在等待确认时，新的快速发送会被 409 拒绝，
    // 而第二次请求还会让手机上的旧请求显得像被取消。这里直接拦截并提示。
    if (hasPendingRequest(_ref.read(sendProvider).values, fingerprint)) {
      _showPendingRequestNotice();
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

    // 先进入“查找设备”阶段；扫描确认设备在线后才切到“等待响应”。
    TransferNotification.startPending(
      sessionId: _searchSessionId(fingerprint),
      title: t.sendTab.nearbyDevices,
      text: t.contextMenuPage.searching,
    );

    _timers.remove(fingerprint)?.cancel();
    _timers[fingerprint] = Timer(_debounce, () => unawaited(_sendBatch(fingerprint)));
  }

  Future<void> _sendBatch(String fingerprint, {List<CrossFile>? filesOverride}) async {
    _timers.remove(fingerprint);
    // 读取文件后立刻结束这一批，下一次点击会重新清空旧选择。
    _batches.remove(fingerprint);

    // 扫描选择器打开期间可能有新的 --scan 批次清空全局选择，因此这里使用
    // 进入选择器前捕获的文件列表。
    final files = filesOverride ?? List<CrossFile>.of(_ref.read(selectedSendingFilesProvider));
    _logger.info('Quick send batch for $fingerprint: ${files.length} file(s)');
    final sessionId = _searchSessionId(fingerprint);
    if (files.isEmpty) {
      TransferProgressWindow.hide();
      TransferNotification.stop(sessionId);
      return;
    }

    _logger.info('Quick send to $fingerprint: ${files.length} file(s)');

    final foreground = await _isMainWindowActive();
    if (foreground) {
      // 主页面发送：选择器不要停在屏幕上，扫描阶段由主页面显示。
      TransferProgressWindow.hide();
    }

    // 已存在的设备：立即尝试发送，同时后台再扫描一次刷新在线状态；
    // 不再先等扫描完成。
    var target = _findDevice(fingerprint);
    if (target != null) {
      _refreshPresenceInBackground();
    } else {
      if (!foreground) {
        TransferNotification.startPending(
          sessionId: sessionId,
          title: t.sendTab.nearbyDevices,
          text: t.contextMenuPage.searching,
        );
      }
      target = await _waitForDevice(fingerprint);
    }
    if (target == null) {
      _logger.info('Device $fingerprint was not found in time.');
      // 显示“暂时无法连接”，而不是进入等待响应的会话。
      TransferNotification.stop(
        sessionId,
        outcome: TransferOutcome.failed,
        text: t.sendPage.connectionLost,
      );
      return;
    }

    if (foreground) {
      TransferNotification.stop(sessionId);
      // 选择器仍然是可见的，主页面发送前先收起。
      TransferProgressWindow.hide();
    }
    await _ref
        .notifier(sendProvider)
        .startSession(
          target: target,
          files: files,
          background: !foreground,
          notifyWhileWaiting: !foreground,
          // 隐藏时沿用“查找设备”的会话 id：startPending 会在原位把文字改成“等待响应”，
          // 避免先 hide 再 show，触发原生窗口尚未结束的隐藏动画而瞬间消失。
          sessionIdOverride: foreground ? null : sessionId,
        );
  }

  Device? _findDevice(String fingerprint) {
    final device = _ref.read(nearbyDevicesProvider).allDevices[fingerprint];
    if (device == null || device.ip == null || device.download) {
      return null;
    }
    return device;
  }

  /// 后台刷新发现列表；发送不等它。
  void _refreshPresenceInBackground() {
    _ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
    unawaited(
      _ref.global.dispatchAsync(StartSmartScan()).catchError((Object e) {
        _logger.info('Background presence scan failed: $e');
      }),
    );
  }

  /// 缓存里的设备不代表现在还在线：移除后重新扫描，找到才算存在。
  Future<Device?> _waitForDevice(String fingerprint) {
    return waitForDevicePresence(_ref, fingerprint, timeout: _deviceTimeout);
  }

  /// 主窗口是否可见且未最小化（只有 Windows 有原生通知窗口）。
  Future<bool> _isMainWindowActive() async {
    if (!checkPlatform([TargetPlatform.windows])) {
      return true;
    }
    try {
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      return visible && !minimized;
    } catch (e) {
      _logger.warning('Could not read the main window state', e);
      return TransferNotification.isMainWindowActive;
    }
  }

  /// 占位项“没有可发送的设备”触发的流程：
  /// 加载传入路径 → 扫描（隐藏时显示通知，前台时切到发送页）→ 原生选择器 → 发送。
  Future<void> scanAndPick(List<String> args) async {
    _ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    final filesAdded = await _ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
    if (!filesAdded) {
      return;
    }
    final pickedFiles = List<CrossFile>.of(_ref.read(selectedSendingFilesProvider));

    final foreground = await _isMainWindowActive();
    if (foreground) {
      _ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
    } else {
      TransferNotification.startPending(
        sessionId: _scanSessionId,
        title: t.sendTab.nearbyDevices,
        text: t.contextMenuPage.scanning,
      );
    }

    try {
      await _ref.global.dispatchAsync(StartSmartScan());
    } catch (e) {
      _logger.warning('Scanning for devices failed', e);
      if (!foreground) {
        TransferNotification.stop(_scanSessionId);
      }
      _showNoDevicesNotice();
      return;
    }

    final devices = _pickableDevices();
    if (devices.isEmpty) {
      if (!foreground) {
        TransferNotification.stop(_scanSessionId);
      }
      _showNoDevicesNotice();
      return;
    }
    if (!TransferProgressWindow.isSupported) {
      if (!foreground) {
        TransferNotification.stop(_scanSessionId);
      }
      _fallBackToSendPage();
      return;
    }

    final selected = await TransferProgressWindow.showDevicePicker(
      title: t.sendTab.nearbyDevices,
      labels: [for (final device in devices) device.alias],
      infos: [for (final device in devices) _deviceInfo(device)],
      sendLabel: t.sendTab.title,
      cancelLabel: t.general.cancel,
    );

    TransferProgressWindow.hide();
    if (!foreground) {
      TransferNotification.clearPending(_scanSessionId);
    }

    if (selected == null || selected < 0 || selected >= devices.length) {
      return;
    }

    await _sendBatch(devices[selected].fingerprint, filesOverride: pickedFiles);
  }

  List<Device> _pickableDevices() {
    final favorites = _ref.read(favoritesProvider).map((favorite) => favorite.fingerprint).toSet();
    final devices = _ref.read(nearbyDevicesProvider).allDevices.values.where((device) => device.ip != null && !device.download).toList();
    devices.sort((a, b) {
      final favoriteA = favorites.contains(a.fingerprint);
      final favoriteB = favorites.contains(b.fingerprint);
      if (favoriteA != favoriteB) {
        return favoriteA ? -1 : 1;
      }
      final byAlias = a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
      return byAlias != 0 ? byAlias : a.fingerprint.compareTo(b.fingerprint);
    });
    return devices;
  }

  String _deviceInfo(Device device) {
    return [
      if (device.deviceModel != null) device.deviceModel!,
      device.deviceType.name,
      if (device.ip != null) device.ip!,
    ].join(' · ');
  }

  void _showNoDevicesNotice() {
    TransferNotification.showNotice(
      title: t.sendTab.nearbyDevices,
      text: t.contextMenuPage.noDevicesFound,
    );
  }

  void _fallBackToSendPage() {
    unawaited(showFromTray());
    _ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
    Routerino.context.showSnackBar(t.contextMenuPage.deviceUnavailable);
  }

  /// 已有请求等待确认时，隐藏主窗口下只弹通知，不再把主窗口叫出来。
  void _showPendingRequestNotice() {
    if (!TransferNotification.isMainWindowActive) {
      TransferNotification.showNotice(
        title: t.progressPage.titleSending,
        text: t.contextMenuPage.requestPending,
      );
      return;
    }
    unawaited(showFromTray());
    Routerino.context.showSnackBar(t.contextMenuPage.requestPending);
  }

  static String _searchSessionId(String fingerprint) => 'search:$fingerprint';
}

/// 该设备是否已有请求正在等待对方确认。
///
/// 手机端同一时间只允许一个会话；等待确认阶段（尚无 `remoteSessionId`）也占用这个位置。
@visibleForTesting
bool hasPendingRequest(Iterable<SendSessionState> sessions, String fingerprint) {
  return sessions.any(
    (session) => session.target.fingerprint == fingerprint && session.status == SessionStatus.waiting && session.remoteSessionId == null,
  );
}

/// 应用启动参数入口：普通启动与右键菜单快速发送共用。
class HandleSendArgumentsAction extends AsyncGlobalAction {
  final List<String> args;

  HandleSendArgumentsAction({required this.args});

  @override
  Future<void> reduce() async {
    if (args.contains('--scan')) {
      await ref.read(quickSendCoordinatorProvider).scanAndPick(args);
      return;
    }
    await ref.read(quickSendCoordinatorProvider).handle(args);
  }
}
