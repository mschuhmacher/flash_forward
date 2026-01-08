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
      _findWorkout('General Warm-up'),
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
      _findWorkout('General Warm-up'),
      _findWorkout('Fingerboard Strength Builder'),
      _findWorkout('Boulder Pyramid Endurance'),
      _findWorkout('Push & Antagonist Training'),
      _findWorkout('Quick Core Maintenance'),
    ],
  ),
  Session(
    title: 'Power',
    description: 'Training power',
    date: DateTime.now(),
    label: 'Power',
    list: [
      _findWorkout('General Warm-up'),
      _findWorkout('Combined Limit Strength'),
      _findWorkout('Dynamic Climbing Power'),
      _findWorkout('Upper Body Power'),
    ],
  ),
  Session(
    title: 'Full body strength training',
    description: 'No climbing, just strength and finger training',
    date: DateTime.now(),
    label: 'Strength',
    list: [
      _findWorkout('General Warm-up'),
      _findWorkout('Weighted pull-ups, pick-ups, hamstring stretch'),
      _findWorkout('Handstand Progression Training'),
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
];
