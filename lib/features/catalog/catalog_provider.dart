import 'package:uuid/uuid.dart';
import 'package:flash_forward/core/uuid.dart';
import 'package:flash_forward/features/catalog/preset_loader.dart';
import 'package:flash_forward/core/sync/sync_status_provider.dart';
import 'package:flash_forward/core/sync/synced_item_ops.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/data/default_exercises.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/features/catalog/preset_logger.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/data/default_session_data.dart';

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

class CatalogProvider extends ChangeNotifier {
  List<Session> _defaultSessions = [];
  List<Workout> _defaultWorkouts = [];
  List<Exercise> _defaultExercises = [];

  List<Session> _userSessions = [];
  List<Workout> _userWorkouts = [];
  List<Exercise> _userExercises = [];

  TrashProvider? _trash;

  void attachTrashProvider(TrashProvider trash) {
    _trash = trash;
    // Forward TrashProvider's notifications through this catalog so listeners
    // of the catalog see trash mutations too (e.g. the merged-list getters
    // re-render when something is moved to trash).
    trash.addListener(notifyListeners);
  }

  SyncStatusProvider? _syncStatus;
  void attachSyncStatus(SyncStatusProvider syncStatus) {
    _syncStatus = syncStatus;
  }

  // Catalog list rule: a user item SHADOWS the default it was forked from,
  // matched by `templateId` (a promoted default keeps templateId = its slug;
  // its own id is a fresh UUID). Deleted defaults stay shadowed by their
  // trashed entry's shadowId. Trashed items are hidden from both lists.
  List<Session> get presetSessions {
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.session) ?? const <String>{};
    final shadowedDefaultIds = <String>{
      ..._userSessions.map((s) => s.templateId ?? s.id),
      ...?_trash?.shadowedDefaultIdsOf(TrashKind.session),
    };
    return [
      ..._defaultSessions.where((s) => !shadowedDefaultIds.contains(s.id)),
      ..._userSessions.where((s) => !trashedIds.contains(s.id)),
    ];
  }

  List<Workout> get presetWorkouts {
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.workout) ?? const <String>{};
    final shadowedDefaultIds = <String>{
      ..._userWorkouts.map((w) => w.templateId ?? w.id),
      ...?_trash?.shadowedDefaultIdsOf(TrashKind.workout),
    };
    return [
      ..._defaultWorkouts.where((w) => !shadowedDefaultIds.contains(w.id)),
      ..._userWorkouts.where((w) => !trashedIds.contains(w.id)),
    ];
  }

  List<Exercise> get presetExercises {
    final trashedIds =
        _trash?.trashedIdsOf(TrashKind.exercise) ?? const <String>{};
    final shadowedDefaultIds = <String>{
      ..._userExercises.map((e) => e.templateId ?? e.id),
      ...?_trash?.shadowedDefaultIdsOf(TrashKind.exercise),
    };
    return [
      ..._defaultExercises.where((e) => !shadowedDefaultIds.contains(e.id)),
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

    // Heal legacy slug-id user items (re-id to UUID + templateId) and drop the
    // matching poison ops before anything tries to sync them.
    await healSlugIdUserItems();
    await service?.syncQueue.dropNonUuidOps();

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
      await healSlugIdUserItems();
      await service.syncQueue.dropNonUuidOps();
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

  /// Seed the in-memory *user* lists directly. Tests use this to set up
  /// override/shadow/heal scenarios without going through init().
  @visibleForTesting
  void debugSeedUserSessions(List<Session> sessions) =>
      _userSessions = List.from(sessions);

  @visibleForTesting
  void debugSeedUserWorkouts(List<Workout> workouts) =>
      _userWorkouts = List.from(workouts);

  @visibleForTesting
  void debugSeedUserExercises(List<Exercise> exercises) =>
      _userExercises = List.from(exercises);

  /// Whether [id] is the id of a stock default (not a user item). Used to
  /// decide whether a promote/delete must fork the item to a UUID first, since
  /// default ids are human-readable slugs that the cloud's uuid columns reject.
  bool isDefaultSessionId(String id) => _defaultSessions.any((s) => s.id == id);
  bool isDefaultWorkoutId(String id) => _defaultWorkouts.any((w) => w.id == id);
  bool isDefaultExerciseId(String id) =>
      _defaultExercises.any((e) => e.id == id);

  Future<void> deleteAllUserPresets() async {
    _userSessions = [];
    _userWorkouts = [];
    _userExercises = [];

    await PresetLogger.deleteAllUserPresetFiles();

    notifyListeners();
  }

  /// Factory reset of the catalog: deletes every user item locally **and** in
  /// the cloud (per-row, so the cloud row is gone and won't re-sync). Removing
  /// the user items also un-shadows the defaults they forked, leaving only
  /// stock defaults. Trash is cleared separately via [TrashProvider.clearAll].
  Future<void> factoryReset() async {
    for (final id in _userSessions.map((s) => s.id).toList()) {
      await deleteSession(id);
    }
    for (final id in _userWorkouts.map((w) => w.id).toList()) {
      await deleteWorkout(id);
    }
    for (final id in _userExercises.map((e) => e.id).toList()) {
      await deleteExercise(id);
    }
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

  // ── CRUD ──────────────────────────────────────────────────────────────────
  //
  // Single canonical operation per kind:
  //   upsertSession / upsertWorkout / upsertExercise — append on first save
  //   (promotes a default into the user list at the same id, where it shadows
  //   the default), replace in place on subsequent saves. Idempotent on retry.
  //   deleteSession / deleteWorkout / deleteExercise — remove from user list +
  //   delete the cloud row.
  //   removeSessionLocal / removeWorkoutLocal / removeExerciseLocal — for
  //   TrashProvider's restore/lift/heal flows. Skip the cloud delete because
  //   the trash entry's upload is what the cloud sees.

  // Fork a stock default into a UUID-bearing user item on first promotion so
  // its slug id never reaches a uuid column. Only the TOP-LEVEL id is replaced
  // — embedded workout/exercise ids live in jsonb (no uuid column) and are
  // stable keys that propagation/trash/templates match on, so they are kept.
  // Idempotent: a re-promote of the same default reuses the existing fork
  // (matched by templateId). Non-default items (already UUIDs) pass through.
  Session _promoteSessionIfDefault(Session s) {
    if (!isDefaultSessionId(s.id)) return s;
    final existing = _userSessions.where((u) => u.templateId == s.id).toList();
    final newId = existing.isEmpty ? const Uuid().v4() : existing.first.id;
    return s.deepCopy(keepId: true).copyWith(id: newId, templateId: s.id);
  }

  Workout _promoteWorkoutIfDefault(Workout w) {
    if (!isDefaultWorkoutId(w.id)) return w;
    final existing = _userWorkouts.where((u) => u.templateId == w.id).toList();
    final newId = existing.isEmpty ? const Uuid().v4() : existing.first.id;
    return w.deepCopy(keepId: true).copyWith(id: newId, templateId: w.id);
  }

  Exercise _promoteExerciseIfDefault(Exercise e) {
    if (!isDefaultExerciseId(e.id)) return e;
    final existing = _userExercises.where((u) => u.templateId == e.id).toList();
    final newId = existing.isEmpty ? const Uuid().v4() : existing.first.id;
    return e.deepCopy(keepId: true).copyWith(id: newId, templateId: e.id);
  }

  /// One-time load heal: re-id any user item whose id is a non-uuid slug (a
  /// customized default from before fork-on-promote, whose cloud upload always
  /// failed) to a fresh UUID + templateId = old slug, so it can finally sync.
  /// Idempotent — uuid-id items are left untouched.
  Future<void> healSlugIdUserItems() async {
    var changed = false;
    for (var i = 0; i < _userSessions.length; i++) {
      final s = _userSessions[i];
      if (isUuid(s.id)) continue;
      _userSessions[i] = s
          .deepCopy(keepId: true)
          .copyWith(id: const Uuid().v4(), templateId: s.templateId ?? s.id);
      changed = true;
    }
    for (var i = 0; i < _userWorkouts.length; i++) {
      final w = _userWorkouts[i];
      if (isUuid(w.id)) continue;
      _userWorkouts[i] = w
          .deepCopy(keepId: true)
          .copyWith(id: const Uuid().v4(), templateId: w.templateId ?? w.id);
      changed = true;
    }
    for (var i = 0; i < _userExercises.length; i++) {
      final e = _userExercises[i];
      if (isUuid(e.id)) continue;
      _userExercises[i] = e
          .deepCopy(keepId: true)
          .copyWith(id: const Uuid().v4(), templateId: e.templateId ?? e.id);
      changed = true;
    }
    if (!changed) return;
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );
    notifyListeners();
  }

  Future<void> upsertSession(Session session) async {
    final item = _promoteSessionIfDefault(session);
    await SyncedItemOps.upsert<Session>(
      list: _userSessions,
      item: item,
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

  Future<void> upsertWorkout(Workout workout) async {
    final item = _promoteWorkoutIfDefault(workout);
    await SyncedItemOps.upsert<Workout>(
      list: _userWorkouts,
      item: item,
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

  Future<void> upsertExercise(Exercise exercise) async {
    final item = _promoteExerciseIfDefault(exercise);
    await SyncedItemOps.upsert<Exercise>(
      list: _userExercises,
      item: item,
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

  Future<void> deleteSession(String id) async {
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
              : () => _syncStatus!.service!.deleteUserSession(id),
      onCloudError:
          (e, stackTrace) => Sentry.captureException(e, stackTrace: stackTrace),
    );
    notifyListeners();
  }

  Future<void> deleteWorkout(String id) async {
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

  Future<void> deleteExercise(String id) async {
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

  /// Used by TrashProvider for restore/lift/heal flows. Removes the entry
  /// locally without uploading a cloud delete — the trash entry's upload is
  /// what the cloud sees.
  Future<void> removeSessionLocal(String id) async {
    _userSessions.removeWhere((s) => s.id == id);
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
  }

  /// Used by TrashProvider for restore/lift/heal flows. See [removeSessionLocal].
  Future<void> removeWorkoutLocal(String id) async {
    _userWorkouts.removeWhere((w) => w.id == id);
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
  }

  /// Used by TrashProvider for restore/lift/heal flows. See [removeSessionLocal].
  Future<void> removeExerciseLocal(String id) async {
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
      // upsertSession promotes default sessions into _userSessions on first
      // propagation; a no-op-on-missing-id update would silently skip them.
      await upsertSession(session.copyWith(workouts: newWorkouts));
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
      await upsertSession(session.copyWith(workouts: newWorkouts));
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
      await upsertWorkout(workout.copyWith(exercises: newExercises));
    }
  }

  /// Reset provider state on logout
  /// This allows re-initialization with a different user
  Future<void> reset() async {
    _isInitialized = false;
    _isLoading = false;
    _defaultSessions = [];
    _defaultWorkouts = [];
    _defaultExercises = [];
    _userSessions = [];
    _userWorkouts = [];
    _userExercises = [];

    await PresetLogger.deleteAllUserPresetFiles();
    notifyListeners();
  }
}
