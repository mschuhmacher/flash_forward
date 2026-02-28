import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

// Helper function for cleaner code
Workout _findWorkout(String title) {
  return kDefaultWorkouts.firstWhere((e) => e.title == title);
}

final List<Session> kDefaultSessions = [
  Session(
    title: 'Projecting session',
    description: 'Flash tries and projecting',
    date: DateTime.now(),
    label: 'Limit',
    list: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Flash and limit bouldering'),
      _findWorkout('Full-Body Strength Workout'),
    ],
  ),
  Session(
    title: 'Powerendurance training',
    description: 'Powerendurance',
    date: DateTime.now(),
    label: 'Powerendurance',
    list: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Max Pick-ups & Minimum Edge Hangs'),
      _findWorkout('Boulder Pyramid Endurance'),
      _findWorkout('General Upper-body Strength'),
    ],
  ),
  Session(
    title: 'Power',
    description: 'Training power',
    date: DateTime.now(),
    label: 'Power',
    list: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Combined Limit Strength'),
      _findWorkout('Dynamic Climbing Power'),
      _findWorkout('Upper-body Power'),
    ],
  ),
  Session(
    title: 'Volume',
    description: 'Lots of easy climbing',
    date: DateTime.now(),
    label: 'Endurance',
    list: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Route Laps Endurance'),
      _findWorkout('Full-Body Strength Workout'),
    ],
  ),
  Session(
    title: 'Full body strength training',
    description: 'No climbing, just strength and finger training',
    date: DateTime.now(),
    label: 'Strength',
    list: [
      _findWorkout('Strength Training Warm-up'),
      _findWorkout('Handstand Training'),
      _findWorkout('Pull-ups & Pick-ups Set'),
      _findWorkout('Dips and front lever'),
      _findWorkout('Barbell Strength Training'),
    ],
  ),
  Session(
    title: 'Daily fingerboard and stretching',
    description: 'Quick light fingerboard and stretching',
    date: DateTime.now(),
    label: 'Daily maintenance',
    list: [_findWorkout('Daily Mobility & Light Hangs')],
  ),
  Session(
    title: 'Daily evening stretch',
    description: 'Relaxed stretching at the end of the day',
    date: DateTime.now(),
    label: 'Daily maintenance',
    list: [_findWorkout('Evening Stretch & Recovery')],
  ),
  Session(
    title: 'Quick fingerboarding',
    description: 'As you\'re passing the fingerboard ',
    date: DateTime.now(),
    label: 'Daily maintenance',
    list: [_findWorkout('Quick Fingerboarding')],
  ),
  // // TEST - UI LIMIT VERIFICATION SESSION
  // Session(
  //   title: 'UI Test Session - Max Limits',
  //   description: 'Test session with exercises at character limits for UI verification and finetuning purposes',
  //   date: DateTime.now(),
  //   label: 'Test',
  //   list: [_findWorkout('Test Workout Maximum Title Lim')],
  // ),
];
