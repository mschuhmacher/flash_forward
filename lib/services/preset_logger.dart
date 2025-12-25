import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:training_schedule_app/_obsolete/obsolete_default_exercise_data.dart';
import 'package:training_schedule_app/data/default_session_data.dart';
import 'package:training_schedule_app/_obsolete/obsolete_default_workout_data.dart';
import 'package:training_schedule_app/models/exercise.dart';
import 'package:training_schedule_app/models/session.dart';
import 'package:training_schedule_app/models/workout.dart';

/// Responsibilities:
/// - Seeds default preset data (sessions, blocks, exercises) to local JSON
///   on first app installation.
/// - Ensures default JSON files exist for the app to read from.
///
/// Why:
/// This class handles the initial setup of immutable default presets,
/// so the app has a consistent source of truth without overwriting user data.

class PresetLogger {
  /// Seed the default data locally upon installation
  /// Finds or creates the local JSON file for the default sessions, workouts, and exercises
  /// WHY DO I SEED THE DATA LOCALLY?
  ///
  static Future<void> seedDefaultData() async {
    final directory = await getApplicationDocumentsDirectory();

    final defaultSessionFile = File('${directory.path}/default_sessions.json');
    final defaultWorkoutFile = File('${directory.path}/default_workouts.json');
    final defaultExerciseFile = File(
      '${directory.path}/default_exercises.json',
    );

    if (!await defaultSessionFile.exists()) {
      await defaultSessionFile.writeAsString(
        jsonEncode(kDefaultSessions.map((e) => e.toJson()).toList()),
      );
    }

    if (!await defaultWorkoutFile.exists()) {
      await defaultWorkoutFile.writeAsString(
        jsonEncode(defaultWorkouts.map((e) => e.toJson()).toList()),
      );
    }

    if (!await defaultExerciseFile.exists()) {
      await defaultExerciseFile.writeAsString(
        jsonEncode(defaultExercises.map((e) => e.toJson()).toList()),
      );
    }
  }

  /// 🔹 Read all preset sessions from file
  static Future<Iterable<Session>> readUserPresetSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final userPresetSessionsFile = File(
        '${dir.path}/user_preset_sessions.json',
      );
      if (!await userPresetSessionsFile.exists()) return [];

      final content = await userPresetSessionsFile.readAsString();
      if (content.isEmpty) return [];
      final data = json.decode(content) as List;
      return data.map((e) => Session.fromJson(e));
    } catch (e) {
      print('Error reading user preset sessions: $e');
      return [];
    }
  }

  static Future<Iterable<Workout>> readUserPresetWorkouts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final userPresetWorkoutsFile = File(
        '${dir.path}/user_preset_workouts.json',
      );
      if (!await userPresetWorkoutsFile.exists()) return [];

      final content = await userPresetWorkoutsFile.readAsString();
      if (content.isEmpty) return [];
      final data = json.decode(content) as List;
      return data.map((e) => Workout.fromJson(e));
    } catch (e) {
      print('Error reading user preset workouts: $e');
      return [];
    }
  }

  static Future<Iterable<Exercise>> readUserPresetExercises() async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final userPresetExercisesFile = File(
        '${dir.path}/user_preset_exercises.json',
      );
      if (!await userPresetExercisesFile.exists()) return [];

      final content = await userPresetExercisesFile.readAsString();
      if (content.isEmpty) return [];
      final data = json.decode(content) as List;
      return data.map((e) => Exercise.fromJson(e));
    } catch (e) {
      print('Error reading user preset exercises: $e');
      return [];
    }
  }

  static Future<void> savePresetToFile(
    String fileName,
    List<dynamic> data,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    final jsonData = data.map((e) => e.toJson()).toList();
    await file.writeAsString(json.encode(jsonData), flush: true);
  }

  static Future<void> deleteAllUserPresetFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    for (var name in [
      'user_preset_sessions.json',
      'user_preset_workouts.json',
      'user_preset_exercises.json',
    ]) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    }
  }
}
