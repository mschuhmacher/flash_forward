import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/catalog_provider.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flash_forward/services/trash_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class TrashProvider extends ChangeNotifier {
  TrashProvider({
    required CatalogProvider catalog,
    required SyncStatusProvider syncStatus,
  }) : _catalog = catalog,
       _syncStatus = syncStatus;

  final CatalogProvider _catalog;
  final SyncStatusProvider _syncStatus;
  final TrashService _trashService = TrashService();

  List<TrashEntry> _trashedItems = [];
  List<TrashEntry> get trashedItems => List.unmodifiable(_trashedItems);

  Set<String> trashedIdsOf(TrashKind kind) {
    return _trashedItems.where((e) => e.kind == kind).map((e) => e.id).toSet();
  }

  @visibleForTesting
  void debugSeedTrash(List<TrashEntry> entries) {
    _trashedItems = List.from(entries);
    notifyListeners();
  }

  /// Purge expired entries (> 90 days) and load the remaining trash from local
  /// storage, then merge with any cloud entries. Cloud entries not yet present
  /// locally are unioned in; conflicts are resolved by latest [deletedAt].
  /// Locally-purged ids are also dropped from the cloud trash table.
  Future<void> loadAndPurge() async {
    final purgedIds = await _trashService.purgeOlderThan(
      const Duration(days: 90),
    );
    _trashedItems = await _trashService.readAll();
    final service = _syncStatus.service;
    if (service == null) return;

    for (final id in purgedIds) {
      try {
        await service.deleteTrashEntry(id);
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }
    try {
      final cloud = await service.fetchUserTrashEntries();
      _trashedItems = PresetSyncMerger.mergeTrashCloudAndLocal(
        _trashedItems,
        cloud,
      );
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
    }

    notifyListeners();
  }

  /// Removes any user-list entries whose id is also in the trash. Older builds
  /// did not delete the cloud user-table row when trashing, so a fresh install
  /// or another device could re-load a stale row that was supposed to be gone.
  /// This drops those rows locally and from the cloud so the catalog matches
  /// the trash filter on disk too, not just at render time.
  Future<void> selfHealCatalogTrashDrift() async {
    final trashedWorkoutIds =
        _trashedItems
            .where((e) => e.kind == TrashKind.workout)
            .map((e) => e.id)
            .toSet();
    final trashedExerciseIds =
        _trashedItems
            .where((e) => e.kind == TrashKind.exercise)
            .map((e) => e.id)
            .toSet();
    final trashedSessionIds =
        _trashedItems
            .where((e) => e.kind == TrashKind.session)
            .map((e) => e.id)
            .toSet();
    final staleSessionIds = _catalog.presetUserSessionIDs.intersection(
      trashedSessionIds,
    );
    final staleWorkoutIds = _catalog.presetUserWorkoutsIDs.intersection(
      trashedWorkoutIds,
    );
    final staleExerciseIds = _catalog.presetUserExerciseIDs.intersection(
      trashedExerciseIds,
    );

    if (staleWorkoutIds.isEmpty &&
        staleExerciseIds.isEmpty &&
        staleSessionIds.isEmpty) {
      return;
    }
    if (staleSessionIds.isNotEmpty) {
      for (final id in staleSessionIds) {
        await _catalog.removeSessionLocal(id);
      }
    }

    if (staleWorkoutIds.isNotEmpty) {
      for (final id in staleWorkoutIds) {
        await _catalog.removeWorkoutLocal(id);
      }
    }
    if (staleExerciseIds.isNotEmpty) {
      for (final id in staleExerciseIds) {
        await _catalog.removeExerciseLocal(id);
      }
    }

    if (_syncStatus.service != null) {
      for (final id in staleWorkoutIds) {
        try {
          await _syncStatus.service!.deleteWorkout(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      for (final id in staleExerciseIds) {
        try {
          await _syncStatus.service!.deleteExercise(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      for (final id in staleSessionIds) {
        try {
          await _syncStatus.service!.deleteSession(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
    }
  }

  /// Moves the item with [id] of the given [kind] to the trash.
  /// The item is removed from the user list (if present) and from the default
  /// shadow. A [TrashEntry] is persisted locally and uploaded to the cloud.
  Future<void> deleteToTrash({
    required String id,
    required TrashKind kind,
  }) async {
    final now = DateTime.now();
    final TrashEntry entry;
    switch (kind) {
      case TrashKind.session:
        final src = _catalog.presetSessions.firstWhere(
          (s) => s.id == id,
          orElse:
              () => throw StateError('deleteToTrash: session $id not found'),
        );
        await _catalog.removeSessionLocal(id);
        entry = TrashEntry.session(session: src, deletedAt: now);
      case TrashKind.workout:
        final src = _catalog.presetWorkouts.firstWhere(
          (w) => w.id == id,
          orElse:
              () => throw StateError('deleteToTrash: workout $id not found'),
        );
        await _catalog.removeWorkoutLocal(id);
        entry = TrashEntry.workout(workout: src, deletedAt: now);
      case TrashKind.exercise:
        final src = _catalog.presetExercises.firstWhere(
          (e) => e.id == id,
          orElse:
              () => throw StateError('deleteToTrash: exercise $id not found'),
        );
        await _catalog.removeExerciseLocal(id);
        entry = TrashEntry.exercise(exercise: src, deletedAt: now);
    }
    _trashedItems.add(entry);
    await _trashService.add(entry);
    final service = _syncStatus.service;
    if (service == null) return;
    try {
      await service.uploadTrashEntry(entry);
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
    }
    try {
      switch (kind) {
        case TrashKind.workout:
          await service.deleteWorkout(id);
        case TrashKind.exercise:
          await service.deleteExercise(id);
        case TrashKind.session:
          await service.deleteSession(id);
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
    }
    notifyListeners();
  }

  /// Restores the trashed item with [id] to the appropriate user list.
  /// If [overrideTitle] is provided, the restored item gets that title instead
  /// of its original one — use after a rename-on-collision dialog.
  /// The caller is responsible for detecting title collisions and prompting the
  /// user before calling this method.
  Future<void> restoreFromTrash(String id, {String? overrideTitle}) async {
    final entry = await _trashService.restore(id);
    if (entry == null) return;
    Workout? restoredWorkout;
    Exercise? restoredExercise;
    Session? restoredSession;
    switch (entry.kind) {
      case TrashKind.session:
        var s = entry.payload as Session;
        if (overrideTitle != null) s = s.copyWith(title: overrideTitle);
        await _catalog.upsertSession(s);
        restoredSession = s;
      case TrashKind.workout:
        var w = entry.payload as Workout;
        if (overrideTitle != null) w = w.copyWith(title: overrideTitle);
        await _catalog.upsertWorkout(w);
        restoredWorkout = w;
      case TrashKind.exercise:
        var e = entry.payload as Exercise;
        if (overrideTitle != null) e = e.copyWith(title: overrideTitle);
        await _catalog.upsertExercise(e);
        restoredExercise = e;
    }
    _trashedItems.removeWhere((e) => e.id == id);

    final service = _syncStatus.service;
    if (service == null) return;
    try {
      await service.deleteTrashEntry(id);
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
    }
    try {
      if (restoredWorkout != null) {
        await service.uploadWorkout(restoredWorkout);
      } else if (restoredExercise != null) {
        await service.uploadExercise(restoredExercise);
      } else if (restoredSession != null) {
        await service.uploadSession(restoredSession);
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
    }

    notifyListeners();
  }

  
// TODO: add in explanatory comment here
  Future<void> refreshAfterSignIn() async {
    if (_syncStatus.service != null) {
      try {
        final cloud = await _syncStatus.service!.fetchUserTrashEntries();
        _trashedItems = PresetSyncMerger.mergeTrashCloudAndLocal(
          _trashedItems,
          cloud,
        );
        notifyListeners();
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }
  }

  void reset() {
    _trashedItems = [];
    notifyListeners();
  }
}
