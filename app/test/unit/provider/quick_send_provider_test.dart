import 'dart:io';

import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/quick_send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('sendToFingerprint', () {
    test('返回 --send-to 后的一项', () {
      expect(sendToFingerprint(['--hidden', '--send-to', 'ABC', r'C:\file.txt']), 'ABC');
    });

    test('缺少参数或为空时返回 null', () {
      expect(sendToFingerprint(['--hidden']), isNull);
      expect(sendToFingerprint(['--send-to']), isNull);
      expect(sendToFingerprint(['--send-to', '   ']), isNull);
    });
  });

  group('hasPendingRequest', () {
    test('等待确认且尚无远端会话时阻止同一设备', () {
      final sessions = [_session(fingerprint: 'fp', status: SessionStatus.waiting)];

      expect(hasPendingRequest(sessions, 'fp'), isTrue);
      expect(hasPendingRequest(sessions, 'other'), isFalse);
    });

    test('已接受或已结束的会话不阻止', () {
      expect(
        hasPendingRequest([_session(fingerprint: 'fp', status: SessionStatus.waiting, remoteSessionId: 'remote')], 'fp'),
        isFalse,
      );
      expect(hasPendingRequest([_session(fingerprint: 'fp', status: SessionStatus.sending, remoteSessionId: 'remote')], 'fp'), isFalse);
      expect(hasPendingRequest([_session(fingerprint: 'fp', status: SessionStatus.finished)], 'fp'), isFalse);
    });
  });

  group('LoadSelectionFromArgsAction', () {
    test('--send-to 的值不会被当作文件路径', () async {
      final temp = Directory.systemTemp.createTempSync('localsend_quick_send');
      addTearDown(() => temp.deleteSync(recursive: true));
      final devicePath = Directory(p.join(temp.path, 'fingerprint'))..createSync();

      final service = ReduxNotifier.test(redux: SelectedSendingFilesNotifier());
      final added = await service.dispatchAsyncTakeResult(
        LoadSelectionFromArgsAction(['--hidden', '--send-to', devicePath.path]),
      );

      expect(added, isFalse);
      expect(service.state, isEmpty);
    });

    test('没有 --send-to 时目录仍会被加载', () async {
      final temp = Directory.systemTemp.createTempSync('localsend_quick_send');
      addTearDown(() => temp.deleteSync(recursive: true));
      final directory = Directory(p.join(temp.path, 'folder'))..createSync();

      final service = ReduxNotifier.test(redux: SelectedSendingFilesNotifier());
      final added = await service.dispatchAsyncTakeResult(LoadSelectionFromArgsAction(['--hidden', directory.path]));

      expect(added, isTrue);
    });
  });
}

Device _device({required String fingerprint, required String alias}) {
  return Device(
    signalingId: null,
    ip: '192.168.1.10',
    version: '2.2',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: alias,
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: false,
    channels: const [HttpChannel(host: '192.168.1.10', port: 53317, https: true)],
  );
}

SendSessionState _session({
  required String fingerprint,
  required SessionStatus status,
  String? remoteSessionId,
}) {
  return SendSessionState(
    sessionId: 'session-$fingerprint',
    remoteSessionId: remoteSessionId,
    background: true,
    status: status,
    target: _device(fingerprint: fingerprint, alias: fingerprint),
    files: const {},
    hashedFileCount: 1,
    startTime: null,
    endTime: null,
    sendingTasks: null,
    errorMessage: null,
  );
}
