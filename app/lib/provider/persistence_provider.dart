import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/persistence/history_direction_filter.dart';
import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/model/persistence/quick_save_mode.dart';
import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/provider/window_dimensions_provider.dart';
import 'package:localsend_app/util/alias_generator.dart';
import 'package:localsend_app/util/native/autostart_helper.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/persistence/history_storage.dart';
import 'package:localsend_app/util/security_helper.dart';
import 'package:localsend_app/util/shared_preferences/shared_preferences_file.dart';
import 'package:localsend_app/util/shared_preferences/shared_preferences_portable.dart';
import 'package:localsend_app/util/ui/animations_status.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/stored_security_context.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:uuid/uuid.dart';

part 'persistence_provider_migrations.dart';

final _logger = Logger('PersistenceService');

String get _windowsFile {
  final appData = Platform.environment['APPDATA'];
  return '$appData\\LocalSend\\settings.json';
}

String get _windowsLegacyFile {
  final appData = Platform.environment['APPDATA'];
  return '$appData\\org.localsend\\localsend_app\\shared_preferences.json';
}

// Version of the storage
const _version = 'ls_version';

// Security keys (generated on first app start)
const _securityContext = 'ls_security_context';

// WebRTC
const _signalingServers = 'ls_signaling_servers';
const _stunServers = 'ls_stun_servers';

// Transfer history
// Older versions stored the history inside settings.json under this key.
// It is only read once for the migration to history.json.
const _legacyReceiveHistory = 'ls_receive_history';
const _historyLimit = 'ls_history_limit'; // 0 = unlimited
const _historyDefaultFilter = 'ls_history_default_filter';
const _historyDefaultLayer = 'ls_history_default_layer';

// Favorites
const _favorites = 'ls_favorites';

// App Window Offset and Size info
const _windowOffsetX = 'ls_window_offset_x';
const _windowOffsetY = 'ls_window_offset_y';
const _windowWidth = 'ls_window_width';
const _windowHeight = 'ls_window_height';
const _saveWindowPlacement = 'ls_save_window_placement';
const _alwaysOnTop = 'ls_always_on_top';
const _framelessWindow = 'ls_frameless_window';
const _showTrayIcon = 'ls_show_tray_icon';
const _transferCompletedDuration = 'ls_transfer_completed_duration';

// Settings
const _showToken = 'ls_show_token';
const _aliasKey = 'ls_alias';
const _themeKey = 'ls_theme'; // now called brightness
const _colorKey = 'ls_color';
const _customColorKey = 'ls_custom_color'; // RRGGBB hex, used by ColorMode.custom
const _localeKey = 'ls_locale';
const _portKey = 'ls_port';
const _networkWhitelistKey = 'ls_network_whitelist';
const _networkBlacklistKey = 'ls_network_blacklist';
const _timeoutKey = 'ls_timeout';
const _multicastGroupKey = 'ls_multicast_group';
const _destinationKey = 'ls_destination';
const _saveToGallery = 'ls_save_to_gallery';
const _saveToHistory = 'ls_save_to_history';
const _quickSave = 'ls_quick_save'; // a QuickSaveMode; was a bool until storage version 2 ('ls_quick_save_from_favorites' is merged into this key)
const _receivePin = 'ls_receive_pin';
const _autoFinish = 'ls_auto_finish';
const _minimizeToTray = 'ls_minimize_to_tray';
const _backgroundMode = 'ls_background_mode';
const _https = 'ls_https';
const _sendMode = 'ls_send_mode';
const _enableAnimations = 'ls_enable_animations';
const _deviceType = 'ls_device_type';
const _deviceModel = 'ls_device_model';
const _shareViaLinkAutoAccept = 'ls_share_via_link_auto_accept';
const _receiveViaLinkAutoAccept = 'ls_receive_via_link_auto_accept';
const _createChecksums = 'ls_create_checksums';
const _verifyChecksums = 'ls_verify_checksums';
const _advancedSettingsKey = 'ls_advanced_settings';
const _whatsNewKey = 'ls_whats_new';

final persistenceProvider = Provider<PersistenceService>((ref) {
  throw Exception('persistenceProvider not initialized');
});

/// This service abstracts the persistence layer.
class PersistenceService {
  final SharedPreferences _prefs;
  final bool isFirstAppStart;
  final HistoryStorage? _historyStorage;
  final List<TransferHistoryEntry> _history;

