import 'package:flash_forward/models/rest_event.dart';
import 'package:flash_forward/models/session_summary.dart';
import 'package:flash_forward/models/set_event.dart';
import 'package:flash_forward/features/session_active/session_progress.dart';

/// Records set and rest events during one active session.
///
/// Owned by [SessionStateProvider] as a single `final` field, cleared on
/// `start()` and `reset()`. Stateful but bounded: the only state is the
/// in-progress drafts, the per-set accumulators, the phase clock, and the
/// accumulated event lists — nothing leaks across session runs.
///
/// The provider drives it from `_onPhaseTransition` (open/close set & rest,
/// attribute time slices) and reads it back at `finalizeSession`
/// (`setEvents` / `restEvents` / `computeSummary`). The *decision* of how long
/// a rest was planned to last stays on the provider (it needs the active
/// session); this class only stores what it's handed.
class SessionTelemetryRecorder {
  final List<SetEvent> _setEvents = [];
  final List<RestEvent> _restEvents = [];

  // In-progress drafts. Null when no set/rest is currently open.
  _OpenSetDraft? _activeSetDraft;
  _OpenRestDraft? _activeRestDraft;

  // Wall-clock time the current phase was entered, for slice attribution.
  DateTime? _currentPhaseEnteredAt;

  // Per-set accumulators — reset when a new set opens.
  Duration _currentSetActiveAccum = Duration.zero;
  Duration _currentSetRepRestAccum = Duration.zero;

  /// Read-only views of the recorded events.
  List<SetEvent> get setEvents => List.unmodifiable(_setEvents);
  List<RestEvent> get restEvents => List.unmodifiable(_restEvents);

  /// Debug seams mirroring the provider's `@visibleForTesting` getters.
  int get restEventCount => _restEvents.length;
  List<RestType> get restEventTypes =>
      _restEvents.map((e) => e.restType).toList();

  /// Stamps the start of slice timing for the current phase. Called when the
  /// first phase opens (session start).
  void beginPhase() {
    _currentPhaseEnteredAt = DateTime.now();
  }

  /// Attributes the time spent in the [from] phase to the right set-level
  /// accumulator, then re-stamps the phase clock. Only `rep` and `repRest`
  /// contribute to set telemetry. No-op before the first [beginPhase].
  void attributeSliceOnExit(TimerPhase from) {
    if (_currentPhaseEnteredAt == null) return;
    final slice = DateTime.now().difference(_currentPhaseEnteredAt!);
    if (from == TimerPhase.rep) _currentSetActiveAccum += slice;
    if (from == TimerPhase.repRest) _currentSetRepRestAccum += slice;
    _currentPhaseEnteredAt = DateTime.now();
  }

