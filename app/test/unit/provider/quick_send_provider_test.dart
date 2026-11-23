import 'dart:io';

import 'package:localsend_app/provider/quick_send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
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
