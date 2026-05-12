import 'package:uuid/uuid.dart';

class SupersetConfig {
  final String id;
  final List<String> exerciseIds;
  /// Rest between exercises in the same round (intra-round). Short pause to
  /// switch equipment.
  final int restSeconds;
  /// Number of sets the whole superset cycles through. Overrides each
  /// member's `Exercise.sets` while the exercise is in the superset.
  final int? supersetSets;
  /// Rest between rounds of the superset. The state machine routes this
  /// onto `exerciseRest` when the user finishes a round and the group
  /// cycles back to its first member.
  final int? supersetSetRest;

  SupersetConfig({
    String? id,
    required this.exerciseIds,
    this.restSeconds = 15,
    this.supersetSets,
    this.supersetSetRest,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseIds': exerciseIds,
        'restSeconds': restSeconds,
        'supersetSets': supersetSets,
        'supersetSetRest': supersetSetRest,
      };

  factory SupersetConfig.fromJson(Map<String, dynamic> json) => SupersetConfig(
        id: json['id'] as String?,
        exerciseIds: List<String>.from(json['exerciseIds'] as List),
        restSeconds: json['restSeconds'] as int? ?? 15,
        supersetSets: json['supersetSets'] as int?,
        supersetSetRest: json['supersetSetRest'] as int?,
      );

  SupersetConfig copyWith({
    String? id,
    List<String>? exerciseIds,
    int? restSeconds,
    int? supersetSets,
    int? supersetSetRest,
  }) =>
      SupersetConfig(
        id: id ?? this.id,
        exerciseIds: exerciseIds ?? this.exerciseIds,
        restSeconds: restSeconds ?? this.restSeconds,
        supersetSets: supersetSets ?? this.supersetSets,
        supersetSetRest: supersetSetRest ?? this.supersetSetRest,
      );
}
