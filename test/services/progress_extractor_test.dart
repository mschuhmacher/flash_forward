import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Minimal builders ─────────────────────────────────────────────────────────

Exercise _maxExercise({
  required double load,
  String templateId = 'ex-1',
  String loadUnit = 'kg',
}) => Exercise(
      templateId: templateId,
      title: 'Test Exercise',
      description: '',
      label: 'Max',
      load: load,
      loadUnit: loadUnit,
    );

Workout _workout(List<Exercise> exercises) => Workout(
      title: 'Test Workout',
      label: 'Max',
      exercises: exercises,
      timeBetweenExercises: 0,
    );

Session _session({
  required DateTime completedAt,
  List<Workout>? workouts,
  GradeEntry? maxGradeClimbed,
  double? bodyWeightKg,
}) => Session(
      title: 'Test Session',
      label: 'Other',
      completedAt: completedAt,
      workouts: workouts ?? [],
      maxGradeClimbed: maxGradeClimbed,
      bodyWeightKg: bodyWeightKg,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('extractLoads — deduplication', () {
    test('two sessions same UTC day → one point with higher load', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 9)),
          workouts: [_workout([_maxExercise(load: 50.0)])],
          bodyWeightKg: 70.0,
        ),
        _session(
          completedAt: day.add(const Duration(hours: 18)),
          workouts: [_workout([_maxExercise(load: 55.0)])],
          bodyWeightKg: 71.0,
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 1);
      expect(result.first.loadKg, 55.0);
      // Body weight comes from the session with the winning (higher) load
      expect(result.first.bodyWeightKg, 71.0);
    });

    test('single point: returns exactly one point with date normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14, 37),
          workouts: [_workout([_maxExercise(load: 60.0)])],
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 1);
      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });

    test('sessions on different UTC days → one point per day', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 10),
          workouts: [_workout([_maxExercise(load: 50.0)])],
        ),
        _session(
          completedAt: DateTime.utc(2026, 3, 21, 10),
          workouts: [_workout([_maxExercise(load: 55.0)])],
        ),
      ];

      final result = ProgressExtractor.extractLoads(sessions, 'ex-1');

      expect(result.length, 2);
    });
  });

  group('extractGrades — deduplication', () {
    test('two sessions same UTC day → one point with higher gradeIndex', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 9)),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 7),
        ),
        _session(
          completedAt: day.add(const Duration(hours: 18)),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 8),
        ),
      ];

      final result =
          ProgressExtractor.extractGrades(sessions, GradeMetric.climbed);

      expect(result.length, 1);
      expect(result.first.grade.gradeIndex, 8);
    });

    test('surviving point date is normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14),
          maxGradeClimbed:
              const GradeEntry(system: GradeSystem.vscale, gradeIndex: 6),
        ),
      ];

      final result =
          ProgressExtractor.extractGrades(sessions, GradeMetric.climbed);

      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });
  });

  group('extractBodyWeight — deduplication', () {
    test('two sessions same UTC day → one point with higher body weight', () {
      final day = DateTime.utc(2026, 3, 20);
      final sessions = [
        _session(
          completedAt: day.add(const Duration(hours: 8)),
          bodyWeightKg: 70.5,
        ),
        _session(
          completedAt: day.add(const Duration(hours: 19)),
          bodyWeightKg: 71.0,
        ),
      ];

      final result = ProgressExtractor.extractBodyWeight(sessions);

      expect(result.length, 1);
      expect(result.first.bodyWeightKg, 71.0);
    });

    test('single point: returns exactly one point with date normalized to UTC midnight', () {
      final sessions = [
        _session(
          completedAt: DateTime.utc(2026, 3, 20, 14, 37),
          bodyWeightKg: 70.0,
        ),
      ];

      final result = ProgressExtractor.extractBodyWeight(sessions);

      expect(result.length, 1);
      expect(result.first.date, DateTime.utc(2026, 3, 20));
    });
  });
}
