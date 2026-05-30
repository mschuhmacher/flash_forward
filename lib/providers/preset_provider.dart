import 'package:flash_forward/providers/preset_loader.dart';
import 'package:flash_forward/providers/sync_status_provider.dart';
import 'package:flash_forward/providers/synced_item_ops.dart';
import 'package:flash_forward/providers/trash_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/data/default_exercises.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import '../models/session.dart';
import '../data/default_session_data.dart';
import '../models/pending_change.dart';

/// Responsibilities:
/// - Holds in-memory state of all presets (sessions, workouts, exercises).
/// - Provides getters for UI and business logic to access presets.
/// - Loads user-added presets from local JSON and merges with defaults.
/// - Allows adding new user presets and persists them to local JSON.
/// - Notifies listeners when presets change.
///
/// Why:
/// This provider manages the app's active preset data, keeping the UI
/// reactive while separating mutable user data from the immutable defaults.

class PresetProvider extends ChangeNotifier {
  List<Session> _defaultSessions = [];
  List<Workout> _defaultWorkouts = [];
  List<Exercise> _defaultExercises = [];

  List<Session> _userSessions = [];
  List<Workout> _userWorkouts = [];
  List<Exercise> _userExercises = [];

  TrashProvider? _trash;

  void attachTrashProvider(TrashProvider trash) {
    _trash = trash;
    // Register notifyListeners from PresetProvider as listener on TrashProvider
    trash.addListener(notifyListeners);
  }

  SyncStatusProvider? _syncStatus;
  void attachSyncStatus(SyncStatusProvider syncStatus) {
    _syncStatus = syncStatus;
  }

