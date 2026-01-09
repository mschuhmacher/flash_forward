import 'package:flash_forward/services/supabase_config.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/exercise.dart';

/// Handles syncing local data with Supabase cloud storage
/// This allows migration from local-only to cloud-backed storage
class SupabaseSyncService {
  final String userId;

  SupabaseSyncService({required this.userId});

  // ========== Session Sync ==========

  /// Upload a session to the cloud
  /// Sessions contain complete nested workout/exercise data as JSON
  Future<void> uploadSession(Session session) async {
    await supabase.from('user_sessions').upsert({
      'id': session.id,
      'user_id': userId,
      'title': session.title,
      'label': session.label,
      'subtitle': session.subtitle,
      'description': session.description,
      'date': session.date?.toIso8601String(),
      'workouts': session.list.map((w) => w.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Fetch all user's sessions from the cloud
  Future<List<Session>> fetchUserSessions() async {
    final response = await supabase
        .from('user_sessions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((json) {
      // Convert workouts JSONB back to Workout objects
      final workoutsList =
          (json['workouts'] as List).map((w) => Workout.fromJson(w)).toList();

      return Session(
        id: json['id'],
        title: json['title'],
        label: json['label'],
        subtitle: json['subtitle'],
        description: json['description'],
        date: json['date'] != null ? DateTime.parse(json['date']) : null,
        list: workoutsList,
        userId: json['user_id'],
      );
    }).toList();
  }

  /// Delete a session from the cloud
  Future<void> deleteSession(String sessionId) async {
    await supabase
        .from('user_sessions')
        .delete()
        .eq('id', sessionId)
        .eq('user_id', userId);
  }

  // ========== Logged Sessions Sync (Workout History) ==========

  /// Log a completed session to workout history
  /// This creates a permanent record separate from the session itself
  Future<void> logCompletedSession(Session session) async {
    await supabase.from('session_logs').insert({
      'user_id': userId,
      'session_id': session.id,
      'completed_at': DateTime.now().toIso8601String(),
      'session_data': session.toJson(),
    });
  }

  /// Fetch workout history (logged sessions) from the cloud
  /// Can filter by date range for calendar views
  Future<List<Session>> fetchLoggedSessions({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Start with the base query (no select yet)
    var query = supabase
        .from('session_logs')
        .select('session_data, completed_at');

    // Apply filters
    query = query.eq('user_id', userId);

    if (startDate != null) {
      query = query.gte('completed_at', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('completed_at', endDate.toIso8601String());
    }

    // Apply ordering and execute
    final response = await query.order('completed_at', ascending: false);

    return (response as List).map((item) {
      final sessionData = item['session_data'] as Map<String, dynamic>;

      // Convert workouts list from JSON
      final workoutsList =
          (sessionData['list'] as List)
              .map((w) => Workout.fromJson(w as Map<String, dynamic>))
              .toList();

      // Create session with completed_at timestamp as the date
      return Session(
        id: sessionData['id'] as String,
        title: sessionData['title'] as String,
        label: sessionData['label'] as String,
        subtitle: sessionData['subtitle'] as String?,
        description: sessionData['description'] as String?,
        date: DateTime.parse(item['completed_at'] as String),
        list: workoutsList,
        userId: sessionData['userId'] as String?,
      );
    }).toList();
  }

  /// Clear all logged sessions (workout history)
  /// Use with caution - this deletes workout history permanently
  Future<void> clearLoggedSessions() async {
    await supabase.from('session_logs').delete().eq('user_id', userId);
  }

  // ========== Workout Presets Sync ==========

  /// Upload a custom workout to user's workout library
  /// Workouts contain complete nested exercise data as JSON
  Future<void> uploadWorkout(Workout workout) async {
    await supabase.from('user_workouts').upsert({
      'id': workout.id,
      'user_id': userId,
      'title': workout.title,
      'label': workout.label,
      'subtitle': workout.subtitle,
      'description': workout.description,
      'difficulty': workout.difficulty,
      'equipment': workout.equipment,
      'time_between_exercises': workout.timeBetweenExercises,
      'exercises': workout.list.map((e) => e.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Fetch all user's custom workouts from the cloud
  Future<List<Workout>> fetchUserWorkouts() async {
    final response = await supabase
        .from('user_workouts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((json) {
      // Convert exercises JSONB back to Exercise objects
      final exercisesList =
          (json['exercises'] as List)
              .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
              .toList();

      return Workout(
        id: json['id'] as String,
        title: json['title'] as String,
        label: json['label'] as String,
        subtitle: json['subtitle'] as String?,
        description: json['description'] as String?,
        difficulty: json['difficulty'] as String?,
        equipment: json['equipment'] as String?,
        timeBetweenExercises: json['time_between_exercises'] as int,
        list: exercisesList,
        userId: json['user_id'] as String,
      );
    }).toList();
  }

  /// Delete a custom workout from user's library
  Future<void> deleteWorkout(String workoutId) async {
    await supabase
        .from('user_workouts')
        .delete()
        .eq('id', workoutId)
        .eq('user_id', userId);
  }

  // ========== Exercise Presets Sync ==========

  /// Upload a custom exercise to user's exercise library
  Future<void> uploadExercise(Exercise exercise) async {
    await supabase.from('user_exercises').upsert({
      'id': exercise.id,
      'user_id': userId,
      'title': exercise.title,
      'label': exercise.label,
      'description': exercise.description,
      'sets': exercise.sets,
      'reps': exercise.reps,
      'time_between_sets': exercise.timeBetweenSets,
      'time_per_rep': exercise.timePerRep,
      'time_between_reps': exercise.timeBetweenReps,
      'load': exercise.load,
      'rpe': exercise.rpe,
      'equipment': exercise.equipment,
      'muscle_groups': exercise.muscleGroups,
      'difficulty': exercise.difficulty,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Fetch all user's custom exercises from the cloud
  Future<List<Exercise>> fetchUserExercises() async {
    final response = await supabase
        .from('user_exercises')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((json) {
      return Exercise(
        id: json['id'] as String,
        title: json['title'] as String,
        label: json['label'] as String,
        description: json['description'] as String?,
        sets: json['sets'] as int,
        reps: json['reps'] as int,
        timeBetweenSets: json['time_between_sets'] as int,
        timePerRep: json['time_per_rep'] as int,
        timeBetweenReps: json['time_between_reps'] as int,
        load: json['load'] as String,
        rpe: json['rpe'] as int?,
        equipment: json['equipment'] as String?,
        muscleGroups: json['muscle_groups'] as String?,
        difficulty: json['difficulty'] as String?,
        userId: json['user_id'] as String,
      );
    }).toList();
  }

  /// Delete a custom exercise from user's library
  Future<void> deleteExercise(String exerciseId) async {
    await supabase
        .from('user_exercises')
        .delete()
        .eq('id', exerciseId)
        .eq('user_id', userId);
  }
}
