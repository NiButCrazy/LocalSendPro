import 'dart:io';

/// Whether the current Windows process runs with administrator privileges.
///
/// `net session` requires an elevated token and fails otherwise.
/// Always false on platforms without the Windows elevation model.
bool isRunningAsAdministrator() {
  if (!Platform.isWindows) {
    return false;
  }
  try {
    final result = Process.runSync(
      'net',
      ['session'],
      runInShell: false,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
