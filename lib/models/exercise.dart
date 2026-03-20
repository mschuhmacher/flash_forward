import 'package:uuid/uuid.dart';

enum ExerciseType { timedReps, fixedDuration, manual }

class Exercise {
  final String id;
  final String? templateId;

  final String title;
  final String description;
  final String label;
  final String? equipment;
  final String? muscleGroups;
  final String? difficulty;
  final String? userId;

  final ExerciseType type;
  final int sets;
  final int? reps; // null means no rep target (only required for timedReps)
  final int timeBetweenSets;
  final int timePerRep;
  final int timeBetweenReps;
  final int activeTime; // seconds; used only by fixedDuration
  final double load;
  final String? loadUnit;
  final int? rpe;
  final String? notes;

  Exercise({
    String? id,
    this.templateId,
    required this.title,
    required this.description,
    required this.label,
    this.equipment,
    this.muscleGroups,
    this.difficulty,
    this.userId,
    this.type = ExerciseType.timedReps,
    this.sets = 3,
    this.reps = 10,
    this.timeBetweenSets = 60,
    this.timePerRep = 3,
    this.timeBetweenReps = 0,
    this.activeTime = 30,
    this.load = 0.0,
    this.loadUnit,
    this.rpe,
    this.notes,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'title': title,
    'description': description,
    'label': label,
    'equipment': equipment,
    'muscleGroups': muscleGroups,
    'difficulty': difficulty,
    'userId': userId,
    'type': type.name,
    'sets': sets,
    'reps': reps,
    'timeBetweenSets': timeBetweenSets,
    'timePerRep': timePerRep,
    'timeBetweenReps': timeBetweenReps,
    'activeTime': activeTime,
    'load': load,
    'loadUnit': loadUnit,
    'rpe': rpe,
    'notes': notes,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] ?? const Uuid().v4(),
    templateId: json['templateId'],
    title: json['title'] ?? 'Untitled exercise',
    description: json['description'] ?? 'No description provided',
    label: json['label'] ?? 'Other',
    equipment: json['equipment'],
    muscleGroups: json['muscleGroups'],
    difficulty: json['difficulty'],
    userId: json['userId'],
    // Backward-compatible: handle old 'default*' keys from ExerciseTemplate/ExerciseInstance
    type: ExerciseType.values.byName(json['type'] ?? 'timedReps'),
    sets: json['sets'] ?? json['defaultSets'] ?? 3,
    reps: json['reps'] ?? json['defaultReps'],
    timeBetweenSets: json['timeBetweenSets'] ?? json['defaultTimeBetweenSets'] ?? 60,
    timePerRep: json['timePerRep'] ?? json['defaultTimePerRep'] ?? 3,
    timeBetweenReps: json['timeBetweenReps'] ?? json['defaultTimeBetweenReps'] ?? 0,
    activeTime: json['activeTime'] ?? 30,
    load: (json['load'] ?? json['defaultLoad'] ?? 0.0) is num
        ? (json['load'] ?? json['defaultLoad'] ?? 0.0 as num).toDouble()
        : 0.0,
    loadUnit: json['loadUnit'],
    rpe: json['rpe'] ?? json['defaultRpe'],
    notes: json['notes'],
  );

  Exercise copyWith({
    String? id,
    String? templateId,
    String? title,
    String? description,
    String? label,
    String? equipment,
    String? muscleGroups,
    String? difficulty,
    String? userId,
    ExerciseType? type,
    int? sets,
    Object? reps = _keep, // use _keep sentinel to allow explicit null
    int? timeBetweenSets,
    int? timePerRep,
    int? timeBetweenReps,
    int? activeTime,
    double? load,
    String? loadUnit,
    int? rpe,
    String? notes,
  }) => Exercise(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    description: description ?? this.description,
    label: label ?? this.label,
    equipment: equipment ?? this.equipment,
    muscleGroups: muscleGroups ?? this.muscleGroups,
    difficulty: difficulty ?? this.difficulty,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    sets: sets ?? this.sets,
    reps: identical(reps, _keep) ? this.reps : reps as int?,
    timeBetweenSets: timeBetweenSets ?? this.timeBetweenSets,
    timePerRep: timePerRep ?? this.timePerRep,
    timeBetweenReps: timeBetweenReps ?? this.timeBetweenReps,
    activeTime: activeTime ?? this.activeTime,
    load: load ?? this.load,
    loadUnit: loadUnit ?? this.loadUnit,
    rpe: rpe ?? this.rpe,
    notes: notes ?? this.notes,
  );

  /// Creates an independent copy with a new UUID — use when adding to a workout
  /// or starting a session so the source is never mutated.
  Exercise deepCopy() => Exercise(
    templateId: templateId ?? id,
    title: title,
    description: description,
    label: label,
    equipment: equipment,
    muscleGroups: muscleGroups,
    difficulty: difficulty,
    userId: userId,
    type: type,
    sets: sets,
    reps: reps,
    timeBetweenSets: timeBetweenSets,
    timePerRep: timePerRep,
    timeBetweenReps: timeBetweenReps,
    activeTime: activeTime,
    load: load,
    loadUnit: loadUnit,
    rpe: rpe,
    notes: notes,
  );
}

// Sentinel for copyWith to distinguish "not provided" from explicit null.
const Object _keep = Object();
