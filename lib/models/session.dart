import 'package:flash_forward/models/workout.dart';
import 'package:uuid/uuid.dart';

class Session {
  Session({
    String? id,
    this.templateId,
    required this.title,
    required this.label,
    this.description,
    this.completedAt,
    required this.workouts,
    this.userId,
    this.notes,
    this.rpe,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String? templateId;
  final String title;
  final String label;
  final String? description;
  final DateTime? completedAt;
  final List<Workout> workouts;
  final String? userId;
  final String? notes;
  final int? rpe;

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'title': title,
    'label': label,
    'description': description,
    'completedAt': completedAt?.toIso8601String(),
    'workouts': workouts.map((w) => w.toJson()).toList(),
    'userId': userId,
    'notes': notes,
    'rpe': rpe,
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] ?? const Uuid().v4(),
    templateId: json['templateId'],
    title: json['title'] ?? 'Untitled session',
    label: json['label'] ?? 'Other',
    description: json['description'],
    // Backward-compatible: handle old 'date' key
    completedAt: (json['completedAt'] ?? json['date']) != null
        ? DateTime.tryParse(json['completedAt'] ?? json['date'])
        : null,
    // Backward-compatible: handle old 'list' key
    workouts: ((json['workouts'] ?? json['list']) as List<dynamic>? ?? [])
        .map((w) => Workout.fromJson(w as Map<String, dynamic>))
        .toList(),
    userId: json['userId'],
    notes: json['notes'],
    rpe: json['rpe'],
  );

  Session copyWith({
    String? id,
    String? templateId,
    String? title,
    String? label,
    String? description,
    DateTime? completedAt,
    List<Workout>? workouts,
    String? userId,
    String? notes,
    int? rpe,
  }) => Session(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    label: label ?? this.label,
    description: description ?? this.description,
    completedAt: completedAt ?? this.completedAt,
    workouts: workouts ?? this.workouts,
    userId: userId ?? this.userId,
    notes: notes ?? this.notes,
    rpe: rpe ?? this.rpe,
  );

  /// Creates an independent copy with a new UUID and deep-copied workouts.
  /// Call this when starting a session so the preset is never mutated.
  Session deepCopy() => Session(
    templateId: templateId ?? id,
    title: title,
    label: label,
    description: description,
    workouts: workouts.map((w) => w.deepCopy()).toList(),
    userId: userId,
  );
}
