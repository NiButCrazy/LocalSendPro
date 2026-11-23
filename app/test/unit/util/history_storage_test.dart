import 'dart:io';

import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:localsend_app/util/persistence/history_storage.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDirectory;
  late HistoryStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('localsend_history_test');
    storage = HistoryStorage(File(p.join(tempDirectory.path, 'history.json')));
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('returns an empty history when the file does not exist', () {
    expect(storage.load(), isEmpty);
  });

  test('round-trips the entries through the history file', () async {
    final entries = [
      _entry('1', TransferDirection.receive),
      _entry('2', TransferDirection.send),
    ];

    await storage.save(entries);

    final loaded = storage.load();
    expect(loaded, hasLength(2));
    expect(loaded.map((entry) => entry.id), ['1', '2']);
    expect(loaded.map((entry) => entry.direction), [TransferDirection.receive, TransferDirection.send]);
    expect(loaded.first.senderAlias, 'peer-1');
  });

  test('ignores a corrupted history file', () async {
    await File(storage.file.path).writeAsString('{not json');

    expect(storage.load(), isEmpty);
  });
}

TransferHistoryEntry _entry(String id, TransferDirection direction) {
  return TransferHistoryEntry(
    id: id,
    fileName: 'file-$id.txt',
    fileType: FileType.text,
    path: null,
    savedToGallery: false,
    isMessage: false,
    fileSize: 12,
    senderAlias: 'peer-$id',
    timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
    direction: direction,
  );
}
