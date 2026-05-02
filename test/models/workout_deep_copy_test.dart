import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';

void main() {
  Workout sample() => Workout(
        id: 'w-1',
        templateId: null,
        title: 't',
        label: 'l',
        exercises: [
          Exercise(id: 'e-1', title: 'a', description: 'd', label: 'l'),
        ],
        timeBetweenExercises: 60,
      );

  test('deepCopy(): new id, fresh exercises with new ids, templateId chain set', () {
    final src = sample();
    final dst = src.deepCopy();
    expect(dst.id, isNot('w-1'));
    expect(dst.templateId, 'w-1');
    expect(dst.exercises.single.id, isNot('e-1'));
    expect(dst.exercises.single.templateId, 'e-1');
    expect(identical(dst.exercises, src.exercises), isFalse);
  });

  test('deepCopy(keepId: true): same id, fresh exercises with same ids, templateId untouched', () {
    final src = sample();
    final dst = src.deepCopy(keepId: true);
    expect(dst.id, 'w-1');
    expect(dst.templateId, isNull);
    expect(dst.exercises.single.id, 'e-1');
    expect(dst.exercises.single.templateId, isNull);
    expect(identical(dst.exercises, src.exercises), isFalse);
    expect(identical(dst.exercises.single, src.exercises.single), isFalse);
  });
}
