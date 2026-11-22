import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

class TransferHistoryState {
  final List<TransferHistoryEntry> runtime;
  final List<TransferHistoryEntry> persistent;

  const TransferHistoryState({
    required this.runtime,
    required this.persistent,
  });
}

/// This provider stores the history of sent and received files.
///
/// Every entry is recorded in the runtime layer.
/// The persistent layer is only written when "save to history" is enabled.
final transferHistoryProvider = ReduxProvider<TransferHistoryService, TransferHistoryState>((ref) {
  return TransferHistoryService(ref.read(persistenceProvider));
});

class TransferHistoryService extends ReduxNotifier<TransferHistoryState> {
  final PersistenceService _persistence;

  TransferHistoryService(this._persistence);

  @override
  TransferHistoryState init() {
    return TransferHistoryState(
      runtime: const [],
      persistent: _persistence.getTransferHistory(),
    );
  }
}

/// Adds an entry to the runtime layer and, if enabled, to the persistent layer.
class RecordHistoryEntryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final TransferHistoryEntry entry;

  RecordHistoryEntryAction(this.entry);

  @override
  Future<TransferHistoryState> reduce() async {
    final runtime = _upsert(state.runtime, entry);
    if (!notifier._persistence.isSaveToHistory()) {
      return TransferHistoryState(runtime: runtime, persistent: state.persistent);
    }

    var persistent = _upsert(state.persistent, entry);
    final limit = notifier._persistence.getHistoryLimit();
    if (limit > 0) {
      persistent = persistent.take(limit).toList();
    }
    await notifier._persistence.setTransferHistory(persistent);
    return TransferHistoryState(runtime: runtime, persistent: persistent);
  }
}

/// Removes an entry from the given layer.
class RemoveHistoryEntryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final HistoryLayer layer;
  final String entryId;

  RemoveHistoryEntryAction(this.layer, this.entryId);

  @override
  Future<TransferHistoryState> reduce() async {
    final entries = layer == HistoryLayer.runtime ? state.runtime : state.persistent;
    final index = entries.indexWhere((e) => e.id == entryId);
    if (index == -1) {
      return state;
    }
    final updated = [...entries]..removeAt(index);

    if (layer == HistoryLayer.runtime) {
      return TransferHistoryState(runtime: updated, persistent: state.persistent);
    }
    await notifier._persistence.setTransferHistory(updated);
    return TransferHistoryState(runtime: state.runtime, persistent: updated);
  }
}

/// Removes several entries from the given layer.
class RemoveHistoryEntriesAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final HistoryLayer layer;
  final Set<String> entryIds;

  RemoveHistoryEntriesAction(this.layer, this.entryIds);

  @override
  Future<TransferHistoryState> reduce() async {
    if (entryIds.isEmpty) {
      return state;
    }
    final entries = layer == HistoryLayer.runtime ? state.runtime : state.persistent;
    final updated = entries.where((e) => !entryIds.contains(e.id)).toList();
    if (updated.length == entries.length) {
      return state;
    }

    if (layer == HistoryLayer.runtime) {
      return TransferHistoryState(runtime: updated, persistent: state.persistent);
    }
    await notifier._persistence.setTransferHistory(updated);
    return TransferHistoryState(runtime: state.runtime, persistent: updated);
  }
}

/// Removes all entries of the given layer.
class ClearHistoryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final HistoryLayer layer;

  ClearHistoryAction(this.layer);

  @override
  Future<TransferHistoryState> reduce() async {
    if (layer == HistoryLayer.runtime) {
      return TransferHistoryState(runtime: const [], persistent: state.persistent);
    }
    await notifier._persistence.setTransferHistory([]);
    return TransferHistoryState(runtime: state.runtime, persistent: const []);
  }
}

/// Truncates the persistent layer to [limit] entries. `0` means unlimited.
class TrimHistoryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final int limit;

  TrimHistoryAction(this.limit);

  @override
  Future<TransferHistoryState> reduce() async {
    if (limit <= 0 || state.persistent.length <= limit) {
      return state;
    }
    final updated = state.persistent.take(limit).toList();
    await notifier._persistence.setTransferHistory(updated);
    return TransferHistoryState(runtime: state.runtime, persistent: updated);
  }
}

/// Moves [entry] to the front, replacing an existing entry with the same id.
List<TransferHistoryEntry> _upsert(List<TransferHistoryEntry> entries, TransferHistoryEntry entry) {
  return [entry, ...entries.where((e) => e.id != entry.id)];
}
