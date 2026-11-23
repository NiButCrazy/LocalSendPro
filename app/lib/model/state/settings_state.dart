import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/history_direction_filter.dart';
import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_isolates/model/device.dart';

part 'settings_state.mapper.dart';

@MappableClass()
class SettingsState with SettingsStateMappable {
  final String showToken; // the token to show / maximize the window because only one instance is allowed
  final String alias;
  final ThemeMode theme;
  final ColorMode colorMode;
  final Color customColor; // seed color for ColorMode.custom
  final AppLocale? locale;
  final int port;
  final List<String>? networkWhitelist; // null = disabled
  final List<String>? networkBlacklist; // null = disabled
  final String multicastGroup;
  final String? destination; // null = default
  final bool saveToGallery; // only Android, iOS
  final bool saveToHistory;
  final int historyLimit; // number of entries kept in the persistent history, 0 = unlimited
  final HistoryDirectionFilter historyDefaultFilter;
  final HistoryLayer historyDefaultLayer;
  final bool quickSave; // automatically accept file requests
  final bool quickSaveFromFavorites; // automatically accept file requests from favorites
  final String? receivePin; // null = disabled
  final bool autoFinish; // automatically finish sessions
  final bool minimizeToTray; // minimize to tray instead of exiting the app
  final bool backgroundMode; // keep running in the tray and pause UI rendering while hidden
  final bool showTrayIcon; // show the system tray icon (Windows)
  final int transferCompletedDuration; // seconds the transfer completion window stays visible (Windows)
  final bool https;
  final SendMode sendMode;
  final bool saveWindowPlacement;
  final bool alwaysOnTop;
  final bool framelessWindow; // hide the native title bar and use the in-app one (Windows)
  final bool enableAnimations;
  final DeviceType? deviceType;
  final String? deviceModel;
  final bool shareViaLinkAutoAccept;
  final bool receiveViaLinkAutoAccept;
  final bool createChecksums; // create checksums when sending files
  final bool verifyChecksums; // verify checksums when receiving files
  final int discoveryTimeout;
  final bool advancedSettings;
  final bool contextMenuQuickSend; // list nearby devices in the Windows context menu submenu
  final bool contextMenuIcon; // show the app icon on the context menu entry

  const SettingsState({
    required this.showToken,
    required this.alias,
    required this.theme,
    required this.colorMode,
    required this.customColor,
    required this.locale,
    required this.port,
    required this.networkWhitelist,
    required this.networkBlacklist,
    required this.multicastGroup,
    required this.destination,
    required this.saveToGallery,
    required this.saveToHistory,
    required this.historyLimit,
    required this.historyDefaultFilter,
    required this.historyDefaultLayer,
    required this.quickSave,
    required this.quickSaveFromFavorites,
    required this.receivePin,
    required this.autoFinish,
    required this.minimizeToTray,
    required this.backgroundMode,
    required this.showTrayIcon,
    required this.transferCompletedDuration,
    required this.https,
    required this.sendMode,
    required this.saveWindowPlacement,
    required this.alwaysOnTop,
    required this.framelessWindow,
    required this.enableAnimations,
    required this.deviceType,
    required this.deviceModel,
    required this.shareViaLinkAutoAccept,
    required this.receiveViaLinkAutoAccept,
    required this.createChecksums,
    required this.verifyChecksums,
    required this.discoveryTimeout,
    required this.advancedSettings,
    required this.contextMenuQuickSend,
    required this.contextMenuIcon,
  });
}
