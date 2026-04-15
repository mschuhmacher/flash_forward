import 'package:flash_forward/data/default_exercises.dart';
import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/data/default_session_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Default data IDs', () {
    test('kDefaultExercises has no duplicate IDs', () {
      final ids = kDefaultExercises.map((e) => e.id).toList();
      expect(ids.toSet().length, equals(ids.length),
          reason: 'Duplicate IDs found in kDefaultExercises');
    });

    test('kDefaultWorkouts has no duplicate IDs', () {
      final ids = kDefaultWorkouts.map((w) => w.id).toList();
      expect(ids.toSet().length, equals(ids.length),
          reason: 'Duplicate IDs found in kDefaultWorkouts');
    });

    test('kDefaultSessions has no duplicate IDs', () {
      final ids = kDefaultSessions.map((s) => s.id).toList();
      expect(ids.toSet().length, equals(ids.length),
          reason: 'Duplicate IDs found in kDefaultSessions');
    });
  });
}
