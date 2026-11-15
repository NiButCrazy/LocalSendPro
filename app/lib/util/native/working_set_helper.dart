import 'dart:io';

import 'package:win32/win32.dart';

/// Asks Windows to move this process's idle pages out of the working set.
///
/// The committed memory does not change, but the memory shown in Task Manager drops
/// significantly while LocalSend is idle in the tray. Pages are paged back in on demand,
/// so the first window restore may take slightly longer.
void trimWorkingSet() {
  if (!Platform.isWindows) {
    return;
  }
  EmptyWorkingSet(GetCurrentProcess());
}
