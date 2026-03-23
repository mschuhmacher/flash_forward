import 'package:flash_forward/utils/nullable.dart';
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

  // Nullable<T> parameters let callers distinguish "not provided" (omit the
  // argument → keep the current value) from "explicitly set to null"
  // (pass Nullable(null) → clear the field). A plain `T? param` cannot express
  // this because `param ?? this.field` treats both cases identically.
  Exercise copyWith({
    String? id,
    String? templateId,
    String? title,
    String? description,
    String? label,
    Nullable<String>? equipment,
    Nullable<String>? muscleGroups,
    Nullable<String>? difficulty,
    String? userId,
    ExerciseType? type,
    int? sets,
    Nullable<int>? reps,
    int? timeBetweenSets,
    int? timePerRep,
    int? timeBetweenReps,
    int? activeTime,
    double? load,
    Nullable<String>? loadUnit,
    Nullable<int>? rpe,
    Nullable<String>? notes,
  }) => Exercise(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    description: description ?? this.description,
    label: label ?? this.label,
    equipment: equipment == null ? this.equipment : equipment.value,
    muscleGroups: muscleGroups == null ? this.muscleGroups : muscleGroups.value,
    difficulty: difficulty == null ? this.difficulty : difficulty.value,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    sets: sets ?? this.sets,
    reps: reps == null ? this.reps : reps.value,
    timeBetweenSets: timeBetweenSets ?? this.timeBetweenSets,
    timePerRep: timePerRep ?? this.timePerRep,
    timeBetweenReps: timeBetweenReps ?? this.timeBetweenReps,
    activeTime: activeTime ?? this.activeTime,
    load: load ?? this.load,
    loadUnit: loadUnit == null ? this.loadUnit : loadUnit.value,
    rpe: rpe == null ? this.rpe : rpe.value,
    notes: notes == null ? this.notes : notes.value,
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
