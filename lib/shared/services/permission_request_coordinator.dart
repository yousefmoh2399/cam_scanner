class PermissionRequestCoordinator {
  PermissionRequestCoordinator._();

  static Future<void> _tail = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    late Future<T> current;
    current = previous.catchError((_) {}).then((_) => action());
    _tail = current.then<void>((_) {}, onError: (_) {});
    return current;
  }
}
