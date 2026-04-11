import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/data/default_exercises.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:flash_forward/services/sync_queue_service.dart';
import '../models/session.dart';
import '../data/default_session_data.dart';

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

  SupabaseSyncService? _syncService;

  List<Session> get presetSessions => [..._defaultSessions, ..._userSessions];
  List<Workout> get presetWorkouts => [..._defaultWorkouts, ..._userWorkouts];
  List<Exercise> get presetExercises => [..._defaultExercises, ..._userExercises];
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
