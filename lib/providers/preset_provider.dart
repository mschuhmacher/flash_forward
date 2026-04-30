import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/data/default_exercises.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:flash_forward/services/sync_queue_service.dart';
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
  static const _keyHiddenDefaultIds = 'pref_hidden_default_ids';
  Set<String> _hiddenDefaultIds = {};

  List<Session> _defaultSessions = [];
  List<Workout> _defaultWorkouts = [];
  List<Exercise> _defaultExercises = [];

  List<Session> _userSessions = [];
  List<Workout> _userWorkouts = [];
  List<Exercise> _userExercises = [];

  SupabaseSyncService? _syncService;

  // Catalog list rule: a user item with the same id as a default SHADOWS that
  // default. Copy-on-edit promotes the default into the user list at the same
  // id, so the default disappears from the catalog automatically.
  List<Session> get presetSessions {
    final userIds = _userSessions.map((s) => s.id).toSet();
    return [
      ..._defaultSessions.where((s) => !userIds.contains(s.id)),
      ..._userSessions,
    ];
  }

  List<Workout> get presetWorkouts {
    final userIds = _userWorkouts.map((w) => w.id).toSet();
    return [
      ..._defaultWorkouts.where((w) => !userIds.contains(w.id)),
      ..._userWorkouts,
    ];
  }

  List<Exercise> get presetExercises {
    final userIds = _userExercises.map((e) => e.id).toSet();
    return [
      ..._defaultExercises.where((e) => !userIds.contains(e.id)),
      ..._userExercises,
    ];
  }
  List<Session> get presetDefaultSessions => _defaultSessions;
  List<Session> get presetUserSessions => _userSessions;

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

    await _loadHiddenDefaultIds();

    // If user is logged in, load their cloud data
    if (userId != null) {
      _syncService = SupabaseSyncService(userId: userId);
      await _syncService!.syncQueue.loadQueue(); // ensure queue loaded before merge
      await _loadUserPresetDataFromCloud();
    } else {
      // Load from local storage (fallback for offline/unauthenticated)
      await _loadUserPresetDataFromLocal();
    }

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

  /// Load user presets from Supabase cloud
  Future<void> _loadUserPresetDataFromCloud() async {
    if (_syncService == null) return;

    try {
      final cloudSessions = await _syncService!.fetchUserSessions();
      final cloudWorkouts = await _syncService!.fetchUserWorkouts();
      final cloudExercises = await _syncService!.fetchUserExercises();
      final pending = _syncService!.syncQueue.pendingOperations;

      _userSessions = mergeWithPendingOps(
        cloudItems: cloudSessions,
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: pending,
      );
      _userWorkouts = mergeWithPendingOps(
        cloudItems: cloudWorkouts,
        getId: (w) => w.id,
        operationType: 'uploadWorkout',
        deleteOperationType: 'deleteWorkout',
        fromJson: Workout.fromJson,
        pendingOps: pending,
      );
      _userExercises = mergeWithPendingOps(
        cloudItems: cloudExercises,
        getId: (e) => e.id,
        operationType: 'uploadExercise',
        deleteOperationType: 'deleteExercise',
        fromJson: Exercise.fromJson,
        pendingOps: pending,
      );
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      await _loadUserPresetDataFromLocal();
    }
  }

  Future<void> _loadHiddenDefaultIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyHiddenDefaultIds) ?? [];
    _hiddenDefaultIds = raw.toSet();
  }

  Future<void> _saveHiddenDefaultIds() async {
    final prefs = await SharedPreferences.getInstance();
    // TODO(sync): sync hiddenDefaultIds to Supabase in a future multi-device release
    await prefs.setStringList(_keyHiddenDefaultIds, _hiddenDefaultIds.toList());
  }

  /// Loads user-added presets if they exist
  Future<void> _loadUserPresetDataFromLocal() async {
    _userSessions = (await PresetLogger.readUserPresetSessions()).toList();
    _userWorkouts = (await PresetLogger.readUserPresetWorkouts()).toList();
    _userExercises = (await PresetLogger.readUserPresetExercises()).toList();
  }

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
    final deletedIds = pendingOps
        .where((op) => op.type == deleteOperationType)
        .map((op) => op.id)
        .toSet();
    final unsynced = pendingOps
        .where((op) =>
            op.type == operationType &&
            !cloudIds.contains(op.id) &&
            !deletedIds.contains(op.id))
        .map((op) => fromJson(op.data));
    final filteredCloud = cloudItems.where((item) => !deletedIds.contains(getId(item))).toList();
    return [...filteredCloud, ...unsynced];
  }

  /// Returns true if [id] belongs to any of the immutable default lists.
  bool isDefaultItem(String id) =>
      _defaultSessions.any((s) => s.id == id) ||
      _defaultWorkouts.any((w) => w.id == id) ||
      _defaultExercises.any((e) => e.id == id);

  /// Returns true if [templateId] points to a default item.
  /// Use to identify user items that are edits of defaults.
  bool isModifiedDefault(String? templateId) {
    if (templateId == null) return false;
    return isDefaultItem(templateId);
  }

  Future<void> hideDefaultItem(String id) async {
    _hiddenDefaultIds.add(id);
    await _saveHiddenDefaultIds();
    notifyListeners();
  }

  /// Clears all hidden defaults AND removes any user items that were created by
  /// editing a default (identified by templateId pointing to a default item).
  ///
  /// Why delete the user copies: if we only un-hid the originals, the user would
  /// see both the restored original and their customized copy in the catalog —
  /// two items with similar names, competing for attention. The UX intent of
  /// "Restore defaults" is "bring me back to a clean slate for default content",
  /// so the customized copies are removed.
  ///
  /// User-created-from-scratch items are NOT affected (templateId is null or points
  /// to another user item, not a default).
  Future<void> restoreAllDefaults() async {
    // Step 1: un-hide originals. This alone makes the catalog show the defaults again.
    _hiddenDefaultIds.clear();
    await _saveHiddenDefaultIds();

    // Step 2: find user items that are "modified defaults" (templateId points to a
    // default item). These were created by the copy-on-edit flow.
    final removedSessionIds = _userSessions
        .where((s) => isModifiedDefault(s.templateId))
        .map((s) => s.id)
        .toList();
    final removedWorkoutIds = _userWorkouts
        .where((w) => isModifiedDefault(w.templateId))
        .map((w) => w.id)
        .toList();
    final removedExerciseIds = _userExercises
        .where((e) => isModifiedDefault(e.templateId))
        .map((e) => e.id)
        .toList();

    // Drop them from in-memory state.
    _userSessions.removeWhere((s) => removedSessionIds.contains(s.id));
    _userWorkouts.removeWhere((w) => removedWorkoutIds.contains(w.id));
    _userExercises.removeWhere((e) => removedExerciseIds.contains(e.id));

    // Persist pruned lists to local JSON (overwrite-in-place).
    await PresetLogger.savePresetToFile('user_preset_sessions.json', _userSessions);
    await PresetLogger.savePresetToFile('user_preset_workouts.json', _userWorkouts);
    await PresetLogger.savePresetToFile('user_preset_exercises.json', _userExercises);

    // Best-effort cloud deletion. We don't block on failures — the sync queue
    // pattern used elsewhere in this file will retry on next connectivity.
    if (_syncService != null) {
      for (final id in removedSessionIds) {
        await _syncService!.deleteSession(id).catchError((_) {});
      }
      for (final id in removedWorkoutIds) {
        await _syncService!.deleteWorkout(id).catchError((_) {});
      }
      for (final id in removedExerciseIds) {
        await _syncService!.deleteExercise(id).catchError((_) {});
      }
    }

    notifyListeners();
  }

  /// Titles of ALL known exercises (defaults + user items), including hidden defaults.
  /// Use only when validating titles during copy-on-edit of a default, so the user
  /// is forced to pick a new title that won't collide with the restored original later.
  List<String> get allKnownExerciseTitles => [
    ..._defaultExercises.map((e) => e.title),
    ..._userExercises.map((e) => e.title),
  ];
  List<String> get allKnownWorkoutTitles => [
    ..._defaultWorkouts.map((w) => w.title),
    ..._userWorkouts.map((w) => w.title),
  ];
  List<String> get allKnownSessionTitles => [
    ..._defaultSessions.map((s) => s.title),
    ..._userSessions.map((s) => s.title),
  ];

  int get userCreatedExerciseCount =>
      _userExercises.where((e) => !isModifiedDefault(e.templateId)).length;
  int get userCreatedWorkoutCount =>
      _userWorkouts.where((w) => !isModifiedDefault(w.templateId)).length;
  int get userCreatedSessionCount =>
      _userSessions.where((s) => !isModifiedDefault(s.templateId)).length;

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

  // Legacy: use promoteAndUpdate* in new code. These methods will be removed
  // once the default-fork cleanup ships and edit screens migrate to
  // commitChanges().
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

  /// Session templates whose workouts list contains [workoutId]
  /// (matched by id or templateId).
  List<Session> usagesOfWorkout(String workoutId) {
    return presetSessions
        .where((s) => s.workouts.any(
              (w) => w.id == workoutId || w.templateId == workoutId,
            ))
        .toList();
  }

  /// Each usage of an exercise is described by which session and which workout
  /// inside that session contain the matching exercise. (Same exercise can
  /// appear in multiple workouts; same workout can appear in multiple sessions.)
  /// Matched by id or templateId.
  List<({Session session, Workout workout})> usagesOfExercise(
      String exerciseId) {
    final result = <({Session session, Workout workout})>[];
    for (final session in presetSessions) {
      for (final workout in session.workouts) {
        final hit = workout.exercises.any(
          (e) => e.id == exerciseId || e.templateId == exerciseId,
        );
        if (hit) {
          result.add((session: session, workout: workout));
        }
      }
    }
    return result;
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside session templates with a fresh deepCopy of [updated], then
  /// persists each affected template. deepCopy ensures each template owns
  /// independent objects (so future edits to one template don't bleed into
  /// another) while preserving the templateId chain back to the catalog.
  Future<void> propagateWorkoutToSessionTemplates(Workout updated) async {
    final affected = usagesOfWorkout(updated.id);
    for (final session in affected) {
      final newWorkouts = session.workouts.map((w) {
        if (w.id == updated.id || w.templateId == updated.id) {
          return updated.deepCopy();
        }
        return w;
      }).toList();
      await updatePresetSession(session.copyWith(workouts: newWorkouts));
    }
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside session-template workouts with a fresh deepCopy of [updated], then
  /// persists each affected template. Each occurrence (even multiple inside the
  /// same workout) gets its own independent deep copy.
  Future<void> propagateExerciseToSessionTemplates(Exercise updated) async {
    final affected =
        usagesOfExercise(updated.id).map((u) => u.session).toSet();
    for (final session in affected) {
      final newWorkouts = session.workouts.map((w) {
        final hasMatch = w.exercises.any(
          (e) => e.id == updated.id || e.templateId == updated.id,
        );
        if (!hasMatch) return w;
        final newExercises = w.exercises.map((e) {
          if (e.id == updated.id || e.templateId == updated.id) {
            return updated.deepCopy();
          }
          return e;
        }).toList();
        return w.copyWith(exercises: newExercises);
      }).toList();
      await updatePresetSession(session.copyWith(workouts: newWorkouts));
    }
  }

  /// Replaces every embedded copy of [updated] (matched by id or templateId)
  /// inside user-list workouts with a fresh deepCopy of [updated], then
  /// persists each affected workout. Why: catalog workouts are not the only
  /// consumer of an exercise — user workouts (whether created from scratch or
  /// promoted from a default) hold their own embedded exercise copies and need
  /// to update too. deepCopy gives each workout an independent instance so
  /// future edits don't cross-contaminate.
  Future<void> propagateExerciseToWorkouts(Exercise updated) async {
    for (final workout in List<Workout>.from(_userWorkouts)) {
      final hasMatch = workout.exercises.any(
        (e) => e.id == updated.id || e.templateId == updated.id,
      );
      if (!hasMatch) continue;
      final newExercises = workout.exercises.map((e) {
        if (e.id == updated.id || e.templateId == updated.id) {
          return updated.deepCopy();
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
    // Promote in dependency order: exercises first, workouts next, session last.
    for (final ec in bag.exercisesById.values) {
      await promoteAndUpdateExercise(ec.exercise);
    }
    for (final wc in bag.workoutsById.values) {
      await promoteAndUpdateWorkout(wc.workout);
    }
    if (bag.session != null) {
      await promoteAndUpdateSession(bag.session!.session);
    }

    // Compute affected consumers AFTER promotion (so usagesOf reflects current state).
    final sessionsByWorkout = <String, List<Session>>{};
    final workoutsByExercise = <String, List<Workout>>{};
    for (final wc in bag.workoutsById.values) {
      final sessions = usagesOfWorkout(wc.workout.id)
          .where((s) => s.id != excludeSessionId)
          .toList();
      if (sessions.isNotEmpty) sessionsByWorkout[wc.workout.id] = sessions;
    }
    for (final ec in bag.exercisesById.values) {
      final workouts = usagesOfExercise(ec.exercise.id)
          .map((u) => u.workout)
          .where((w) => w.id != excludeWorkoutId)
          .toSet() // dedupe: same workout may appear via multiple sessions
          .toList();
      if (workouts.isNotEmpty) workoutsByExercise[ec.exercise.id] = workouts;
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
  Future<void> propagateBag(PendingChangeBag bag) async {
    for (final ec in bag.exercisesById.values) {
      await propagateExerciseToSessionTemplates(ec.exercise);
      await propagateExerciseToWorkouts(ec.exercise);
    }
    for (final wc in bag.workoutsById.values) {
      await propagateWorkoutToSessionTemplates(wc.workout);
    }
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
    _hiddenDefaultIds = {};
    _saveHiddenDefaultIds(); // fire-and-forget: clear persisted hidden IDs on logout
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
