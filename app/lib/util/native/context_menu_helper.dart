import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/shell_change_notify.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:win32_registry/win32_registry.dart';

final _logger = Logger('ContextMenuHelper');

/// A GUID keeps the verb key unique and lets old installs be cleaned up reliably.
const _verbKey = '{6D3F2C8A-5B4E-4F1A-9C7D-2E8B1A0F4C63}';

/// 级联菜单的数据根键，`ExtendedSubCommandsKey` 相对 `HKCU\Software\Classes` 解析。
const _devicesKey = 'LocalSend.ContextMenuDevices';
const _backgroundDevicesKey = 'LocalSend.ContextMenuDevicesBackground';

/// 一次最多写入的设备数量，避免菜单过长。
const _maxDeviceEntries = 20;

/// 三个父动词的位置：文件、文件夹、文件夹背景。
const _verbPaths = <List<String>>[
  ['*', 'shell', _verbKey],
  ['Directory', 'shell', _verbKey],
  ['Directory', 'Background', 'shell', _verbKey],
];

/// 上一次写入设备子项的内容签名，避免无变化的重复重写。
String? _lastDeviceSignature;

/// 右键菜单里的一个设备条目。
@immutable
class DeviceMenuEntry {
  final String fingerprint;

  /// 已转义（`&` → `&&`）并去掉换行的显示名；空别名回退为指纹。
  final String displayAlias;
  final bool favorite;

  const DeviceMenuEntry({
    required this.fingerprint,
    required this.displayAlias,
    required this.favorite,
  });
}

/// 写入（或刷新）右键菜单。
///
/// [quickSend] 为 true 时父键变成级联菜单，设备列表由 [updateContextMenuDevices] 填充；
/// 为 false 时保持经典的单一动词。
Future<bool> enableContextMenu({required bool quickSend, bool showIcon = true, String? menuLabel}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    // 只有父键在“普通动词”和“级联菜单”之间切换（或首次写入）时才需要通知外壳。
    // 每次启动都刷新会让桌面图标/关联闪一下。
    final structureChanged = !_menuStructureMatches(quickSend: quickSend, showIcon: showIcon, menuLabel: menuLabel);
    final menuWritten = _writeContextMenu(quickSend: quickSend, showIcon: showIcon, menuLabel: menuLabel);
    try {
      await _createSendToShortcut();
    } catch (e, stackTrace) {
      _logger.warning('Could not create the SendTo shortcut', e, stackTrace);
    }
    if (structureChanged) {
      notifyShellAssociationsChanged();
    }
    return menuWritten;
  } catch (e, stackTrace) {
    _logger.severe('Failed to enable context menu', e, stackTrace);
    return false;
  }
}

Future<bool> disableContextMenu() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final wasEnabled = await isContextMenuEnabled();
    final shortcut = File(_getWindowsFilePath(_windowsFileName));
    if (await shortcut.exists()) {
      await shortcut.delete();
    }
    final deleted = _deleteContextMenu();
    if (wasEnabled) {
      notifyShellAssociationsChanged();
    }
    return deleted;
  } catch (e, stackTrace) {
    _logger.warning('Failed to disable context menu', e, stackTrace);
    return false;
  }
}

Future<bool> isContextMenuEnabled() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final verb = Registry.openPath(
      RegistryHive.currentUser,
      path: r'Software\Classes\*\shell\' + _verbKey,
      desiredAccessRights: AccessRights.readOnly,
    );
    verb.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Adds the menu for installs that only had the SendTo shortcut before, and
/// keeps the command pointing at the current executable after an update.
Future<void> migrateContextMenu({required bool quickSend, bool showIcon = true, String? menuLabel}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return;
  }
  if (await isContextMenuEnabled()) {
    await enableContextMenu(quickSend: quickSend, showIcon: showIcon, menuLabel: menuLabel);
    return;
  }
  if (await File(_getWindowsFilePath(_windowsFileName)).exists()) {
    await enableContextMenu(quickSend: quickSend, showIcon: showIcon, menuLabel: menuLabel);
  }
}

