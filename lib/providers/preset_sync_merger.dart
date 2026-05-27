import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/services/sync_queue_service.dart';

class PresetSyncMerger {
  PresetSyncMerger._();

  /// Merges [cloudItems] with items from [pendingOps] that have not yet been
  /// uploaded (i.e. their id is absent from cloud results).
  ///
  /// Only operations matching [operationType] are considered.
  /// Items with a pending [deleteOperationType] op are excluded — they were
  /// deleted locally and must not be re-surfaced.
  /// Cloud always wins when the same id appears in both cloud and upload queue.
  ///
  /// Note: [fromJson] receives data serialised by the model's own toJson()
  /// (camelCase keys from the local queue), not the Supabase column mapping
  /// used in fetchUser*. Do not swap these callsites.
  static List<T> mergeWithPendingOps<T>({
    required List<T> cloudItems,
    required String Function(T) getId,
    required String operationType,
    required String deleteOperationType,
    required T Function(Map<String, dynamic>) fromJson,
    required List<SyncOperation> pendingOps,
  }) {
    final cloudIds = cloudItems.map(getId).toSet();
    final deletedIds =
        pendingOps
            .where((op) => op.type == deleteOperationType)
            .map((op) => op.id)
            .toSet();
    final unsynced = pendingOps
        .where(
          (op) =>
              op.type == operationType &&
              !cloudIds.contains(op.id) &&
              !deletedIds.contains(op.id),
        )
        .map((op) => fromJson(op.data));
    final filteredCloud =
        cloudItems.where((item) => !deletedIds.contains(getId(item))).toList();
    return [...filteredCloud, ...unsynced];
  }

  /// Merges [local] and [cloud] trash lists, deduplicating by id.
  /// When both lists contain the same id, the entry with the later [deletedAt]
  /// wins (last-write-wins conflict resolution).

  static List<TrashEntry> mergeTrashCloudAndLocal(
    List<TrashEntry> local,
    List<TrashEntry> cloud,
  ) {
    final byId = <String, TrashEntry>{};
    for (final e in local) {
      byId[e.id] = e;
    }
    for (final e in cloud) {
      final existing = byId[e.id];
      if (existing == null || e.deletedAt.isAfter(existing.deletedAt)) {
        byId[e.id] = e;
      }
    }
    return byId.values.toList();
  }
}
