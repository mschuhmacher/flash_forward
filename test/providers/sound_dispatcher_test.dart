import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/providers/sound_dispatcher.dart';
import 'package:flash_forward/providers/settings_provider.dart' show SoundMode;
import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

// Lead times mirror the provider's constants. Fixtures keep prev/new
// remaining within ~100 ms of the thresholds, matching the 100 ms ticker —
// a larger gap would be unrealistic and could mask a regression.
const _audioLead = Duration(milliseconds: 300);
const _countdownLead = Duration(milliseconds: 400);
// Countdown threshold = 3s + countdownLead = 3400 ms.
const _countdownThreshold = Duration(milliseconds: 3400);

List<BeepType> _classify({
  required TimerPhase prevPhase,
  TimerPhase? newPhase,
  required Duration prevRemaining,
  required Duration newRemaining,
  bool playInApp = true,
}) =>
    SoundDispatcher.classifyTickEdge(
      prevPhase: prevPhase,
      newPhase: newPhase ?? prevPhase,
      prevRemaining: prevRemaining,
      newRemaining: newRemaining,
      playInApp: playInApp,
      audioLeadTime: _audioLead,
      countdownLeadTime: _countdownLead,
    );

void main() {
  group('shouldPlayInApp', () {
    test('true only when foregrounded and mode includes sounds', () {
      expect(
        SoundDispatcher.shouldPlayInApp(
          isForegrounded: true,
          mode: SoundMode.soundsOnly,
        ),
        isTrue,
      );
      expect(
        SoundDispatcher.shouldPlayInApp(
          isForegrounded: true,
          mode: SoundMode.both,
        ),
        isTrue,
      );
      expect(
        SoundDispatcher.shouldPlayInApp(
          isForegrounded: false,
          mode: SoundMode.both,
        ),
        isFalse,
      );
      expect(
        SoundDispatcher.shouldPlayInApp(
          isForegrounded: true,
          mode: SoundMode.notificationsOnly,
        ),
        isFalse,
      );
      expect(
        SoundDispatcher.shouldPlayInApp(
          isForegrounded: true,
          mode: SoundMode.none,
        ),
        isFalse,
      );
    });
  });

  group('shouldUseNotifications', () {
    test('true only when backgrounded, not paused, has session, mode allows',
        () {
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: false,
          hasActiveSession: true,
          mode: SoundMode.both,
        ),
        isTrue,
      );
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: false,
          hasActiveSession: true,
          mode: SoundMode.notificationsOnly,
        ),
        isTrue,
      );
      // Foregrounded → false.
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: true,
          isPaused: false,
          hasActiveSession: true,
          mode: SoundMode.both,
        ),
        isFalse,
      );
      // Paused → false.
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: true,
          hasActiveSession: true,
          mode: SoundMode.both,
        ),
        isFalse,
      );
      // No session → false.
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: false,
          hasActiveSession: false,
          mode: SoundMode.both,
        ),
        isFalse,
      );
      // soundsOnly / none → false.
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: false,
          hasActiveSession: true,
          mode: SoundMode.soundsOnly,
        ),
        isFalse,
      );
      expect(
        SoundDispatcher.shouldUseNotifications(
          isForegrounded: false,
          isPaused: false,
          hasActiveSession: true,
          mode: SoundMode.none,
        ),
        isFalse,
      );
    });
  });

  group('classifyTickEdge — countdown', () {
    for (final source in [
      TimerPhase.getReady,
      TimerPhase.setRest,
      TimerPhase.supersetRest,
    ]) {
      test('fires when crossing the threshold from $source', () {
        final beeps = _classify(
          prevPhase: source,
          prevRemaining: _countdownThreshold + const Duration(milliseconds: 50),
          newRemaining: _countdownThreshold - const Duration(milliseconds: 50),
        );
        expect(beeps, contains(BeepType.countdown));
      });
    }

    test('does not fire once remaining hits zero', () {
      final beeps = _classify(
        prevPhase: TimerPhase.setRest,
        prevRemaining: const Duration(milliseconds: 50),
        newRemaining: Duration.zero,
      );
      expect(beeps, isNot(contains(BeepType.countdown)));
    });

    test('does not fire from repRest (no countdown for inter-rep rest)', () {
      final beeps = _classify(
        prevPhase: TimerPhase.repRest,
        prevRemaining: _countdownThreshold + const Duration(milliseconds: 50),
        newRemaining: _countdownThreshold - const Duration(milliseconds: 50),
      );
      expect(beeps, isNot(contains(BeepType.countdown)));
    });
  });

  group('classifyTickEdge — go', () {
    for (final source in [
      TimerPhase.getReady,
      TimerPhase.setRest,
      TimerPhase.repRest,
      TimerPhase.supersetRest,
    ]) {
      test('fires when leaving $source within the audio lead window', () {
        final beeps = _classify(
          prevPhase: source,
          prevRemaining: _audioLead + const Duration(milliseconds: 50),
          newRemaining: _audioLead - const Duration(milliseconds: 50),
        );
        expect(beeps, contains(BeepType.go));
      });
    }
  });

  group('classifyTickEdge — stop', () {
    test('fires when still in rep and crossing the audio lead window', () {
      final beeps = _classify(
        prevPhase: TimerPhase.rep,
        newPhase: TimerPhase.rep,
        prevRemaining: _audioLead + const Duration(milliseconds: 50),
        newRemaining: _audioLead - const Duration(milliseconds: 50),
      );
      expect(beeps, [BeepType.stop]);
    });

    test('does not fire if the phase already left rep', () {
      final beeps = _classify(
        prevPhase: TimerPhase.rep,
        newPhase: TimerPhase.repRest,
        prevRemaining: _audioLead + const Duration(milliseconds: 50),
        newRemaining: _audioLead - const Duration(milliseconds: 50),
      );
      expect(beeps, isNot(contains(BeepType.stop)));
    });
  });

  group('classifyTickEdge — combinations & empties', () {
    test('countdown AND go can both fire on a single tick', () {
      // A long-isolated tick on a short getReady crosses both windows at once:
      // prev above the countdown threshold, new below the audio lead.
      final beeps = _classify(
        prevPhase: TimerPhase.getReady,
        prevRemaining: _countdownThreshold + const Duration(milliseconds: 50),
        newRemaining: _audioLead - const Duration(milliseconds: 50),
      );
      expect(beeps, [BeepType.countdown, BeepType.go]);
    });

    test('empty when playInApp is false', () {
      final beeps = _classify(
        prevPhase: TimerPhase.getReady,
        prevRemaining: _countdownThreshold + const Duration(milliseconds: 50),
        newRemaining: _audioLead - const Duration(milliseconds: 50),
        playInApp: false,
      );
      expect(beeps, isEmpty);
    });

    test('empty mid-rep when no window is crossed', () {
      final beeps = _classify(
        prevPhase: TimerPhase.rep,
        newPhase: TimerPhase.rep,
        prevRemaining: const Duration(seconds: 10),
        newRemaining: const Duration(milliseconds: 9900),
      );
      expect(beeps, isEmpty);
    });
  });
}
