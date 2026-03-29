import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A record of a single cloud operation that failed and needs to be retried.
///
/// When the app tries to upload or delete data in Supabase and the call fails
/// (e.g. no internet, server error), we don't just lose that change. Instead
/// we create a [SyncOperation] and hand it to [SyncQueueService.enqueue] so
/// it can be retried automatically once the device is back online.
///
/// Fields:
/// - [id]        — the ID of the entity being operated on (session id, workout
///                 id, etc.). Used to look up and deduplicate queue entries.
/// - [type]      — what kind of operation this is, e.g. 'uploadSession',
///                 'deleteSession', 'uploadWorkout'. Used together with [id]
///                 to uniquely identify an entry: the same entity can have
///                 both an upload *and* a delete pending at the same time
///                 (different types = two separate queue entries).
/// - [data]      — the full payload needed to retry the operation. For uploads
///                 this is the model's toJson() output. For deletes it is just
///                 `{'sessionId': id}` (or the equivalent key for the type).
/// - [createdAt] — when the operation was originally queued. Useful for
///                 debugging and future expiry logic.
class SyncOperation {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  SyncOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
    id: json['id'],
    type: json['type'],
    data: json['data'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// Persists and retries failed Supabase operations so data is never silently lost.
///
/// ## Why this exists
/// The app supports offline use. When a cloud call fails we cannot just drop
/// the change — the user's data would be lost. This service acts as a
/// durable outbox: failed operations are written to a local JSON file and
/// retried the next time [processQueue] is called (typically on app resume or
/// connectivity restoration).
///
/// ## How it works
/// 1. A cloud call (upload, delete, etc.) fails and catches the error.
/// 2. It calls [enqueue] with a [SyncOperation] describing what to retry.
/// 3. The operation is saved to `sync_queue.json` on disk so it survives
///    app restarts.
/// 4. When connectivity is restored, [processQueue] is called with a handler
///    that knows how to execute each operation type.
/// 5. Each successful retry calls [dequeue] to remove it from the queue.
///    Failed retries stay in the queue for the next attempt.
class SyncQueueService {
  static const String _queueFileName = 'sync_queue.json';

  List<SyncOperation> _queue = [];
  bool _isProcessing = false;

  /// Loads the persisted queue from disk into memory.
  ///
  /// Call this once at startup (before reading [pendingOperations]) to ensure
  /// operations queued in previous app sessions are not lost. It is safe to
  /// call multiple times — later calls simply overwrite the in-memory list
  /// with the same file contents.
  Future<void> loadQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_queueFileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(contents);
        _queue = jsonList.map((json) => SyncOperation.fromJson(json)).toList();
      }
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      _queue = [];
    }
  }

  /// Writes the current in-memory queue to disk.
  ///
  /// Called automatically by [enqueue] and [dequeue] after every mutation so
  /// the on-disk state always matches memory. If the write fails the error is
  /// reported to Sentry but not rethrown — a failed save is bad, but it is
  /// better to continue than to crash the app.
  Future<void> _saveQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_queueFileName');
      final jsonList = _queue.map((op) => op.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Adds [operation] to the queue and persists it to disk.
  ///
  /// ## Deduplication
  /// Before adding, any existing entry with the same `(id, type)` pair is
  /// removed. This means re-enqueuing the same upload (e.g. after a second
  /// failed attempt) replaces the old entry rather than accumulating
  /// duplicates. The replacement also refreshes [SyncOperation.data] to the
  /// latest version of the payload.
  ///
  /// Note that `id` alone is *not* used for deduplication. A session can
  /// legitimately have both an `uploadSession` *and* a `deleteSession` pending
  /// at the same time — for example if the user creates a session offline and
  /// then immediately deletes it before any sync runs. These are two distinct
  /// operations that must both be preserved.
  Future<void> enqueue(SyncOperation operation) async {
    // Replace any existing entry for this (id, type) pair to avoid duplicates.
    // We match on both fields so that an upload and a delete for the same
    // entity can coexist in the queue as separate entries.
    _queue.removeWhere(
        (op) => op.id == operation.id && op.type == operation.type);
    _queue.add(operation);
    await _saveQueue();
  }

  /// Removes the entry matching both [operationId] and [operationType] from
  /// the queue and persists the change to disk.
  ///
  /// ## Why both id AND type must match
  /// Consider this scenario: a session is created offline (`uploadSession`
  /// queued) and then immediately deleted (`deleteSession` queued). Both
  /// entries share the same `id`. When [processQueue] successfully retries the
  /// upload it must only remove the `uploadSession` entry — the `deleteSession`
  /// must stay in the queue so it is retried next. Matching on `id` alone
  /// would silently remove the pending delete, leaving the session in the cloud
  /// forever.
  ///
  /// Called automatically by [processQueue] after each successful retry.
  Future<void> dequeue(String operationId, String operationType) async {
    _queue.removeWhere(
        (op) => op.id == operationId && op.type == operationType);
    await _saveQueue();
  }

  /// Returns an unmodifiable snapshot of all pending operations.
  ///
  /// Use this to inspect what is waiting to be synced — for example to merge
  /// locally-queued items with cloud data on app startup. The list is a copy,
  /// so mutations to the queue do not affect any reference you hold to it.
  List<SyncOperation> get pendingOperations => List.unmodifiable(_queue);

  /// Whether there are any operations waiting to be synced.
  bool get hasPendingOperations => _queue.isNotEmpty;

  /// Number of operations currently waiting to be synced.
  int get pendingCount => _queue.length;

  /// Returns true if the device has an active internet connection.
  Future<bool> hasConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.any((result) =>
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.ethernet
    );
  }

  /// Retries all pending operations using the provided [handler].
  ///
  /// [handler] receives each [SyncOperation] and returns `true` if it
  /// succeeded (so it can be dequeued) or `false` if it failed (so it stays
  /// for the next attempt). The handler is defined in [SupabaseSyncService]
  /// and contains the switch statement that maps each operation type to the
  /// correct Supabase call.
  ///
  /// Returns the number of operations that succeeded.
  ///
  /// This method is a no-op if:
  /// - the queue is empty, or
  /// - a previous call is still running ([_isProcessing] guard), or
  /// - the device has no internet connection.
  Future<int> processQueue(
    Future<bool> Function(SyncOperation operation) handler,
  ) async {
    if (_isProcessing || _queue.isEmpty) return 0;

    if (!await hasConnectivity()) {
      return 0;
    }

    _isProcessing = true;
    int successCount = 0;

    // Iterate over a snapshot of the queue taken at the start of this run.
    // We must not iterate _queue directly because dequeue() mutates it — that
    // would cause a "concurrent modification" error mid-loop.
    final queueCopy = List<SyncOperation>.from(_queue);

    for (final operation in queueCopy) {
      try {
        final success = await handler(operation);
        if (success) {
          // Remove only this specific (id, type) pair so any co-pending
          // operation for the same entity (e.g. a deleteSession that followed
          // a successful uploadSession) is preserved for the next retry.
          await dequeue(operation.id, operation.type);
          successCount++;
        }
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
        // Keep in queue for retry — do not rethrow.
      }
    }

    _isProcessing = false;
    return successCount;
  }

  /// Removes all pending operations and persists the empty queue to disk.
  ///
  /// Use with caution — this permanently discards any unsynced changes.
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
  }
}
