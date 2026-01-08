import 'package:flash_forward/_obsolete/obsolete_workout.dart';
import 'package:flash_forward/_obsolete/obsolete_exercise.dart';
import 'package:flash_forward/models/session.dart';

final List<Session> defaultSessions = [
  Session(
    title: 'Projecting session',
    description: 'Flash tries and projecting',
    date: DateTime.now(),
    label: 'Limit',
    list:
        defaultWorkouts
            .where(
              (w) => [
                'Warm-up',
                'Flashen en projecten',
                'Strength training - full body',
              ].contains(w.title),
            )
            .toList(),
  ),
  Session(
    title: 'Powerendurance training',
    description: 'Powerendurance',
    date: DateTime.now(),
    list:
        defaultWorkouts
            .where(
              (w) => [
                'Warm-up',
                'Fingerboard',
                'Powerendurance',
                'Strength training - basic',
              ].contains(w.title),
            )
            .toList(),
  ),
  Session(
    title: 'Whatever you want',
    description: 'Unstructured climbing',
    date: DateTime.now(),
    list:
        defaultWorkouts
            .where(
              (w) => [
                'Warm-up',
                'Fingerboard',
                'Vrij klimmen',
                'Strength training - back',
              ].contains(w.title),
            )
            .toList(),
  ),
];

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

final List<ExerciseObsolete> defaultExercises = [
  ExerciseObsolete(
    title: 'Hangboard repeaters',
    reps: 3,
    sets: 4,
    timeBetweenSets: 3,
    timeForReps: 7,
    load: 0,
    description: '3x on 20mm and 1x on 14mm',
  ),
  ExerciseObsolete(
    title: 'Pull-ups, push-ups, shoulder rotation',
    reps: 8,
    sets: 2,
    timeBetweenSets: 30,
    timeForReps: 60,
    load: 0,
    description: 'Easy and good form',
  ),
  ExerciseObsolete(
    title: 'Pick-ups',
    reps: 2,
    sets: 5,
    timeBetweenSets: 120,
    timeForReps: 30,
    load: 45,
    description: 'Loading pin, 7 second hold for each arm',
  ),
  ExerciseObsolete(
    title: 'Flash game',
    reps: 2,
    sets: 10,
    timeBetweenSets: 120,
    timeForReps: 60,
    load: 0,
    description: '10 flash climbs, max 2 attempts.',
  ),
  ExerciseObsolete(
    title: 'Projecting',
    reps: 3,
    sets: 2,
    timeBetweenSets: 120,
    timeForReps: 60,
    load: 0,
    description: 'Projecting on 2 climbs. 7B-7C level.',
  ),
  ExerciseObsolete(
    title: 'Kilter pyramids',
    reps: 30,
    sets: 15,
    timeBetweenSets: 180,
    timeForReps: 60,
    load: 0,
    description: '8 routes in increasing difficulty, then in reverse order',
  ),
  ExerciseObsolete(
    title: '4x4',
    reps: 4,
    sets: 4,
    timeBetweenSets: 240,
    timeForReps: 180,
    load: 0,
    description: '4 climbs, each 4 times in a row with 4 minutes rest.',
  ),
  ExerciseObsolete(
    title: 'Vrij klimmen',
    reps: 1,
    sets: 1,
    timeBetweenSets: 0,
    timeForReps: 3600,
    load: 0,
    description: 'Gewoon wat die dag goed voelt',
  ),
  ExerciseObsolete(
    title: 'Handstands',
    reps: 10,
    sets: 3,
    timeBetweenSets: 60,
    timeForReps: 300,
    load: 0,
    description: 'Attempting handstands, against wall and H-stands.',
  ),
  ExerciseObsolete(
    title: 'Superset pullups, toes to bar, hamstring stretches',
    reps: 6,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 120,
    load: 0,
    description: '6 pull-ups, 8 ttb, 90s stretches',
  ),
  ExerciseObsolete(
    title: 'Superset weighted pullups and hamstring stretches',
    reps: 6,
    sets: 4,
    timeBetweenSets: 120,
    timeForReps: 30,
    load: 10,
    description: 'between 4-8 pullups',
  ),
  ExerciseObsolete(
    title: 'Superset windshield wipers and dumb bells press',
    reps: 6,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 90,
    load: 10,
    description: '6 of each',
  ),
  ExerciseObsolete(
    title: 'Superset wall angels and IYT',
    reps: 6,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 60,
    load: 0,
    description: 'with TRX',
  ),
  ExerciseObsolete(
    title: 'Superset weighted pullups and dips',
    reps: 6,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 90,
    load: 10,
    description: '6 of each',
  ),
];
