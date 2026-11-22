import 'package:intl/date_symbol_data_local.dart';
import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:localsend_app/provider/transfer_history_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockPersistenceService persistenceService;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    persistenceService = MockPersistenceService();
    when(persistenceService.isSaveToHistory()).thenReturn(true);
  });

  test('Should record an entry in both layers', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
    );

    final entry = _createEntry('1');

    await service.dispatchAsync(RecordHistoryEntryAction(entry));

    expect(service.state.runtime, [entry]);
    expect(service.state.persistent, [entry]);
    verify(persistenceService.setTransferHistory([entry])).called(1);
  });

  test('Should only record in the runtime layer if disabled', () async {
    when(persistenceService.isSaveToHistory()).thenReturn(false);

    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
    );

    final entry = _createEntry('1');

    await service.dispatchAsync(RecordHistoryEntryAction(entry));

    expect(service.state.runtime, [entry]);
    expect(service.state.persistent, isEmpty);
    verifyNever(persistenceService.setTransferHistory(any));
  });

  test('Should not limit the persistent layer by default', () async {
    when(persistenceService.getHistoryLimit()).thenReturn(0);

    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
    );

    for (var i = 0; i < 40; i++) {
      await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('$i')));
    }

    expect(service.state.runtime.length, 40);
    expect(service.state.persistent.length, 40);
    expect(service.state.persistent.first, _createEntry('39'));
  });

  test('Should apply the configured limit to the persistent layer only', () async {
    when(persistenceService.getHistoryLimit()).thenReturn(2);

    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
    );

    await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('1')));
    await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('2')));
    await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('3')));

    expect(service.state.runtime.length, 3);
    expect(service.state.persistent, [
      _createEntry('3'),
      _createEntry('2'),
    ]);
  });

  test('Should move a retried entry to the front in both layers', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
    );

    await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('1')));
    await service.dispatchAsync(RecordHistoryEntryAction(_createEntry('2')));

    final retried = TransferHistoryEntry(
      id: '1',
      fileName: 'retried',
      fileType: FileType.image,
      path: 'path',
      savedToGallery: true,
      isMessage: false,
      fileSize: 123,
      senderAlias: 'senderAlias',
      timestamp: DateTime(2021, 1, 1),
      direction: TransferDirection.receive,
    );
    await service.dispatchAsync(RecordHistoryEntryAction(retried));

    expect(service.state.runtime, [retried, _createEntry('2')]);
    expect(service.state.persistent, [retried, _createEntry('2')]);
  });

  test('Should remove an entry from the runtime layer only', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
      initialState: TransferHistoryState(
        runtime: [
          _createEntry('1'),
          _createEntry('2'),
        ],
        persistent: [
          _createEntry('1'),
          _createEntry('2'),
        ],
      ),
    );

    await service.dispatchAsync(RemoveHistoryEntryAction(HistoryLayer.runtime, '2'));

    expect(service.state.runtime, [_createEntry('1')]);
    expect(service.state.persistent, [
      _createEntry('1'),
      _createEntry('2'),
    ]);
    verifyNever(persistenceService.setTransferHistory(any));
  });

  test('Should remove an entry from the persistent layer only', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
      initialState: TransferHistoryState(
        runtime: [
          _createEntry('1'),
          _createEntry('2'),
        ],
        persistent: [
          _createEntry('1'),
          _createEntry('2'),
        ],
      ),
    );

    await service.dispatchAsync(RemoveHistoryEntryAction(HistoryLayer.persistent, '2'));

    expect(service.state.runtime, [
      _createEntry('1'),
      _createEntry('2'),
    ]);
    expect(service.state.persistent, [_createEntry('1')]);
    verify(persistenceService.setTransferHistory([_createEntry('1')]));
  });

  test('Should clear the runtime layer only', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
      initialState: TransferHistoryState(
        runtime: [_createEntry('1')],
        persistent: [_createEntry('1')],
      ),
    );

    await service.dispatchAsync(ClearHistoryAction(HistoryLayer.runtime));

    expect(service.state.runtime, isEmpty);
    expect(service.state.persistent, [_createEntry('1')]);
    verifyNever(persistenceService.setTransferHistory(any));
  });

  test('Should clear the persistent layer', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
      initialState: TransferHistoryState(
        runtime: [_createEntry('1')],
        persistent: [_createEntry('1')],
      ),
    );

    await service.dispatchAsync(ClearHistoryAction(HistoryLayer.persistent));

    expect(service.state.runtime, [_createEntry('1')]);
    expect(service.state.persistent, isEmpty);
    verify(persistenceService.setTransferHistory([]));
  });

  test('Should trim the persistent layer', () async {
    final service = ReduxNotifier.test(
      redux: TransferHistoryService(persistenceService),
      initialState: TransferHistoryState(
        runtime: [
          _createEntry('1'),
          _createEntry('2'),
          _createEntry('3'),
        ],
        persistent: [
          _createEntry('1'),
          _createEntry('2'),
          _createEntry('3'),
        ],
      ),
    );

    await service.dispatchAsync(TrimHistoryAction(2));

    expect(service.state.runtime.length, 3);
    expect(service.state.persistent, [
      _createEntry('1'),
      _createEntry('2'),
    ]);
    verify(
      persistenceService.setTransferHistory([
        _createEntry('1'),
        _createEntry('2'),
      ]),
    );
  });

  test('Should decode legacy entries without direction as receive', () {
    final entry = TransferHistoryEntry.fromJson({
      'id': '1',
      'fileName': 'fileName',
      'fileType': 'image',
      'path': 'path',
      'savedToGallery': true,
      'isMessage': false,
      'fileSize': 123,
      'senderAlias': 'senderAlias',
      'timestamp': '2021-01-01T00:00:00.000Z',
    });

    expect(entry.direction, TransferDirection.receive);
    expect(entry.senderAlias, 'senderAlias');
    expect(entry.timestamp, DateTime.utc(2021, 1, 1));
  });

  test('Should encode and decode the direction', () {
    final entry = TransferHistoryEntry(
      id: '1',
      fileName: 'fileName',
      fileType: FileType.image,
      path: 'path',
      savedToGallery: false,
      isMessage: false,
      fileSize: 123,
      senderAlias: 'recipientAlias',
      timestamp: DateTime.utc(2021, 1, 1),
      direction: TransferDirection.send,
    );

    final decoded = TransferHistoryEntry.fromJson(entry.toJson());

    expect(decoded.direction, TransferDirection.send);
    expect(decoded.senderAlias, 'recipientAlias');
  });
}

TransferHistoryEntry _createEntry(String id) {
  return TransferHistoryEntry(
    id: id,
    fileName: 'fileName',
    fileType: FileType.image,
    path: 'path',
    savedToGallery: true,
    isMessage: false,
    fileSize: 123,
    senderAlias: 'senderAlias',
    timestamp: DateTime(2021, 1, 1),
    direction: TransferDirection.receive,
  );
}
