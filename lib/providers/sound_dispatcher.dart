import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/session_progress.dart';
import 'package:flash_forward/providers/session_state_machine.dart';
import 'package:flash_forward/providers/settings_provider.dart' show SoundMode;
import 'package:flash_forward/services/audio_beep_player.dart';
import 'package:flash_forward/services/beep_scheduler.dart';

/// Decides what to beep and when, given timer state.
///
/// Two responsibilities:
/// - **Background notifications** (`reschedule`): simulates the remaining
///   session and schedules OS-level beep notifications via [BeepScheduler].
/// - **In-app beeps** (`classifyTickEdge`): on each ticker boundary, decides
///   which beeps the foreground player should fire *right now*.
///
/// Holds the injected [BeepScheduler] / [AudioBeepPlayer] for convenience but
/// does not own their lifecycles — the provider wires those in and disposes
/// them. Session progress is never stored; the caller passes it in.
class SoundDispatcher {
  BeepScheduler? _scheduler;
  AudioBeepPlayer? _player;

  void setScheduler(BeepScheduler scheduler) => _scheduler = scheduler;
  void setPlayer(AudioBeepPlayer player) => _player = player;

  BeepScheduler? get scheduler => _scheduler;
  AudioBeepPlayer? get player => _player;

  /// True when in-app audio should play, given foreground state and mode.
  static bool shouldPlayInApp({
    required bool isForegrounded,
    required SoundMode mode,
  }) =>
      isForegrounded &&
      (mode == SoundMode.soundsOnly || mode == SoundMode.both);

  /// True when OS-level notifications should be scheduled, given foreground
  /// state, pause state, session presence, and mode.
  static bool shouldUseNotifications({
    required bool isForegrounded,
    required bool isPaused,
    required bool hasActiveSession,
    required SoundMode mode,
  }) =>
      !isForegrounded &&
      !isPaused &&
      hasActiveSession &&
      (mode == SoundMode.both || mode == SoundMode.notificationsOnly);

