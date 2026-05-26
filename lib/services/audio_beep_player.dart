import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:just_audio/just_audio.dart';

/// Plays beep sounds in-app using just_audio.
///
/// Three [AudioPlayer] instances are preloaded (one per [BeepType]) so playback
/// starts immediately without asset-loading latency. Call [init] once at app
/// start, [play] during sessions, and [dispose] on shutdown.
class AudioBeepPlayer {
  final _players = <BeepType, AudioPlayer>{};
  AudioSession? _audioSession;
  // Delays deactivation so back-to-back beeps (countdown → go, gap ~100 ms)
  // don't cause background audio to pop to full volume between them.
  Timer? _deactivationTimer;
  static const Duration _deactivationDelay = Duration(milliseconds: 300);

  Future<void> init() async {
    // Duck background audio (e.g. Spotify) while a beep plays rather than
    // interrupting it. On iOS: AVAudioSessionCategoryPlayback + .duckOthers.
    // On Android: AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK. Both platforms restore
    // the other app's volume automatically when the beep finishes.
    // Note: this only applies to foreground (in-app) playback. When the app is
    // backgrounded, beeps are delivered as OS notification sounds via
    // BeepScheduler, which bypasses AVAudioSession entirely — those will
    // interrupt background audio. This is an OS-level constraint on both
    // iOS and Android and is acceptable UX (user has locked their phone).
    _audioSession = await AudioSession.instance;
    await _audioSession!.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.assistanceSonification,
        flags: AndroidAudioFlags.none,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));

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
    // Cancel any pending deactivation from a previous beep so the session
    // stays active across the countdown → go cluster. Activate (no-op if
    // already active), then play and schedule deactivation _deactivationDelay
    // after the audio finishes. If another beep starts in that window, the
    // timer is cancelled and the cluster continues uninterrupted.
    // notifyOthersOnDeactivation tells iOS to signal other apps that they can
    // resume full volume immediately when we finally deactivate.
    _deactivationTimer?.cancel();
    await _audioSession?.setActive(true);
    await player.seek(Duration.zero);
    await player.play();
    await player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
    _deactivationTimer = Timer(_deactivationDelay, () async {
      await _audioSession?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    });
  }

  Future<void> dispose() async {
    _deactivationTimer?.cancel();
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