  // Catalog list rule: a user item with the same id as a default SHADOWS that
  // default. Trashed items are hidden from both lists regardless of source.
  List<Session> get presetSessions {
    final userIds = _userSessions.map((s) => s.id).toSet();
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.session) ?? const <String>{};
    return [
      ..._defaultSessions.where(
        (s) => !userIds.contains(s.id) && !trashedIds.contains(s.id),
      ),
      ..._userSessions.where((s) => !trashedIds.contains(s.id)),
    ];
  }

  List<Workout> get presetWorkouts {
    final userIds = _userWorkouts.map((w) => w.id).toSet();
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.workout) ?? const <String>{};
    return [
      ..._defaultWorkouts.where(
        (w) => !userIds.contains(w.id) && !trashedIds.contains(w.id),
      ),
      ..._userWorkouts.where((w) => !trashedIds.contains(w.id)),
    ];
  }

  List<Exercise> get presetExercises {
    final userIds = _userExercises.map((e) => e.id).toSet();
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.exercise) ?? const <String>{};
    return [
      ..._defaultExercises.where(
        (e) => !userIds.contains(e.id) && !trashedIds.contains(e.id),
      ),
      ..._userExercises.where((e) => !trashedIds.contains(e.id)),
    ];
  }

  // Return the IDs of the user-defined workouts and exercises
  Set<String> get presetUserWorkoutsIDs =>
      _userWorkouts.map((w) => w.id).toSet();
  Set<String> get presetUserExerciseIDs =>
      _userExercises.map((e) => e.id).toSet();
  Set<String> get presetUserSessionIDs =>
      _userSessions.map((s) => s.id).toSet();

  bool _isInitialized = false;
  bool _isLoading = false;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;

  Future<void> init({TrashProvider? trash}) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _isLoading = true;
    notifyListeners();

    // Load defaults
    _defaultSessions = List.from(kDefaultSessions);
    _defaultWorkouts = List.from(kDefaultWorkouts);
    _defaultExercises = List.from(kDefaultExercises);

    // If user is logged in, load their cloud data
    final service = _syncStatus?.service;
    if (service != null) {
      await service.syncQueue.loadQueue();
      try {
        final loaded = await PresetLoader.loadFromCloud(service);
        _userSessions = loaded.sessions;
        _userWorkouts = loaded.workouts;
        _userExercises = loaded.exercises;
      } catch (e) {
        // Load from local storage (fallback for offline/unauthenticated)
        final local = await PresetLoader.loadFromLocal();
        _userSessions = local.sessions;
        _userWorkouts = local.workouts;
        _userExercises = local.exercises;
      }
    } else {
      // Load from local storage (fallback for offline/unauthenticated)
      final local = await PresetLoader.loadFromLocal();
      _userSessions = local.sessions;
      _userWorkouts = local.workouts;
      _userExercises = local.exercises;
    }

    if (trash != null) {
      await trash.loadAndPurge();
      await trash.selfHealCatalogTrashDrift();
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _trash?.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> refreshAfterSignIn() async {
    final service = _syncStatus?.service;
    if (service == null) return;
    try {
      await service.syncQueue.loadQueue();
      final result = await PresetLoader.loadFromCloud(service);
      _userSessions = result.sessions;
      _userWorkouts = result.workouts;
      _userExercises = result.exercises;
      return;
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Seed in-memory default lists directly. Tests use this to set up shadow /
  /// promotion scenarios without going through init() (which would also touch
  /// SharedPreferences and the real default data).
  @visibleForTesting
  void debugSeedDefaults({
    List<Session> sessions = const [],
    List<Workout> workouts = const [],
    List<Exercise> exercises = const [],
  }) {
    _defaultSessions = List.from(sessions);
    _defaultWorkouts = List.from(workouts);
    _defaultExercises = List.from(exercises);
  }

  Future<void> deleteAllUserPresets() async {
    _userSessions = [];
    _userWorkouts = [];
    _userExercises = [];

    await PresetLogger.deleteAllUserPresetFiles();

    notifyListeners();
  }

  Future<void> deleteAllUserPresetSessions() async {
    _userSessions = [];

    // overwrite old user_preset_sessions.json with new empty list
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );

    notifyListeners();
  }

  // These add/update methods are still used by the _isNew add path in edit
  // screens, by _copyItem in catalog, and by propagation helpers internally.
  // New callers editing existing items should use promoteAndUpdate* instead.
  /// Save new user-added presets
  Future<void> addPresetSession(Session session) async {
    await SyncedItemOps.upsert<Session>(
      list: _userSessions,
      item: session,
      getId: (s) => s.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_sessions.json',
            _userSessions,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (s) => _syncStatus!.service!.uploadSession(s),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );

    notifyListeners();
  }

  Future<void> updatePresetSession(Session session) async {
    await SyncedItemOps.upsert<Session>(
      list: _userSessions,
      item: session,
      getId: (s) => s.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_sessions.json',
            _userSessions,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (s) => _syncStatus!.service!.uploadSession(s),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  // Remove user added preset session
  Future<void> deleteUserPresetSession(String id) async {
    await SyncedItemOps.removeById<Session>(
      list: _userSessions,
      id: id,
      getId: (s) => s.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_sessions.json',
            _userSessions,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : () => _syncStatus!.service!.deleteSession(id),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  // Remove user added preset workout
  Future<void> deleteUserPresetWorkout(String id) async {
    await SyncedItemOps.removeById<Workout>(
      list: _userWorkouts,
      id: id,
      getId: (w) => w.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_workouts.json',
            _userWorkouts,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : () => _syncStatus!.service!.deleteWorkout(id),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  // Remove user added preset exercise
  Future<void> deleteUserPresetExercise(String id) async {
    await SyncedItemOps.removeById<Exercise>(
      list: _userExercises,
      id: id,
      getId: (e) => e.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_exercises.json',
            _userExercises,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : () => _syncStatus!.service!.deleteExercise(id),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> addPresetWorkout(Workout workout) async {
    await SyncedItemOps.upsert<Workout>(
      list: _userWorkouts,
      item: workout,
      getId: (w) => w.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_workouts.json',
            _userWorkouts,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (w) => _syncStatus!.service!.uploadWorkout(w),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> updatePresetWorkout(Workout workout) async {
    await SyncedItemOps.upsert<Workout>(
      list: _userWorkouts,
      item: workout,
      getId: (w) => w.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_workouts.json',
            _userWorkouts,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (w) => _syncStatus!.service!.uploadWorkout(w),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> updatePresetExercise(Exercise exercise) async {
    await SyncedItemOps.upsert<Exercise>(
      list: _userExercises,
      item: exercise,
      getId: (e) => e.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_exercises.json',
            _userExercises,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (e) => _syncStatus!.service!.uploadExercise(e),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> addPresetExercise(Exercise exercise) async {
    await SyncedItemOps.upsert<Exercise>(
      list: _userExercises,
      item: exercise,
      getId: (e) => e.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_exercises.json',
            _userExercises,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (e) => _syncStatus!.service!.uploadExercise(e),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  // Single entry point used by the edit flow: append on first save (promotes a
  // default into the user list at the same id, where it shadows the default),
  // replace in place on subsequent saves. Idempotent on retry.

  Future<void> promoteAndUpdateWorkout(Workout updated) async {
    await SyncedItemOps.upsert<Workout>(
      list: _userWorkouts,
      item: updated,
      getId: (w) => w.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_workouts.json',
            _userWorkouts,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (w) => _syncStatus!.service!.uploadWorkout(w),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> promoteAndUpdateExercise(Exercise updated) async {
    await SyncedItemOps.upsert<Exercise>(
      list: _userExercises,
      item: updated,
      getId: (e) => e.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_exercises.json',
            _userExercises,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (e) => _syncStatus!.service!.uploadExercise(e),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> promoteAndUpdateSession(Session updated) async {
    await SyncedItemOps.upsert<Session>(
      list: _userSessions,
      item: updated,
      getId: (s) => s.id,
      saveLocal:
          () => PresetLogger.savePresetToFile(
            'user_preset_sessions.json',
            _userSessions,
          ),
      cloudOp:
          _syncStatus?.service == null
              ? null
              : (s) => _syncStatus!.service!.uploadSession(s),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  // Temporary wrapper functions for during the refactoring work. deleting these at the end (task 12)
  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> upsertUserSession(Session session) =>
      promoteAndUpdateSession(session);

  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> upsertUserWorkout(Workout workout) =>
      promoteAndUpdateWorkout(workout);

  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> upsertUserExercise(Exercise exercise) =>
      promoteAndUpdateExercise(exercise);

  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> removeUserSessionLocal(String id) async {
    _userSessions.removeWhere((s) => s.id == id);
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
  }

  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> removeUserWorkoutLocal(String id) async {
    _userWorkouts.removeWhere((w) => w.id == id);
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
  }

  /// Used by TrashProvider for restore/lift/heal flows. Not part of the
  /// public catalog API — prefer the existing upsert*/delete* methods.
  Future<void> removeUserExerciseLocal(String id) async {
    _userExercises.removeWhere((e) => e.id == id);
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );
  }

  // ── Propagation: catalog edits → session templates ────────────────────────
  //
  // When a user edits a catalog workout/exercise, embedded copies in session
  // templates do NOT auto-update. The save flow looks these up and offers the
  // user a yes/no prompt to propagate. Matching is by id OR templateId because
  // session templates can hold either: workouts added via AddItemScreen carry
  // the catalog id directly; workouts produced by deepCopy carry the catalog
  // id in templateId.

  /// Sessions whose embedded workouts list contains a workout matching
  /// [workoutId] (by id or templateId), optionally widened to also match by
  /// [alsoMatchTemplateId]. Pass the source workout's `templateId` when the
  /// caller is a session-embedded copy (fresh UUID with a templateId chain
  /// back to the catalog) so sibling embeds linked via the same catalog id
  /// are also returned.
  List<Session> usagesOfWorkout(
    String workoutId, {
    String? alsoMatchTemplateId,
  }) {
    final keys = <String>{workoutId};
    if (alsoMatchTemplateId != null) keys.add(alsoMatchTemplateId);
    return presetSessions
        .where(
          (s) => s.workouts.any(
            (w) => keys.contains(w.id) || keys.contains(w.templateId),
          ),
        )
        .toList();
  }

  /// Each usage of an exercise is described by which session (if any) and
  /// which workout contain the matching exercise. Catalog workouts that
  /// contain the exercise but are not embedded in any session yield a tuple
  /// with `session == null`. Matched by id or templateId. When the caller
  /// is editing an embedded exercise (fresh UUID with a templateId pointing
  /// to the catalog), pass [alsoMatchTemplateId] so sibling embeds linked
  /// via the catalog id are also returned.
  List<({Session? session, Workout workout})> usagesOfExercise(
    String exerciseId, {
    String? alsoMatchTemplateId,
  }) {
    final keys = <String>{exerciseId};
    if (alsoMatchTemplateId != null) keys.add(alsoMatchTemplateId);
    bool workoutContains(Workout w) => w.exercises.any(
      (e) => keys.contains(e.id) || keys.contains(e.templateId),
    );

    final result = <({Session? session, Workout workout})>[];
    final sessionWorkoutIds = <String>{};
    for (final session in presetSessions) {
      for (final workout in session.workouts) {
        if (workoutContains(workout)) {
          result.add((session: session, workout: workout));
          sessionWorkoutIds.add(workout.id);
        }
      }
    }
    // Include catalog workouts that contain the exercise but aren't embedded
    // in any session — otherwise editing an exercise misses standalone
    // catalog consumers.
    for (final workout in presetWorkouts) {
      if (sessionWorkoutIds.contains(workout.id)) continue;
      if (workoutContains(workout)) {
        result.add((session: null, workout: workout));
      }
    }
    return result;
  }

  /// All sessions whose workouts list contains an item with [id]
  /// (matched by id or templateId). Convenience wrapper over [usagesOfWorkout].
  List<Session> sessionsContainingWorkout(String id) => usagesOfWorkout(id);

  /// Deduplicated list of workouts (across all sessions) that contain an
  /// exercise with [id] (matched by id or templateId). Convenience wrapper
  /// over [usagesOfExercise]. Dedupes by workout.id, not object identity —
  /// sessions loaded from JSON produce separate Workout instances for the
  /// same id, so .toSet() on the raw objects fails to collapse them.
  List<Workout> workoutsContainingExercise(String id) {
    final byId = <String, Workout>{};
    for (final u in usagesOfExercise(id)) {
      byId[u.workout.id] = u.workout;
    }
    return byId.values.toList();
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside session templates with a fresh deepCopy(keepId: true) of [updated],
  /// then persists each affected template. The deep copy gives each template
  /// its own independent Dart instance (so future edits to one template don't
  /// bleed into another) while keeping the catalog id intact so subsequent
  /// usagesOfWorkout lookups can find every sibling instance directly.
  Future<void> propagateWorkoutToSessionTemplates(
    Workout updated, {
    Set<String>? onlyToSessionIds,
  }) async {
    final affected =
        usagesOfWorkout(updated.id, alsoMatchTemplateId: updated.templateId)
            .where(
              (s) =>
                  onlyToSessionIds == null || onlyToSessionIds.contains(s.id),
            )
            .toList();
    final matchKeys = <String>{
      updated.id,
      if (updated.templateId != null) updated.templateId!,
    };
    for (final session in affected) {
      final newWorkouts =
          session.workouts.map((w) {
            if (matchKeys.contains(w.id) || matchKeys.contains(w.templateId)) {
              return updated.deepCopy(keepId: true);
            }
            return w;
          }).toList();
      // promoteAndUpdate so default sessions get promoted into _userSessions
      // on first propagation; updatePresetSession would silently no-op for them.
      await promoteAndUpdateSession(session.copyWith(workouts: newWorkouts));
    }
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside session-template workouts with a fresh deepCopy of [updated], then
  /// persists each affected template. Each occurrence (even multiple inside the
  /// same workout) gets its own independent deep copy.
  Future<void> propagateExerciseToSessionTemplates(
    Exercise updated, {
    Set<String>? onlyToSessionIds,
  }) async {
    final affected =
        usagesOfExercise(updated.id, alsoMatchTemplateId: updated.templateId)
            .map((u) => u.session)
            .whereType<Session>()
            .where(
              (s) =>
                  onlyToSessionIds == null || onlyToSessionIds.contains(s.id),
            )
            .toSet();
    final matchKeys = <String>{
      updated.id,
      if (updated.templateId != null) updated.templateId!,
    };
    for (final session in affected) {
      final newWorkouts =
          session.workouts.map((w) {
            final hasMatch = w.exercises.any(
              (e) =>
                  matchKeys.contains(e.id) || matchKeys.contains(e.templateId),
            );
            if (!hasMatch) return w;
            final newExercises =
                w.exercises.map((e) {
                  if (matchKeys.contains(e.id) ||
                      matchKeys.contains(e.templateId)) {
                    return updated.deepCopy(keepId: true);
                  }
                  return e;
                }).toList();
            return w.copyWith(exercises: newExercises);
          }).toList();
      await promoteAndUpdateSession(session.copyWith(workouts: newWorkouts));
    }
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside user-list workouts with a fresh deepCopy of [updated], then
  /// persists each affected workout. Why: catalog workouts are not the only
  /// consumer of an exercise — user workouts (whether created from scratch or
  /// promoted from a default) hold their own embedded exercise copies and need
  /// to update too. deepCopy gives each workout an independent instance so
  /// future edits don't cross-contaminate.
  Future<void> propagateExerciseToWorkouts(
    Exercise updated, {
    Set<String>? onlyToWorkoutIds,
  }) async {
    // Iterates presetWorkouts (the catalog) directly rather than going through
    // usagesOfExercise — this propagation only touches catalog-level workouts
    // that consume the exercise. Session-embedded workout copies are handled
    // separately by propagateExerciseToSessionTemplates.
    final matchKeys = <String>{
      updated.id,
      if (updated.templateId != null) updated.templateId!,
    };
    for (final workout in List<Workout>.from(presetWorkouts)) {
      if (onlyToWorkoutIds != null && !onlyToWorkoutIds.contains(workout.id))
        continue;
      final hasMatch = workout.exercises.any(
        (e) => matchKeys.contains(e.id) || matchKeys.contains(e.templateId),
      );
      if (!hasMatch) continue;
      final newExercises =
          workout.exercises.map((e) {
            if (matchKeys.contains(e.id) || matchKeys.contains(e.templateId)) {
              return updated.deepCopy(keepId: true);
            }
            return e;
          }).toList();
      await promoteAndUpdateWorkout(workout.copyWith(exercises: newExercises));
    }
  }

  /// Single entry point edit screens call to commit a [PendingChangeBag].
  /// Promotes happen in dependency order (exercises → workouts → session) and
  /// the returned [CommitResult] describes other consumers affected, so the
  /// caller can render the combined propagation prompt.
  ///
  /// Suppression rule: if a bagged exercise also lives inside a bagged
  /// workout's exercises list, its `affectedWorkoutsByExerciseId` entry is
  /// suppressed — the exercise change reaches its only relevant consumer (the
  /// parent workout) via the workout's own propagation, so prompting again at
  /// the exercise level would be misleading.
  ///
  /// Partial-failure semantics: if a promote mid-flight throws (e.g. disk or
  /// network failure), some items may already be persisted while others
  /// aren't. There is no automatic rollback; the caller must surface the error
  /// to the user. (Each promoteAndUpdateX is itself best-effort with
  /// Sentry-on-upload-failure; this note covers uncaught exceptions bubbling
  /// up from the local-write step.)
  Future<CommitResult> commitChanges(
    PendingChangeBag bag, {
    String? excludeSessionId,
    String? excludeWorkoutId,
  }) async {
    // When the bag has a session, the bagged workouts and exercises are
    // session-embedded: they live inside the session JSON and are persisted
    // via the session's own promote below. Pushing them into the catalog
    // (_userWorkouts/_userExercises) would create silent duplicates.
    final isSessionScopedCommit = bag.session != null;

    if (!isSessionScopedCommit) {
      // Promote in dependency order: exercises first, workouts next.
      for (final ec in bag.exercisesById.values) {
        await promoteAndUpdateExercise(ec.exercise);
      }
      for (final wc in bag.workoutsById.values) {
        await promoteAndUpdateWorkout(wc.workout);
      }
    }
    if (bag.session != null) {
      await promoteAndUpdateSession(bag.session!.session);
    }

    // Compute affected consumers AFTER promotion (so usagesOf reflects current state).
    final sessionsByWorkout = <String, List<Session>>{};
    final workoutsByExercise = <String, List<Workout>>{};
    for (final wc in bag.workoutsById.values) {
      final sessions =
          usagesOfWorkout(
            wc.workout.id,
            alsoMatchTemplateId: wc.workout.templateId,
          ).where((s) => s.id != excludeSessionId).toList();
      if (sessions.isNotEmpty) sessionsByWorkout[wc.workout.id] = sessions;
    }
    // Suppress exercise-level propagation for exercises that live inside a
    // workout that's also being committed. The user's edit was scoped to that
    // workout context; the exercise change reaches its only relevant consumer
    // (the parent workout) via the workout's own propagation.
    final exerciseIdsInsideBaggedWorkouts = <String>{
      for (final wc in bag.workoutsById.values)
        for (final e in wc.workout.exercises) e.id,
    };
    for (final ec in bag.exercisesById.values) {
      if (exerciseIdsInsideBaggedWorkouts.contains(ec.exercise.id)) continue;
      // Dedupe by workout.id, not object identity — sessions loaded from JSON
      // produce separate Workout instances for the same id, so .toSet() on the
      // raw objects fails to collapse them.
      final byId = <String, Workout>{};
      for (final u in usagesOfExercise(
        ec.exercise.id,
        alsoMatchTemplateId: ec.exercise.templateId,
      )) {
        if (u.workout.id == excludeWorkoutId) continue;
        byId[u.workout.id] = u.workout;
      }
      if (byId.isNotEmpty) {
        workoutsByExercise[ec.exercise.id] = byId.values.toList();
      }
    }
    return CommitResult(
      affectedSessionsByWorkoutId: sessionsByWorkout,
      affectedWorkoutsByExerciseId: workoutsByExercise,
    );
  }

  /// Runs every propagation path implied by the bag. Called when the user
  /// confirms the combined propagation prompt. Exercises propagate into both
  /// session templates and user workouts; workouts propagate into session
  /// templates. Session changes don't propagate (sessions are leaf consumers).
  /// Pass [selection] to honour the per-consumer checkboxes; null means all.
  Future<void> propagateBag(
    PendingChangeBag bag, {
    PropagationSelection? selection,
  }) async {
    // Mirror the suppression in commitChanges: exercises that live inside a
    // bagged workout already reach session templates via the workout's own
    // propagation. Calling propagateExerciseToSessionTemplates separately
    // would ignore the selection filter (no 'exercise-in-sessions' key exists)
    // and overwrite correctly-excluded sessions.
    final exerciseIdsInsideBaggedWorkouts = <String>{
      for (final wc in bag.workoutsById.values)
        for (final e in wc.workout.exercises) e.id,
    };

    for (final ec in bag.exercisesById.values) {
      if (!exerciseIdsInsideBaggedWorkouts.contains(ec.exercise.id)) {
        await propagateExerciseToSessionTemplates(
          ec.exercise,
          onlyToSessionIds: selection?.sessionIdsFor(
            'exercise',
            ec.exercise.id,
          ),
        );
      }
      await propagateExerciseToWorkouts(
        ec.exercise,
        onlyToWorkoutIds: selection?.workoutIdsFor('exercise', ec.exercise.id),
      );
    }
    for (final wc in bag.workoutsById.values) {
      await propagateWorkoutToSessionTemplates(
        wc.workout,
        onlyToSessionIds: selection?.sessionIdsFor('workout', wc.workout.id),
      );
    }
  }

  // ── Trash ─────────────────────────────────────────────────────────────────

  /// Moves the item with [id] of the given [kind] to the trash.
  /// Delegates to the attached [TrashProvider]; an attached provider is
  /// required because trash state lives there.
  Future<void> deleteToTrash({required String id, required TrashKind kind}) =>
      _trash!.deleteToTrash(id: id, kind: kind);

  /// Restores the trashed item with [id] to the appropriate user list.
  /// Delegates to the attached [TrashProvider].
  Future<void> restoreFromTrash(String id, {String? overrideTitle}) =>
      _trash!.restoreFromTrash(id, overrideTitle: overrideTitle);

  /// Lifts a session-embedded (or otherwise catalog-absent) item into the user
  /// catalog. Delegates to the attached [TrashProvider].
  Future<void> liftToCatalog({
    required Object item,
    required TrashKind kind,
    String? overrideTitle,
    String? overrideId,
  }) => _trash!.liftToCatalog(
    item: item,
    kind: kind,
    overrideTitle: overrideTitle,
    overrideId: overrideId,
  );

  /// Reset provider state on logout
  /// This allows re-initialization with a different user
  void reset() {
    _isInitialized = false;
    _isLoading = false;
    _defaultSessions = [];
    _defaultWorkouts = [];
    _defaultExercises = [];
    _userSessions = [];
    _userWorkouts = [];
    _userExercises = [];
    notifyListeners();
  }

}

/// Returned by [PresetProvider.commitChanges] so the edit screen can render a
/// single combined "this also affects …" prompt covering every promoted item.
/// Lists are already filtered by the optional excludes (the workout/session
/// being edited is suppressed from its own consumer list).
class CommitResult {
  CommitResult({
    required this.affectedSessionsByWorkoutId,
    required this.affectedWorkoutsByExerciseId,
  });

  /// Workout id → sessions (other than the one being edited, if any) that use it.
  final Map<String, List<Session>> affectedSessionsByWorkoutId;

  /// Exercise id → workouts (other than the one being edited, if any) that use it.
  final Map<String, List<Workout>> affectedWorkoutsByExerciseId;

  bool get hasAny =>
      affectedSessionsByWorkoutId.values.any((l) => l.isNotEmpty) ||
      affectedWorkoutsByExerciseId.values.any((l) => l.isNotEmpty);
}
