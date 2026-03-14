import 'package:flash_forward/models/exercise.dart';
import 'package:uuid/uuid.dart';

class Workout {
  Workout({
    String? id,
    this.templateId,
    required this.title,
    required this.label,
    this.description,
    required this.exercises,
    this.difficulty,
    this.equipment,
    required this.timeBetweenExercises,
    this.userId,
    this.notes,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String? templateId;
  final String title;
  final String label;
  final String? description;
  final List<Exercise> exercises;
  final String? difficulty;
  final String? equipment;
  final int timeBetweenExercises;
  final String? userId;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'title': title,
    'label': label,
    'description': description,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'difficulty': difficulty,
    'equipment': equipment,
    'timeBetweenExercises': timeBetweenExercises,
    'userId': userId,
    'notes': notes,
  };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'],
    templateId: json['templateId'],
    title: json['title'] ?? 'Untitled workout',
    label: json['label'] ?? 'Other',
    description: json['description'],
    // Backward-compatible: handle old 'list' key
    exercises: ((json['exercises'] ?? json['list']) as List<dynamic>? ?? [])
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    difficulty: json['difficulty'],
    equipment: json['equipment'],
    timeBetweenExercises: json['timeBetweenExercises'] ?? 120,
    userId: json['userId'],
    notes: json['notes'],
  );

  Workout copyWith({
    String? id,
    String? templateId,
    String? title,
    String? label,
    String? description,
    List<Exercise>? exercises,
    String? difficulty,
    String? equipment,
    int? timeBetweenExercises,
    String? userId,
    String? notes,
  }) => Workout(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    label: label ?? this.label,
    description: description ?? this.description,
    exercises: exercises ?? this.exercises,
    difficulty: difficulty ?? this.difficulty,
    equipment: equipment ?? this.equipment,
    timeBetweenExercises: timeBetweenExercises ?? this.timeBetweenExercises,
    userId: userId ?? this.userId,
    notes: notes ?? this.notes,
  );

  /// Creates an independent copy with a new UUID and deep-copied exercises.
  /// Use when adding to a session or starting a session.
  Workout deepCopy() => Workout(
    templateId: templateId ?? id,
    title: title,
    label: label,
    description: description,
    exercises: exercises.map((e) => e.deepCopy()).toList(),
    difficulty: difficulty,
    equipment: equipment,
    timeBetweenExercises: timeBetweenExercises,
    userId: userId,
    notes: notes,
  );
}
