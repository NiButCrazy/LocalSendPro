import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:logging/logging.dart';

final _logger = Logger('HistoryStorage');

/// Stores the persistent transfer history in its own JSON file.
///
/// History used to live in `settings.json` (SharedPreferences), which mixed
/// frequently written transfer data with app settings and made the settings
/// file grow without bound.
class HistoryStorage {
  final File file;

  HistoryStorage(this.file);

  /// Reads the history file.
  ///
  /// A missing or corrupted file yields an empty history instead of failing the
  /// app start; the next write replaces the corrupted file.
  List<TransferHistoryEntry> load() {
    if (!file.existsSync()) {
      return [];
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final rawEntries = switch (decoded) {
        {'entries': final List<dynamic> entries} => entries,
        final List<dynamic> entries => entries,
        _ => <dynamic>[],
      };

      return rawEntries.whereType<Map<String, dynamic>>().map(TransferHistoryEntry.fromJson).toList();
    } catch (e, stackTrace) {
      _logger.warning('Could not read transfer history from ${file.path}', e, stackTrace);
      return [];
    }
  }

  /// Writes the history atomically: a temporary file is flushed and then moved
  /// over the target, so an interrupted write cannot leave a partially written
  /// history file behind.
  Future<void> save(List<TransferHistoryEntry> entries) async {
    await file.parent.create(recursive: true);

    final content = jsonEncode({
      'version': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(content, flush: true);

    try {
      await tempFile.rename(file.path);
    } on FileSystemException {
      // Windows can refuse to rename over an existing file.
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    }
  }
}
