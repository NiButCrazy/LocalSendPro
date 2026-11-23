import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/cache_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache cleanup completes only after temporary file deletion', () async {
    final file = _ControlledFile();
    var completed = false;
    final cleanup = clearTemporaryCacheFiles(_ControlledDirectory(Stream.value(file))).then((_) => completed = true);

    try {
      await file.deleteStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
    } finally {
      file.deleteFinished.complete(file);
      await cleanup;
    }
    expect(completed, isTrue);
  });

  test('does not spawn the platform-message isolate on desktop', () async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }

    // Desktop engines cannot route platform messages from a background isolate.
    // Before the guard, this threw inside the isolate's message callback.
    await ClearCacheAction().reduce();
  });
}

class _ControlledDirectory implements Directory {
  final Stream<FileSystemEntity> entries;

  _ControlledDirectory(this.entries);

  @override
  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledFile implements File {
  final deleteStarted = Completer<void>();
  final deleteFinished = Completer<File>();

  @override
  Future<File> delete({bool recursive = false}) {
    deleteStarted.complete();
    return deleteFinished.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
