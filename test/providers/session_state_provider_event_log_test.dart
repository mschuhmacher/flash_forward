import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
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
  group('Event log', () {
    test('pause during setRest splits rest event into three segments', () {
      final p = SessionStateProvider()..start(_fixture());
      p.debugSetPhase(TimerPhase.setRest);
      p.pause();
      p.resume();
      // Force transition out of setRest to close the resumed rest draft.
      p.debugSetPhase(TimerPhase.rep);
      expect(
        p.debugRestEventTypes().sublist(1),
        [RestType.setRest, RestType.paused, RestType.setRest],
      );
    });
  });
}