/// 重写设备子菜单。
///
/// [quickSend] 为 false 时递归删除两个设备根键。
Future<void> updateContextMenuDevices({
  required bool quickSend,
  required Iterable<Device> devices,
  required Set<String> favoriteFingerprints,
}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return;
  }

  final entries = quickSend ? buildDeviceMenuEntries(devices: devices, favoriteFingerprints: favoriteFingerprints) : const <DeviceMenuEntry>[];
  try {
    final classes = Registry.openPath(
      RegistryHive.currentUser,
      path: r'Software\Classes',
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      _writeDeviceEntries(classes, quickSend: quickSend, entries: entries);
    } finally {
      classes.close();
    }
    // 设备子项只在展开级联菜单时读取，不需要 SHChangeNotify：那会让桌面刷新。
  } catch (e, stackTrace) {
    _logger.warning('Failed to update the context menu devices', e, stackTrace);
  }
}

/// 过滤出可接收上传的设备，收藏优先，按别名排序并截断到 [_maxDeviceEntries]。
///
/// 也用于同步定时器计算签名，所以不是测试专用。
List<DeviceMenuEntry> buildDeviceMenuEntries({
  required Iterable<Device> devices,
  required Set<String> favoriteFingerprints,
}) {
  final seen = <String>{};
  final candidates = <({Device device, bool favorite})>[];
  for (final device in devices) {
    if (device.ip == null || device.download) {
      continue;
    }
    if (!seen.add(device.fingerprint)) {
      continue;
    }
    candidates.add((device: device, favorite: favoriteFingerprints.contains(device.fingerprint)));
  }

  candidates.sort((a, b) {
    if (a.favorite != b.favorite) {
      return a.favorite ? -1 : 1;
    }
    final byAlias = a.device.alias.toLowerCase().compareTo(b.device.alias.toLowerCase());
    if (byAlias != 0) {
      return byAlias;
    }
    return a.device.fingerprint.compareTo(b.device.fingerprint);
  });

  return candidates
      .take(_maxDeviceEntries)
      .map((candidate) {
        final label = escapeMenuLabel(candidate.device.alias);
        return DeviceMenuEntry(
          fingerprint: candidate.device.fingerprint,
          displayAlias: label.isEmpty ? candidate.device.fingerprint : label,
          favorite: candidate.favorite,
        );
      })
      .toList(growable: false);
}

/// 把别名转成静态菜单可用的标签：`&` 需要转义，换行会破坏单项显示。
@visibleForTesting
String escapeMenuLabel(String alias) {
  return alias.replaceAll('&', '&&').replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
}

/// 菜单命令：隐藏启动并直接把文件发给指定指纹。
@visibleForTesting
String buildDeviceCommand({
  required String executable,
  required String fingerprint,
  required String pathToken,
}) {
  return '"$executable" --hidden --send-to "$fingerprint" "$pathToken"';
}

/// 菜单命令：隐藏启动、扫描并打开设备选择器发送该路径。
@visibleForTesting
String buildScanCommand({required String executable, required String pathToken}) {
  return '"$executable" --hidden --scan "$pathToken"';
}

bool _writeContextMenu({required bool quickSend, required bool showIcon, String? menuLabel}) {
  final executable = Platform.resolvedExecutable;
  final title = _menuTitle(custom: menuLabel);
  final icon = '"$executable",0';
  final classes = Registry.openPath(
    RegistryHive.currentUser,
    path: r'Software\Classes',
    desiredAccessRights: AccessRights.allAccess,
  );

  try {
    for (final path in _verbPaths) {
      _writeVerb(
        classes,
        path,
        title: title,
        icon: icon,
        executable: executable,
        quickSend: quickSend,
        showIcon: showIcon,
        background: path[1] == 'Background',
      );
    }
    if (quickSend) {
      // 保留上一次写入的设备列表；发现列表变化由定时器/设置页补齐。
      _ensureDeviceRoots(classes);
    } else {
      _writeDeviceEntries(classes, quickSend: false, entries: const []);
    }
    return true;
  } finally {
    classes.close();
  }
}

/// 只保证两个设备根键存在，不清空已有内容。
void _ensureDeviceRoots(RegistryKey classes) {
  for (final rootKey in [_devicesKey, _backgroundDevicesKey]) {
    final root = _createKeyPath(classes, [rootKey]);
    try {
      root.createKey('shell').close();
    } finally {
      root.close();
    }
  }
}

