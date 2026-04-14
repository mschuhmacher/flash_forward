import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

// Helper function for cleaner code
Workout _findWorkout(String title) {
  return kDefaultWorkouts.firstWhere((e) => e.title == title);
}

final List<Session> kDefaultSessions = [
  Session(
    id: 'projecting-session',
    title: 'Projecting session',
    description: 'Flash tries and projecting',
    label: 'Limit',
    workouts: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Flash and limit bouldering'),
      _findWorkout('Full-Body Strength Workout'),
    ],
  ),
  Session(
    id: 'powerendurance-training',
    title: 'Powerendurance training',
    description: 'Powerendurance',
    label: 'Powerendurance',
    workouts: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Max Pick-ups & Min Edge Hangs'),
      _findWorkout('Boulder Pyramid Endurance'),
      _findWorkout('General Upper-body Strength'),
    ],
  ),
  Session(
    id: 'power-session',
    title: 'Power',
    description: 'Training power',
    label: 'Power',
    workouts: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Combined Limit Strength'),
      _findWorkout('Dynamic Climbing Power'),
      _findWorkout('Upper-body Power'),
    ],
  ),
  Session(
    id: 'volume-session',
    title: 'Volume',
    description: 'Lots of easy climbing',
    label: 'Endurance',
    workouts: [
      _findWorkout('Climbing Warm-up'),
      _findWorkout('Route Laps Endurance'),
      _findWorkout('Full-Body Strength Workout'),
    ],
  ),
  Session(
    id: 'full-body-strength-session',
    title: 'Full body strength training',
    description: 'No climbing, just strength and finger training',
    label: 'Strength',
    workouts: [
      _findWorkout('Strength Training Warm-up'),
      _findWorkout('Handstand Training'),
      _findWorkout('Pull-ups & Pick-ups Set'),
      _findWorkout('Dips and front lever'),
      _findWorkout('Barbell Strength Training'),
    ],
  ),
  Session(
    id: 'daily-fingerboard-stretching',
    title: 'Daily fingerboard and stretching',
    description: 'Quick light fingerboard and stretching',
    label: 'Daily maintenance',
    workouts: [_findWorkout('Daily Mobility & Light Hangs')],
  ),
  Session(
    id: 'daily-evening-stretch',
    title: 'Daily evening stretch',
    description: 'Relaxed stretching at the end of the day',
    label: 'Daily maintenance',
    workouts: [_findWorkout('Evening Stretch & Recovery')],
  ),
  Session(
    id: 'quick-fingerboarding-session',
    title: 'Quick fingerboarding',
    description: 'As you\'re passing the fingerboard ',
    label: 'Daily maintenance',
    workouts: [_findWorkout('Quick Fingerboarding')],
  ),
];
