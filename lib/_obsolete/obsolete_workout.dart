import 'package:flash_forward/_obsolete/obsolete_exercise.dart';
import 'package:uuid/uuid.dart';

class WorkoutObsolete {
  WorkoutObsolete({
    String? id,
    required this.title,
    this.subtitle,
    this.label,
    this.description,
    this.date,
    required this.list,
  }) : id = id ?? Uuid().v4();

  final String id;
  final String title;
  final String? subtitle;
  final String? label;
  final String? description;
  final DateTime? date;
  final List<ExerciseObsolete> list;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'label': label,
    'description': description,
    'date': date?.toIso8601String(),
    'list': list.map((e) => e.toJson()).toList(),
  };

  factory WorkoutObsolete.fromJson(Map<String, dynamic> json) =>
      WorkoutObsolete(
        id: json['id'],
        title: json['title'] ?? 'Untitled workout',
        subtitle: json['subtitle'],
        label: json['label'],
        description: json['description'],
        date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
        list:
            (json['list'] as List<dynamic>? ?? [])
                .map((e) => ExerciseObsolete.fromJson(e))
                .toList(),
      );
}