/// 三个父键是否已经是目标形态（普通动词或级联菜单）。
///
/// 形态没变时不需要 `SHChangeNotify`，否则每次启动/切换都会让桌面刷新。
bool _menuStructureMatches({required bool quickSend, required bool showIcon, String? menuLabel}) {
  for (final path in _verbPaths) {
    final RegistryKey verb;
    try {
      verb = Registry.openPath(
        RegistryHive.currentUser,
        path: 'Software\\Classes\\${path.join('\\')}',
        desiredAccessRights: AccessRights.readOnly,
      );
    } catch (_) {
      return false;
    }

    try {
      final extended = verb.getStringValue('ExtendedSubCommandsKey');
      final hasCommand = _keyExists('Software\\Classes\\${[...path, 'command'].join('\\')}');
      final hasIcon = verb.getStringValue('Icon') != null;
      if (quickSend ? (extended == null || hasCommand) : (extended != null || !hasCommand)) {
        return false;
      }
      if (hasIcon != showIcon) {
        return false;
      }
      final expectedTitle = _menuTitle(custom: menuLabel);
      final actualTitle = quickSend ? verb.getStringValue('MUIVerb') : verb.getStringValue('');
      if (actualTitle != expectedTitle) {
        return false;
      }
    } finally {
      verb.close();
    }
  }
  return true;
}

bool _keyExists(String path) {
  try {
    Registry.openPath(
      RegistryHive.currentUser,
      path: path,
      desiredAccessRights: AccessRights.readOnly,
    ).close();
    return true;
  } catch (_) {
    return false;
  }
}

void _writeVerb(
  RegistryKey classes,
  List<String> path, {
  required String title,
  required String icon,
  required String executable,
  required bool quickSend,
  required bool showIcon,
  bool background = false,
}) {
  // 整键重建：两种模式使用的值不同，残留的默认值或 command 子键会让 Windows 用错模式。
  final shell = _createKeyPath(classes, path.sublist(0, path.length - 1));
  try {
    shell.deleteKey(path.last, recursive: true);
  } catch (_) {
    // 动词可能尚不存在。
  } finally {
    shell.close();
  }

  final verb = _createKeyPath(classes, path);
  try {
    if (quickSend) {
      // 级联菜单：父键不能有默认值，否则 Windows 仍按普通动词处理。
      verb.createValue(RegistryValue.string('MUIVerb', title));
      if (showIcon) {
        verb.createValue(RegistryValue.string('Icon', icon));
      }
      verb.createValue(RegistryValue.string('MultiSelectModel', 'Player'));
      verb.createValue(RegistryValue.string('ExtendedSubCommandsKey', background ? _backgroundDevicesKey : _devicesKey));
    } else {
      verb.createValue(RegistryValue.string('', title));
      if (showIcon) {
        verb.createValue(RegistryValue.string('Icon', icon));
      }
      verb.createValue(RegistryValue.string('MultiSelectModel', 'Player'));
    }
  } finally {
    verb.close();
  }

  if (!quickSend) {
    final commandKey = _createKeyPath(classes, [...path, 'command']);
    try {
      commandKey.createValue(RegistryValue.string('', '"$executable" "${background ? '%V' : '%1'}"'));
    } finally {
      commandKey.close();
    }
  }
}

void _writeDeviceEntries(
  RegistryKey classes, {
  required bool quickSend,
  required List<DeviceMenuEntry> entries,
}) {
  final signature = quickSend
      ? 'on\n${entries.map((entry) => '${entry.fingerprint}\u0002${entry.displayAlias}\u0002${entry.favorite}').join('\n')}'
      : 'off';
  if (signature == _lastDeviceSignature) {
    return;
  }

  if (!quickSend) {
    _deleteKeySilently(classes, _devicesKey);
    _deleteKeySilently(classes, _backgroundDevicesKey);
    _lastDeviceSignature = signature;
    return;
  }

  final executable = Platform.resolvedExecutable;
  _rewriteDeviceRoot(classes, rootKey: _devicesKey, entries: entries, executable: executable, pathToken: '%1');
  _rewriteDeviceRoot(classes, rootKey: _backgroundDevicesKey, entries: entries, executable: executable, pathToken: '%V');
  _lastDeviceSignature = signature;
}

