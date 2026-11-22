/// The layer of the transfer history.
enum HistoryLayer {
  /// Entries recorded since this process started. Lost on exit.
  runtime,

  /// Entries persisted across restarts.
  persistent,
}
