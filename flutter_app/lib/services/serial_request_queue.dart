/// Runs asynchronous work one request at a time and coalesces duplicate keys.
///
/// Different keys are never allowed to disappear behind the current request;
/// they wait in FIFO order. A failed request is returned to its caller but
/// does not poison the queue for later work.
class SerialRequestQueue<K, V> {
  final Map<K, Future<V>> _requests = <K, Future<V>>{};
  Future<void> _tail = Future<void>.value();

  /// Waits for all work already submitted to this queue, including requests
  /// added while an earlier request was finishing.
  Future<void> waitForIdle() async {
    while (true) {
      final observedTail = _tail;
      await observedTail;
      if (identical(observedTail, _tail)) return;
    }
  }

  Future<V> run(K key, Future<V> Function() operation) {
    final existing = _requests[key];
    if (existing != null) return existing;

    final predecessor = _tail;
    late final Future<V> request;
    request = predecessor.then((_) => operation()).whenComplete(() {
      if (identical(_requests[key], request)) _requests.remove(key);
    });
    _requests[key] = request;
    // Keep the sequencing tail successful even if this request fails. The
    // original [request] still preserves the error for its own caller.
    _tail = request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }
}
