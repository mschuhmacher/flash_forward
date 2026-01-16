// Default workouts
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/data/default_exercise_templates.dart';

// Helper function to find exercises by title
Exercise _findExercise(String title) {
  return kDefaultExerciseTemplates.firstWhere((e) => e.title == title);
}

List<Workout> kDefaultWorkouts = [
  // ============================================================================
  // WARM-UPS
  // ============================================================================
  Workout(
    title: 'General Warm-up',
    label: 'Warm-up',
    description: 'Finger and major muscle groups warm-up',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 15,
    list: [
      _findExercise('Repeaters'),
      _findExercise('Band-assisted pull-ups'),
      _findExercise('Push-ups'),
      _findExercise('No Monies'),
      _findExercise('External Rotations'),
    ],
  ),

  Workout(
    title: 'Basic Warm-up',
    label: 'Warm-up',
    description: 'Complete warm-up for any training session',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 15,
    list: [
      _findExercise('Jumping Jacks'),
      _findExercise('Arm Circles'),
      _findExercise('Leg Swings'),
      _findExercise('Shoulder Rolls'),
      _findExercise('Wrist Circles'),
    ],
  ),

  Workout(
    title: 'Climbing-Specific Warm-up',
    label: 'Warm-up',
    description: 'Targeted warm-up for climbing and hangboard sessions',
    difficulty: 'Intermediate',
    equipment: 'Resistance band',
    timeBetweenExercises: 20,
    list: [
      _findExercise('Arm Circles'),
      _findExercise('Shoulder Rolls'),
      _findExercise('Wrist Circles'),
      _findExercise('Finger Flexor Stretch'),
      _findExercise('Shoulder Dislocates'),
      _findExercise('Cat-Cow Stretch'),
    ],
  ),

  Workout(
    title: 'Strength Training Warm-up',
    label: 'Warm-up',
    description: 'Dynamic warm-up for pull-ups, dips, and strength work',
    difficulty: 'Beginner',
    equipment: 'Low bar',
    timeBetweenExercises: 20,
    list: [
      _findExercise('Jumping Jacks'),
      _findExercise('High Knees'),
      _findExercise('Arm Circles'),
      _findExercise('Shoulder Dislocates'),
      _findExercise('Australian Pull-ups'),
    ],
  ),

  // ============================================================================
  // TECHNIQUE DRILLS
  // ============================================================================
  Workout(
    title: 'Footwork Fundamentals',
    label: 'Technique',
    description: 'Develop precise and quiet footwork',
    difficulty: 'Beginner',
    equipment: 'Climbing wall',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Silent Feet Drill'),
      _findExercise('Down Climbing'),
      _findExercise('One foot'),
    ],
  ),

  Workout(
    title: 'Body Positioning & Movement',
    label: 'Technique',
    description: 'Practice efficient body positioning techniques',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Straight Arm Climbing'),
      _findExercise('Flag Practice'),
      _findExercise('Twist Locks'),
      _findExercise('Drop Knee Practice'),
    ],
  ),

  Workout(
    title: 'Dynamic Movement Practice',
    label: 'Technique',
    description: 'Develop power and coordination for dynamic moves',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 120,
    list: [_findExercise('Hover Hands'), _findExercise('Dyno Practice')],
  ),

  Workout(
    title: 'Advanced Technique Drills',
    label: 'Technique',
    description: 'Challenge balance and body awareness',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 120,
    list: [
      _findExercise('One foot'),
      _findExercise('Hover Hands'),
      _findExercise('Straight Arm Climbing'),
    ],
  ),

  // ============================================================================
  // STRENGTH TRAINING
  // ============================================================================
  Workout(
    title: 'Pull-Focused Strength',
    label: 'Strength',
    description: 'Comprehensive pulling strength for climbing',
    difficulty: 'Intermediate',
    equipment: 'Pull-up bar',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Pull-ups'),
      _findExercise('Lock-offs'),
      _findExercise('Hanging Leg Raises'),
      _findExercise('Frenchies'),
    ],
  ),

  Workout(
    title: 'Advanced Pull Strength',
    label: 'Strength',
    description: 'High-intensity pulling exercises for experienced climbers',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar, Weight belt',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Weighted Pull-ups'),
      _findExercise('One Arm Pull-up Negatives'),
      _findExercise('Typewriter Pull-ups'),
      _findExercise('Toes to Bar'),
    ],
  ),

  Workout(
    title: 'Push & Antagonist Training',
    label: 'Strength',
    description: 'Balance pulling muscles with pushing exercises',
    difficulty: 'Intermediate',
    equipment: 'Resistance band, Dumbbell',
    timeBetweenExercises: 60,
    list: [
      _findExercise('Push-ups'),
      _findExercise('Diamond Push-ups'),
      _findExercise('No Monies'),
      _findExercise('Face Pulls'),
      _findExercise('External Rotations'),
    ],
  ),

  Workout(
    title: 'Core Strength Builder',
    label: 'Strength',
    description: 'Complete core workout for climbing stability',
    difficulty: 'Intermediate',
    equipment: 'Pull-up bar',
    timeBetweenExercises: 60,
    list: [
      _findExercise('Hanging Knee Raises'),
      _findExercise('Hanging Leg Raises'),
      _findExercise('Plank'),
      _findExercise('Side Plank'),
      _findExercise('Hollow Body Hold'),
    ],
  ),

  Workout(
    title: 'Advanced Core Strength',
    label: 'Strength',
    description: 'High-level core exercises for power and control',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar, Bench',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Toes to Bar'),
      _findExercise('Windshield Wipers'),
      _findExercise('Front Lever Progressions'),
      _findExercise('Copenhagen Plank'),
    ],
  ),

  Workout(
    title: 'Full-Body Strength Workout',
    label: 'Strength',
    description: 'Balanced full-body workout combining push, pull, and core',
    difficulty: 'Intermediate',
    equipment: 'Pull-up bar, Resistance band',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Pull-ups'),
      _findExercise('Push-ups'),
      _findExercise('Toes to Bar'),
      _findExercise('Pike Push-ups'),
      _findExercise('No Monies'),
    ],
  ),

  Workout(
    title: 'Beginner Strength Foundation',
    label: 'Strength',
    description: 'Build base strength for climbing progression',
    difficulty: 'Beginner',
    equipment: 'Low bar, Resistance band',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Band-assisted pull-ups'),
      _findExercise('Push-ups'),
      _findExercise('Hanging Knee Raises'),
      _findExercise('Plank'),
    ],
  ),

  Workout(
    title: 'Barbell Strength Training',
    label: 'Strength',
    description: 'Traditional compound lifts for overall strength',
    difficulty: 'Intermediate',
    equipment: 'Barbell, Bench',
    timeBetweenExercises: 180,
    list: [
      _findExercise('Bench press'),
      _findExercise('Romanian deadlift'),
      _findExercise('Seated overhead dumbbell press'),
    ],
  ),

  Workout(
    title: 'Weighted pull-ups, pick-ups, hamstring stretch',
    label: 'Strength',
    description: 'Superset of 3 exercises',
    difficulty: 'Intermediate',
    equipment: 'Weight belt, pull-up bar, loading pin',
    timeBetweenExercises: 0,
    list: [
      _findExercise('Weighted Pull-ups'),
      _findExercise('Pick-ups'),
      _findExercise('Standing Forward Fold (Wide-legged)'),
    ],
  ),

  Workout(
    title: 'Dips and front lever',
    label: 'Strength',
    description: 'Superset of 2',
    difficulty: 'Intermediate',
    equipment: 'Parallel bars, pull-up bar',
    timeBetweenExercises: 180,
    list: [_findExercise('Dips'), _findExercise('Front Lever Progressions')],
  ),

  // ============================================================================
  // POWER TRAINING
  // ============================================================================
  Workout(
    title: 'Campus Board Power Development',
    label: 'Power',
    description: 'Build explosive finger and pulling power',
    difficulty: 'Advanced',
    equipment: 'Campus board',
    timeBetweenExercises: 180,
    list: [
      _findExercise('Campus Board Bumps'),
      _findExercise('Campus Board 1-4-7'),
      _findExercise('Campus Board Max Catch'),
    ],
  ),

  Workout(
    title: 'Dynamic Climbing Power',
    label: 'Power',
    description: 'Develop explosive movement on the wall',
    difficulty: 'Advanced',
    equipment: 'Climbing wall',
    timeBetweenExercises: 150,
    list: [
      _findExercise('Dyno Practice'),
      _findExercise('One Arm Dynos'),
      _findExercise('Lock-off Dynos'),
    ],
  ),

  Workout(
    title: 'Upper Body Power',
    label: 'Power',
    description: 'Explosive pulling and pushing movements',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Explosive Pull-ups'),
      _findExercise('Chest-to-Bar Pull-ups'),
      _findExercise('Plyometric Push-ups'),
    ],
  ),

  Workout(
    title: 'Lower Body Power',
    label: 'Power',
    description: 'Explosive leg strength and coordination',
    difficulty: 'Intermediate',
    equipment: 'Box/Platform',
    timeBetweenExercises: 90,
    list: [_findExercise('Box Jumps'), _findExercise('Tuck Jumps')],
  ),

  Workout(
    title: 'Mixed Power Training',
    label: 'Power',
    description: 'Combine campus work and bodyweight power',
    difficulty: 'Advanced',
    equipment: 'Campus board, Pull-up bar',
    timeBetweenExercises: 150,
    list: [
      _findExercise('Campus Board Pyramid Catches'),
      _findExercise('Explosive Pull-ups'),
      _findExercise('Campus Board 1-3-5-7'),
    ],
  ),

  // ============================================================================
  // POWER ENDURANCE
  // ============================================================================
  Workout(
    title: 'Campus Board Power Endurance',
    label: 'Powerendurance',
    description: 'Build powerful endurance through campus training',
    difficulty: 'Advanced',
    equipment: 'Campus board',
    timeBetweenExercises: 180,
    list: [_findExercise('Campus Board Ladders')],
  ),

  Workout(
    title: '4x4 Boulder Circuits',
    label: 'Powerendurance',
    description: 'Classic power endurance training on boulder problems',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 240,
    list: [_findExercise('4x4s')],
  ),

  Workout(
    title: 'Linked Problems Power',
    label: 'Powerendurance',
    description: 'Build endurance by linking boulder problems',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 240,
    list: [_findExercise('Linked Boulder Problems')],
  ),

  Workout(
    title: 'Boulder Pyramid Endurance',
    label: 'Powerendurance',
    description: 'Pyramid protocol for sustained power',
    difficulty: 'Intermediate',
    equipment: 'Climbing board',
    timeBetweenExercises: 120,
    list: [_findExercise('Pyramids')],
  ),

  Workout(
    title: '6 in 6 Power Endurance',
    label: 'Powerendurance',
    description: 'High-intensity boulder circuit in time limit',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 360,
    list: [_findExercise('6 in 6')],
  ),

  // ============================================================================
  // FINGER STRENGTH
  // ============================================================================
  Workout(
    title: 'Max Fingerboard Strength',
    label: 'Finger strength',
    description: 'Maximum finger strength development',
    difficulty: 'Advanced',
    equipment: 'Hangboard',
    timeBetweenExercises: 180,
    list: [_findExercise('Max Hangs'), _findExercise('Minimum Edge Hangs')],
  ),

  Workout(
    title: 'Fingerboard Strength Builder',
    label: 'Finger strength',
    description: 'Build finger strength with various grips',
    difficulty: 'Intermediate',
    equipment: 'Hangboard',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Half Crimp Hangs'),
      _findExercise('Three Finger Drag Hangs'),
      _findExercise('Repeaters'),
    ],
  ),

  Workout(
    title: 'Beginner Finger Strength',
    label: 'Finger strength',
    description: 'Safe introduction to hangboard training',
    difficulty: 'Beginner',
    equipment: 'Hangboard',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Recruitment pulls'),
      _findExercise('Open Hand Hangs'),
    ],
  ),

  Workout(
    title: 'Combined Limit Strength',
    label: 'Limit',
    description:
        'Full limit strength session combining fingerboard and pulling',
    difficulty: 'Advanced',
    equipment: 'Hangboard, Pull-up bar',
    timeBetweenExercises: 180,
    list: [
      _findExercise('Max Hangs'),
      _findExercise('Weighted Pull-ups'),
      _findExercise('Minimum Edge Hangs'),
    ],
  ),

  // ============================================================================
  // ENDURANCE
  // ============================================================================
  Workout(
    title: 'ARC Endurance Training',
    label: 'Endurance',
    description: 'Continuous easy climbing for aerobic capacity',
    difficulty: 'Beginner',
    equipment: 'Climbing wall',
    timeBetweenExercises: 300,
    list: [_findExercise('ARC Training')],
  ),

  Workout(
    title: 'Route Laps Endurance',
    label: 'Endurance',
    description: 'Build muscular endurance through repeated laps',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 180,
    list: [_findExercise('Laps on Route')],
  ),

  // ============================================================================
  // FLEXIBILITY & MOBILITY
  // ============================================================================
  Workout(
    title: 'Post-Climb Cooldown & Stretch',
    label: 'Flexibility',
    description: 'Full-body stretching routine after climbing',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 15,
    list: [
      _findExercise('Cat-Cow Stretch'),
      _findExercise('Hip Flexor Stretch'),
      _findExercise('Pigeon Pose'),
      _findExercise('Seated Forward Fold'),
      _findExercise('Shoulder Dislocates'),
    ],
  ),

  Workout(
    title: 'Deep Flexibility Session',
    label: 'Flexibility',
    description: 'Extended stretching for mobility development',
    difficulty: 'Intermediate',
    equipment: 'Resistance band',
    timeBetweenExercises: 30,
    list: [
      _findExercise('Shoulder Dislocates'),
      _findExercise('Cat-Cow Stretch'),
      _findExercise('Hip Flexor Stretch'),
      _findExercise('Pigeon Pose'),
      _findExercise('Pancake Stretch'),
      _findExercise('Thoracic Bridge'),
    ],
  ),

  Workout(
    title: 'Hamstring & Hip Flexibility',
    label: 'Flexibility',
    description: 'Focus on lower body mobility for high steps',
    difficulty: 'Intermediate',
    equipment: 'None',
    timeBetweenExercises: 30,
    list: [
      _findExercise('Standing Forward Fold'),
      _findExercise('Standing Forward Fold (Wide-legged)'),
      _findExercise('Seated Forward Fold'),
      _findExercise('Pigeon Pose'),
      _findExercise('Middle Splits Progression'),
    ],
  ),

  // ============================================================================
  // CALISTHENICS SKILLS
  // ============================================================================
  Workout(
    title: 'Handstand Progression Training',
    label: 'Skills',
    description: 'Develop handstand strength and balance',
    difficulty: 'Intermediate',
    equipment: 'Wall',
    timeBetweenExercises: 90,
    list: [
      _findExercise('Freestanding Handstand'),
      _findExercise('Handstand Hold (Wall)'),
      _findExercise('Handstand Taps (Wall)'),
      _findExercise('Crow Pose'),
    ],
  ),

  Workout(
    title: 'Advanced Handstand Skills',
    label: 'Skills',
    description: 'High-level handstand and balance work',
    difficulty: 'Advanced',
    equipment: 'Wall',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Handstand Push-ups'),
      _findExercise('Freestanding Handstand'),
      _findExercise('Handstand Walk'),
      _findExercise('Crane Pose'),
    ],
  ),

  Workout(
    title: 'Planche Progression Training',
    label: 'Skills',
    description: 'Build toward planche with progressions',
    difficulty: 'Advanced',
    equipment: 'None',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Tuck Planche'),
      _findExercise('Advanced Tuck Planche'),
      _findExercise('L-Sit Hold'),
      _findExercise('Crow Pose'),
    ],
  ),

  Workout(
    title: 'Elite Planche Training',
    label: 'Skills',
    description: 'Advanced planche variations',
    difficulty: 'Advanced',
    equipment: 'None',
    timeBetweenExercises: 150,
    list: [
      _findExercise('Advanced Tuck Planche'),
      _findExercise('Straddle Planche'),
      _findExercise('Full Planche'),
    ],
  ),

  Workout(
    title: 'Lever Progressions',
    label: 'Skills',
    description: 'Front and back lever skill development',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Front Lever Progressions'),
      _findExercise('Back Lever Progressions'),
      _findExercise('Skin the Cat'),
    ],
  ),

  Workout(
    title: 'Muscle-up Development',
    label: 'Skills',
    description: 'Build strength for muscle-ups',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar, Rings',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Pull-ups'),
      _findExercise('Dips'),
      _findExercise('Muscle-up'),
      _findExercise('Ring Muscle-up'),
    ],
  ),

  Workout(
    title: 'Single Leg Strength',
    label: 'Skills',
    description: 'Develop unilateral leg strength and balance',
    difficulty: 'Advanced',
    equipment: 'None',
    timeBetweenExercises: 90,
    list: [_findExercise('Pistol Squat'), _findExercise('Shrimp Squat')],
  ),

  Workout(
    title: 'Dynamic Calisthenics Skills',
    label: 'Skills',
    description: 'Explosive movements and transitions',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar, Pole',
    timeBetweenExercises: 120,
    list: [
      _findExercise('Muscle-up'),
      _findExercise('Human Flag Progressions'),
      _findExercise('Skin the Cat'),
    ],
  ),

  // ============================================================================
  // DAILY MAINTENANCE
  // ============================================================================
  Workout(
    title: 'Morning Mobility & Light Hangs',
    label: 'Daily maintenance',
    description: '10-minute morning routine to wake up fingers and joints',
    difficulty: 'Beginner',
    equipment: 'Hangboard',
    timeBetweenExercises: 30,
    list: [
      _findExercise('Wrist Circles'),
      _findExercise('Finger Flexor Stretch'),
      _findExercise('Arm Circles'),
      _findExercise('Open Hand Hangs'),
    ],
  ),

  Workout(
    title: 'Daily Mobility & Light Hangs',
    label: 'Daily maintenance',
    description: 'Quick daily routine for light fingerboarding and mobility',
    difficulty: 'Beginner',
    equipment: 'Hangboard',
    timeBetweenExercises: 30,
    list: [
      _findExercise('Recruitment pulls'),
      _findExercise('Standing Forward Fold (Wide-legged)'),
      _findExercise('Recruitment pulls'),
      _findExercise('Shoulder Dislocates'),
    ],
  ),

  Workout(
    title: 'Evening Stretch & Recovery',
    label: 'Daily maintenance',
    description: '15-minute evening routine for recovery and relaxation',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 20,
    list: [
      _findExercise('Cat-Cow Stretch'),
      _findExercise('Pigeon Pose'),
      _findExercise('Shoulder Dislocates'),
      _findExercise('Standing Forward Fold (Wide-legged)'),
      _findExercise('Seated Forward Fold (Single leg)'),
    ],
  ),

  Workout(
    title: 'Antagonist Maintenance',
    label: 'Daily maintenance',
    description: '10-minute antagonist work for injury prevention',
    difficulty: 'Beginner',
    equipment: 'Resistance band, Dumbbell',
    timeBetweenExercises: 30,
    list: [
      _findExercise('No Monies'),
      _findExercise('Face Pulls'),
      _findExercise('External Rotations'),
      _findExercise('Reverse Wrist Curls'),
    ],
  ),

  Workout(
    title: 'Finger Care & Maintenance',
    label: 'Daily maintenance',
    description: '12-minute routine for finger health and strength maintenance',
    difficulty: 'Intermediate',
    equipment: 'Hangboard',
    timeBetweenExercises: 30,
    list: [
      _findExercise('Wrist Circles'),
      _findExercise('Finger Flexor Stretch'),
      _findExercise('Repeaters'),
      _findExercise('Reverse Wrist Curls'),
    ],
  ),

  Workout(
    title: 'Quick Core Maintenance',
    label: 'Daily maintenance',
    description: '8-minute daily core activation',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 20,
    list: [
      _findExercise('Plank'),
      _findExercise('Side Plank'),
      _findExercise('Dead Bug'),
      _findExercise('Hollow Body Hold'),
    ],
  ),

  Workout(
    title: 'Shoulder Health Routine',
    label: 'Daily maintenance',
    description: '10-minute shoulder mobility and stability work',
    difficulty: 'Beginner',
    equipment: 'Resistance band',
    timeBetweenExercises: 25,
    list: [
      _findExercise('Arm Circles'),
      _findExercise('Shoulder Rolls'),
      _findExercise('Shoulder Dislocates'),
      _findExercise('External Rotations'),
      _findExercise('Face Pulls'),
    ],
  ),

  // ============================================================================
  // LIMIT
  // ============================================================================
  Workout(
    title: 'Flash and limit bouldering',
    label: 'Limit',
    description: 'Focussing on trying hard',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 300,
    list: [_findExercise('Flash'), _findExercise('Limit bouldering')],
  ),
];
