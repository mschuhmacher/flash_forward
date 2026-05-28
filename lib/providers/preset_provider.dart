import 'package:flash_forward/providers/preset_loader.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
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
import 'package:flash_forward/services/sync_queue_service.dart';
import 'package:flash_forward/services/trash_service.dart';
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

  final TrashService _trashService = TrashService();
  List<TrashEntry> _trashedItems = [];

  List<TrashEntry> get trashedItems => List.unmodifiable(_trashedItems);

  SupabaseSyncService? _syncService;

  // Catalog list rule: a user item with the same id as a default SHADOWS that
  // default. Trashed items are hidden from both lists regardless of source.
  List<Session> get presetSessions {
    final userIds = _userSessions.map((s) => s.id).toSet();
    final trashedIds =
        _trashedItems
            .where((e) => e.kind == TrashKind.session)
            .map((e) => e.id)
            .toSet();
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
        _trashedItems
            .where((e) => e.kind == TrashKind.workout)
            .map((e) => e.id)
            .toSet();
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
        _trashedItems
            .where((e) => e.kind == TrashKind.exercise)
            .map((e) => e.id)
            .toSet();
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

  Future<void> init({String? userId}) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _isLoading = true;
    notifyListeners();

    // Load defaults
    _defaultSessions = List.from(kDefaultSessions);
    _defaultWorkouts = List.from(kDefaultWorkouts);
    _defaultExercises = List.from(kDefaultExercises);

    // If user is logged in, load their cloud data
    if (userId != null) {
      _syncService = SupabaseSyncService(userId: userId);
      await _syncService!.syncQueue
          .loadQueue(); // ensure queue loaded before merge
      final loaded = await PresetLoader.loadFromCloud(_syncService!);
      _userSessions = loaded.sessions;
      _userWorkouts = loaded.workouts;
      _userExercises = loaded.exercises;
    } else {
      // Load from local storage (fallback for offline/unauthenticated)
      final local = await PresetLoader.loadFromLocal();
      _userSessions = local.sessions;
      _userWorkouts = local.workouts;
      _userExercises = local.exercises;
    }

    await _loadAndPurgeTrash();
    await _selfHealCatalogTrashDrift();

    _isLoading = false;
    notifyListeners();
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

  /// Seed in-memory trash list directly. Tests use this to set up trash
  /// scenarios without going through init() and disk I/O.
  @visibleForTesting
  void debugSeedTrash(List<TrashEntry> entries) {
    _trashedItems = List.from(entries);
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
    _userSessions.add(session);
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );

    // Save to cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.uploadSession(session);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  Future<void> updatePresetSession(Session session) async {
    final index = _userSessions.indexWhere((s) => s.id == session.id);
    if (index == -1) return;
    _userSessions[index] = session;
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadSession(session);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
  }

  // Remove user added preset session
  Future<void> deleteUserPresetSession(String id) async {
    _userSessions.removeWhere((s) => s.id == id);

    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );

    if (_syncService != null) {
      try {
        await _syncService!.deleteSession(id);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  // Remove user added preset workout
  Future<void> deleteUserPresetWorkout(String id) async {
    _userWorkouts.removeWhere((w) => w.id == id);

    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );

    // Delete from cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.deleteWorkout(id);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  // Remove user added preset exercise
  Future<void> deleteUserPresetExercise(String id) async {
    _userExercises.removeWhere((e) => e.id == id);

    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );

    // Delete from cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.deleteExercise(id);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  Future<void> addPresetWorkout(Workout workout) async {
    _userWorkouts.add(workout);
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
    // Save to cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.uploadWorkout(workout);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  Future<void> updatePresetWorkout(Workout workout) async {
    final index = _userWorkouts.indexWhere((w) => w.id == workout.id);
    if (index == -1) return;
    _userWorkouts[index] = workout;
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadWorkout(workout);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
  }

  Future<void> updatePresetExercise(Exercise exercise) async {
    final index = _userExercises.indexWhere((e) => e.id == exercise.id);
    if (index == -1) return;
    _userExercises[index] = exercise;
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadExercise(exercise);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
  }

  Future<void> addPresetExercise(Exercise exercise) async {
    _userExercises.add(exercise);
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );

    // Save to cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.uploadExercise(exercise);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }

    notifyListeners();
  }

  // Single entry point used by the edit flow: append on first save (promotes a
  // default into the user list at the same id, where it shadows the default),
  // replace in place on subsequent saves. Idempotent on retry.

  Future<void> promoteAndUpdateWorkout(Workout updated) async {
    final i = _userWorkouts.indexWhere((w) => w.id == updated.id);
    if (i == -1) {
      _userWorkouts.add(updated);
    } else {
      _userWorkouts[i] = updated;
    }
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadWorkout(updated);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
  }

  Future<void> promoteAndUpdateExercise(Exercise updated) async {
    final i = _userExercises.indexWhere((e) => e.id == updated.id);
    if (i == -1) {
      _userExercises.add(updated);
    } else {
      _userExercises[i] = updated;
    }
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadExercise(updated);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
  }

  Future<void> promoteAndUpdateSession(Session updated) async {
    final i = _userSessions.indexWhere((s) => s.id == updated.id);
    if (i == -1) {
      _userSessions.add(updated);
    } else {
      _userSessions[i] = updated;
    }
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
    if (_syncService != null) {
      try {
        await _syncService!.uploadSession(updated);
      } catch (e, stackTrace) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
    notifyListeners();
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

  /// Purge expired entries (> 90 days) and load the remaining trash from local
  /// storage, then merge with any cloud entries. Cloud entries not yet present
  /// locally are unioned in; conflicts are resolved by latest [deletedAt].
  /// Locally-purged ids are also dropped from the cloud trash table.
  Future<void> _loadAndPurgeTrash() async {
    final purgedIds = await _trashService.purgeOlderThan(
      const Duration(days: 90),
    );
    _trashedItems = await _trashService.readAll();
    if (_syncService != null) {
      for (final id in purgedIds) {
        try {
          await _syncService!.deleteTrashEntry(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      try {
        final cloud = await _syncService!.fetchUserTrashEntries();
        _trashedItems = PresetSyncMerger.mergeTrashCloudAndLocal(
          _trashedItems,
          cloud,
        );
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }
  }

  /// Removes any user-list entries whose id is also in the trash. Older builds
  /// did not delete the cloud user-table row when trashing, so a fresh install
  /// or another device could re-load a stale row that was supposed to be gone.
  /// This drops those rows locally and from the cloud so the catalog matches
  /// the trash filter on disk too, not just at render time.
  Future<void> _selfHealCatalogTrashDrift() async {
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

    final staleWorkoutIds =
        _userWorkouts
            .where((w) => trashedWorkoutIds.contains(w.id))
            .map((w) => w.id)
            .toList();
    final staleExerciseIds =
        _userExercises
            .where((e) => trashedExerciseIds.contains(e.id))
            .map((e) => e.id)
            .toList();
    final staleSessionIds =
        _userSessions
            .where((s) => trashedSessionIds.contains(s.id))
            .map((s) => s.id)
            .toList();

    if (staleWorkoutIds.isEmpty &&
        staleExerciseIds.isEmpty &&
        staleSessionIds.isEmpty) {
      return;
    }

    if (staleWorkoutIds.isNotEmpty) {
      _userWorkouts.removeWhere((w) => staleWorkoutIds.contains(w.id));
      await PresetLogger.savePresetToFile(
        'user_preset_workouts.json',
        _userWorkouts,
      );
    }
    if (staleExerciseIds.isNotEmpty) {
      _userExercises.removeWhere((e) => staleExerciseIds.contains(e.id));
      await PresetLogger.savePresetToFile(
        'user_preset_exercises.json',
        _userExercises,
      );
    }
    if (staleSessionIds.isNotEmpty) {
      _userSessions.removeWhere((s) => staleSessionIds.contains(s.id));
      await PresetLogger.savePresetToFile(
        'user_preset_sessions.json',
        _userSessions,
      );
    }

    if (_syncService != null) {
      for (final id in staleWorkoutIds) {
        try {
          await _syncService!.deleteWorkout(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      for (final id in staleExerciseIds) {
        try {
          await _syncService!.deleteExercise(id);
        } catch (e, st) {
          Sentry.captureException(e, stackTrace: st);
        }
      }
      for (final id in staleSessionIds) {
        try {
          await _syncService!.deleteSession(id);
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
      case TrashKind.workout:
        final src = presetWorkouts.firstWhere(
          (w) => w.id == id,
          orElse:
              () => throw StateError('deleteToTrash: workout $id not found'),
        );
        _userWorkouts.removeWhere((w) => w.id == id);
        await PresetLogger.savePresetToFile(
          'user_preset_workouts.json',
          _userWorkouts,
        );
        entry = TrashEntry.workout(workout: src, deletedAt: now);
      case TrashKind.exercise:
        final src = presetExercises.firstWhere(
          (e) => e.id == id,
          orElse:
              () => throw StateError('deleteToTrash: exercise $id not found'),
        );
        _userExercises.removeWhere((e) => e.id == id);
        await PresetLogger.savePresetToFile(
          'user_preset_exercises.json',
          _userExercises,
        );
        entry = TrashEntry.exercise(exercise: src, deletedAt: now);
      case TrashKind.session:
        final src = presetSessions.firstWhere(
          (s) => s.id == id,
          orElse:
              () => throw StateError('deleteToTrash: session $id not found'),
        );
        _userSessions.removeWhere((s) => s.id == id);
        await PresetLogger.savePresetToFile(
          'user_preset_sessions.json',
          _userSessions,
        );
        entry = TrashEntry.session(session: src, deletedAt: now);
    }
    _trashedItems.add(entry);
    await _trashService.add(entry);
    if (_syncService != null) {
      try {
        await _syncService!.uploadTrashEntry(entry);
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
      try {
        switch (kind) {
          case TrashKind.workout:
            await _syncService!.deleteWorkout(id);
          case TrashKind.exercise:
            await _syncService!.deleteExercise(id);
          case TrashKind.session:
            await _syncService!.deleteSession(id);
        }
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
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
      case TrashKind.workout:
        var w = entry.payload as Workout;
        if (overrideTitle != null) w = w.copyWith(title: overrideTitle);
        _userWorkouts.removeWhere((x) => x.id == w.id);
        _userWorkouts.add(w);
        await PresetLogger.savePresetToFile(
          'user_preset_workouts.json',
          _userWorkouts,
        );
        restoredWorkout = w;
      case TrashKind.exercise:
        var e = entry.payload as Exercise;
        if (overrideTitle != null) e = e.copyWith(title: overrideTitle);
        _userExercises.removeWhere((x) => x.id == e.id);
        _userExercises.add(e);
        await PresetLogger.savePresetToFile(
          'user_preset_exercises.json',
          _userExercises,
        );
        restoredExercise = e;
      case TrashKind.session:
        var s = entry.payload as Session;
        if (overrideTitle != null) s = s.copyWith(title: overrideTitle);
        _userSessions.removeWhere((x) => x.id == s.id);
        _userSessions.add(s);
        await PresetLogger.savePresetToFile(
          'user_preset_sessions.json',
          _userSessions,
        );
        restoredSession = s;
    }
    _trashedItems.removeWhere((e) => e.id == id);
    if (_syncService != null) {
      try {
        await _syncService!.deleteTrashEntry(id);
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
      try {
        if (restoredWorkout != null) {
          await _syncService!.uploadWorkout(restoredWorkout);
        } else if (restoredExercise != null) {
          await _syncService!.uploadExercise(restoredExercise);
        } else if (restoredSession != null) {
          await _syncService!.uploadSession(restoredSession);
        }
      } catch (e, st) {
        Sentry.captureException(e, stackTrace: st);
      }
    }
    notifyListeners();
  }

  /// Lifts a session-embedded (or otherwise catalog-absent) item into the user
  /// catalog. Purely additive — does not affect any embedded copies in sessions.
  /// If [overrideTitle] is provided, the item is saved under that title.
  /// If [overrideId] is provided, the item is saved under that id (use when the
  /// original id already exists in the catalog).
  Future<void> liftToCatalog({
    required Object item,
    required TrashKind kind,
    String? overrideTitle,
    String? overrideId,
  }) async {
    switch (kind) {
      case TrashKind.workout:
        var w = item as Workout;
        if (overrideTitle != null) w = w.copyWith(title: overrideTitle);
        if (overrideId != null) w = w.copyWith(id: overrideId);
        _userWorkouts.add(w);
        await PresetLogger.savePresetToFile(
          'user_preset_workouts.json',
          _userWorkouts,
        );
        if (_syncService != null) {
          try {
            await _syncService!.uploadWorkout(w);
          } catch (e, st) {
            Sentry.captureException(e, stackTrace: st);
          }
        }
      case TrashKind.exercise:
        var e = item as Exercise;
        if (overrideTitle != null) e = e.copyWith(title: overrideTitle);
        if (overrideId != null) e = e.copyWith(id: overrideId);
        _userExercises.add(e);
        await PresetLogger.savePresetToFile(
          'user_preset_exercises.json',
          _userExercises,
        );
        if (_syncService != null) {
          try {
            await _syncService!.uploadExercise(e);
          } catch (e, st) {
            Sentry.captureException(e, stackTrace: st);
          }
        }
      case TrashKind.session:
        var s = item as Session;
        if (overrideTitle != null) s = s.copyWith(title: overrideTitle);
        if (overrideId != null) s = s.copyWith(id: overrideId);
        _userSessions.add(s);
        await PresetLogger.savePresetToFile(
          'user_preset_sessions.json',
          _userSessions,
        );
        if (_syncService != null) {
          try {
            await _syncService!.uploadSession(s);
          } catch (e, st) {
            Sentry.captureException(e, stackTrace: st);
          }
        }
    }
    notifyListeners();
  }

  /// Reset provider state on logout
  /// This allows re-initialization with a different user
  void reset() {
    _isInitialized = false;
    _isLoading = false;
    _syncService = null;
    _defaultSessions = [];
    _defaultWorkouts = [];
    _defaultExercises = [];
    _userSessions = [];
    _userWorkouts = [];
    _userExercises = [];
    _trashedItems = [];
    notifyListeners();
  }

  /// Check if there are pending sync operations
  bool get hasPendingSync => _syncService?.hasPendingSync ?? false;

  /// Get count of pending sync operations
  int get pendingSyncCount => _syncService?.pendingSyncCount ?? 0;

  /// Process any pending sync operations
  /// Call this when connectivity is restored
  Future<int> processPendingSync() async {
    if (_syncService == null) return 0;
    return await _syncService!.processPendingSync();
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
