class SessionSummary {
  final Duration totalTime;
  final Duration activeTime;
  final Duration interRepRestTime;
  final Duration setRestTime;
  final Duration supersetRestTime;
  final Duration exerciseRestTime;
  final Duration getReadyTime;
  final Duration overtime;
  final Duration pausedTime;

  const SessionSummary({
    required this.totalTime,
    required this.activeTime,
    required this.interRepRestTime,
    required this.setRestTime,
    this.supersetRestTime = Duration.zero,
    required this.exerciseRestTime,
    required this.getReadyTime,
    required this.overtime,
    required this.pausedTime,
  });

  Map<String, dynamic> toJson() => {
        'totalTimeSeconds': totalTime.inSeconds,
        'activeTimeSeconds': activeTime.inSeconds,
        'interRepRestTimeSeconds': interRepRestTime.inSeconds,
        'setRestTimeSeconds': setRestTime.inSeconds,
        'supersetRestTimeSeconds': supersetRestTime.inSeconds,
        'exerciseRestTimeSeconds': exerciseRestTime.inSeconds,
        'getReadyTimeSeconds': getReadyTime.inSeconds,
        'overtimeSeconds': overtime.inSeconds,
        'pausedTimeSeconds': pausedTime.inSeconds,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        totalTime: Duration(seconds: json['totalTimeSeconds'] as int),
        activeTime: Duration(seconds: json['activeTimeSeconds'] as int),
        interRepRestTime: Duration(seconds: json['interRepRestTimeSeconds'] as int),
        setRestTime: Duration(seconds: json['setRestTimeSeconds'] as int),
        supersetRestTime:
            Duration(seconds: json['supersetRestTimeSeconds'] as int? ?? 0),
        exerciseRestTime: Duration(seconds: json['exerciseRestTimeSeconds'] as int),
        getReadyTime: Duration(seconds: json['getReadyTimeSeconds'] as int),
        overtime: Duration(seconds: json['overtimeSeconds'] as int),
        pausedTime: Duration(seconds: json['pausedTimeSeconds'] as int),
      );
}