  PersistenceService._(this._prefs, this.isFirstAppStart, this._historyStorage, this._history);

  static Future<PersistenceService> initialize({
    required bool supportsDynamicColors,
    @visibleForTesting File? historyFile,
  }) async {
    SharedPreferences prefs;

    final portableStore = SharedPreferencesPortable();
    bool usingLegacyStore = false;
    if (checkPlatform(const [TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS]) && portableStore.exists()) {
      _logger.info('Using portable settings.');
      SharedPreferencesStorePlatform.instance = portableStore;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      final legacyStore = SharedPreferencesFile(filePath: _windowsLegacyFile);
      if (legacyStore.exists()) {
        _logger.info('Using legacy settings. Will migrate in the next step.');
        SharedPreferencesStorePlatform.instance = legacyStore;
        usingLegacyStore = true;
      } else {
        SharedPreferencesStorePlatform.instance = SharedPreferencesFile(filePath: _windowsFile);
      }
    }

    final bool isFirstAppStart;
    final existingPrefs = await SharedPreferencesStorePlatform.instance.getAll();
    final existingVersion = existingPrefs['flutter.$_version'] as int?;
    _logger.info('Existing version: $existingVersion');
    isFirstAppStart = existingVersion == null && !usingLegacyStore && !existingPrefs.keys.any((key) => key.startsWith('flutter.ls_'));
    if (isFirstAppStart) {
      await SharedPreferencesStorePlatform.instance.setValue('Int', 'flutter.$_version', _latestVersion);
    } else {
      // Unversioned profiles in the current store may already contain string modes.
      // Only apply the repair migration; older migrations would replace those modes.
      final fromVersion = existingVersion ?? (usingLegacyStore ? 1 : 3);
      if (fromVersion < _latestVersion) {
        await _runMigrations(fromVersion);
      }
    }

    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      if (checkPlatform([TargetPlatform.windows])) {
        _logger.info('Could not initialize SharedPreferences, trying to delete corrupted settings file', e);
        File(_windowsFile).deleteSync();
        prefs = await SharedPreferences.getInstance();
      } else {
        throw Exception('Could not initialize SharedPreferences');
      }
    }

    // Locale configuration upon persistence initialisation to prevent unlocalised Alias generation
    final persistedLocale = prefs.getString(_localeKey);
    if (persistedLocale == null) {
      await LocaleSettings.useDeviceLocale();
    } else {
      await LocaleSettings.setLocaleRaw(persistedLocale);
    }

    if (prefs.getString(_showToken) == null) {
      await prefs.setString(_showToken, const Uuid().v4());
    }

    if (prefs.getString(_aliasKey) == null) {
      await prefs.setString(_aliasKey, generateRandomAlias());
    }

    if (prefs.getString(_securityContext) == null) {
      await prefs.setString(_securityContext, jsonEncode(await generateSecurityContext()));
    }

    if (isFirstAppStart) {
      final systemAnimations = await getSystemAnimationsStatus();
      if (!systemAnimations) {
        _logger.info('System animations are disabled, disabling animations in the app.');
        await prefs.setBool(_enableAnimations, false);
      }
    }

    if (prefs.getString(_colorKey) == null) {
      await _initColorSetting(prefs, supportsDynamicColors);
    } else {
      // fix when device does not support dynamic colors
      final supported = supportsDynamicColors ? ColorMode.values : ColorMode.values.where((e) => e != ColorMode.system);
      final colorMode = supported.firstWhereOrNull((color) => color.name == prefs.getString(_colorKey));
      if (colorMode == null) {
        await _initColorSetting(prefs, supportsDynamicColors);
      }
    }

    // migrate legacy auto start settings (current implementation is stateless and relies on the Windows registry / file system)
    const launchAtStartupLegacyKey = 'ls_launch_at_startup';
    const launchMinimizedLegacyKey = 'ls_auto_start_launch_minimized';
    if (prefs.getBool(launchAtStartupLegacyKey) == true) {
      _logger.info('Enable auto start on legacy settings');
      await prefs.remove(launchAtStartupLegacyKey);
      await enableAutoStart(startHidden: prefs.getBool(launchMinimizedLegacyKey) == true);
      await prefs.remove(launchMinimizedLegacyKey);
    }

