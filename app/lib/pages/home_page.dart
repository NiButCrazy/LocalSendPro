import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/pages/tabs/transfer_history_tab.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:window_manager/window_manager.dart';

enum HomeTab {
  receive(Icons.wifi),
  send(Icons.send),
  history(Icons.history),
  settings(Icons.settings);

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.history:
        return t.receiveHistoryPage.title;
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena, WindowListener {
  bool _dragAndDropIndicator = false;

  /// 右键菜单设备子菜单的防抖定时器（仅 Windows）。
  Timer? _contextMenuDebounce;

  /// 监听设置/设备/收藏变化的订阅。
  final _contextMenuSubscriptions = <StreamSubscription<dynamic>>[];

  /// 上一次写入子菜单时的内容签名，避免无变化时打开注册表。
  String? _contextMenuSignature;

  @override
  void initState() {
    super.initState();

    if (checkPlatform([TargetPlatform.windows])) {
      windowManager.addListener(this);
      unawaited(_syncMainWindowActive());
    }

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
      if (!mounted) {
        return;
      }
      if (checkPlatform([TargetPlatform.windows])) {
        _startContextMenuSync();
        await _syncContextMenuDevices();
      }
    });
  }

  @override
  void dispose() {
    _contextMenuDebounce?.cancel();
    for (final subscription in _contextMenuSubscriptions) {
      unawaited(subscription.cancel());
    }
    if (checkPlatform([TargetPlatform.windows])) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// 设备、收藏或开关变化后合并 500ms 内的多次事件，再写一次注册表。
  void _startContextMenuSync() {
    void onChange() {
      _contextMenuDebounce?.cancel();
      _contextMenuDebounce = Timer(const Duration(milliseconds: 500), () => unawaited(_syncContextMenuDevices()));
    }

    _contextMenuSubscriptions
      ..add(ref.stream(settingsProvider).listen((_) => onChange()))
      ..add(ref.stream(nearbyDevicesProvider).listen((_) => onChange()))
      ..add(ref.stream(favoritesProvider).listen((_) => onChange()));
  }

  /// 把当前发现列表同步到右键菜单的设备子菜单。
  Future<void> _syncContextMenuDevices() async {
    if (!mounted) {
      return;
    }

    final quickSend = ref.read(settingsProvider).contextMenuQuickSend;
    if (!quickSend) {
      if (_contextMenuSignature == 'off') {
        return;
      }
      _contextMenuSignature = 'off';
      await updateContextMenuDevices(quickSend: false, devices: const [], favoriteFingerprints: const {});
      return;
    }

    final devices = ref.read(nearbyDevicesProvider).allDevices.values.toList(growable: false);
    final favorites = ref.read(favoritesProvider).map((favorite) => favorite.fingerprint).toSet();
    final signature = [
      'on',
      for (final entry in buildDeviceMenuEntries(devices: devices, favoriteFingerprints: favorites))
        '${entry.fingerprint}|${entry.displayAlias}|${entry.favorite}',
    ].join('\n');
    if (signature == _contextMenuSignature) {
      return;
    }

    _contextMenuSignature = signature;
    await updateContextMenuDevices(quickSend: true, devices: devices, favoriteFingerprints: favorites);
  }

  /// Keeps the native transfer window hidden while the app window is usable.
  Future<void> _syncMainWindowActive() async {
    final visible = await windowManager.isVisible();
    final minimized = await windowManager.isMinimized();
    TransferNotification.setMainWindowActive(visible && !minimized);
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'show' || eventName == 'hide') {
      unawaited(_syncMainWindowActive());
    }
  }

  @override
  void onWindowMinimize() => unawaited(_syncMainWindowActive());

  @override
  void onWindowRestore() => unawaited(_syncMainWindowActive());

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);
    final framelessWindow = context.watch(settingsProvider.select((settings) => settings.framelessWindow));

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        // the drop may contain a mix of files and directories
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();

        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }

        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: droppedFiles,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          return Scaffold(
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  NavigationRail(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    extended: sizingInformation.isDesktop,
                    backgroundColor: Theme.of(context).cardColorWithElevation,
                    leading: sizingInformation.isDesktop
                        ? const Column(
                            children: [
                              SizedBox(height: 20),
                              Text(
                                'LocalSend',
                                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 20),
                            ],
                          )
                        : null,
                    destinations: HomeTab.values.map((tab) {
                      return NavigationRailDestination(
                        icon: Icon(tab.icon),
                        label: Text(tab.label),
                      );
                    }).toList(),
                  ),
                Expanded(
                  child: ColoredBox(
                    color: framelessWindow && !sizingInformation.isMobile ? Theme.of(context).cardColorWithElevation : Colors.transparent,
                    child: ClipRRect(
                      borderRadius: framelessWindow && !sizingInformation.isMobile
                          ? const BorderRadius.vertical(top: Radius.circular(12))
                          : BorderRadius.zero,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: SafeArea(
                          left: sizingInformation.isMobile,
                          child: Stack(
                            children: [
                              PageView(
                                controller: vm.controller,
                                physics: const NeverScrollableScrollPhysics(),
                                children: const [
                                  ReceiveTab(),
                                  SendTab(),
                                  TransferHistoryTab(),
                                  SettingsTab(),
                                ],
                              ),
                              if (_dragAndDropIndicator)
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.file_download, size: 128),
                                      const SizedBox(height: 30),
                                      Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleLarge),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? NavigationBar(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(icon: Icon(tab.icon), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
  }
}
