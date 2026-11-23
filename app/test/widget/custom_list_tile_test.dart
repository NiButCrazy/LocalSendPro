import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_isolates/model/device.dart';

const _device = Device(
  signalingId: null,
  ip: '192.168.1.2',
  version: '2.2',
  port: 53317,
  https: true,
  fingerprint: 'fingerprint',
  alias: '整洁的桃子',
  deviceModel: 'Vivo',
  deviceType: DeviceType.mobile,
  download: false,
  channels: [],
);

Widget _build({double? height, String? statusLabel}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          height: height,
          child: DeviceListTile(
            device: _device,
            statusLabel: statusLabel,
            onDetailsTap: _noop,
          ),
        ),
      ),
    ),
  );
}

void _noop() {}

void main() {
  testWidgets('DeviceListTile does not overflow when constrained below its natural height', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    final naturalHeight = tester.getSize(find.byType(DeviceListTile)).height;

    // Hero 飞行会把列表项约束到插值高度，可能比自然高度略小。
    await tester.pumpWidget(_build(height: naturalHeight - 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DeviceListTile)).height, naturalHeight - 2);
  });

  testWidgets('DeviceListTile renders a status badge', (tester) async {
    await tester.pumpWidget(_build(statusLabel: '等待确认'));
    await tester.pumpAndSettle();

    expect(find.text('等待确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
