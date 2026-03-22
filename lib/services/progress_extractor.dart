import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/models/session.dart';

enum GradeMetric { climbed, flashed }

/// A single strength data point extracted from a logged session.
typedef StrengthPoint = ({DateTime date, double loadKg, double? bodyWeightKg});

/// A single grade data point extracted from a logged session.
typedef GradePoint = ({DateTime date, GradeEntry grade});

/// A discovered Max exercise (for populating the chart dropdown).
typedef MaxExerciseInfo = ({String templateId, String title});

/// Pure functions for extracting progress data from session logs.
/// No state — safe to call from any widget or provider.
class ProgressExtractor {
  const ProgressExtractor._();

  /// Returns true if [exercise] should be tracked for progress.
  /// Any exercise labeled 'Max' qualifies — including user-created ones.
  static bool isMaxExercise(Exercise exercise) => exercise.label == 'Max';

  /// Returns true if [session] contains at least one Max exercise.
  /// Used to decide whether to show the body weight prompt at completion.
  static bool sessionHasMaxExercise(Session session) => session.workouts
      .any((w) => w.exercises.any(isMaxExercise));

  /// Discovers all distinct Max exercises ever logged across [sessions].
  /// Groups by templateId (falls back to title when templateId is null).
  /// Returns one entry per unique exercise, sorted alphabetically by title.
  static List<MaxExerciseInfo> discoverMaxExercises(List<Session> sessions) {
    final seen = <String, String>{}; // templateId → title
    for (final session in sessions) {
      for (final workout in session.workouts) {
        for (final exercise in workout.exercises) {
          if (!isMaxExercise(exercise)) continue;
          final key = exercise.templateId ?? exercise.title;
          seen.putIfAbsent(key, () => exercise.title);
        }
      }
    }
    final result = seen.entries
        .map((e) => (templateId: e.key, title: e.value))
        .toList();
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  /// Returns all strength data points for the Max exercise identified by
  /// [templateId] across [sessions], sorted ascending by date.
  ///
  /// Loads are normalized to kg: if [Exercise.loadUnit] is 'lbs', the value
  /// is divided by 2.20462 before being returned.
  static List<StrengthPoint> extractLoads(
    List<Session> sessions,
    String templateId,
  ) {
    final points = <StrengthPoint>[];
    for (final session in sessions) {
      if (session.completedAt == null) continue;
      for (final workout in session.workouts) {
        for (final exercise in workout.exercises) {
          if (!isMaxExercise(exercise)) continue;
          final key = exercise.templateId ?? exercise.title;
          if (key != templateId) continue;
          if (exercise.load <= 0) continue;
          final loadKg = _normalizeToKg(exercise.load, exercise.loadUnit);
          points.add((
            date: session.completedAt!,
            loadKg: loadKg,
            bodyWeightKg: session.bodyWeightKg,
          ));
        }
      }
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  /// Returns all grade data points for [metric] across [sessions],
  /// sorted ascending by date.
  static List<GradePoint> extractGrades(
    List<Session> sessions,
    GradeMetric metric,
  ) {
    final points = <GradePoint>[];
    for (final session in sessions) {
      if (session.completedAt == null) continue;
      final grade = metric == GradeMetric.climbed
          ? session.maxGradeClimbed
          : session.maxGradeFlashed;
      if (grade == null) continue;
      points.add((date: session.completedAt!, grade: grade));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  /// Returns body weight data points from sessions where [bodyWeightKg] was
  /// logged, sorted ascending by date.
  static List<({DateTime date, double bodyWeightKg})> extractBodyWeight(
    List<Session> sessions,
  ) {
    final points = <({DateTime date, double bodyWeightKg})>[];
    for (final session in sessions) {
      if (session.completedAt == null) continue;
      if (session.bodyWeightKg == null) continue;
      points.add((
        date: session.completedAt!,
        bodyWeightKg: session.bodyWeightKg!,
      ));
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  /// Scans [sessions] in reverse and returns the most recent non-null
  /// bodyWeightKg. Used to pre-fill the body weight prompt.
  static double? lastKnownBodyWeight(List<Session> sessions) {
    for (final session in sessions.reversed) {
      if (session.bodyWeightKg != null) return session.bodyWeightKg;
    }
    return null;
  }

  /// Converts [load] to kg using [loadUnit].
  static double _normalizeToKg(double load, String? loadUnit) {
    if (loadUnit?.toLowerCase() == 'lbs') return load / 2.20462;
    return load;
  }
}
