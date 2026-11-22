import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/history_direction_filter.dart';
import 'package:localsend_app/model/persistence/history_layer.dart';
import 'package:localsend_app/model/persistence/transfer_history_entry.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/transfer_history_provider.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _EntryOption {
  open,
  showInFolder,
  info,
  delete;

  String get label {
    return switch (this) {
      _EntryOption.open => t.receiveHistoryPage.entryActions.open,
      _EntryOption.showInFolder => t.receiveHistoryPage.entryActions.showInFolder,
      _EntryOption.info => t.receiveHistoryPage.entryActions.info,
      _EntryOption.delete => t.receiveHistoryPage.entryActions.deleteFromHistory,
    };
  }
}

const _optionsAll = _EntryOption.values;
final _optionsWithoutOpen = [_EntryOption.info, _EntryOption.delete];

enum _DeleteMissingChoice { thisOnly, allMissing }

extension on HistoryDirectionFilter {
  String get label {
    return switch (this) {
      HistoryDirectionFilter.all => t.receiveHistoryPage.filters.all,
      HistoryDirectionFilter.receive => t.receiveHistoryPage.filters.receive,
      HistoryDirectionFilter.send => t.receiveHistoryPage.filters.send,
    };
  }
}

class TransferHistoryTab extends StatefulWidget {
  const TransferHistoryTab({super.key});

  @override
  State<TransferHistoryTab> createState() => _TransferHistoryTabState();
}

class _TransferHistoryTabState extends State<TransferHistoryTab> {
  HistoryLayer _layer = HistoryLayer.runtime;
  late HistoryDirectionFilter _directionFilter;
  bool _filterInitialized = false;

