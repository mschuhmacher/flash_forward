import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/trash_entry.dart';

Exercise _exercise(String id) => Exercise(
      id: id,
      title: 'Pull-up $id',
      description: 'Hang and pull',
      label: 'Strength',
      sets: 4,
      reps: 8,
    );

Workout _workout(String id) => Workout(
      id: id,
      title: 'Upper Body $id',
      label: 'Strength',
      exercises: [_exercise('ex-$id')],
      timeBetweenExercises: 90,
    );

Session _session(String id) => Session(
      id: id,
      title: 'Morning Session $id',
      label: 'Strength',
      workouts: [_workout('wo-$id')],
    );

void main() {
  final t = DateTime.utc(2026, 4, 28, 12, 30, 45);

  group('TrashEntry.session round-trip', () {
    test('kind, deletedAt, id, title, and nested workout count survive toJson/fromJson', () {
      final s = _session('s1');
      final entry = TrashEntry.session(session: s, deletedAt: t);

      final restored = TrashEntry.fromJson(entry.toJson());

      expect(restored.kind, TrashKind.session);
      expect(restored.deletedAt, t);
      expect(restored.id, s.id);
      expect(restored.title, s.title);

      final restoredSession = restored.payload as Session;
      expect(restoredSession.id, s.id);
      expect(restoredSession.title, s.title);
      expect(restoredSession.workouts.length, s.workouts.length);
    });

    test('id and title getters return correct values without JSON round-trip', () {
      final s = _session('s2');
      final entry = TrashEntry.session(session: s, deletedAt: t);
      expect(entry.id, s.id);
      expect(entry.title, s.title);
    });
  });

  group('TrashEntry.workout round-trip', () {
    test('kind, deletedAt, id, title, and nested exercise count survive toJson/fromJson', () {
      final w = _workout('w1');
      final entry = TrashEntry.workout(workout: w, deletedAt: t);

      final restored = TrashEntry.fromJson(entry.toJson());

      expect(restored.kind, TrashKind.workout);
      expect(restored.deletedAt, t);
      expect(restored.id, w.id);
      expect(restored.title, w.title);

      final restoredWorkout = restored.payload as Workout;
      expect(restoredWorkout.id, w.id);
      expect(restoredWorkout.title, w.title);
      expect(restoredWorkout.exercises.length, w.exercises.length);
    });

    test('id and title getters return correct values without JSON round-trip', () {
      final w = _workout('w2');
      final entry = TrashEntry.workout(workout: w, deletedAt: t);
      expect(entry.id, w.id);
      expect(entry.title, w.title);
    });
  });

  group('TrashEntry.exercise round-trip', () {
    test('kind, deletedAt, id, title, and non-default fields survive toJson/fromJson', () {
      final e = Exercise(
        id: 'ex1',
        title: 'Deadlift',
        description: 'Hip hinge',
        label: 'Strength',
        sets: 5,
        reps: 5,
        load: 100.0,
        loadUnit: 'kg',
      );
      final entry = TrashEntry.exercise(exercise: e, deletedAt: t);

      final restored = TrashEntry.fromJson(entry.toJson());

      expect(restored.kind, TrashKind.exercise);
      expect(restored.deletedAt, t);
      expect(restored.id, e.id);
      expect(restored.title, e.title);

      final restoredExercise = restored.payload as Exercise;
      expect(restoredExercise.id, e.id);
      expect(restoredExercise.title, e.title);
      expect(restoredExercise.load, e.load);
      expect(restoredExercise.loadUnit, e.loadUnit);
    });

    test('id and title getters return correct values without JSON round-trip', () {
      final e = _exercise('ex2');
      final entry = TrashEntry.exercise(exercise: e, deletedAt: t);
      expect(entry.id, e.id);
      expect(entry.title, e.title);
    });
  });
}
