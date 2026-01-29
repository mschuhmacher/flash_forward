import 'package:uuid/uuid.dart';

class ExerciseTemplate {
  final String id;
  final String title;
  final String description;
  final String label;
  final String? equipment;
  final String? muscleGroups;
  final String? difficulty;
  final String? userId;

  final int defaultSets;
  final int defaultReps;
  final int defaultTimeBetweenSets;
  final int defaultTimePerRep;
  final int defaultTimeBetweenReps;
  final String defaultLoad;
  final int? defaultRpe;

  ExerciseTemplate({
    String? id,
    required this.title,
    required this.description,
    required this.label,
    this.equipment,
    this.muscleGroups,
    this.difficulty,
    this.userId,
    this.defaultSets = 3,
    this.defaultReps = 10,
    this.defaultTimeBetweenSets = 60,
    this.defaultTimePerRep = 3,
    this.defaultTimeBetweenReps = 0,
    this.defaultLoad = 'Bodyweight',
    this.defaultRpe,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'label': label,
    'equipment': equipment,
    'muscleGroups': muscleGroups,
    'difficulty': difficulty,
    'userId': userId,
    'defaultSets': defaultSets,
    'defaultReps': defaultReps,
    'defaultTimeBetweenSets': defaultTimeBetweenSets,
    'defaultTimePerRep': defaultTimePerRep,
    'defaultTimeBetweenReps': defaultTimeBetweenReps,
    'defaultLoad': defaultLoad,
    'defaultRpe': defaultRpe,
  };

  factory ExerciseTemplate.fromJson(Map<String, dynamic> json) =>
      ExerciseTemplate(
        id: json['id'] ?? const Uuid().v4(),
        title: json['title'] ?? 'Untitled exercise',
        description: json['description'] ?? 'No description provided',
        label: json['label'] ?? 'No label provided',
        equipment: json['equipment'] ?? 'No equipment specified',
        muscleGroups: json['muscleGroups'] ?? 'No muscle groups specified',
        difficulty: json['difficulty'] ?? 'No difficulty specified',
        userId: json['userId'],
        defaultSets: json['defaultSets'] ?? 3,
        defaultReps: json['defaultReps'] ?? 10,
        defaultTimeBetweenSets: json['defaultTimeBetweenSets'] ?? 60,
        defaultTimePerRep: json['defaultTimePerRep'] ?? 3,
        defaultTimeBetweenReps: json['defaultTimeBetweenReps'] ?? 0,
        defaultLoad: json['defaultLoad'] ?? 'Bodyweight',
        defaultRpe: json['defaultRpe'],
      );

  ExerciseTemplate copyWith({
    String? id,
    String? title,
    String? description,
    String? label,
    String? equipment,
    String? muscleGroups,
    String? difficulty,
    String? userId,
    int? defaultSets,
    int? defaultReps,
    int? defaultTimeBetweenSets,
    int? defaultTimePerRep,
    int? defaultTimeBetweenReps,
    String? defaultLoad,
    int? defaultRpe,
  }) {
    return ExerciseTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      label: label ?? this.label,
      equipment: equipment ?? this.equipment,
      muscleGroups: muscleGroups ?? this.muscleGroups,
      difficulty: difficulty ?? this.difficulty,
      userId: userId ?? this.userId,
      defaultSets: defaultSets ?? this.defaultSets,
      defaultReps: defaultReps ?? this.defaultReps,
      defaultTimeBetweenSets:
          defaultTimeBetweenSets ?? this.defaultTimeBetweenSets,
      defaultTimePerRep: defaultTimePerRep ?? this.defaultTimePerRep,
      defaultTimeBetweenReps:
          defaultTimeBetweenReps ?? this.defaultTimeBetweenReps,
      defaultLoad: defaultLoad ?? this.defaultLoad,
      defaultRpe: defaultRpe ?? this.defaultRpe,
    );
  }
}
