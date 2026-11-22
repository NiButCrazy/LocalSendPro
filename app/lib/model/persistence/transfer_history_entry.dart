import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/widgets.dart';
import 'package:localsend_app/util/system_date_time_formatter.dart';
import 'package:localsend_isolates/model/file_type.dart';

part 'transfer_history_entry.mapper.dart';

/// The direction of a transfer.
@MappableEnum()
enum TransferDirection { receive, send }

@MappableClass()
class TransferHistoryEntry with TransferHistoryEntryMappable {
  final String id;

  /// The name of the file.
  /// If [isMessage] is true, this is the message content.
  final String fileName;

  final FileType fileType;
  final String? path;
  final bool savedToGallery;

  @MappableField(hook: IsMessageHook())
  final bool isMessage;

  final int fileSize;

  /// The alias of the other device: the sender for received files,
  /// the recipient for sent files.
  final String senderAlias;

  final DateTime timestamp;

  @MappableField(hook: DirectionHook())
  final TransferDirection direction;

  const TransferHistoryEntry({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.path,
    required this.savedToGallery,
    required this.isMessage,
    required this.fileSize,
    required this.senderAlias,
    required this.timestamp,
    required this.direction,
  });

  /// Format string using the system date and time format.
  /// Because the raw timestamp is saved in UTC, we need to transform it to local time zone first.
  String timestampString(BuildContext context) {
    return SystemDateTimeFormatter.dateTime(context, timestamp.toLocal());
  }

  static const fromJson = TransferHistoryEntryMapper.fromJson;
}

class IsMessageHook extends MappingHook {
  const IsMessageHook();

  @override
  Object? beforeDecode(Object? value) {
    return value == true;
  }
}

class DirectionHook extends MappingHook {
  const DirectionHook();

  @override
  Object? beforeDecode(Object? value) {
    // 旧版本没有 direction 字段，全部是接收记录。
    if (value == null) {
      return TransferDirection.receive;
    }
    return value;
  }
}
