class SetEvent {
  final int workoutIndex;
  final int exerciseIndex;
  final int setIndex;
  final DateTime startAt;
  final DateTime endAt;
  final Duration activeTime;
  final Duration interRepRestTime;
  final int repsCompleted;

  SetEvent({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.endAt,
    required this.activeTime,
    required this.interRepRestTime,
    required this.repsCompleted,
  });

  Map<String, dynamic> toJson() => {
        'workoutIndex': workoutIndex,
        'exerciseIndex': exerciseIndex,
        'setIndex': setIndex,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'activeTimeSeconds': activeTime.inSeconds,
        'interRepRestTimeSeconds': interRepRestTime.inSeconds,
        'repsCompleted': repsCompleted,
      };

  factory SetEvent.fromJson(Map<String, dynamic> json) => SetEvent(
        workoutIndex: json['workoutIndex'] as int,
        exerciseIndex: json['exerciseIndex'] as int,
        setIndex: json['setIndex'] as int,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: DateTime.parse(json['endAt'] as String),
        activeTime: Duration(seconds: json['activeTimeSeconds'] as int),
        interRepRestTime: Duration(seconds: json['interRepRestTimeSeconds'] as int),
        repsCompleted: json['repsCompleted'] as int,
      );

}