void _rewriteDeviceRoot(
  RegistryKey classes, {
  required String rootKey,
  required List<DeviceMenuEntry> entries,
  required String executable,
  required String pathToken,
}) {
  final shell = _createKeyPath(classes, [rootKey, 'shell']);
  try {
    final desiredNames = entries.isEmpty ? {'none'} : {for (var i = 0; i < entries.length; i++) 'd$i'};
    // Enumerate before deleting; the generator reads the key live.
    for (final name in shell.subkeyNames.toList(growable: false)) {
      if (desiredNames.contains(name)) {
        continue;
      }
      try {
        shell.deleteKey(name, recursive: true);
      } catch (_) {
        // Ignore keys that disappeared in the meantime.
      }
    }

    if (entries.isEmpty) {
      final placeholder = shell.createKey('none');
      try {
        _setStringIfChanged(placeholder, 'MUIVerb', _noDevicesLabel());
        _setIntIfChanged(placeholder, 'CommandFlags', 0);
        final command = placeholder.createKey('command');
        try {
          _setStringIfChanged(command, '', buildScanCommand(executable: executable, pathToken: pathToken));
        } finally {
          command.close();
        }
      } finally {
        placeholder.close();
      }
      return;
    }

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final keyName = 'd$i';
      final verb = shell.createKey(keyName);
      try {
        _setStringIfChanged(verb, 'MUIVerb', entry.displayAlias);
        _setStringIfChanged(verb, 'MultiSelectModel', 'Player');
        _setIntIfChanged(verb, 'CommandFlags', 0);
      } finally {
        verb.close();
      }

      final command = _createKeyPath(classes, [rootKey, 'shell', keyName, 'command']);
      try {
        _setStringIfChanged(
          command,
          '',
          buildDeviceCommand(executable: executable, fingerprint: entry.fingerprint, pathToken: pathToken),
        );
      } finally {
        command.close();
      }
    }
  } finally {
    shell.close();
  }
}

/// Updates a value only when it differs, keeping in-place syncs cheap.
void _setStringIfChanged(RegistryKey key, String name, String value) {
  if (key.getStringValue(name) == value) {
    return;
  }
  key.createValue(RegistryValue.string(name, value));
}

void _setIntIfChanged(RegistryKey key, String name, int value) {
  if (key.getIntValue(name) == value) {
    return;
  }
  key.createValue(RegistryValue.int32(name, value));
}

bool _deleteContextMenu() {
  final classes = Registry.openPath(
    RegistryHive.currentUser,
    path: r'Software\Classes',
    desiredAccessRights: AccessRights.allAccess,
  );

  try {
    for (final path in _verbPaths) {
      _deleteVerb(classes, path);
    }
    _deleteKeySilently(classes, _devicesKey);
    _deleteKeySilently(classes, _backgroundDevicesKey);
    _lastDeviceSignature = 'off';
    return true;
  } finally {
    classes.close();
  }
}

void _deleteVerb(RegistryKey classes, List<String> path) {
  final shell = _createKeyPath(classes, path.sublist(0, path.length - 1));
  try {
    shell.deleteKey(path.last, recursive: true);
  } catch (_) {
    // The verb may not exist.
  } finally {
    shell.close();
  }
}

void _deleteKeySilently(RegistryKey classes, String key) {
  try {
    classes.deleteKey(key, recursive: true);
  } catch (_) {
    // 键可能不存在。
  }
}

RegistryKey _createKeyPath(RegistryKey root, List<String> segments) {
  var current = root;
  for (final segment in segments) {
    final next = current.createKey(segment);
    if (!identical(current, root)) {
      current.close();
    }
    current = next;
  }
  return current;
}

String _menuTitle({String? custom}) {
  final label = custom?.trim();
  if (label != null && label.isNotEmpty) {
    return escapeMenuLabel(label);
  }
  final locale = Platform.localeName.toLowerCase();
  return locale.startsWith('zh') ? '使用 LocalSend 发送' : 'Send with LocalSend';
}

String _noDevicesLabel() {
  final locale = Platform.localeName.toLowerCase();
  return locale.startsWith('zh') ? '没有可发送的设备' : 'No devices available';
}

Future<void> _createSendToShortcut() async {
  final String script =
      '''
\$TargetPath = "${Platform.resolvedExecutable}"
\$ShortcutFile = "${_getWindowsFilePath(_windowsFileName)}"
\$WScriptShell = New-Object -ComObject WScript.Shell
\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutFile)
\$Shortcut.TargetPath = \$TargetPath
\$Shortcut.Save()
''';
  final result = await Process.run('powershell', ['-Command', script]);
  if (result.stderr != null && result.stderr!.isNotEmpty) {
    throw Exception('Failed to create shortcut: ${result.stderr}');
  }
}

const _windowsFileName = 'LocalSend';

String _getWindowsFilePath(String appName) {
  final appData = Platform.environment['APPDATA'];
  return '$appData/Microsoft/Windows/SendTo/$appName.lnk';
}
