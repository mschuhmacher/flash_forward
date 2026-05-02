import 'package:flutter_test/flutter_test.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/models/pending_change.dart';

Exercise _ex(String id) =>
    Exercise(id: id, title: id, description: '', label: 'l');

Workout _wo(String id) =>
    Workout(id: id, title: id, label: 'l', exercises: [], timeBetweenExercises: 60);

void main() {
  test('isEmpty is true on a fresh bag', () {
    expect(PendingChangeBag().isEmpty, isTrue);
  });

  test('isEmpty is false after adding an exercise', () {
    final bag = PendingChangeBag()..addExercise(_ex('e1'));
    expect(bag.isEmpty, isFalse);
  });

  test('isEmpty is false after adding a workout', () {
    final bag = PendingChangeBag()..addWorkout(_wo('w1'));
    expect(bag.isEmpty, isFalse);
  });

  test('same-id exercise replay overwrites previous entry (last write wins)', () {
    final bag = PendingChangeBag();
    final e1 = _ex('e1');
    final e1b = Exercise(id: 'e1', title: 'updated', description: '', label: 'l');
    bag.addExercise(e1);
    bag.addExercise(e1b);
    expect(bag.exercisesById['e1']!.exercise.title, 'updated');
    expect(bag.exercisesById.length, 1);
  });

  test('same-id workout replay overwrites previous entry', () {
    final bag = PendingChangeBag();
    bag.addWorkout(_wo('w1'));
    final w1b = Workout(id: 'w1', title: 'updated', label: 'l', exercises: [], timeBetweenExercises: 60);
    bag.addWorkout(w1b);
    expect(bag.workoutsById['w1']!.workout.title, 'updated');
    expect(bag.workoutsById.length, 1);
  });

  test('merge: other entries are added and overwrite on id collision', () {
    final a = PendingChangeBag()..addExercise(_ex('e1'))..addWorkout(_wo('w1'));
    final b = PendingChangeBag();
    final e1b = Exercise(id: 'e1', title: 'from-b', description: '', label: 'l');
    b.addExercise(e1b);
    b.addWorkout(_wo('w2'));
    a.merge(b);
    expect(a.exercisesById['e1']!.exercise.title, 'from-b');
    expect(a.workoutsById.containsKey('w1'), isTrue);
    expect(a.workoutsById.containsKey('w2'), isTrue);
  });
}
