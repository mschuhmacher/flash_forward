// A deleted item held in the trash, preserving its kind and deletion timestamp.
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';

enum TrashKind { session, workout, exercise }

class TrashEntry {
  TrashEntry._({required this.kind, required this.payload, required this.deletedAt});

  factory TrashEntry.session({required Session session, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.session, payload: session, deletedAt: deletedAt);

  factory TrashEntry.workout({required Workout workout, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.workout, payload: workout, deletedAt: deletedAt);

  factory TrashEntry.exercise({required Exercise exercise, required DateTime deletedAt}) =>
      TrashEntry._(kind: TrashKind.exercise, payload: exercise, deletedAt: deletedAt);

  final TrashKind kind;
  final Object payload;
  final DateTime deletedAt;

  String get id => switch (kind) {
        TrashKind.session => (payload as Session).id,
        TrashKind.workout => (payload as Workout).id,
        TrashKind.exercise => (payload as Exercise).id,
      };

  /// The default id this entry suppresses, if it is a fork of a default.
  /// Forking a default sets `templateId = <default slug>`; for a plain user
  /// item (no templateId) this is just the item's own id. Used by the catalog
  /// to keep a deleted default hidden even though the entry's id is a fresh UUID.
  String get shadowId => switch (kind) {
        TrashKind.session => (payload as Session).templateId ?? id,
        TrashKind.workout => (payload as Workout).templateId ?? id,
        TrashKind.exercise => (payload as Exercise).templateId ?? id,
      };

  String get title => switch (kind) {
        TrashKind.session => (payload as Session).title,
        TrashKind.workout => (payload as Workout).title,
        TrashKind.exercise => (payload as Exercise).title,
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'deletedAt': deletedAt.toIso8601String(),
        'payload': switch (kind) {
          TrashKind.session => (payload as Session).toJson(),
          TrashKind.workout => (payload as Workout).toJson(),
          TrashKind.exercise => (payload as Exercise).toJson(),
        },
      };

  factory TrashEntry.fromJson(Map<String, dynamic> json) {
    final kind = TrashKind.values.byName(json['kind'] as String);
    final deletedAt = DateTime.parse(json['deletedAt'] as String);
    final p = json['payload'] as Map<String, dynamic>;
    return switch (kind) {
      TrashKind.session =>
        TrashEntry.session(session: Session.fromJson(p), deletedAt: deletedAt),
      TrashKind.workout =>
        TrashEntry.workout(workout: Workout.fromJson(p), deletedAt: deletedAt),
      TrashKind.exercise =>
        TrashEntry.exercise(exercise: Exercise.fromJson(p), deletedAt: deletedAt),
    };
  }
}
