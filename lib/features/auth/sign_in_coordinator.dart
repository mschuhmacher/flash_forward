import 'package:flash_forward/core/sync/supabase_sync_service.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/features/auth/guest_mode_store.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SignInCoordinator {
  SignInCoordinator({
    required this.catalogProvider,
    required this.trashProvider,
    required this.sessionLogProvider,
    required this.syncStatusProvider,
    SupabaseSyncService Function(String userId)? serviceFactory,
  }) : _serviceFactory =
           serviceFactory ?? ((userId) => SupabaseSyncService(userId: userId));

  final CatalogProvider catalogProvider;
  final TrashProvider trashProvider;
  final SessionLogProvider sessionLogProvider;
  final SyncStatusProvider syncStatusProvider;
  final SupabaseSyncService Function(String userId) _serviceFactory;

  factory SignInCoordinator.of(BuildContext context) {
    return SignInCoordinator(
      catalogProvider: context.read<CatalogProvider>(),
      trashProvider: context.read<TrashProvider>(),
      sessionLogProvider: context.read<SessionLogProvider>(),
      syncStatusProvider: context.read<SyncStatusProvider>(),
    );
  }

  /// Cold start, already authenticated. Attach a freshly-built service, plug
  /// the catalog into sync-status and trash, init both, then drain any sync
  /// operations queued while offline.
  Future<void> initForUser(String userId) async {
    syncStatusProvider.attach(_serviceFactory(userId));
    catalogProvider.attachSyncStatus(syncStatusProvider);
    catalogProvider.attachTrashProvider(trashProvider);
    await sessionLogProvider.init(userId: userId);
    await catalogProvider.init(trash: trashProvider);

    await sessionLogProvider.processPendingSync();
    await syncStatusProvider.processPendingSync();
  }

  /// Cold start as a guest. Local-only: no service is attached (an unattached
  /// sync-status is the signal providers use to take their local paths), and
  /// there is nothing to sync.
  Future<void> initForGuest() async {
    catalogProvider.attachSyncStatus(syncStatusProvider);
    catalogProvider.attachTrashProvider(trashProvider);
    await sessionLogProvider.init();
    await catalogProvider.init(trash: trashProvider);
  }

  /// Deferred sign-in from the auth wall. Providers are already initialised
  /// (the app has been running as a guest); attach ONE shared service and
  /// upgrade each provider via its refreshAfterSignIn seam, then drain the
  /// queue and clear the guest flag.
  Future<void> onSignedIn(String userId) async {
    final service = _serviceFactory(userId);
    syncStatusProvider.attach(service);
    await catalogProvider.refreshAfterSignIn();
    await trashProvider.refreshAfterSignIn();
    await sessionLogProvider.refreshAfterSignIn(service);

    await sessionLogProvider.processPendingSync();
    await syncStatusProvider.processPendingSync();

    await GuestModeStore.disable();
  }
}