  /// Whether the file behind an entry still exists, checked lazily per entry.
  final Map<String, bool> _fileExists = {};
  final Set<String> _checkingFiles = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_filterInitialized) {
      _filterInitialized = true;
      final settings = context.read(settingsProvider);
      _directionFilter = settings.historyDefaultFilter;
      _layer = settings.historyDefaultLayer;
    }
  }

  Future<void> _openFile(
    TransferHistoryEntry entry,
    Dispatcher<TransferHistoryService, TransferHistoryState> dispatcher,
  ) async {
    if (entry.path != null) {
      await openFile(
        context,
        entry.fileType,
        entry.path!,
        onDeleteTap: () => dispatcher.dispatchAsync(RemoveHistoryEntryAction(_layer, entry.id)),
      );
    }
  }

  void _toggleLayer() {
    setState(() => _layer = _layer == HistoryLayer.runtime ? HistoryLayer.persistent : HistoryLayer.runtime);
  }

  /// Checks the file once, the first time the entry is built.
  void _ensureFileExists(TransferHistoryEntry entry) {
    final path = entry.path;
    if (path == null || path.startsWith('content://') || _fileExists.containsKey(entry.id) || !_checkingFiles.add(entry.id)) {
      return;
    }

    unawaited(
      File(path).exists().then(
        (exists) {
          if (!mounted) {
            return;
          }
          setState(() => _fileExists[entry.id] = exists);
        },
        onError: (_) {
          if (!mounted) {
            return;
          }
          setState(() => _fileExists[entry.id] = false);
        },
      ),
    );
  }

  /// Collects the entries of [entries] whose file no longer exists.
  Future<Set<String>> _collectMissingFileIds(List<TransferHistoryEntry> entries) async {
    final missing = <String>{};
    for (final entry in entries) {
      final path = entry.path;
      if (path == null || path.startsWith('content://')) {
        continue;
      }
      final exists = _fileExists[entry.id] ?? await File(path).exists().catchError((_) => false);
      if (!exists) {
        missing.add(entry.id);
      }
    }
    return missing;
  }

  Future<void> _clear() async {
    if (_layer == HistoryLayer.runtime) {
      // 运行层只存在内存中，无需确认。
      await context.redux(transferHistoryProvider).dispatchAsync(ClearHistoryAction(HistoryLayer.runtime));
      return;
    }

    final result = await showDialog(
      context: context,
      builder: (_) => const HistoryClearDialog(),
    );
    if (!mounted || result != true) {
      return;
    }
    await context.redux(transferHistoryProvider).dispatchAsync(ClearHistoryAction(HistoryLayer.persistent));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(transferHistoryProvider);
    final layerEntries = _layer == HistoryLayer.runtime ? state.runtime : state.persistent;
    final entries = switch (_directionFilter) {
      HistoryDirectionFilter.all => layerEntries,
      HistoryDirectionFilter.receive => layerEntries.where((e) => e.direction == TransferDirection.receive).toList(),
      HistoryDirectionFilter.send => layerEntries.where((e) => e.direction == TransferDirection.send).toList(),
    };
    final layerLabel = _layer == HistoryLayer.runtime ? t.receiveHistoryPage.segments.runtime : t.receiveHistoryPage.segments.persistent;
    final layerIcon = _layer == HistoryLayer.runtime ? Icons.schedule : Icons.all_inclusive;
    final isNarrow = SizingInformation(MediaQuery.sizeOf(context).width).isMobile;

    final layerIconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(layerIcon, key: ValueKey(_layer), size: 18),
    );

    final layerButton = Tooltip(
      message: layerLabel,
      child: isNarrow
          ? OutlinedButton(
              onPressed: _toggleLayer,
              child: layerIconWidget,
            )
          : OutlinedButton.icon(
              onPressed: _toggleLayer,
              icon: layerIconWidget,
              label: Text(layerLabel),
            ),
    );
    final actionStyle = ElevatedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainerIfDark,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainerIfDark,
    );
    final openFolderLabel = t.receiveHistoryPage.openFolder;
    final clearLabel = _layer == HistoryLayer.runtime ? t.receiveHistoryPage.clearRuntime : t.receiveHistoryPage.deleteHistory;
    final onOpenFolder = checkPlatform([TargetPlatform.iOS])
        ? null
        : () async {
            // ignore: use_build_context_synchronously
            final destination = context.read(settingsProvider).destination ?? await getDefaultDestinationDirectory();
            await openFolder(folderPath: destination);
          };
    final onClear = layerEntries.isEmpty ? null : _clear;

    final openFolderButton = isNarrow
        ? Tooltip(
            message: openFolderLabel,
            child: ElevatedButton(
              style: actionStyle,
              onPressed: onOpenFolder,
              child: const Icon(Icons.folder),
            ),
          )
        : ElevatedButton.icon(
            style: actionStyle,
            onPressed: onOpenFolder,
            icon: const Icon(Icons.folder),
            label: Text(openFolderLabel),
          );
    final clearButton = isNarrow
        ? Tooltip(
            message: clearLabel,
            child: ElevatedButton(
              style: actionStyle,
              onPressed: onClear,
              child: const Icon(Icons.delete),
            ),
          )
        : ElevatedButton.icon(
            style: actionStyle,
            onPressed: onClear,
            icon: const Icon(Icons.delete),
            label: Text(clearLabel),
          );
    final actionButtons = [
      if (_layer == HistoryLayer.persistent) openFolderButton,
      clearButton,
    ];

    return ResponsiveListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        Center(
          child: SegmentedButton<HistoryDirectionFilter>(
            segments: HistoryDirectionFilter.values.map((filter) => ButtonSegment(value: filter, label: Text(filter.label))).toList(),
            selected: {_directionFilter},
            onSelectionChanged: (selection) => setState(() => _directionFilter = selection.first),
          ),
        ),
        const SizedBox(height: 20),
        if (isNarrow)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                layerButton,
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 8,
                      children: actionButtons,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 15),
                layerButton,
                for (final button in actionButtons) ...[
                  const SizedBox(width: 20),
                  button,
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Icon(
                Icons.history,
                size: 200,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          )
        else
          Column(
            children: entries.map((entry) {
              _ensureFileExists(entry);
              final fileMissing = _fileExists[entry.id] == false;
              final peer = entry.direction == TransferDirection.send
                  ? t.receiveHistoryPage.sentTo(alias: entry.senderAlias)
                  : t.receiveHistoryPage.receivedFrom(alias: entry.senderAlias);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    splashColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    hoverColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    onTap: !fileMissing && (entry.path != null || entry.isMessage)
                        ? () async {
                            if (entry.isMessage) {
                              final vm = ViewProvider((ref) {
                                return ReceivePageVm(
                                  status: SessionStatus.waiting,
                                  sender: Device(
                                    signalingId: null,
                                    ip: '0.0.0.0',
                                    version: '1.0.0',
                                    port: 8080,
                                    https: false,
                                    fingerprint: 'fingerprint',
                                    alias: entry.senderAlias,
                                    deviceModel: 'deviceModel',
                                    deviceType: DeviceType.web,
                                    download: true,
                                    channels: const [],
                                  ),
                                  showSenderInfo: false,
                                  files: [],
                                  message: entry.fileName,
                                  onAccept: () {},
                                  onDecline: () {},
                                  onClose: () {},
                                );
                              });

                              // ignore: unawaited_futures
                              context.push(() => ReceivePage(vm));
                              return;
                            }

                            await _openFile(entry, context.redux(transferHistoryProvider));
                          }
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            FilePathThumbnail(
                              path: entry.path,
                              fileType: entry.fileType,
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IgnorePointer(
                                ignoring: !fileMissing,
                                child: AnimatedScale(
                                  scale: fileMissing ? 1 : 0,
                                  alignment: Alignment.topRight,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedOpacity(
                                    opacity: fileMissing ? 1 : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: Tooltip(
                                      message: t.receiveHistoryPage.fileMissing,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.priority_high,
                                          size: 10,
                                          color: Theme.of(context).colorScheme.onError,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 3),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: fileMissing ? 0.5 : 1),
                                ),
                                child: Text(
                                  entry.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                ),
                              ),
                              Text(
                                '${entry.timestampString(context)} - ${entry.fileSize.asReadableFileSize} - $peer',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        PopupMenuButton<_EntryOption>(
                          onSelected: (_EntryOption item) async {
                            switch (item) {
                              case _EntryOption.open:
                                await _openFile(entry, context.redux(transferHistoryProvider));
                                break;
                              case _EntryOption.showInFolder:
                                if (entry.path != null) {
                                  await openFolder(
                                    folderPath: File(entry.path!).parent.path,
                                    fileName: path.basename(entry.path!),
                                  );
                                }
                                break;
                              case _EntryOption.info:
                                // ignore: use_build_context_synchronously
                                await showDialog(
                                  context: context,
                                  builder: (_) => FileInfoDialog(entry: entry),
                                );
                                break;
                              case _EntryOption.delete:
                                if (!fileMissing) {
                                  // ignore: use_build_context_synchronously
                                  await context.redux(transferHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(_layer, entry.id));
                                  break;
                                }

                                // Offer to clean up every entry whose file is gone as well.
                                final missingFileIds = await _collectMissingFileIds(layerEntries);
                                missingFileIds.add(entry.id);
                                if (!mounted) {
                                  return;
                                }
                                if (missingFileIds.length <= 1) {
                                  // ignore: use_build_context_synchronously
                                  await context.redux(transferHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(_layer, entry.id));
                                  break;
                                }
                                // ignore: use_build_context_synchronously
                                final choice = await showDialog<_DeleteMissingChoice>(
                                  // ignore: use_build_context_synchronously
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: Text(t.receiveHistoryPage.entryActions.deleteFromHistory),
                                      content: Text(t.receiveHistoryPage.deleteMissingPrompt(n: missingFileIds.length)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => context.pop(),
                                          child: Text(t.general.cancel),
                                        ),
                                        TextButton(
                                          onPressed: () => context.pop(_DeleteMissingChoice.thisOnly),
                                          child: Text(t.receiveHistoryPage.deleteThisOnly),
                                        ),
                                        FilledButton(
                                          onPressed: () => context.pop(_DeleteMissingChoice.allMissing),
                                          child: Text(t.receiveHistoryPage.deleteAllMissing),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (!mounted || choice == null) {
                                  return;
                                }
                                // ignore: use_build_context_synchronously
                                final dispatcher = context.redux(transferHistoryProvider);
                                if (choice == _DeleteMissingChoice.allMissing) {
                                  await dispatcher.dispatchAsync(RemoveHistoryEntriesAction(_layer, missingFileIds));
                                } else {
                                  await dispatcher.dispatchAsync(RemoveHistoryEntryAction(_layer, entry.id));
                                }
                                break;
                            }
                          },
                          itemBuilder: (BuildContext context) {
                            return (entry.path != null && !fileMissing ? _optionsAll : _optionsWithoutOpen).map((e) {
                              return PopupMenuItem<_EntryOption>(
                                value: e,
                                child: Text(e.label),
                              );
                            }).toList();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
