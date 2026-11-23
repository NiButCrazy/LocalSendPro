import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_isolates/model/device.dart';

void main() {
  group('buildDeviceMenuEntries', () {
    test('只保留可直连且可接收上传的设备', () {
      final entries = buildDeviceMenuEntries(
        devices: [
          _device(fingerprint: 'direct', alias: 'Direct'),
          _device(fingerprint: 'download', alias: 'Download', download: true),
          _device(fingerprint: 'signaling', alias: 'Signaling', ip: null),
        ],
        favoriteFingerprints: const {},
      );

      expect(entries.map((entry) => entry.fingerprint), ['direct']);
    });

    test('按指纹去重', () {
      final entries = buildDeviceMenuEntries(
        devices: [
          _device(fingerprint: 'a', alias: 'A'),
          _device(fingerprint: 'a', alias: 'A'),
        ],
        favoriteFingerprints: const {},
      );

      expect(entries, hasLength(1));
    });

    test('收藏优先，然后按别名与指纹排序', () {
      final entries = buildDeviceMenuEntries(
        devices: [
          _device(fingerprint: 'z', alias: 'Zulu'),
          _device(fingerprint: 'b', alias: 'bravo'),
          _device(fingerprint: 'a', alias: 'Alpha'),
          _device(fingerprint: 'f', alias: 'foxtrot'),
        ],
        favoriteFingerprints: {'z'},
      );

      expect(entries.map((entry) => entry.fingerprint), ['z', 'a', 'b', 'f']);
      expect(entries.first.favorite, isTrue);
    });

    test('最多保留 20 个设备', () {
      final entries = buildDeviceMenuEntries(
        devices: [for (var i = 0; i < 30; i++) _device(fingerprint: 'fp$i', alias: 'Device $i')],
        favoriteFingerprints: const {},
      );

      expect(entries, hasLength(20));
    });

    test('空别名回退为指纹', () {
      final entries = buildDeviceMenuEntries(
        devices: [_device(fingerprint: 'abc', alias: '   ')],
        favoriteFingerprints: const {},
      );

      expect(entries.single.displayAlias, 'abc');
    });
  });

  group('escapeMenuLabel', () {
    test('转义 & 并折叠换行', () {
      expect(escapeMenuLabel('A&B'), 'A&&B');
      expect(escapeMenuLabel('  A\r\nB  '), 'A B');
      expect(escapeMenuLabel(''), '');
    });
  });

  test('buildDeviceCommand 使用隐藏启动与指纹', () {
    expect(
      buildDeviceCommand(executable: r'C:\app.exe', fingerprint: 'FP', pathToken: '%1'),
      r'"C:\app.exe" --hidden --send-to "FP" "%1"',
    );
  });
}

Device _device({
  required String fingerprint,
  required String alias,
  String? ip = '192.168.1.10',
  bool download = false,
}) {
  return Device(
    signalingId: null,
    ip: ip,
    version: '2.2',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: alias,
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: download,
    channels: [
      if (ip != null) HttpChannel(host: ip, port: 53317, https: true),
    ],
  );
}
