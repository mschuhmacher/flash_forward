import 'package:uuid/uuid.dart';

class SupersetConfig {
  final String id;
  final List<String> exerciseIds;
  final int restSeconds;
  final int? supersetSets;

  SupersetConfig({
    String? id,
    required this.exerciseIds,
    this.restSeconds = 15,
    this.supersetSets,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseIds': exerciseIds,
        'restSeconds': restSeconds,
        'supersetSets': supersetSets,
      };

  factory SupersetConfig.fromJson(Map<String, dynamic> json) => SupersetConfig(
        id: json['id'] as String?,
        exerciseIds: List<String>.from(json['exerciseIds'] as List),
        restSeconds: json['restSeconds'] as int? ?? 15,
        supersetSets: json['supersetSets'] as int?,
      );

  SupersetConfig copyWith({
    String? id,
    List<String>? exerciseIds,
    int? restSeconds,
    int? supersetSets,
  }) =>
      SupersetConfig(
        id: id ?? this.id,
        exerciseIds: exerciseIds ?? this.exerciseIds,
        restSeconds: restSeconds ?? this.restSeconds,
        supersetSets: supersetSets ?? this.supersetSets,
      );
}
