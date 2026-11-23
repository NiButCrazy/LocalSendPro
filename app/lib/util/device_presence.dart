import 'dart:async';

import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('DevicePresence');

/// 设备列表可能是旧缓存：移除后重新扫描，只有再次被发现才算在线。
///
/// The caller should show a "looking for device" state while this runs, so an
/// offline device fails before a session starts waiting for a response.
Future<Device?> waitForDevicePresence(
  Ref ref,
  String fingerprint, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  Device? find(NearbyDevicesState state) {
    final device = state.allDevices[fingerprint];
    if (device == null || device.ip == null || device.download) {
      return null;
    }
    return device;
  }

  ref.redux(nearbyDevicesProvider).dispatch(RemoveDeviceAction(fingerprint));
  final immediate = find(ref.read(nearbyDevicesProvider));
  if (immediate != null) {
    return immediate;
  }

  ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
  unawaited(
    ref.global.dispatchAsync(StartSmartScan()).catchError((Object e) {
      _logger.info('Scanning while looking for $fingerprint failed: $e');
    }),
  );

  try {
    return await ref
        .stream(nearbyDevicesProvider)
        .map((event) => find(event.next))
        .where((device) => device != null)
        .cast<Device>()
        .first
        .timeout(timeout);
  } on TimeoutException {
    return null;
  }
}
