import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/features/session_active/session_progress.dart';
import 'package:flash_forward/features/session_active/session_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Session _fixture() => Session(
      title: 'test',
      label: 'other',
      workouts: [
        Workout(
          title: 'WorkoutTitle',
          label: 'Other',
          exercises: [
            Exercise(
              title: 'ExerciseTitle',
              description: 'TestDescription',
              label: 'Other',
              sets: 2,
              reps: 10,
              timeBetweenSets: 10,
            ),
          ],
          timeBetweenExercises: 100,
        ),
      ],
    );

void main() {
  group('finalizeSession', () {
    test('returns session with telemetry fields populated', () {
      final p = SessionStateProvider()..start(_fixture());
      p.debugSetPhase(TimerPhase.rep);
      final result = p.finalizeSession();
      expect(result.setEvents, isNotNull);
      expect(result.restEvents, isNotNull);
      expect(result.summary, isNotNull);
    });
  });
}
