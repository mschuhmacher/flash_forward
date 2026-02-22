import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/data/default_exercise_templates.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise_instance.dart';
import 'package:flash_forward/models/exercise_template.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import '../models/session.dart';
import '../data/default_session_data.dart';

/// Responsibilities:
/// - Holds in-memory state of all presets (sessions, blocks, exercises).
/// - Provides getters for UI and business logic to access presets.
/// - Loads user-added presets from local JSON and merges with defaults.
/// - Allows adding new user presets and persists them to local JSON.
/// - Notifies listeners when presets change.
///
/// Why:
/// This provider manages the app’s active preset data, keeping the UI
/// reactive while separating mutable user data from the immutable defaults.

class PresetProvider extends ChangeNotifier {
  List<Session> _defaultSessions = [];
  List<Workout> _defaultWorkouts = [];
  List<ExerciseTemplate> _defaultExerciseTemplates = [];

  List<Session> _userSessions = [];
  List<Workout> _userWorkouts = [];
  List<ExerciseTemplate> _userExerciseTemplates = [];

  SupabaseSyncService? _syncService;

  List<Session> get presetSessions => [..._defaultSessions, ..._userSessions];
  List<Workout> get presetWorkouts => [..._defaultWorkouts, ..._userWorkouts];
  List<ExerciseTemplate> get presetExerciseTemplates => [
    ..._defaultExerciseTemplates,
    ..._userExerciseTemplates,
  ];
  List<Session> get presetDefaultSessions => _defaultSessions;
  List<Session> get presetUserSessions => _userSessions;

  // Return the IDs of the user-defined workouts and exerciseTemplates
  Set<String> get presetUserWorkoutsIDs =>
      _userWorkouts.map((w) => w.id).toSet();
  Set<String> get presetUserExerciseTemplateIDs =>
      _userExerciseTemplates.map((e) => e.id).toSet();

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
    _defaultExerciseTemplates = List.from(kDefaultExerciseTemplates);

    // If user is logged in, load their cloud data
    if (userId != null) {
      _syncService = SupabaseSyncService(userId: userId);
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
      _userSessions = await _syncService!.fetchUserSessions();
      _userWorkouts = await _syncService!.fetchUserWorkouts();
      _userExerciseTemplates = await _syncService!.fetchUserExercises();
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      await _loadUserPresetDataFromLocal();
    }
  }

  /// Loads user-added presets if they exist
  Future<void> _loadUserPresetDataFromLocal() async {
    _userSessions = (await PresetLogger.readUserPresetSessions()).toList();
    _userWorkouts = (await PresetLogger.readUserPresetWorkouts()).toList();
    _userExerciseTemplates =
        (await PresetLogger.readUserPresetExercises()).toList();
  }

  Future<void> deleteAllUserPresets() async {
    _userSessions = [];
    _userWorkouts = [];
    _userExerciseTemplates = [];

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

  // Remove user added preset session
  Future<void> deleteUserPresetSession(int index) async {
    //TODO: update to use IDs instead of index?
    final sessionToDelete = _userSessions[index];
    _userSessions.removeAt(index);

    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );

    // Delete from cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.deleteSession(sessionToDelete.id);
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
    _userExerciseTemplates.removeWhere((w) => w.id == id);

    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExerciseTemplates,
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

  Future<void> addPresetExercise(ExerciseTemplate exerciseTemplate) async {
    _userExerciseTemplates.add(exerciseTemplate);
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExerciseTemplates,
    );

    // Save to cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.uploadExercise(exerciseTemplate);
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
    _defaultExerciseTemplates = [];
    _userSessions = [];
    _userWorkouts = [];
    _userExerciseTemplates = [];
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

  /// Create an ExerciseInstance from a template
  ExerciseInstance createExerciseInstanceFromTemplate(
    String templateId, {
    int? sets,
    int? reps,
    int? timeBetweenSets,
    int? timePerRep,
    int? timeBetweenReps,
    double? load,
    int? rpe,
  }) {
    final template = presetExerciseTemplates.firstWhere(
      (template) => template.id == templateId,
    );
    return ExerciseInstance.fromTemplate(
      template,
      sets: sets,
      reps: reps,
      timeBetweenSets: timeBetweenSets,
      timePerRep: timePerRep,
      timeBetweenReps: timeBetweenReps,
      load: load,
      rpe: rpe,
    );
  }
}
