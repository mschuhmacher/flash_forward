import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NewExerciseResult.computeSupersetSetsChange', () {
    test('returns null when exercise is not in a superset', () {
      final v = NewExerciseResult.computeSupersetSetsChange(
        membership: null,
        displayedSets: 5,
        existingSupersetSets: 3,
        exerciseSetsFallback: 4,
      );
      expect(v, isNull);
    });

    test(
        'returns null when displayed sets equal existing supersetSets '
        '(no-op edit)', () {
      final ss = SupersetConfig(
          id: 'ss', exerciseIds: ['a', 'b'], supersetSets: 4);
      final v = NewExerciseResult.computeSupersetSetsChange(
        membership: ss,
        displayedSets: 4,
        existingSupersetSets: 4,
        exerciseSetsFallback: 3,
      );
      expect(v, isNull);
    });

    test(
        'returns the new value when displayed sets differ from existing '
        'supersetSets', () {
      final ss = SupersetConfig(
          id: 'ss', exerciseIds: ['a', 'b'], supersetSets: 4);
      final v = NewExerciseResult.computeSupersetSetsChange(
        membership: ss,
        displayedSets: 5,
        existingSupersetSets: 4,
        exerciseSetsFallback: 3,
      );
      expect(v, 5);
    });

    test(
        'falls back to exercise.sets when existing supersetSets is null '
        '(legacy data)', () {
      final ss = SupersetConfig(id: 'ss', exerciseIds: ['a', 'b']);
      // Displayed equals fallback → no change.
      final unchanged = NewExerciseResult.computeSupersetSetsChange(
        membership: ss,
        displayedSets: 3,
        existingSupersetSets: null,
        exerciseSetsFallback: 3,
      );
      expect(unchanged, isNull);
      // Displayed differs from fallback → change.
      final changed = NewExerciseResult.computeSupersetSetsChange(
        membership: ss,
        displayedSets: 4,
        existingSupersetSets: null,
        exerciseSetsFallback: 3,
      );
      expect(changed, 4);
    });
  });
}
