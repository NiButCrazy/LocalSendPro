import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:win32_registry/win32_registry.dart';

final _logger = Logger('ContextMenuHelper');

/// A GUID keeps the verb key unique and lets old installs be cleaned up reliably.
const _verbKey = '{6D3F2C8A-5B4E-4F1A-9C7D-2E8B1A0F4C63}';

Future<bool> enableContextMenu() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final menuWritten = _writeContextMenu();
    try {
      await _createSendToShortcut();
    } catch (e, stackTrace) {
      _logger.warning('Could not create the SendTo shortcut', e, stackTrace);
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
    final shortcut = File(_getWindowsFilePath(_windowsFileName));
    if (await shortcut.exists()) {
      await shortcut.delete();
    }
    return _deleteContextMenu();
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
Future<void> migrateContextMenu() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return;
  }
  if (await isContextMenuEnabled()) {
    await enableContextMenu();
    return;
  }
  if (await File(_getWindowsFilePath(_windowsFileName)).exists()) {
    await enableContextMenu();
  }
}

bool _writeContextMenu() {
  final executable = Platform.resolvedExecutable;
  final title = _menuTitle();
  final icon = '"$executable",0';
  final classes = Registry.openPath(
    RegistryHive.currentUser,
    path: r'Software\Classes',
    desiredAccessRights: AccessRights.allAccess,
  );

  try {
    _writeVerb(classes, ['*', 'shell', _verbKey], title, icon, '"$executable" "%1"');
    _writeVerb(classes, ['Directory', 'shell', _verbKey], title, icon, '"$executable" "%1"');
    _writeVerb(classes, ['Directory', 'Background', 'shell', _verbKey], title, icon, '"$executable" "%V"');
    return true;
  } finally {
    classes.close();
  }
}

void _writeVerb(
  RegistryKey classes,
  List<String> path,
  String title,
  String icon,
  String command,
) {
  final verb = _createKeyPath(classes, path);
  try {
    verb.createValue(RegistryValue.string('', title));
    verb.createValue(RegistryValue.string('Icon', icon));
    verb.createValue(RegistryValue.string('MultiSelectModel', 'Player'));
  } finally {
    verb.close();
  }

  final commandKey = _createKeyPath(classes, [...path, 'command']);
  try {
    commandKey.createValue(RegistryValue.string('', command));
  } finally {
    commandKey.close();
  }
}

bool _deleteContextMenu() {
  final classes = Registry.openPath(
    RegistryHive.currentUser,
    path: r'Software\Classes',
    desiredAccessRights: AccessRights.allAccess,
  );

  try {
    _deleteVerb(classes, ['*', 'shell', _verbKey]);
    _deleteVerb(classes, ['Directory', 'shell', _verbKey]);
    _deleteVerb(classes, ['Directory', 'Background', 'shell', _verbKey]);
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

String _menuTitle() {
  final locale = Platform.localeName.toLowerCase();
  return locale.startsWith('zh') ? '使用 LocalSend 发送' : 'Send with LocalSend';
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