    final resolvedHistoryStorage = _resolveHistoryStorage(historyFile);
    var history = <TransferHistoryEntry>[];
    if (resolvedHistoryStorage != null) {
      history = resolvedHistoryStorage.load();

      final legacyHistory = prefs.getStringList(_legacyReceiveHistory);
      if (legacyHistory != null) {
        var canRemoveLegacy = true;
        if (history.isEmpty && legacyHistory.isNotEmpty) {
          history = _decodeHistory(legacyHistory);
          try {
            await resolvedHistoryStorage.save(history);
          } catch (e, stackTrace) {
            _logger.severe('Could not migrate the transfer history to ${resolvedHistoryStorage.file.path}', e, stackTrace);
            canRemoveLegacy = false;
          }
        }
        if (canRemoveLegacy) {
          await prefs.remove(_legacyReceiveHistory);
        }
      }
    } else {
      // Platforms without a dedicated file keep the legacy storage.
      history = _decodeHistory(prefs.getStringList(_legacyReceiveHistory) ?? const []);
    }

    return PersistenceService._(prefs, isFirstAppStart, resolvedHistoryStorage, history);
  }

  /// Resolves the history file next to the settings or in the user data dir.
  ///
  /// Windows: `%APPDATA%\LocalSend\history.json`
  /// Portable: `<exe directory>\history.json`
  static HistoryStorage? _resolveHistoryStorage(File? override) {
    if (override != null) {
      return HistoryStorage(override);
    }

    final store = SharedPreferencesStorePlatform.instance;
    if (store is SharedPreferencesPortable) {
      return HistoryStorage(File(p.join(File(store.getPath()).parent.path, 'history.json')));
    }

    if (checkPlatform([TargetPlatform.windows])) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        return null;
      }
      return HistoryStorage(File(p.join(appData, 'LocalSend', 'history.json')));
    }

    if (checkPlatform([TargetPlatform.linux])) {
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'];
      final base = xdgDataHome != null && xdgDataHome.isNotEmpty
          ? xdgDataHome
          : home != null && home.isNotEmpty
          ? p.join(home, '.local', 'share')
          : null;
      if (base == null) {
        return null;
      }
      return HistoryStorage(File(p.join(base, 'localsend', 'history.json')));
    }

    if (checkPlatform([TargetPlatform.macOS])) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        return null;
      }
      return HistoryStorage(File(p.join(home, 'Library', 'Application Support', 'LocalSend', 'history.json')));
    }

    return null;
  }

  static List<TransferHistoryEntry> _decodeHistory(List<String> rawEntries) {
    final entries = <TransferHistoryEntry>[];
    for (final rawEntry in rawEntries) {
      try {
        entries.add(TransferHistoryEntry.fromJson(jsonDecode(rawEntry)));
      } catch (e, stackTrace) {
        _logger.warning('Skipping an unreadable transfer history entry', e, stackTrace);
      }
    }
    return entries;
  }

  static Future<void> _initColorSetting(SharedPreferences prefs, bool supportsDynamicColors) async {
    await prefs.setString(
      _colorKey,
      checkPlatform([TargetPlatform.android]) && supportsDynamicColors ? ColorMode.system.name : ColorMode.localsend.name,
    );
  }

  bool isPortableMode() {
    return SharedPreferencesStorePlatform.instance is SharedPreferencesPortable;
  }

  StoredSecurityContext getSecurityContext() {
    final contextRaw = _prefs.getString(_securityContext)!;
    return StoredSecurityContext.fromJson(jsonDecode(contextRaw));
  }

  Future<void> setSecurityContext(StoredSecurityContext context) async {
    await _prefs.setString(_securityContext, jsonEncode(context));
  }

  List<String>? getSignalingServers() {
    final serversRaw = _prefs.getString(_signalingServers);
    if (serversRaw == null) {
      return null;
    }

    return (jsonDecode(serversRaw) as List).cast<String>();
  }

  Future<void> setSignalingServers(List<String> servers) async {
    await _prefs.setString(_signalingServers, jsonEncode(servers));
  }

  List<String>? getStunServers() {
    final serversRaw = _prefs.getString(_stunServers);
    if (serversRaw == null) {
      return null;
    }

    return (jsonDecode(serversRaw) as List).cast<String>();
  }

  Future<void> setStunServers(List<String> servers) async {
    await _prefs.setString(_stunServers, jsonEncode(servers));
  }

  List<TransferHistoryEntry> getTransferHistory() {
    return List.unmodifiable(_history);
  }

  Future<void> setTransferHistory(List<TransferHistoryEntry> entries) async {
    _history
      ..clear()
      ..addAll(entries);

    final storage = _historyStorage;
    if (storage != null) {
      try {
        await storage.save(entries);
      } catch (e, stackTrace) {
        _logger.severe('Could not write the transfer history to ${storage.file.path}', e, stackTrace);
      }
      return;
    }

    // Legacy platforms keep the history inside SharedPreferences.
    final historyRaw = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await _prefs.setStringList(_legacyReceiveHistory, historyRaw);
  }

  /// The number of entries kept in the persistent history. `0` means unlimited.
  int getHistoryLimit() {
    return (_prefs.getInt(_historyLimit) ?? 0).clamp(0, 10000);
  }

  Future<void> setHistoryLimit(int limit) async {
    await _prefs.setInt(_historyLimit, limit.clamp(0, 10000));
  }

  HistoryDirectionFilter getHistoryDefaultFilter() {
    final value = _prefs.getString(_historyDefaultFilter);
    return HistoryDirectionFilter.values.firstWhereOrNull((filter) => filter.name == value) ?? HistoryDirectionFilter.all;
  }

  Future<void> setHistoryDefaultFilter(HistoryDirectionFilter filter) async {
    await _prefs.setString(_historyDefaultFilter, filter.name);
  }

  HistoryLayer getHistoryDefaultLayer() {
    final value = _prefs.getString(_historyDefaultLayer);
    return HistoryLayer.values.firstWhereOrNull((layer) => layer.name == value) ?? HistoryLayer.runtime;
  }

  Future<void> setHistoryDefaultLayer(HistoryLayer layer) async {
    await _prefs.setString(_historyDefaultLayer, layer.name);
  }

  List<FavoriteDevice> getFavorites() {
    final favoritesRaw = _prefs.getStringList(_favorites) ?? [];
    return favoritesRaw.map((entry) => FavoriteDevice.fromJson(jsonDecode(entry))).toList();
  }

  Future<void> setFavorites(List<FavoriteDevice> entries) async {
    final favoritesRaw = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await _prefs.setStringList(_favorites, favoritesRaw);
  }

  String getShowToken() {
    return _prefs.getString(_showToken)!;
  }

  String getAlias() {
    return _prefs.getString(_aliasKey) ?? generateRandomAlias();
  }

  Future<void> setAlias(String alias) async {
    await _prefs.setString(_aliasKey, alias);
  }

  ThemeMode getTheme() {
    final value = _prefs.getString(_themeKey);
    if (value == null) {
      return ThemeMode.system;
    }
    return ThemeMode.values.firstWhereOrNull((theme) => theme.name == value) ?? ThemeMode.system;
  }

  Future<void> setTheme(ThemeMode theme) async {
    await _prefs.setString(_themeKey, theme.name);
  }

  ColorMode getColorMode() {
    final value = _prefs.getString(_colorKey);
    if (value == null) {
      return ColorMode.system;
    }
    return ColorMode.values.firstWhereOrNull((color) => color.name == value) ?? ColorMode.system;
  }

  Future<void> setColorMode(ColorMode color) async {
    await _prefs.setString(_colorKey, color.name);
  }

  Color getCustomColor() {
    final value = _prefs.getString(_customColorKey);
    final rgb = value == null ? null : int.tryParse(value, radix: 16);
    if (rgb == null) {
      return Colors.teal;
    }
    return Color(0xff000000 | rgb);
  }

  Future<void> setCustomColor(Color color) async {
    await _prefs.setString(_customColorKey, color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2));
  }

  AppLocale? getLocale() {
    final value = _prefs.getString(_localeKey);
    if (value == null) {
      return null;
    }
    return AppLocale.values.firstWhereOrNull((locale) => locale.languageTag == value);
  }

  Future<void> setLocale(AppLocale? locale) async {
    if (locale == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, locale.languageTag);
    }
  }

  int getPort() {
    return _prefs.getInt(_portKey) ?? defaultPort;
  }

  Future<void> setPort(int port) async {
    await _prefs.setInt(_portKey, port);
  }

  List<String>? getNetworkWhitelist() {
    return _prefs.getStringList(_networkWhitelistKey);
  }

  Future<void> setNetworkWhitelist(List<String>? whitelist) async {
    if (whitelist == null) {
      await _prefs.remove(_networkWhitelistKey);
    } else {
      await _prefs.setStringList(_networkWhitelistKey, whitelist);
    }
  }

  List<String>? getNetworkBlacklist() {
    return _prefs.getStringList(_networkBlacklistKey);
  }

  Future<void> setNetworkBlacklist(List<String>? blacklist) async {
    if (blacklist == null) {
      await _prefs.remove(_networkBlacklistKey);
    } else {
      await _prefs.setStringList(_networkBlacklistKey, blacklist);
    }
  }

  int getDiscoveryTimeout() {
    return _prefs.getInt(_timeoutKey) ?? defaultDiscoveryTimeout;
  }

  Future<void> setDiscoveryTimeout(int timeout) async {
    await _prefs.setInt(_timeoutKey, timeout);
  }

  bool getShareViaLinkAutoAccept() {
    return _prefs.getBool(_shareViaLinkAutoAccept) ?? false;
  }

  Future<void> setShareViaLinkAutoAccept(bool shareViaLinkAutoAccept) async {
    await _prefs.setBool(_shareViaLinkAutoAccept, shareViaLinkAutoAccept);
  }

  bool getReceiveViaLinkAutoAccept() {
    return _prefs.getBool(_receiveViaLinkAutoAccept) ?? false;
  }

  Future<void> setReceiveViaLinkAutoAccept(bool receiveViaLinkAutoAccept) async {
    await _prefs.setBool(_receiveViaLinkAutoAccept, receiveViaLinkAutoAccept);
  }

  bool getCreateChecksums() {
    return _prefs.getBool(_createChecksums) ?? true;
  }

  Future<void> setCreateChecksums(bool createChecksums) async {
    await _prefs.setBool(_createChecksums, createChecksums);
  }

  bool getVerifyChecksums() {
    return _prefs.getBool(_verifyChecksums) ?? true;
  }

  Future<void> setVerifyChecksums(bool verifyChecksums) async {
    await _prefs.setBool(_verifyChecksums, verifyChecksums);
  }

  String getMulticastGroup() {
    return _prefs.getString(_multicastGroupKey) ?? defaultMulticastGroup;
  }

  Future<void> setMulticastGroup(String group) async {
    await _prefs.setString(_multicastGroupKey, group);
  }

  String? getDestination() {
    return _prefs.getString(_destinationKey);
  }

  Future<void> setDestination(String? destination) async {
    if (destination == null) {
      await _prefs.remove(_destinationKey);
    } else {
      await _prefs.setString(_destinationKey, destination);
    }
  }

  bool isSaveToGallery() {
    return _prefs.getBool(_saveToGallery) ?? true;
  }

  Future<void> setSaveToGallery(bool saveToGallery) async {
    await _prefs.setBool(_saveToGallery, saveToGallery);
  }

  bool isSaveToHistory() {
    return _prefs.getBool(_saveToHistory) ?? true;
  }

  Future<void> setSaveToHistory(bool saveToHistory) async {
    await _prefs.setBool(_saveToHistory, saveToHistory);
  }

  bool getAdvancedSettingsEnabled() {
    return _prefs.getBool(_advancedSettingsKey) ?? false;
  }

  Future<void> setAdvancedSettingsEnabled(bool isEnabled) async {
    await _prefs.setBool(_advancedSettingsKey, isEnabled);
  }

  QuickSaveMode getQuickSave() {
    final value = _prefs.getString(_quickSave);
    return QuickSaveMode.values.firstWhereOrNull((mode) => mode.name == value) ?? QuickSaveMode.paired;
  }

  Future<void> setQuickSave(QuickSaveMode mode) async {
    await _prefs.setString(_quickSave, mode.name);
  }

  String? getReceivePin() {
    return _prefs.getString(_receivePin);
  }

  Future<void> setReceivePin(String? pin) async {
    if (pin == null) {
      await _prefs.remove(_receivePin);
    } else {
      await _prefs.setString(_receivePin, pin);
    }
  }

  bool isAutoFinish() {
    return _prefs.getBool(_autoFinish) ?? false;
  }

  Future<void> setAutoFinish(bool autoFinish) async {
    await _prefs.setBool(_autoFinish, autoFinish);
  }

  bool isMinimizeToTray() {
    return _prefs.getBool(_minimizeToTray) ?? false;
  }

  Future<void> setMinimizeToTray(bool minimizeToTray) async {
    await _prefs.setBool(_minimizeToTray, minimizeToTray);
  }

  bool isBackgroundMode() {
    return _prefs.getBool(_backgroundMode) ?? false;
  }

  Future<void> setBackgroundMode(bool backgroundMode) async {
    await _prefs.setBool(_backgroundMode, backgroundMode);
  }

  bool isHttps() {
    return _prefs.getBool(_https) ?? true;
  }

  Future<void> setHttps(bool https) async {
    await _prefs.setBool(_https, https);
  }

  SendMode getSendMode() {
    return SendMode.values.firstWhereOrNull((m) => m.name == _prefs.getString(_sendMode)) ?? SendMode.single;
  }

  Future<void> setSendMode(SendMode mode) async {
    await _prefs.setString(_sendMode, mode.name);
  }

  Future<void> setWindowOffsetX(double x) async {
    await _prefs.setDouble(_windowOffsetX, x);
  }

  Future<void> setWindowOffsetY(double y) async {
    await _prefs.setDouble(_windowOffsetY, y);
  }

  Future<void> setWindowHeight(double height) async {
    await _prefs.setDouble(_windowHeight, height);
  }

  Future<void> setWindowWidth(double width) async {
    await _prefs.setDouble(_windowWidth, width);
  }

  WindowDimensions? getWindowLastDimensions() {
    Size? size;
    Offset? position;
    final offsetX = _prefs.getDouble(_windowOffsetX);
    final offsetY = _prefs.getDouble(_windowOffsetY);
    final width = _prefs.getDouble(_windowWidth);
    final height = _prefs.getDouble(_windowHeight);

    if (width != null && height != null) {
      size = Size(width, height);
    }

    if (offsetX != null && offsetY != null) {
      position = Offset(offsetX, offsetY);
    }

    if (size == null || position == null) {
      return null;
    }

    return WindowDimensions(
      position: position,
      size: size,
    );
  }

  Future<void> setSaveWindowPlacement(bool savePlacement) async {
    await _prefs.setBool(_saveWindowPlacement, savePlacement);
  }

  bool getSaveWindowPlacement() {
    if (!checkPlatformIsNotWaylandDesktop()) return false;
    return _prefs.getBool(_saveWindowPlacement) ?? true;
  }

  Future<void> setAlwaysOnTop(bool alwaysOnTop) async {
    await _prefs.setBool(_alwaysOnTop, alwaysOnTop);
  }

  bool isFramelessWindow() {
    return _prefs.getBool(_framelessWindow) ?? false;
  }

  Future<void> setFramelessWindow(bool framelessWindow) async {
    await _prefs.setBool(_framelessWindow, framelessWindow);
  }

  bool isShowTrayIcon() {
    return _prefs.getBool(_showTrayIcon) ?? true;
  }

  Future<void> setShowTrayIcon(bool showTrayIcon) async {
    await _prefs.setBool(_showTrayIcon, showTrayIcon);
  }

  int getTransferCompletedDuration() {
    return (_prefs.getInt(_transferCompletedDuration) ?? 3).clamp(0, 60);
  }

  Future<void> setTransferCompletedDuration(int seconds) async {
    await _prefs.setInt(_transferCompletedDuration, seconds.clamp(0, 60));
  }

  bool getAlwaysOnTop() {
    return _prefs.getBool(_alwaysOnTop) ?? false;
  }

  Future<void> setEnableAnimations(bool enableAnimations) async {
    await _prefs.setBool(_enableAnimations, enableAnimations);
  }

  bool getEnableAnimations() {
    return _prefs.getBool(_enableAnimations) ?? true;
  }

  DeviceType? getDeviceType() {
    return DeviceType.values.firstWhereOrNull((m) => m.name == _prefs.getString(_deviceType));
  }

  Future<void> setDeviceType(DeviceType deviceType) async {
    await _prefs.setString(_deviceType, deviceType.name);
  }

  String? getDeviceModel() {
    return _prefs.getString(_deviceModel);
  }

  Future<void> setDeviceModel(String deviceModel) async {
    await _prefs.setString(_deviceModel, deviceModel);
  }

  String? getWhatsNew() {
    return _prefs.getString(_whatsNewKey);
  }

  Future<void> setWhatsNew(String version) async {
    await _prefs.setString(_whatsNewKey, version);
  }

  Future<void> clear() async {
    await _prefs.clear();
  }
}
