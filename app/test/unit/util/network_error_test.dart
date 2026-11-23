import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/network_error.dart';

void main() {
  test('recognizes dropped and unreachable connections', () {
    expect(
      isConnectionError('error sending request: client error (SendRequest): connection error: 远程主机强迫关闭了一个现有的连接。 (os error 10054)'),
      isTrue,
    );
    expect(isConnectionError('tcp connect error: 由于目标计算机积极拒绝，无法连接。 (os error 10061)'), isTrue);
    expect(isConnectionError('connection reset by peer'), isTrue);
  });

  test('keeps protocol errors out', () {
    expect(isConnectionError('[403] Rejected'), isFalse);
    expect(isConnectionError('[409] Blocked by another session'), isFalse);
    expect(isConnectionError('error decoding response body'), isFalse);
  });
}
