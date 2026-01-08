import 'package:flash_forward/_obsolete/obsolete_workout.dart';
import 'package:flash_forward/_obsolete/obsolete_exercise.dart';
import 'package:flash_forward/models/session.dart';

// TODO: add weeks to data structure
// Plan >> Week >> Session >> Block >> Exercise
final List<Session> sessionList = [
  Session(
    title: 'Today',
    description: 'First day of training',
    date: DateTime.now(),
    list: blockList,
  ),
  Session(
    title: 'Tomorrow',
    description: 'Second day of training',
    date: DateTime.now(),
    list: blockList2,
  ),
  Session(
    title: 'Third day',
    description: 'Third day of training',
    date: DateTime.now(),
    list: blockList3,
  ),
];

final List<WorkoutObsolete> blockList = [
  WorkoutObsolete(
    title: 'Warm-up',
    description: 'Warm-up',
    date: DateTime.now(),
    list: exerciseList,
  ),
  WorkoutObsolete(
    title: 'Kilterboard',
    description: 'The one with the pretty lights',
    date: DateTime.now(),
    list: exerciseList2,
  ),
  WorkoutObsolete(
    title: 'Strength training',
    description: 'Weights and supersets',
    date: DateTime.now(),
    list: exerciseList3,
  ),
];

final List<WorkoutObsolete> blockList2 = [
  WorkoutObsolete(
    title: 'Warm-up',
    description: 'Warm-up',
    date: DateTime.now(),
    list: exerciseList,
  ),
  WorkoutObsolete(
    title: 'Kilterboard',
    description: 'The one with the pretty lights',
    date: DateTime.now(),
    list: exerciseList4,
  ),
  WorkoutObsolete(
    title: 'Supersets',
    description: 'Weights and supersets',
    date: DateTime.now(),
    list: exerciseList5,
  ),
];

final List<WorkoutObsolete> blockList3 = [
  WorkoutObsolete(
    title: 'Warm-up',
    description: 'Warm-up',
    date: DateTime.now(),
    list: exerciseList,
  ),
  WorkoutObsolete(
    title: 'Kilterboard',
    description: 'The one with the pretty lights',
    date: DateTime.now(),
    list: exerciseList6,
  ),
  WorkoutObsolete(
    title: 'Strength training',
    description: 'Weights and supersets',
    date: DateTime.now(),
    list: exerciseList7,
  ),
];

final List<ExerciseObsolete> exerciseList = [
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
    description: 'Banded pull-ups',
  ),
];

final List<ExerciseObsolete> exerciseList2 = [
  ExerciseObsolete(
    title: 'Board 10',
    reps: 4,
    sets: 10,
    timeBetweenSets: 300,
    timeForReps: 120,
    load: 0,
    description:
        '5 around flash grade, 5 project grade. Max 4 attempts per climb, must attempt all climbs',
  ),
  ExerciseObsolete(
    title: 'Campussing',
    reps: 2,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 60,
    load: 0,
    description: 'Static campussing',
  ),
];

final List<ExerciseObsolete> exerciseList3 = [
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
    title: 'Superset pullups, toes to bar, dips',
    reps: 6,
    sets: 3,
    timeBetweenSets: 120,
    timeForReps: 120,
    load: 0,
    description: '6 pull-ups, 8 ttb, 8 dips',
  ),
];

final List<ExerciseObsolete> exerciseList4 = [
  ExerciseObsolete(
    title: 'Pyramids',
    reps: 30,
    sets: 15,
    timeBetweenSets: 180,
    timeForReps: 60,
    load: 0,
    description: '8 routes in increasing difficulty, then in reverse order',
  ),
];

final List<ExerciseObsolete> exerciseList5 = [
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
];

final List<ExerciseObsolete> exerciseList6 = [
  ExerciseObsolete(
    title: '4x4',
    reps: 4,
    sets: 4,
    timeBetweenSets: 240,
    timeForReps: 180,
    load: 0,
    description: '4x4',
  ),
];

final List<ExerciseObsolete> exerciseList7 = [
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
