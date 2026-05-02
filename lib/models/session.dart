import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/utils/nullable.dart';
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
    this.maxGradeClimbed,
    this.maxGradeFlashed,
    this.bodyWeightKg,
    this.setEvents,
    this.restEvents,
    this.summary,
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
  final GradeEntry? maxGradeClimbed;
  final GradeEntry? maxGradeFlashed;
  final double? bodyWeightKg;
  final List<SetEvent>? setEvents;
  final List<RestEvent>? restEvents;
  final SessionSummary? summary;

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
    'maxGradeClimbed': maxGradeClimbed?.toJson(),
    'maxGradeFlashed': maxGradeFlashed?.toJson(),
    'bodyWeightKg': bodyWeightKg,
    'setEvents': setEvents?.map((s) => s.toJson()).toList(),
    'restEvents': restEvents?.map((r) => r.toJson()).toList(),
    'summary': summary?.toJson(),
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] ?? const Uuid().v4(),
    templateId: json['templateId'],
    title: json['title'] ?? 'Untitled session',
    label: json['label'] ?? 'Other',
    description: json['description'],
    // Backward-compatible: handle old 'date' key
    completedAt:
        (json['completedAt'] ?? json['date']) != null
            ? DateTime.tryParse(json['completedAt'] ?? json['date'])
            : null,
    // Backward-compatible: handle old 'list' key
    workouts:
        ((json['workouts'] ?? json['list']) as List<dynamic>? ?? [])
            .map((w) => Workout.fromJson(w as Map<String, dynamic>))
            .toList(),
    userId: json['userId'],
    notes: json['notes'],
    rpe: json['rpe'],
    maxGradeClimbed:
        json['maxGradeClimbed'] != null
            ? GradeEntry.fromJson(
              json['maxGradeClimbed'] as Map<String, dynamic>,
            )
            : null,
    maxGradeFlashed:
        json['maxGradeFlashed'] != null
            ? GradeEntry.fromJson(
              json['maxGradeFlashed'] as Map<String, dynamic>,
            )
            : null,
    bodyWeightKg: (json['bodyWeightKg'] as num?)?.toDouble(),
    setEvents: (json['setEvents'] as List<dynamic>?)
        ?.map((e) => SetEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    restEvents: (json['restEvents'] as List<dynamic>?)
        ?.map((e) => RestEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    summary: json['summary'] != null
        ? SessionSummary.fromJson(json['summary'] as Map<String, dynamic>)
        : null,
  );

  // Nullable<T> parameters let callers distinguish "not provided" (omit the
  // argument → keep the current value) from "explicitly set to null"
  // (pass Nullable(null) → clear the field). A plain `T? param` cannot express
  // this because `param ?? this.field` treats both cases identically.
  Session copyWith({
    String? id,
    String? templateId,
    String? title,
    String? label,
    Nullable<String>? description,
    Nullable<DateTime>? completedAt,
    List<Workout>? workouts,
    String? userId,
    Nullable<String>? notes,
    Nullable<int>? rpe,
    Nullable<GradeEntry>? maxGradeClimbed,
    Nullable<GradeEntry>? maxGradeFlashed,
    Nullable<double>? bodyWeightKg,
    List<SetEvent>? setEvents,
    List<RestEvent>? restEvents,
    SessionSummary? summary,
  }) => Session(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    title: title ?? this.title,
    label: label ?? this.label,
    description: description == null ? this.description : description.value,
    completedAt: completedAt == null ? this.completedAt : completedAt.value,
    workouts: workouts ?? this.workouts,
    userId: userId ?? this.userId,
    notes: notes == null ? this.notes : notes.value,
    rpe: rpe == null ? this.rpe : rpe.value,
    maxGradeClimbed:
        maxGradeClimbed == null ? this.maxGradeClimbed : maxGradeClimbed.value,
    maxGradeFlashed:
        maxGradeFlashed == null ? this.maxGradeFlashed : maxGradeFlashed.value,
    bodyWeightKg: bodyWeightKg == null ? this.bodyWeightKg : bodyWeightKg.value,
    setEvents: setEvents ?? this.setEvents,
    restEvents: restEvents ?? this.restEvents,
    summary: summary ?? this.summary,
  );

  /// Creates an independent copy with deep-copied workouts (and their exercises).
  /// With [keepId] = false (default), generates a fresh UUID and sets
  /// [templateId] as a breadcrumb — use when starting a session from a template.
  /// With [keepId] = true, preserves the original id so saves target the correct
  /// catalog row — use when opening a session template in an edit screen.
  /// Completion fields (grades, events, summary) are always omitted; they are
  /// set post-run and are never part of the template.
  Session deepCopy({bool keepId = false}) => Session(
    id: keepId ? id : null,
    templateId: keepId ? templateId : (templateId ?? id),
    title: title,
    label: label,
    description: description,
    workouts: workouts.map((w) => w.deepCopy(keepId: keepId)).toList(),
    userId: userId,
  );
}
