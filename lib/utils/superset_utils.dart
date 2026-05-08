import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter/material.dart';

const _kSupersetPalette = [
  Color(0xFF4CAF50), // green
  Color(0xFF2196F3), // blue
  Color(0xFFF44336), // red
  Color(0xFFFF9800), // orange
  Color(0xFF9C27B0), // purple
];

/// Stable color for a superset by its index in `workout.supersets`.
Color supersetColorForIndex(int index) =>
    _kSupersetPalette[index % _kSupersetPalette.length];

/// Stable fallback: derives palette index from the superset id.
Color supersetColor(String supersetId) {
  final hash = supersetId.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7FFFFFFF);
  return _kSupersetPalette[hash % _kSupersetPalette.length];
}

/// Returns the [SupersetConfig] that contains [exerciseId], or null.
SupersetConfig? supersetForExercise(Workout workout, String exerciseId) {
  for (final ss in workout.supersets) {
    if (ss.exerciseIds.contains(exerciseId)) return ss;
  }
  return null;
}

/// True if the exercise at [exerciseIndex] is in a superset AND the next
/// exercise in the workout list is also in the same superset.
/// Relies on the contiguous-block invariant (see [supersetsRemainContiguous]).
bool hasNextInSuperset(Workout workout, int exerciseIndex) {
  if (exerciseIndex + 1 >= workout.exercises.length) return false;
  final currentId = workout.exercises[exerciseIndex].id;
  final nextId = workout.exercises[exerciseIndex + 1].id;
  final ss = supersetForExercise(workout, currentId);
  if (ss == null) return false;
  return ss.exerciseIds.contains(nextId);
}

/// Returns the workout list index of the first exercise that belongs to the
/// same superset as the exercise at [exerciseIndex]. Returns [exerciseIndex]
/// itself if that exercise is not in any superset. Walks backward — relies
/// on the contiguous-block invariant.
int supersetGroupStartIndex(Workout workout, int exerciseIndex) {
  final exercise = workout.exercises[exerciseIndex];
  final ss = supersetForExercise(workout, exercise.id);
  if (ss == null) return exerciseIndex;
  for (var i = exerciseIndex - 1; i >= 0; i--) {
    if (!ss.exerciseIds.contains(workout.exercises[i].id)) return i + 1;
  }
  return 0;
}

/// Returns the effective set count for [exercise] inside [workout]:
/// `superset.supersetSets` if a member of a superset with an override,
/// `exercise.sets` otherwise.
int setsForExerciseInWorkout(Workout workout, Exercise exercise) {
  final ss = supersetForExercise(workout, exercise.id);
  return ss?.supersetSets ?? exercise.sets;
}

/// True if every superset's members are a contiguous block in [exercises].
/// Order *within* the block is not constrained.
bool supersetsRemainContiguous(
  List<Exercise> exercises,
  List<SupersetConfig> supersets,
) {
  for (final ss in supersets) {
    final indices = <int>[];
    for (var i = 0; i < exercises.length; i++) {
      if (ss.exerciseIds.contains(exercises[i].id)) indices.add(i);
    }
    if (indices.isEmpty) continue;
    if (indices.last - indices.first + 1 != indices.length) return false;
  }
  return true;
}

/// Strips [exerciseId] from every superset in [supersets]. Returns a new
/// list with supersets that drop below 2 members removed entirely.
List<SupersetConfig> removeExerciseFromSupersets(
  String exerciseId,
  List<SupersetConfig> supersets,
) {
  final result = <SupersetConfig>[];
  for (final ss in supersets) {
    if (!ss.exerciseIds.contains(exerciseId)) {
      result.add(ss);
      continue;
    }
    final newIds = ss.exerciseIds.where((id) => id != exerciseId).toList();
    if (newIds.length >= 2) {
      result.add(ss.copyWith(exerciseIds: newIds));
    }
  }
  return result;
}
