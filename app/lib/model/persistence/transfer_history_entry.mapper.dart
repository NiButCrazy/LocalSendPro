// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'transfer_history_entry.dart';

class TransferDirectionMapper extends EnumMapper<TransferDirection> {
  TransferDirectionMapper._();

  static TransferDirectionMapper? _instance;
  static TransferDirectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TransferDirectionMapper._());
    }
    return _instance!;
  }

  static TransferDirection fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TransferDirection decode(dynamic value) {
    switch (value) {
      case r'receive':
        return TransferDirection.receive;
      case r'send':
        return TransferDirection.send;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TransferDirection self) {
    switch (self) {
      case TransferDirection.receive:
        return r'receive';
      case TransferDirection.send:
        return r'send';
    }
  }
}

extension TransferDirectionMapperExtension on TransferDirection {
  String toValue() {
    TransferDirectionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TransferDirection>(this) as String;
  }
}

class TransferHistoryEntryMapper extends ClassMapperBase<TransferHistoryEntry> {
  TransferHistoryEntryMapper._();

  static TransferHistoryEntryMapper? _instance;
  static TransferHistoryEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TransferHistoryEntryMapper._());
      FileTypeMapper.ensureInitialized();
      TransferDirectionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TransferHistoryEntry';

  static String _$id(TransferHistoryEntry v) => v.id;
  static const Field<TransferHistoryEntry, String> _f$id = Field('id', _$id);
  static String _$fileName(TransferHistoryEntry v) => v.fileName;
  static const Field<TransferHistoryEntry, String> _f$fileName = Field(
    'fileName',
    _$fileName,
  );
  static FileType _$fileType(TransferHistoryEntry v) => v.fileType;
  static const Field<TransferHistoryEntry, FileType> _f$fileType = Field(
    'fileType',
    _$fileType,
  );
  static String? _$path(TransferHistoryEntry v) => v.path;
  static const Field<TransferHistoryEntry, String> _f$path = Field(
    'path',
    _$path,
  );
  static bool _$savedToGallery(TransferHistoryEntry v) => v.savedToGallery;
  static const Field<TransferHistoryEntry, bool> _f$savedToGallery = Field(
    'savedToGallery',
    _$savedToGallery,
  );
  static bool _$isMessage(TransferHistoryEntry v) => v.isMessage;
  static const Field<TransferHistoryEntry, bool> _f$isMessage = Field(
    'isMessage',
    _$isMessage,
    hook: IsMessageHook(),
  );
  static int _$fileSize(TransferHistoryEntry v) => v.fileSize;
  static const Field<TransferHistoryEntry, int> _f$fileSize = Field(
    'fileSize',
    _$fileSize,
  );
  static String _$senderAlias(TransferHistoryEntry v) => v.senderAlias;
  static const Field<TransferHistoryEntry, String> _f$senderAlias = Field(
    'senderAlias',
    _$senderAlias,
  );
  static DateTime _$timestamp(TransferHistoryEntry v) => v.timestamp;
  static const Field<TransferHistoryEntry, DateTime> _f$timestamp = Field(
    'timestamp',
    _$timestamp,
  );
  static TransferDirection _$direction(TransferHistoryEntry v) => v.direction;
  static const Field<TransferHistoryEntry, TransferDirection> _f$direction =
      Field('direction', _$direction, hook: DirectionHook());

  @override
  final MappableFields<TransferHistoryEntry> fields = const {
    #id: _f$id,
    #fileName: _f$fileName,
    #fileType: _f$fileType,
    #path: _f$path,
    #savedToGallery: _f$savedToGallery,
    #isMessage: _f$isMessage,
    #fileSize: _f$fileSize,
    #senderAlias: _f$senderAlias,
    #timestamp: _f$timestamp,
    #direction: _f$direction,
  };

  static TransferHistoryEntry _instantiate(DecodingData data) {
    return TransferHistoryEntry(
      id: data.dec(_f$id),
      fileName: data.dec(_f$fileName),
      fileType: data.dec(_f$fileType),
      path: data.dec(_f$path),
      savedToGallery: data.dec(_f$savedToGallery),
      isMessage: data.dec(_f$isMessage),
      fileSize: data.dec(_f$fileSize),
      senderAlias: data.dec(_f$senderAlias),
      timestamp: data.dec(_f$timestamp),
      direction: data.dec(_f$direction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TransferHistoryEntry fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TransferHistoryEntry>(map);
  }

  static TransferHistoryEntry deserialize(String json) {
    return ensureInitialized().decodeJson<TransferHistoryEntry>(json);
  }
}

mixin TransferHistoryEntryMappable {
  String serialize() {
    return TransferHistoryEntryMapper.ensureInitialized()
        .encodeJson<TransferHistoryEntry>(this as TransferHistoryEntry);
  }

  Map<String, dynamic> toJson() {
    return TransferHistoryEntryMapper.ensureInitialized()
        .encodeMap<TransferHistoryEntry>(this as TransferHistoryEntry);
  }

  TransferHistoryEntryCopyWith<
    TransferHistoryEntry,
    TransferHistoryEntry,
    TransferHistoryEntry
  >
  get copyWith =>
      _TransferHistoryEntryCopyWithImpl<
        TransferHistoryEntry,
        TransferHistoryEntry
      >(this as TransferHistoryEntry, $identity, $identity);
  @override
  String toString() {
    return TransferHistoryEntryMapper.ensureInitialized().stringifyValue(
      this as TransferHistoryEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return TransferHistoryEntryMapper.ensureInitialized().equalsValue(
      this as TransferHistoryEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return TransferHistoryEntryMapper.ensureInitialized().hashValue(
      this as TransferHistoryEntry,
    );
  }
}

extension TransferHistoryEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TransferHistoryEntry, $Out> {
  TransferHistoryEntryCopyWith<$R, TransferHistoryEntry, $Out>
  get $asTransferHistoryEntry => $base.as(
    (v, t, t2) => _TransferHistoryEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TransferHistoryEntryCopyWith<
  $R,
  $In extends TransferHistoryEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? fileName,
    FileType? fileType,
    String? path,
    bool? savedToGallery,
    bool? isMessage,
    int? fileSize,
    String? senderAlias,
    DateTime? timestamp,
    TransferDirection? direction,
  });
  TransferHistoryEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TransferHistoryEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TransferHistoryEntry, $Out>
    implements TransferHistoryEntryCopyWith<$R, TransferHistoryEntry, $Out> {
  _TransferHistoryEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TransferHistoryEntry> $mapper =
      TransferHistoryEntryMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? fileName,
    FileType? fileType,
    Object? path = $none,
    bool? savedToGallery,
    bool? isMessage,
    int? fileSize,
    String? senderAlias,
    DateTime? timestamp,
    TransferDirection? direction,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (fileName != null) #fileName: fileName,
      if (fileType != null) #fileType: fileType,
      if (path != $none) #path: path,
      if (savedToGallery != null) #savedToGallery: savedToGallery,
      if (isMessage != null) #isMessage: isMessage,
      if (fileSize != null) #fileSize: fileSize,
      if (senderAlias != null) #senderAlias: senderAlias,
      if (timestamp != null) #timestamp: timestamp,
      if (direction != null) #direction: direction,
    }),
  );
  @override
  TransferHistoryEntry $make(CopyWithData data) => TransferHistoryEntry(
    id: data.get(#id, or: $value.id),
    fileName: data.get(#fileName, or: $value.fileName),
    fileType: data.get(#fileType, or: $value.fileType),
    path: data.get(#path, or: $value.path),
    savedToGallery: data.get(#savedToGallery, or: $value.savedToGallery),
    isMessage: data.get(#isMessage, or: $value.isMessage),
    fileSize: data.get(#fileSize, or: $value.fileSize),
    senderAlias: data.get(#senderAlias, or: $value.senderAlias),
    timestamp: data.get(#timestamp, or: $value.timestamp),
    direction: data.get(#direction, or: $value.direction),
  );

  @override
  TransferHistoryEntryCopyWith<$R2, TransferHistoryEntry, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _TransferHistoryEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

