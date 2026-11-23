import 'dart:ffi';
import 'dart:io';

import 'package:logging/logging.dart';

final _logger = Logger('ShellChangeNotify');

/// 与 `SHCNE_ASSOCCHANGED` 对齐：通知外壳文件关联/动词已变更。
const _shcneAssocChanged = 0x08000000;

/// 与 `SHCNF_IDLIST` 对齐：只刷新项列表，不携带路径参数。
const _shcnfIdList = 0x0000;

typedef _ShChangeNotifyNative = Void Function(Int32, Uint32, Pointer<Void>, Pointer<Void>);
typedef _ShChangeNotifyDart = void Function(int, int, Pointer<Void>, Pointer<Void>);

_ShChangeNotifyDart? _cached;
bool _resolved = false;

/// 通知资源管理器右键菜单缓存已失效。
///
/// 仅 Windows 有效；其它平台静默返回。旧版 Explorer 可能仍然缓存子菜单，
/// 此时只能重启 Explorer。
void notifyShellAssociationsChanged() {
  if (!Platform.isWindows) {
    return;
  }

  if (!_resolved) {
    _resolved = true;
    try {
      final library = DynamicLibrary.open('shell32.dll');
      _cached = library.lookupFunction<_ShChangeNotifyNative, _ShChangeNotifyDart>('SHChangeNotify');
    } catch (e, stackTrace) {
      _logger.warning('Could not load SHChangeNotify', e, stackTrace);
    }
  }

  final notify = _cached;
  if (notify == null) {
    return;
  }
  notify(_shcneAssocChanged, _shcnfIdList, nullptr, nullptr);
}
