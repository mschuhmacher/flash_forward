import 'package:flash_forward/models/exercise_template.dart';
import 'package:uuid/uuid.dart';

class ExerciseInstance {
  final String id;
  final String templateId;

  final String title;
  final String description;
  final String label;
  final String? equipment;
  final String? muscleGroups;
  final String? difficulty;
  final String? userId;

  int sets;
  int reps;
  int timeBetweenSets;
  int timePerRep;
  int timeBetweenReps;
  String load;
  int? rpe;

  ExerciseInstance({
    String? id,
    required this.templateId,
    required this.title,
    required this.description,
    required this.label,
    this.equipment,
    this.muscleGroups,
    this.difficulty,
    required this.sets,
    required this.reps,
    required this.timeBetweenSets,
    required this.timePerRep,
    required this.timeBetweenReps,
    required this.load,
    this.rpe,
    this.userId,
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
    'sets': sets,
    'reps': reps,
    'timeBetweenSets': timeBetweenSets,
    'timePerRep': timePerRep,
    'timeBetweenReps': timeBetweenReps,
    'load': load,
    'rpe': rpe,
  };

  factory ExerciseInstance.fromJson(Map<String, dynamic> json) =>
      ExerciseInstance(
        id: json['id'] ?? const Uuid().v4(),
        templateId: json['templateId'] ?? '',
        title: json['title'] ?? 'Untitled exercise',
        description: json['description'] ?? 'No description provided',
        label: json['label'] ?? 'No label provided',
        equipment: json['equipment'] ?? 'No equipment specified',
        muscleGroups: json['muscleGroups'] ?? 'No muscle groups specified',
        difficulty: json['difficulty'] ?? 'No difficulty specified',
        userId: json['userId'],
        sets: json['sets'],
        reps: json['reps'],
        timeBetweenSets: json['timeBetweenSets'],
        timePerRep: json['timePerRep'],
        timeBetweenReps: json['timeBetweenReps'],
        load: json['load'],
        rpe: json['rpe'],
      );

  ExerciseInstance copyWith({
    String? id,
    String? templateId,
    String? title,
    String? description,
    String? label,
    String? equipment,
    String? muscleGroups,
    String? difficulty,
    String? userId,
    int? sets,
    int? reps,
    int? timeBetweenSets,
    int? timePerRep,
    int? timeBetweenReps,
    String? load,
    int? rpe,
  }) {
    return ExerciseInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      title: title ?? this.title,
      description: description ?? this.description,
      label: label ?? this.label,
      equipment: equipment ?? this.equipment,
      muscleGroups: muscleGroups ?? this.muscleGroups,
      difficulty: difficulty ?? this.difficulty,
      userId: userId ?? this.userId,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      timeBetweenSets: timeBetweenSets ?? this.timeBetweenSets,
      timePerRep: timePerRep ?? this.timePerRep,
      timeBetweenReps: timeBetweenReps ?? this.timeBetweenReps,
      load: load ?? this.load,
      rpe: rpe ?? this.rpe,
    );
  }

  factory ExerciseInstance.fromTemplate(
    ExerciseTemplate template, {
    int? sets,
    int? reps,
    int? timeBetweenSets,
    int? timePerRep,
    int? timeBetweenReps,
    String? load,
    int? rpe,
  }) {
    return ExerciseInstance(
      templateId: template.id,
      title: template.title,
      description: template.description,
      label: template.label,
      equipment: template.equipment,
      muscleGroups: template.muscleGroups,
      difficulty: template.difficulty,
      sets: sets ?? template.defaultSets,
      reps: reps ?? template.defaultReps,
      timeBetweenSets: timeBetweenSets ?? template.defaultTimeBetweenSets,
      timePerRep: timePerRep ?? template.defaultTimePerRep,
      timeBetweenReps: timeBetweenReps ?? template.defaultTimeBetweenReps,
      load: load ?? template.defaultLoad,
      rpe: rpe ?? template.defaultRpe,
    );
  }
}
