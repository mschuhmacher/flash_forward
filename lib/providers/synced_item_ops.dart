class SyncedItemOps {
  SyncedItemOps._();

  static Future<void> upsert<T>({
    required List<T> list,
    required T item,
    required String Function(T) getId,
    required Future<void> Function() saveLocal,
    Future<void> Function(T)? cloudOp,
    void Function(Object, StackTrace)? onCloudError,
  }) async {
    final id = getId(item);
    final index = list.indexWhere((i) => getId(i) == id);
    if (index == -1) {
      list.add(item);
    } else {
      list[index] = item;
    }
    await saveLocal();

    try {
      await cloudOp?.call(item);
    } catch (e, stackTrace) {
      onCloudError?.call(e, stackTrace);
    }
  }

  static Future<void> removeById<T>({
    required List<T> list,
    required String id,
    required String Function(T) getId,
    required Future<void> Function() saveLocal,
    Future<void> Function()? cloudOp,
    void Function(Object, StackTrace)? onCloudError,
  }) async {
    list.removeWhere((i) => getId(i) == id);
    await saveLocal();
    try {
      await cloudOp?.call();
    } catch (e, stackTrace) {
      onCloudError?.call(e, stackTrace);
    }
  }
}
