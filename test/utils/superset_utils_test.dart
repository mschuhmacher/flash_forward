import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _ex(String id, {int sets = 3}) => Exercise(
    id: id, title: id, description: 'd', label: 'l', sets: sets);

SupersetConfig _ss(String id, List<String> exIds,
        {int rest = 10, int? supersetSets}) =>
    SupersetConfig(
        id: id, exerciseIds: exIds, restSeconds: rest, supersetSets: supersetSets);

Workout _workout(List<Exercise> exs, List<SupersetConfig> ss) => Workout(
    title: 'W',
    label: 'l',
    exercises: exs,
    timeBetweenExercises: 120,
    supersets: ss);

void main() {
  group('supersetForExercise', () {
    test('returns null when exercise is not in any superset', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(supersetForExercise(w, 'a'), isNull);
    });

    test('returns config when exercise is in a superset', () {
      final w = _workout([_ex('a'), _ex('b')], [_ss('ss1', ['a', 'b'])]);
      expect(supersetForExercise(w, 'a')?.id, 'ss1');
    });
  });

  group('hasNextInSuperset', () {
    test('returns false for solo exercise', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(hasNextInSuperset(w, 0), isFalse);
    });

    test('returns true for first superset member with next-in-block', () {
      final w = _workout([_ex('a'), _ex('b')], [_ss('ss1', ['a', 'b'])]);
      expect(hasNextInSuperset(w, 0), isTrue);
    });

    test('returns false for last superset member', () {
      final w = _workout([_ex('a'), _ex('b')], [_ss('ss1', ['a', 'b'])]);
      expect(hasNextInSuperset(w, 1), isFalse);
    });
  });

  group('supersetGroupStartIndex', () {
    test('returns same index for solo exercise', () {
      final w = _workout([_ex('a'), _ex('b')], []);
      expect(supersetGroupStartIndex(w, 1), 1);
    });

    test('returns index of first member for last exercise in group', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c')],
          [_ss('ss1', ['a', 'b', 'c'])]);
      expect(supersetGroupStartIndex(w, 2), 0);
    });
  });

  group('setsForExerciseInWorkout', () {
    test('returns exercise.sets for solo exercise', () {
      final w = _workout([_ex('a', sets: 4)], []);
      expect(setsForExerciseInWorkout(w, w.exercises.first), 4);
    });

    test('returns supersetSets when member is in superset with override', () {
      final w = _workout([_ex('a', sets: 3), _ex('b', sets: 4)],
          [_ss('ss1', ['a', 'b'], supersetSets: 5)]);
      expect(setsForExerciseInWorkout(w, w.exercises[0]), 5);
      expect(setsForExerciseInWorkout(w, w.exercises[1]), 5);
    });

    test('falls back to exercise.sets when supersetSets is null', () {
      final w = _workout([_ex('a', sets: 3), _ex('b', sets: 3)],
          [_ss('ss1', ['a', 'b'])]);
      expect(setsForExerciseInWorkout(w, w.exercises[0]), 3);
    });
  });

  group('supersetsRemainContiguous', () {
    test('returns true when no supersets', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c')], []);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns true when all supersets are contiguous', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c'), _ex('d')],
          [_ss('ss1', ['a', 'b']), _ss('ss2', ['c', 'd'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns false when a superset has a gap', () {
      final w = _workout([_ex('a'), _ex('b'), _ex('c')],
          [_ss('ss1', ['a', 'c'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isFalse);
    });

    test('handles within-block reorder (members not in canonical order)', () {
      final w = _workout([_ex('c'), _ex('b'), _ex('a')],
          [_ss('ss1', ['a', 'b', 'c'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });

    test('returns true when a superset references absent exercise ids', () {
      final w = _workout([_ex('a'), _ex('b')],
          [_ss('ss1', ['a', 'ghost'])]);
      expect(supersetsRemainContiguous(w.exercises, w.supersets), isTrue);
    });
  });

  group('removeExerciseFromSupersets', () {
    test('strips id from a superset, preserves others', () {
      final supersets = [_ss('ss1', ['a', 'b', 'c'])];
      final result = removeExerciseFromSupersets('b', supersets);
      expect(result, hasLength(1));
      expect(result.single.exerciseIds, ['a', 'c']);
    });

    test('dissolves superset that drops below 2 members', () {
      final supersets = [_ss('ss1', ['a', 'b'])];
      final result = removeExerciseFromSupersets('b', supersets);
      expect(result, isEmpty);
    });

    test('only modifies supersets that contain the id', () {
      final supersets = [
        _ss('ss1', ['a', 'b']),
        _ss('ss2', ['c', 'd']),
      ];
      final result = removeExerciseFromSupersets('a', supersets);
      // ss1 dissolves (drops to 1), ss2 untouched.
      expect(result, hasLength(1));
      expect(result.single.id, 'ss2');
    });
  });

  group('supersetColor', () {
    test('same id returns same color', () {
      expect(supersetColor('abc'), equals(supersetColor('abc')));
    });
  });

  group('supersetColorForIndex', () {
    test('cycles through palette on overflow', () {
      expect(supersetColorForIndex(0), equals(supersetColorForIndex(5)));
    });
  });
}
