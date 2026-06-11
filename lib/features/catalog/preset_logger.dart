import 'dart:convert';
import 'dart:io';
import 'package:flash_forward/models/exercise.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

class PresetLogger {
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
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
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
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
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
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
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
