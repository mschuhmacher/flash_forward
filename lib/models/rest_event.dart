enum RestType { getReady, setRest, exerciseRest, overtime, paused }

class RestEvent {
  final RestType restType;
  final int workoutIndex;
  final int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final DateTime endAt;
  final Duration plannedDuration;
  final Duration actualDuration;
  final Duration overtimeDuration;

  const RestEvent({
    required this.restType,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.endAt,
    required this.plannedDuration,
    required this.actualDuration,
    required this.overtimeDuration,
  });

  Map<String, dynamic> toJson() => {
        'restType': restType.name,
        'workoutIndex': workoutIndex,
        'exerciseIndex': exerciseIndex,
        'setIndex': setIndex,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'plannedDurationSeconds': plannedDuration.inSeconds,
        'actualDurationSeconds': actualDuration.inSeconds,
        'overtimeDurationSeconds': overtimeDuration.inSeconds,
      };

  factory RestEvent.fromJson(Map<String, dynamic> json) => RestEvent(
        restType: RestType.values.byName(json['restType'] as String),
        workoutIndex: json['workoutIndex'] as int,
        exerciseIndex: json['exerciseIndex'] as int,
        setIndex: json['setIndex'] as int?,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: DateTime.parse(json['endAt'] as String),
        plannedDuration: Duration(seconds: json['plannedDurationSeconds'] as int),
        actualDuration: Duration(seconds: json['actualDurationSeconds'] as int),
        overtimeDuration: Duration(seconds: json['overtimeDurationSeconds'] as int),
      );
}
