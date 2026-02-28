// Default workouts
import 'package:flash_forward/models/exercise_instance.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/data/default_exercise_templates.dart';

// Helper function to create ExerciseInstance from template by ID
ExerciseInstance _findInstance(String id) {
  final template = kDefaultExerciseTemplates.firstWhere((t) => t.id == id);
  return ExerciseInstance.fromTemplate(template);
}

List<Workout> kDefaultWorkouts = [
  // ============================================================================
  // WARM-UPS
  // ============================================================================
  Workout(
    title: 'Climbing Warm-up',
    label: 'Warm-up',
    description: 'Finger and major muscle groups warm-up',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 15,
    list: [
      _findInstance('repeaters'),
      _findInstance('band-assisted-pull-ups'),
      _findInstance('push-ups'),
      _findInstance('no-monies'),
      _findInstance('external-rotations'),
    ],
  ),

  Workout(
    title: 'General Warm-up',
    label: 'Warm-up',
    description: 'Complete warm-up for any training session',
    difficulty: 'Beginner',
    equipment: 'None',
    timeBetweenExercises: 15,
    list: [
      _findInstance('jumping-jacks'),
      _findInstance('arm-circles'),
      _findInstance('leg-swings'),
      _findInstance('shoulder-rolls'),
      _findInstance('wrist-circles'),
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
      _findInstance('scapular-pull-ups'),
      _findInstance('shoulder-dislocates'),
      _findInstance('push-ups'),
      _findInstance('australian-pull-ups'),
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
      _findInstance('silent-feet-drill'),
      _findInstance('down-climbing'),
      _findInstance('one-foot'),
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
      _findInstance('straight-arm-climbing'),
      _findInstance('flag-practice'),
      _findInstance('twist-locks'),
      _findInstance('drop-knee-practice'),
    ],
  ),

  Workout(
    title: 'Dynamic Movement Practice',
    label: 'Technique',
    description: 'Develop power and coordination for dynamic moves',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 120,
    list: [_findInstance('hover-hands'), _findInstance('dyno-practice')],
  ),

  Workout(
    title: 'Advanced Technique Drills',
    label: 'Technique',
    description: 'Challenge balance and body awareness',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 120,
    list: [
      _findInstance('one-foot'),
      _findInstance('hover-hands'),
      _findInstance('straight-arm-climbing'),
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
      _findInstance('pull-ups'),
      _findInstance('lock-offs'),
      _findInstance('hanging-leg-raises'),
      _findInstance('frenchies'),
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
      _findInstance('weighted-pull-ups'),
      _findInstance('one-arm-pull-up-negatives'),
      _findInstance('typewriter-pull-ups'),
      _findInstance('toes-to-bar'),
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
      _findInstance('push-ups'),
      _findInstance('diamond-push-ups'),
      _findInstance('no-monies'),
      _findInstance('face-pulls'),
      _findInstance('external-rotations'),
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
      _findInstance('hanging-knee-raises'),
      _findInstance('hanging-leg-raises'),
      _findInstance('plank'),
      _findInstance('side-plank'),
      _findInstance('hollow-body-hold'),
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
      _findInstance('toes-to-bar'),
      _findInstance('windshield-wipers'),
      _findInstance('front-lever-progressions'),
      _findInstance('copenhagen-plank'),
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
      _findInstance('pull-ups'),
      _findInstance('push-ups'),
      _findInstance('toes-to-bar'),
      _findInstance('pike-push-ups'),
      _findInstance('no-monies'),
    ],
  ),

  Workout(
    title: 'General Upper-body Strength',
    label: 'Strength',
    description: 'Upper-body strength exercises with push and pulls',
    difficulty: 'Intermediate',
    equipment: 'Pull-up bar, Resistance band',
    timeBetweenExercises: 90,
    list: [
      _findInstance('weighted-pull-ups'),
      _findInstance('dips'),
      _findInstance('wall-touches'),
      _findInstance('pike-push-ups'),
      _findInstance('face-pulls'),
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
      _findInstance('band-assisted-pull-ups'),
      _findInstance('push-ups'),
      _findInstance('hanging-knee-raises'),
      _findInstance('plank'),
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
      _findInstance('bench-press'),
      _findInstance('romanian-deadlift'),
      _findInstance('seated-overhead-dumbbell-press'),
    ],
  ),

  Workout(
    title: 'Pull-ups & Pick-ups Set',
    label: 'Strength',
    description: 'Superset of 3 exercises',
    difficulty: 'Intermediate',
    equipment: 'Weight belt, pull-up bar, loading pin',
    timeBetweenExercises: 0,
    list: [
      _findInstance('weighted-pull-ups'),
      _findInstance('max-pick-ups'),
      _findInstance('standing-forward-fold-wide-legged'),
    ],
  ),

  Workout(
    title: 'Dips and front lever',
    label: 'Strength',
    description: 'Superset of 2',
    difficulty: 'Intermediate',
    equipment: 'Parallel bars, pull-up bar',
    timeBetweenExercises: 180,
    list: [_findInstance('dips'), _findInstance('front-lever-progressions')],
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
      _findInstance('campus-board-bumps'),
      _findInstance('campus-board-1-4-7'),
      _findInstance('campus-board-max-catch'),
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
      _findInstance('dyno-practice'),
      _findInstance('one-arm-dynos'),
      _findInstance('lock-off-dynos'),
    ],
  ),

  Workout(
    title: 'Upper-body Power',
    label: 'Power',
    description: 'Explosive pulling and pushing movements',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar',
    timeBetweenExercises: 120,
    list: [
      _findInstance('explosive-pull-ups'),
      _findInstance('chest-to-bar-pull-ups'),
      _findInstance('plyometric-push-ups'),
    ],
  ),

  Workout(
    title: 'Lower Body Power',
    label: 'Power',
    description: 'Explosive leg strength and coordination',
    difficulty: 'Intermediate',
    equipment: 'Box/Platform',
    timeBetweenExercises: 90,
    list: [_findInstance('box-jumps'), _findInstance('tuck-jumps')],
  ),

  Workout(
    title: 'Mixed Power Training',
    label: 'Power',
    description: 'Combine campus work and bodyweight power',
    difficulty: 'Advanced',
    equipment: 'Campus board, Pull-up bar',
    timeBetweenExercises: 150,
    list: [
      _findInstance('campus-board-pyramid-catches'),
      _findInstance('explosive-pull-ups'),
      _findInstance('campus-board-1-3-5-7'),
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
    list: [_findInstance('campus-board-ladders')],
  ),

  Workout(
    title: '4x4 Boulder Circuits',
    label: 'Powerendurance',
    description: 'Classic power endurance training on boulder problems',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 240,
    list: [_findInstance('4x4s')],
  ),

  Workout(
    title: 'Linked Problems Power',
    label: 'Powerendurance',
    description: 'Build endurance by linking boulder problems',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 240,
    list: [_findInstance('linked-boulder-problems')],
  ),

  Workout(
    title: 'Boulder Pyramid Endurance',
    label: 'Powerendurance',
    description: 'Pyramid protocol for sustained power',
    difficulty: 'Intermediate',
    equipment: 'Climbing board',
    timeBetweenExercises: 120,
    list: [_findInstance('pyramids')],
  ),

  Workout(
    title: '6 in 6 Power Endurance',
    label: 'Powerendurance',
    description: 'High-intensity boulder circuit in time limit',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 360,
    list: [_findInstance('6-in-6')],
  ),

  // ============================================================================
  // FINGER STRENGTH
  // ============================================================================
  Workout(
    title: 'Max Pick-ups & Minimum Edge Hangs',
    label: 'Finger strength',
    description: 'Maximum finger strength development',
    difficulty: 'Advanced',
    equipment: 'Hangboard',
    timeBetweenExercises: 180,
    list: [_findInstance('max-pick-ups'), _findInstance('minimum-edge-hangs')],
  ),

  Workout(
    title: 'Max Hangs & Minimum Edge Hangs',
    label: 'Finger strength',
    description: 'Maximum finger strength development',
    difficulty: 'Advanced',
    equipment: 'Hangboard',
    timeBetweenExercises: 180,
    list: [_findInstance('max-hangs'), _findInstance('minimum-edge-hangs')],
  ),

  Workout(
    title: 'Fingerboard Strength Builder',
    label: 'Finger strength',
    description: 'Build finger strength with various grips',
    difficulty: 'Intermediate',
    equipment: 'Hangboard',
    timeBetweenExercises: 120,
    list: [
      _findInstance('half-crimp-hangs'),
      _findInstance('three-finger-drag-hangs'),
      _findInstance('repeaters'),
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
      _findInstance('recruitment-pulls'),
      _findInstance('open-hand-hangs'),
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
      _findInstance('max-hangs'),
      _findInstance('weighted-pull-ups'),
      _findInstance('minimum-edge-hangs'),
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
    list: [_findInstance('arc-training')],
  ),

  Workout(
    title: 'Route Laps Endurance',
    label: 'Endurance',
    description: 'Build muscular endurance through repeated laps',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 180,
    list: [_findInstance('laps-on-route')],
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
      _findInstance('cat-cow-stretch'),
      _findInstance('hip-flexor-stretch'),
      _findInstance('pigeon-pose'),
      _findInstance('seated-forward-fold'),
      _findInstance('shoulder-dislocates'),
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
      _findInstance('shoulder-dislocates'),
      _findInstance('cat-cow-stretch'),
      _findInstance('hip-flexor-stretch'),
      _findInstance('pigeon-pose'),
      _findInstance('pancake-stretch'),
      _findInstance('thoracic-bridge'),
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
      _findInstance('standing-forward-fold'),
      _findInstance('standing-forward-fold-wide-legged'),
      _findInstance('seated-forward-fold'),
      _findInstance('pigeon-pose'),
      _findInstance('middle-splits-progression'),
    ],
  ),

  // ============================================================================
  // CALISTHENICS SKILLS
  // ============================================================================
  Workout(
    title: 'Handstand Training',
    label: 'Skills',
    description: 'General handstand practice',
    difficulty: 'Intermediate',
    equipment: 'Wall',
    timeBetweenExercises: 60,
    list: [_findInstance('freestanding-handstand'), _findInstance('crow-pose')],
  ),
  Workout(
    title: 'Handstand Progression Training',
    label: 'Skills',
    description: 'Develop handstand strength and balance',
    difficulty: 'Intermediate',
    equipment: 'Wall',
    timeBetweenExercises: 90,
    list: [
      _findInstance('freestanding-handstand'),
      _findInstance('handstand-hold-wall'),
      _findInstance('handstand-taps-wall'),
      _findInstance('crow-pose'),
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
      _findInstance('handstand-push-ups'),
      _findInstance('freestanding-handstand'),
      _findInstance('handstand-walk'),
      _findInstance('crane-pose'),
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
      _findInstance('tuck-planche'),
      _findInstance('advanced-tuck-planche'),
      _findInstance('l-sit-hold'),
      _findInstance('crow-pose'),
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
      _findInstance('advanced-tuck-planche'),
      _findInstance('straddle-planche'),
      _findInstance('full-planche'),
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
      _findInstance('front-lever-progressions'),
      _findInstance('back-lever-progressions'),
      _findInstance('skin-the-cat'),
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
      _findInstance('pull-ups'),
      _findInstance('dips'),
      _findInstance('muscle-up'),
      _findInstance('ring-muscle-up'),
    ],
  ),

  Workout(
    title: 'Single Leg Strength',
    label: 'Skills',
    description: 'Develop unilateral leg strength and balance',
    difficulty: 'Advanced',
    equipment: 'None',
    timeBetweenExercises: 90,
    list: [_findInstance('pistol-squat'), _findInstance('shrimp-squat')],
  ),

  Workout(
    title: 'Dynamic Calisthenics Skills',
    label: 'Skills',
    description: 'Explosive movements and transitions',
    difficulty: 'Advanced',
    equipment: 'Pull-up bar, Pole',
    timeBetweenExercises: 120,
    list: [
      _findInstance('muscle-up'),
      _findInstance('human-flag-progressions'),
      _findInstance('skin-the-cat'),
    ],
  ),

  // ============================================================================
  // DAILY MAINTENANCE
  // ============================================================================
  Workout(
    title: 'Quick Fingerboarding',
    label: 'Daily maintenance',
    description: 'Quick, light fingerboarding for in between',
    difficulty: 'Beginner',
    equipment: 'Hangboard',
    timeBetweenExercises: 30,
    list: [_findInstance('repeaters')],
  ),

  Workout(
    title: 'Daily Mobility & Light Hangs',
    label: 'Daily maintenance',
    description: 'Quick daily routine for light fingerboarding and mobility',
    difficulty: 'Beginner',
    equipment: 'Hangboard',
    timeBetweenExercises: 30,
    list: [
      _findInstance('repeaters'),
      _findInstance('seated-single-leg-stretch'),
      _findInstance('recruitment-pulls'),
      _findInstance('shoulder-dislocates'),
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
      _findInstance('seated-single-leg-stretch'),
      _findInstance('pigeon-pose'),
      _findInstance('shoulder-dislocates'),
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
      _findInstance('no-monies'),
      _findInstance('face-pulls'),
      _findInstance('external-rotations'),
      _findInstance('reverse-wrist-curls'),
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
      _findInstance('wrist-circles'),
      _findInstance('finger-flexor-stretch'),
      _findInstance('repeaters'),
      _findInstance('reverse-wrist-curls'),
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
      _findInstance('plank'),
      _findInstance('side-plank'),
      _findInstance('dead-bug'),
      _findInstance('hollow-body-hold'),
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
      _findInstance('arm-circles'),
      _findInstance('shoulder-rolls'),
      _findInstance('shoulder-dislocates'),
      _findInstance('external-rotations'),
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
    list: [_findInstance('flash'), _findInstance('limit-bouldering')],
  ),

  Workout(
    title: 'Projecting',
    label: 'Limit',
    description: 'Focussing on trying hard',
    difficulty: 'Intermediate',
    equipment: 'Climbing wall',
    timeBetweenExercises: 300,
    list: [_findInstance('limit-bouldering')],
  ),

  // ============================================================================
  // TEST - UI LIMIT VERIFICATION
  // ============================================================================
  // Workout(
  //   title: 'Test Workout Maximum Title Lim', // exactly 30 characters
  //   label: 'Test',
  //   description:
  //       'This workout description tests the maximum allowed character limit of exactly one hundred characters', // exactly 100 characters
  //   difficulty: 'Beginner',
  //   equipment: 'None',
  //   timeBetweenExercises: 30,
  //   list: [
  //     _findInstance('test-max-title-25-chars'),
  //     _findInstance('test-short-title'),
  //   ],
  // ),
];
