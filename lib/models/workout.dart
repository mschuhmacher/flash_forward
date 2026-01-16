import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/exercise_instance.dart';
import 'package:uuid/uuid.dart';

class Workout {
  Workout({
    String? id,
    required this.title,
    this.subtitle,
    required this.label,
    this.description,
    this.date,
    required this.list,
    this.difficulty,
    this.equipment,
    required this.timeBetweenExercises,
    this.userId,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String title;
  final String? subtitle;
  final String label;
  final String? description;
  final DateTime? date;
  final List<ExerciseInstance> list;
  final String? difficulty;
  final String? equipment;
  final int timeBetweenExercises;
  final String? userId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'label': label,
    'description': description,
    'date': date?.toIso8601String(),
    'list': list.map((e) => e.toJson()).toList(),
    'difficulty': difficulty,
    'equipment': equipment,
    'timeBetweenExercises': timeBetweenExercises,
    'userId': userId,
  };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'],
    title: json['title'] ?? 'Untitled workout',
    subtitle: json['subtitle'],
    label: json['label'] ?? 'Other',
    description: json['description'],
    date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
    list:
        (json['list'] as List<dynamic>? ?? [])
            .map((e) => ExerciseInstance.fromJson(e))
            .toList(),
    difficulty: json['difficulty'],
    equipment: json['equipment'],
    timeBetweenExercises: json['timeBetweenExercises'] ?? 120,
    userId: json['userId'],
  );
}
