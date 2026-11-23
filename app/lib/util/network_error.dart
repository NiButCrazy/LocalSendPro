/// 判断底层传输错误是否属于“连接被断开/无法建立”。
///
/// Rust/reqwest 的错误文本随系统语言变化，这里只匹配稳定片段：Windows socket
/// 错误码与中英文连接错误描述。
bool isConnectionError(String message) {
  final lower = message.toLowerCase();
  const hints = [
    '10054', // 远程主机强迫关闭
    '10060', // 连接超时
    '10061', // 目标计算机积极拒绝
    'connection reset',
    'connection refused',
    'connection error',
    'tcp connect error',
    '远程主机强迫关闭',
    '积极拒绝',
  ];
  return hints.any(lower.contains);
}
