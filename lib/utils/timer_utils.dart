/// Formats an elapsed/count-up duration as `mm:ss` (floor seconds).
/// Use for stopwatches, overtime, and anything counting up from zero —
/// `0ms` reads as `00:00`, `1500ms` as `00:01`.
String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Formats a countdown duration as `mm:ss` (ceiling seconds), so the
/// displayed value matches the bucket the time falls into. A 7-second
/// phase shows `00:07` for ~1s, then `00:06` for ~1s, etc. — instead of
/// the floor behavior where `00:07` would flash for one tick and `00:00`
/// would sit visible for a full second before the phase ends.
String formatCountdown(Duration d) {
  if (d <= Duration.zero) return '00:00';
  final totalSeconds = (d.inMilliseconds / 1000).ceil();
  final minutes = ((totalSeconds ~/ 60) % 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}