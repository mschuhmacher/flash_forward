import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:flutter/foundation.dart';

/// Responsibilities:
/// - A touchpoint for the rest of the app to query the status on sync operations to cloud.
/// - Needs a SupabaseSyncService attached and then provides information on whether there are pending sync and if so how many.
///
/// Why:
/// - centralised SupabaseSyncService instance per user for the whole app.
/// - one place to query its status.
/// - previously each domain provider (PresetProvider, SessionLogProvider) owned
///   its own service instance, which meant duplicated sync queues and ambiguous
///   pending-count totals. Centralising here also lets CatalogProvider and
///   TrashProvider share one service and unblocks the demo-before-signin flow.
///
/// Lifecycle:
/// - Constructed once in MultiProvider at app startup with no service attached.
/// - [attach] called by LoadingScreen / LoginScreen after a successful sign-in,
///   passing a SupabaseSyncService(userId: signedInUserId).
/// - [detach] called by RootScreen on logout — clears the reference so any
///   further reads route to default values rather than the wrong-user service.
///
/// Demo mode:
/// - "No service attached" is a valid, supported state. If [attach] is never
///   called (demo browsing, or pre-sign-in app boot), every getter returns its
///   default: hasPendingSync → false, pendingSyncCount → 0, processPendingSync
///   → 0. No cloud calls are attempted. Domain providers reading
///   `_syncStatus?.service` see null and route through their local-only paths.
class SyncStatusProvider extends ChangeNotifier {
  SupabaseSyncService? _service;

  SupabaseSyncService? get service => _service;

  /// Check if there are pending sync operations
  bool get hasPendingSync => _service?.hasPendingSync ?? false;

  /// Get count of pending sync operations
  int get pendingSyncCount => _service?.pendingSyncCount ?? 0;

  /// Process any pending sync operations
  /// Call this when connectivity is restored
  Future<int> processPendingSync() async {
    if (_service == null) return 0;
    return await _service!.processPendingSync();
  }

  void attach(SupabaseSyncService service) {
    _service = service;
    notifyListeners();
  }

  void detach() {
    _service = null;
    notifyListeners();
  }
}
