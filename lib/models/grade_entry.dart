enum GradeSystem { vscale, fontainebleau }

/// A climbing grade tagged with its scale system, so historical entries are
/// never ambiguous if the user's grade system preference later changes.
class GradeEntry {
  const GradeEntry({required this.system, required this.gradeIndex});

  final GradeSystem system;

  /// For V-scale: integer 0–17, displayed as 'V$gradeIndex'.
  /// For Fontainebleau: index into [kFontScale] (0='4' … 21='9A').
  final int gradeIndex;

  Map<String, dynamic> toJson() => {
    'system': system.name,
    'gradeIndex': gradeIndex,
  };

  factory GradeEntry.fromJson(Map<String, dynamic> json) => GradeEntry(
    system: GradeSystem.values.byName(json['system'] as String),
    gradeIndex: json['gradeIndex'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is GradeEntry &&
      other.system == system &&
      other.gradeIndex == gradeIndex;

  @override
  int get hashCode => Object.hash(system, gradeIndex);
}