  /// Cancels or reschedules OS notifications based on the current sound mode
  /// and foreground state. In-app audio is driven directly by the ticker via
  /// [classifyTickEdge] and does not need scheduling here.
  void reschedule({
    required bool isForegrounded,
    required bool isPaused,
    required SessionProgress progress,
    required Duration remaining,
    required Session? activeSession,
    required SoundMode mode,
    required bool restOvertimeOnBackground,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    final useNotifications = shouldUseNotifications(
      isForegrounded: isForegrounded,
      isPaused: isPaused,
      hasActiveSession: activeSession != null,
      mode: mode,
    );
    if (useNotifications && _scheduler != null) {
      _scheduler!.scheduleAll(
        _calculateFutureBeeps(
          progress: progress,
          remaining: remaining,
          activeSession: activeSession!,
          restOvertimeOnBackground: restOvertimeOnBackground,
          audioLeadTime: audioLeadTime,
          countdownLeadTime: countdownLeadTime,
        ),
      );
    } else {
      _scheduler?.cancelAll();
    }
  }

  /// Simulates the remaining state machine from the current position and
  /// returns a chronological list of beeps to schedule. Stops at
  /// [BeepScheduler.maxBeeps] entries (iOS limit) or when a manual rep phase
  /// is reached (unknown duration).
  List<ScheduledBeep> _calculateFutureBeeps({
    required SessionProgress progress,
    required Duration remaining,
    required Session activeSession,
    required bool restOvertimeOnBackground,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    final beeps = <ScheduledBeep>[];
    var simProgress = progress;
    var phaseEndAt = DateTime.now().add(remaining);

    while (true) {
      _addBeepsForPhase(
        beeps,
        simProgress,
        phaseEndAt,
        audioLeadTime,
        countdownLeadTime,
      );
      if (beeps.length >= BeepScheduler.maxBeeps) break;

      final next =
          SessionStateMachine.calculateNextState(simProgress, activeSession);
      if (next == null) break;

      if (restOvertimeOnBackground &&
          (simProgress.phase == TimerPhase.setRest ||
              simProgress.phase == TimerPhase.exerciseRest)) {
        break;
      }

      // Manual rep phase: duration unknown — cannot predict further.
      final exercise = activeSession
          .workouts[next.workoutIndex].exercises[next.exerciseIndex];
      if (exercise.type == ExerciseType.manual &&
          next.phase == TimerPhase.rep) {
        break;
      }

      phaseEndAt = phaseEndAt
          .add(SessionStateMachine.getDurationForPhase(next, activeSession));
      simProgress = next;
    }

    return beeps;
  }

  void _addBeepsForPhase(
    List<ScheduledBeep> beeps,
    SessionProgress p,
    DateTime phaseEndAt,
    Duration audioLeadTime,
    Duration countdownLeadTime,
  ) {
    final now = DateTime.now();
    switch (p.phase) {
      case TimerPhase.rep:
        // Stop beep fires audioLeadTime before the rep ends.
        final stopAt = phaseEndAt.subtract(audioLeadTime);
        if (stopAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: stopAt, type: BeepType.stop));
        }
      case TimerPhase.getReady:
      case TimerPhase.setRest:
      case TimerPhase.supersetRest:
        // Countdown at 3 s + countdownLeadTime before phase end so the "3"
        // beep aligns with 3 s remaining. Go beep audioLeadTime before end.
        // repRest intentionally excluded — no countdown for inter-rep rests.
        final countdownAt = phaseEndAt.subtract(
          const Duration(seconds: 3) + countdownLeadTime,
        );
        if (countdownAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: countdownAt, type: BeepType.countdown));
        }
        final goAt = phaseEndAt.subtract(audioLeadTime);
        if (goAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: goAt, type: BeepType.go));
        }
      case TimerPhase.repRest:
        // No countdown for inter-rep rests; go beep audioLeadTime before end.
        final goAt = phaseEndAt.subtract(audioLeadTime);
        if (goAt.isAfter(now)) {
          beeps.add(ScheduledBeep(at: goAt, type: BeepType.go));
        }
      default:
        break; // exerciseRest, workoutComplete, paused, overtime: no beeps
    }
  }

  /// Classifies the in-app beeps that should fire on this tick boundary.
  /// Returns a (possibly empty) list — countdown and go can BOTH fire on the
  /// same tick when the windows overlap (e.g. after an isolate suspension on a
  /// short getReady). Stop-beep is mutually exclusive with the other two by
  /// phase predicate. The caller plays each entry in order.
  ///
  /// Source phases for countdown and go include `supersetRest`, matching the
  /// ticker behaviour after supersets shipped.
  static List<BeepType> classifyTickEdge({
    required TimerPhase prevPhase,
    required TimerPhase newPhase,
    required Duration prevRemaining,
    required Duration newRemaining,
    required bool playInApp,
    required Duration audioLeadTime,
    required Duration countdownLeadTime,
  }) {
    if (!playInApp) return const [];

    final beeps = <BeepType>[];
    final countdownThreshold = const Duration(seconds: 3) + countdownLeadTime;

    // Countdown: crossing the threshold during getReady/setRest/supersetRest.
    if ((prevPhase == TimerPhase.getReady ||
            prevPhase == TimerPhase.setRest ||
            prevPhase == TimerPhase.supersetRest) &&
        prevRemaining > countdownThreshold &&
        newRemaining <= countdownThreshold &&
        newRemaining > Duration.zero) {
      beeps.add(BeepType.countdown);
    }

    // Go beep: leaving any lead-in phase with <= audioLeadTime remaining.
    if ((prevPhase == TimerPhase.getReady ||
            prevPhase == TimerPhase.setRest ||
            prevPhase == TimerPhase.repRest ||
            prevPhase == TimerPhase.supersetRest) &&
        prevRemaining > audioLeadTime &&
        newRemaining <= audioLeadTime) {
      beeps.add(BeepType.go);
    }

    // Stop beep: still in rep, about to end. Mutually exclusive with the above
    // by phase predicate (prevPhase != rep above; prevPhase == rep here).
    if (prevPhase == TimerPhase.rep &&
        newPhase == TimerPhase.rep &&
        prevRemaining > audioLeadTime &&
        newRemaining <= audioLeadTime) {
      beeps.add(BeepType.stop);
    }

    return beeps;
  }

  /// Cancels all scheduled notifications. Convenience for the provider's
  /// reset/finalize/complete paths.
  void cancelAll() => _scheduler?.cancelAll();

  Future<bool> canScheduleExactAlarms() =>
      _scheduler?.canScheduleExactAlarms() ?? Future.value(true);

  Future<void> requestExactAlarmPermission() =>
      _scheduler?.requestExactAlarmPermission() ?? Future.value();
}
