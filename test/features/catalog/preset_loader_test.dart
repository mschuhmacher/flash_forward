import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/features/catalog/preset_loader.dart';

void main() {
  test('exposes the three lists provided in the constructor', () {
    final result = PresetLoaderResult(
      sessions: const <Session>[],
      workouts: const <Workout>[],
      exercises: const <Exercise>[],
    );
    expect(result.sessions, isEmpty);
    expect(result.workouts, isEmpty);
    expect(result.exercises, isEmpty);
  });
}
