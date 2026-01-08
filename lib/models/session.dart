import 'package:flash_forward/models/workout.dart';
import 'package:uuid/uuid.dart';

class Session {
  Session({
    String? id,
    required this.title,
    required this.label,
    this.subtitle,
    this.description,
    this.date,
    required this.list,
  }) : id = id ?? Uuid().v4();
  // ?? is null-coalescing operator, provides a default value if null. If id is null, then assign new id. If not null, then use existing id.
  // so, if left-hand value is null, use right-hand value

  final String id;
  final String title;
  final String label;
  final String? subtitle;
  final String? description;
  final DateTime? date;
  final List<Workout> list;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'label': label,
    'subtitle': subtitle,
    'description': description,
    'date': date?.toIso8601String(),
    'list': list.map((b) => b.toJson()).toList(),
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] ?? const Uuid().v4(),
    title: json['title'] ?? 'Untitled session',
    label: json['label'] ?? 'No label provided',
    subtitle: json['subtitle'] ?? 'No subtitle provided',
    description: json['description'] ?? 'No description provided',
    date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
    list:
        (json['list'] as List<dynamic>? ?? [])
            .map((b) => Workout.fromJson(b))
            .toList(),
  );
}
