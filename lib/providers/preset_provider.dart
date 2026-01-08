import 'package:flutter/foundation.dart';
import 'package:training_schedule_app/data/default_exercise_data.dart';
import 'package:training_schedule_app/data/default_workout_data.dart';
import 'package:training_schedule_app/models/exercise.dart';
import 'package:training_schedule_app/models/workout.dart';
import 'package:training_schedule_app/services/preset_logger.dart';
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

  List<Session> get presetSessions => [..._defaultSessions, ..._userSessions];
  List<Workout> get presetWorkouts => [..._defaultWorkouts, ..._userWorkouts];
  List<Exercise> get presetExercises => [
    ..._defaultExercises,
    ..._userExercises,
  ];
  List<Session> get presetDefaultSessions => _defaultSessions;
  List<Session> get presetUserSessions => _userSessions;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Seed the default data on first app installation
    PresetLogger.seedDefaultData;

    // TODO: change to read the JSONs instead of Dart defined Lists
    // Load defaults
    _defaultSessions = List.from(kDefaultSessions);
    _defaultWorkouts = List.from(kDefaultWorkouts);
    _defaultExercises = List.from(kDefaultExercises);

    // Merge with user presets
    await _loadUserPresetData();

    notifyListeners();
  }

  /// Loads user-added presets if they exist
  Future<void> _loadUserPresetData() async {
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
    notifyListeners();
  }

  // Remove user added preset
  Future<void> deleteUserPresetSession(int index) async {
    _userSessions.removeAt(index);
    await PresetLogger.savePresetToFile(
      'user_preset_sessions.json',
      _userSessions,
    );
    notifyListeners();
  }

  Future<void> addPresetWorkout(Workout workout) async {
    _userWorkouts.add(workout);
    await PresetLogger.savePresetToFile(
      'user_preset_workouts.json',
      _userWorkouts,
    );
    notifyListeners();
  }

  Future<void> addPresetExercise(Exercise exercise) async {
    _userExercises.add(exercise);
    await PresetLogger.savePresetToFile(
      'user_preset_exercises.json',
      _userExercises,
    );
    notifyListeners();
  }
}
