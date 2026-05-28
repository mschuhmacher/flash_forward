import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/preset_sync_merger.dart';
import 'package:flash_forward/services/preset_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class PresetLoader {
  PresetLoader._();

  /// Load user presets from Supabase cloud
  static Future<PresetLoaderResult> loadFromCloud(
    SupabaseSyncService syncService,
  ) async {
    try {
      final cloudSessions = await syncService.fetchUserSessions();
      final cloudWorkouts = await syncService.fetchUserWorkouts();
      final cloudExercises = await syncService.fetchUserExercises();
      final pending = syncService.syncQueue.pendingOperations;

      final userSessions = PresetSyncMerger.mergeWithPendingOps(
        cloudItems: cloudSessions,
        getId: (s) => s.id,
        operationType: 'uploadSession',
        deleteOperationType: 'deleteSession',
        fromJson: Session.fromJson,
        pendingOps: pending,
      );
      final userWorkouts = PresetSyncMerger.mergeWithPendingOps(
        cloudItems: cloudWorkouts,
        getId: (w) => w.id,
        operationType: 'uploadWorkout',
        deleteOperationType: 'deleteWorkout',
        fromJson: Workout.fromJson,
        pendingOps: pending,
      );
      final userExercises = PresetSyncMerger.mergeWithPendingOps(
        cloudItems: cloudExercises,
        getId: (e) => e.id,
        operationType: 'uploadExercise',
        deleteOperationType: 'deleteExercise',
        fromJson: Exercise.fromJson,
        pendingOps: pending,
      );

      return PresetLoaderResult(
        sessions: userSessions,
        workouts: userWorkouts,
        exercises: userExercises,
      );
    } catch (e, stackTrace) {
      Sentry.captureException(e, stackTrace: stackTrace);
      return loadFromLocal();
    }
  }

  /// Loads user-added presets if they exist
  static Future<PresetLoaderResult> loadFromLocal() async {
    final userSessions = (await PresetLogger.readUserPresetSessions()).toList();
    final userWorkouts = (await PresetLogger.readUserPresetWorkouts()).toList();
    final userExercises =
        (await PresetLogger.readUserPresetExercises()).toList();

    return PresetLoaderResult(
      sessions: userSessions,
      workouts: userWorkouts,
      exercises: userExercises,
    );
  }
}

class PresetLoaderResult {
  PresetLoaderResult({
    required this.sessions,
    required this.workouts,
    required this.exercises,
  });

  final List<Session> sessions;
  final List<Workout> workouts;
  final List<Exercise> exercises;
}
