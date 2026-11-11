Future<bool> withClientTokenLock(
  Future<void> Function() action, {
  bool requireLock = false,
}) async {
  await action();
  return true;
}
