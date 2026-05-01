import 'package:flash_forward/data/default_workout_data.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

// Helper function for cleaner code
Workout _findWorkout(String id) {
  return kDefaultWorkouts.firstWhere((w) => w.id == id);
}

// IMPORTANT: IDs are stable keys. The user list shadows the default list by id
// when an item is promoted on edit, so changing an existing id: value after it
// ships would orphan a user's promoted copy. When adding a new session, pick a
// unique kebab-case ID.
final List<Session> kDefaultSessions = [
  Session(
    id: 'projecting-session',
    title: 'Projecting session',
    description: 'Flash tries and projecting',
    label: 'Limit',
    workouts: [
      _findWorkout('climbing-warm-up'),
      _findWorkout('flash-and-limit-bouldering'),
      _findWorkout('full-body-strength-workout'),
    ],
  ),
  Session(
    id: 'powerendurance-training',
    title: 'Powerendurance training',
    description: 'Powerendurance',
    label: 'Powerendurance',
    workouts: [
      _findWorkout('climbing-warm-up'),
      _findWorkout('max-pick-ups-and-min-edge-hangs'),
      _findWorkout('boulder-pyramid-endurance'),
      _findWorkout('general-upper-body-strength'),
    ],
  ),
  Session(
    id: 'power-session',
    title: 'Power',
    description: 'Training power',
    label: 'Power',
    workouts: [
      _findWorkout('climbing-warm-up'),
      _findWorkout('combined-limit-strength'),
      _findWorkout('dynamic-climbing-power'),
      _findWorkout('upper-body-power'),
    ],
  ),
  Session(
    id: 'volume-session',
    title: 'Volume',
    description: 'Lots of easy climbing',
    label: 'Endurance',
    workouts: [
      _findWorkout('climbing-warm-up'),
      _findWorkout('route-laps-endurance'),
      _findWorkout('full-body-strength-workout'),
    ],
  ),
  Session(
    id: 'full-body-strength-session',
    title: 'Full body strength training',
    description: 'No climbing, just strength and finger training',
    label: 'Strength',
    workouts: [
      _findWorkout('strength-training-warm-up'),
      _findWorkout('handstand-training'),
      _findWorkout('pull-ups-and-pick-ups-set'),
      _findWorkout('dips-and-front-lever'),
      _findWorkout('barbell-strength-training'),
    ],
  ),
  Session(
    id: 'daily-fingerboard-stretching',
    title: 'Daily fingerboard and stretching',
    description: 'Quick light fingerboard and stretching',
    label: 'Daily maintenance',
    workouts: [_findWorkout('daily-mobility-and-light-hangs')],
  ),
  Session(
    id: 'daily-evening-stretch',
    title: 'Daily evening stretch',
    description: 'Relaxed stretching at the end of the day',
    label: 'Daily maintenance',
    workouts: [_findWorkout('evening-stretch-and-recovery')],
  ),
  Session(
    id: 'quick-fingerboarding-session',
    title: 'Quick fingerboarding',
    description: 'As you\'re passing the fingerboard ',
    label: 'Daily maintenance',
    workouts: [_findWorkout('quick-fingerboarding')],
  ),
];
