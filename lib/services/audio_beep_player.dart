import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:just_audio/just_audio.dart';

/// Plays beep sounds in-app using just_audio.
///
/// Three [AudioPlayer] instances are preloaded (one per [BeepType]) so playback
/// starts immediately without asset-loading latency. Call [init] once at app
/// start, [play] during sessions, and [dispose] on shutdown.
class AudioBeepPlayer {
  final _players = <BeepType, AudioPlayer>{};

  Future<void> init() async {
    for (final type in BeepType.values) {
      final player = AudioPlayer();
      final asset = switch (type) {
        BeepType.countdown => 'assets/sounds/countdown_beep.mp3',
        BeepType.go => 'assets/sounds/go_beep.mp3',
        BeepType.stop => 'assets/sounds/stop_beep.mp3',
      };
      await player.setAsset(asset);
      _players[type] = player;
    }
  }

  Future<void> play(BeepType type) async {
    final player = _players[type];
    if (player == null) return;
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