  /// Opens a new set draft at [p] and resets the per-set accumulators.
  void openSet(SessionProgress p) {
    _activeSetDraft = _OpenSetDraft(
      workoutIndex: p.workoutIndex,
      exerciseIndex: p.exerciseIndex,
      setIndex: p.currentSet,
      startAt: DateTime.now(),
    );
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  /// Closes the open set draft into a [SetEvent]. No-op if none is open.
  void closeSet({required int repsCompleted}) {
    if (_activeSetDraft == null) return;

    _setEvents.add(
      SetEvent(
        workoutIndex: _activeSetDraft!.workoutIndex,
        exerciseIndex: _activeSetDraft!.exerciseIndex,
        setIndex: _activeSetDraft!.setIndex,
        startAt: _activeSetDraft!.startAt,
        endAt: DateTime.now(),
        activeTime: _currentSetActiveAccum,
        interRepRestTime: _currentSetRepRestAccum,
        repsCompleted: repsCompleted,
      ),
    );
    _activeSetDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
  }

  /// Opens a new rest draft for [restType] at [progress]. [plannedDuration] is
  /// the duration the rest was scheduled to run (the provider computes this,
  /// passing `Duration.zero` for overtime/paused). The set index is recorded
  /// only for `setRest`.
  void openRest({
    required RestType restType,
    required SessionProgress progress,
    required Duration plannedDuration,
  }) {
    int? setIndex;
    if (restType == RestType.setRest) {
      setIndex = progress.currentSet;
    }

    _activeRestDraft = _OpenRestDraft(
      restType: restType,
      workoutIndex: progress.workoutIndex,
      exerciseIndex: progress.exerciseIndex,
      setIndex: setIndex,
      startAt: DateTime.now(),
      plannedDuration: plannedDuration,
    );
  }

  /// Closes the open rest draft into a [RestEvent]. No-op if none is open.
  void closeRest() {
    if (_activeRestDraft == null) return;

    final actual = DateTime.now().difference(_activeRestDraft!.startAt);
    final overtimeDuration =
        _activeRestDraft!.restType == RestType.overtime ? actual : Duration.zero;

    _restEvents.add(
      RestEvent(
        restType: _activeRestDraft!.restType,
        workoutIndex: _activeRestDraft!.workoutIndex,
        exerciseIndex: _activeRestDraft!.exerciseIndex,
        setIndex: _activeRestDraft!.setIndex,
        startAt: _activeRestDraft!.startAt,
        endAt: DateTime.now(),
        plannedDuration: _activeRestDraft!.plannedDuration,
        actualDuration: actual,
        overtimeDuration: overtimeDuration,
      ),
    );

    _activeRestDraft = null;
  }

  /// Rewrites the open drafts' position to match a mid-session edit that moved
  /// the active exercise. No-op for drafts that aren't open.
  void updateActiveDraftIndices(int workoutIndex, int exerciseIndex) {
    if (_activeSetDraft != null) {
      _activeSetDraft!.workoutIndex = workoutIndex;
      _activeSetDraft!.exerciseIndex = exerciseIndex;
    }
    if (_activeRestDraft != null) {
      _activeRestDraft!.workoutIndex = workoutIndex;
      _activeRestDraft!.exerciseIndex = exerciseIndex;
    }
  }

  /// Drops any in-flight drafts and resets the per-set accumulators and the
  /// phase clock. Closed events are kept.
  void discardDrafts() {
    _activeRestDraft = null;
    _activeSetDraft = null;
    _currentSetActiveAccum = Duration.zero;
    _currentSetRepRestAccum = Duration.zero;
    _currentPhaseEnteredAt = null;
  }

  /// Resets to initial state: clears both event lists and discards drafts.
  void clear() {
    _setEvents.clear();
    _restEvents.clear();
    discardDrafts();
  }

  /// Aggregates the recorded set and rest events into a [SessionSummary].
  SessionSummary computeSummary() {
    var activeTime = Duration.zero;
    var interRepRestTime = Duration.zero;
    for (final e in _setEvents) {
      activeTime += e.activeTime;
      interRepRestTime += e.interRepRestTime;
    }

    var setRestTime = Duration.zero;
    var supersetRestTime = Duration.zero;
    var exerciseRestTime = Duration.zero;
    var getReadyTime = Duration.zero;
    var overtime = Duration.zero;
    var pausedTime = Duration.zero;
    for (final e in _restEvents) {
      switch (e.restType) {
        case RestType.setRest:
          setRestTime += e.actualDuration;
        case RestType.supersetRest:
          supersetRestTime += e.actualDuration;
        case RestType.exerciseRest:
          exerciseRestTime += e.actualDuration;
        case RestType.getReady:
          getReadyTime += e.actualDuration;
        case RestType.overtime:
          overtime += e.actualDuration;
        case RestType.paused:
          pausedTime += e.actualDuration;
      }
    }

    final totalTime = activeTime +
        interRepRestTime +
        setRestTime +
        supersetRestTime +
        exerciseRestTime +
        getReadyTime +
        overtime +
        pausedTime;

    return SessionSummary(
      totalTime: totalTime,
      activeTime: activeTime,
      interRepRestTime: interRepRestTime,
      setRestTime: setRestTime,
      supersetRestTime: supersetRestTime,
      exerciseRestTime: exerciseRestTime,
      getReadyTime: getReadyTime,
      overtime: overtime,
      pausedTime: pausedTime,
    );
  }
}

class _OpenSetDraft {
  int workoutIndex;
  int exerciseIndex;
  final int setIndex;
  final DateTime startAt;

  _OpenSetDraft({
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
  });
}

class _OpenRestDraft {
  final RestType restType;
  int workoutIndex;
  int exerciseIndex;
  final int? setIndex;
  final DateTime startAt;
  final Duration plannedDuration;

  _OpenRestDraft({
    required this.restType,
    required this.workoutIndex,
    required this.exerciseIndex,
    required this.setIndex,
    required this.startAt,
    required this.plannedDuration,
  });
}
