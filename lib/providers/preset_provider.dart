import 'package:flutter/foundation.dart';
import 'package:flash_forward/data/default_exercise_data.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/exercise.dart';
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
  List<Exercise> _defaultExercises = [];

  List<Session> _userSessions = [];
  List<Workout> _userWorkouts = [];
  List<Exercise> _userExercises = [];

  SupabaseSyncService? _syncService;

  List<Session> get presetSessions => [..._defaultSessions, ..._userSessions];
  List<Workout> get presetWorkouts => [..._defaultWorkouts, ..._userWorkouts];
  List<Exercise> get presetExercises => [
    ..._defaultExercises,
    ..._userExercises,
  ];
  List<Session> get presetDefaultSessions => _defaultSessions;
  List<Session> get presetUserSessions => _userSessions;

  bool _isInitialized = false;

  Future<void> init({String? userId}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Seed the default data on first app installation
    await PresetLogger.seedDefaultData();

    // TODO: change to read the JSONs instead of Dart defined Lists
    // Load defaults
    _defaultSessions = List.from(kDefaultSessions);
    _defaultWorkouts = List.from(kDefaultWorkouts);
    _defaultExercises = List.from(kDefaultExercises);

    // If user is logged in, load their cloud data
    if (userId != null) {
      _syncService = SupabaseSyncService(userId: userId);
      await _loadUserPresetDataFromCloud();
    } else {
      // Load from local storage (fallback for offline/unauthenticated)
      await _loadUserPresetDataFromLocal();
    }

    notifyListeners();
  }

  /// Load user presets from Supabase cloud
  Future<void> _loadUserPresetDataFromCloud() async {
    if (_syncService == null) return;

    try {
      _userSessions = await _syncService!.fetchUserSessions();
      _userWorkouts = await _syncService!.fetchUserWorkouts();
      _userExercises = await _syncService!.fetchUserExercises();
    } catch (e) {
      print('Error loading from cloud, falling back to local: $e');
      await _loadUserPresetDataFromLocal();
    }
  }

  /// Loads user-added presets if they exist
  Future<void> _loadUserPresetDataFromLocal() async {
    _userSessions = (await PresetLogger.readUserPresetSessions()).toList();
    _userWorkouts = (await PresetLogger.readUserPresetWorkouts()).toList();
    _userExercises = (await PresetLogger.readUserPresetExercises()).toList();
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
      } catch (e) {
        print('Error uploading session to cloud: $e');
      }
    }

    notifyListeners();
  }

  // Remove user added preset
  Future<void> deleteUserPresetSession(int index) async {
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
      } catch (e) {
        print('Error deleting session from cloud: $e');
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
      } catch (e) {
        print('Error uploading workout to cloud: $e');
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
      } catch (e) {
        print('Error uploading exercise to cloud: $e');
      }
    }

    notifyListeners();
  }

  /// Reset provider state on logout
  /// This allows re-initialization with a different user
  void reset() {
    _isInitialized = false;
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
