import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/session.dart';

void main() {
  Session sample() => Session(
        id: 's-1',
        templateId: null,
        title: 'title',
        label: 'label',
        workouts: [
          Workout(
            id: 'w-1',
            title: 'w',
            label: 'l',
            exercises: [
              Exercise(id: 'e-1', title: 'a', description: 'd', label: 'l'),
            ],
            timeBetweenExercises: 60,
          ),
        ],
      );

  test('deepCopy(): new id, fresh workouts/exercises with new ids, templateId chain set', () {
    final src = sample();
    final dst = src.deepCopy();
    expect(dst.id, isNot('s-1'));
    expect(dst.templateId, 's-1');
    expect(dst.workouts.single.id, isNot('w-1'));
    expect(dst.workouts.single.templateId, 'w-1');
    expect(dst.workouts.single.exercises.single.id, isNot('e-1'));
    expect(identical(dst.workouts, src.workouts), isFalse);
  });

  test('deepCopy(keepId: true): same ids preserved, templateId untouched, lists are fresh', () {
    final src = sample();
    final dst = src.deepCopy(keepId: true);
    expect(dst.id, 's-1');
    expect(dst.templateId, isNull);
    expect(dst.workouts.single.id, 'w-1');
    expect(dst.workouts.single.templateId, isNull);
    expect(dst.workouts.single.exercises.single.id, 'e-1');
    expect(identical(dst.workouts, src.workouts), isFalse);
    expect(identical(dst.workouts.single, src.workouts.single), isFalse);
  });
}
