import 'package:flash_forward/_obsolete/obsolete_default_exercise_data.dart';
import 'package:flash_forward/_obsolete/obsolete_workout.dart';

final List<WorkoutObsolete> defaultWorkouts = [
  WorkoutObsolete(
    title: 'Warm-up',
    description: 'Warming up',
    date: DateTime.now(),
    list:
        defaultExercises
            .where(
              (w) => [
                'Hangboard repeaters',
                'Pull-ups, push-ups, shoulder rotation',
              ].contains(w.title),
            )
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Fingerboard',
    description: 'Pickups with loading pin',
    date: DateTime.now(),
    list:
        defaultExercises.where((w) => ['Pick-ups'].contains(w.title)).toList(),
  ),
  WorkoutObsolete(
    title: 'Flashen en projecten',
    description: '10 flash boulder, max 2 pogingen. 2 project boulders',
    date: DateTime.now(),
    list:
        defaultExercises
            .where((w) => ['Flash game', 'Projecting'].contains(w.title))
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Powerendurance',
    description: 'Max 2 pogingen per boulder',
    date: DateTime.now(),
    list:
        defaultExercises
            .where((w) => ['Kilter pyramids', '4x4'].contains(w.title))
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Vrij klimmen',
    description: 'Lekker ongestructureerd',
    date: DateTime.now(),
    list:
        defaultExercises
            .where((w) => ['Vrij klimmen'].contains(w.title))
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Strength training - basic',
    description: 'Handstand and supersets',
    date: DateTime.now(),
    list:
        defaultExercises
            .where(
              (w) => [
                'Handstands',
                'Superset pullups, toes to bar, hamstring stretches',
              ].contains(w.title),
            )
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Strength training - full body',
    description: 'Handstand and full body exercises',
    date: DateTime.now(),
    list:
        defaultExercises
            .where(
              (w) => [
                'Handstands',
                'Superset weighted pullups and dips',
                'Superset windshield wipers and dumb bells press',
              ].contains(w.title),
            )
            .toList(),
  ),
  WorkoutObsolete(
    title: 'Strength training - back',
    description: 'Handstand and back exercises',
    date: DateTime.now(),
    list:
        defaultExercises
            .where(
              (w) => [
                'Handstands',
                'Superset weighted pullups and dips',
                'Superset wall angels and IYT',
              ].contains(w.title),
            )
            .toList(),
  ),
];
