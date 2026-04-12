# Timer Background Continuity + Countdown Beeps

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the session timer ticking correctly when the screen is locked, and play sound cues (3-2-1 countdown, go, stop) throughout a session even with the screen fully off.

**Architecture:** Two independent changes. (1) The `SessionStateProvider` timer switches from tick-counting to wall-clock elapsed time so it catches up after the OS suspends the Dart isolate. (2) A new `BeepScheduler` service wraps `flutter_local_notifications` and pre-schedules the entire session's beep timeline at session start — OS-level delivery works regardless of app state. The provider calls `_scheduleAllFutureBeeps()` on every state change; `WidgetsBindingObserver` in the active session screen triggers reconciliation on foreground return.

**Tech Stack:** Flutter, flutter_local_notifications, timezone, Provider

---

## Key design decisions

**Why pre-schedule the entire session upfront (not phase-by-phase):** When the screen is locked, the Dart isolate is suspended — the ticker never fires between phases, so per-phase scheduling breaks after the first phase. The simulation walks the full state machine from the current position and schedules all beeps at once.

**iOS 64-notification limit (per app, independent of other apps):** Sessions with many timed reps may exhaust 64 slots mid-session. Beeps stop there until the user unlocks, which triggers `reconcileAfterBackground()` and reschedules the remainder.

**Sound types:**
| Type | Phases | Sound file |
|------|--------|------------|
| Countdown | Last 3 s of `getReady` and `setRest` | `countdown_beep` |
| Go | End of `getReady`, `setRest`, `repRest` (= rep start) | `go_beep` |
| Stop | End of `rep` phase | `stop_beep` (microwave-style ding) |

**Manual exercises:** rep duration is unknown, so simulation stops at the first manual rep phase.

---

## File Map

| Action | File | What changes |
|--------|------|--------------|
| Modify | `lib/providers/session_state_provider.dart` | Elapsed-time timer, `_calculateFutureBeeps()`, `_scheduleAllFutureBeeps()`, `BeepScheduler` hook |
| Modify | `lib/presentation/screens/session_flow/session_active_screen.dart` | `WidgetsBindingObserver` mixin for foreground reconciliation |
| Create | `lib/services/beep_scheduler.dart` | Wraps `flutter_local_notifications`; schedules full session beeps |
| Modify | `lib/main.dart` | Initialize `BeepScheduler`, inject into provider |
| Modify | `pubspec.yaml` | Add `flutter_local_notifications`, `timezone` |
| Modify | `android/app/src/main/AndroidManifest.xml` | Notification permissions + receivers |
| Add | `ios/Runner/countdown_beep.caf` + `go_beep.caf` + `stop_beep.caf` | Sound files |
| Add | `android/app/src/main/res/raw/countdown_beep.mp3` + `go_beep.mp3` + `stop_beep.mp3` | Sound files |

---

### Task 1: Add packages and sound files

**Files:**
- Modify: `pubspec.yaml`
- Add: sound files in platform-native directories

- [ ] **Step 1: Add packages to `pubspec.yaml`**

```yaml
dependencies:
  flutter_local_notifications: ^18.0.0
  timezone: ^0.9.4
```

- [ ] **Step 2: Run `flutter pub get`**

```bash
flutter pub get
```

- [ ] **Step 3: Add sound files**

Place sound files in the platform-native locations (Flutter assets are NOT used for notification sounds — files must be in the native directories):

```
ios/Runner/countdown_beep.caf
ios/Runner/go_beep.caf
ios/Runner/stop_beep.caf

android/app/src/main/res/raw/countdown_beep.mp3
android/app/src/main/res/raw/go_beep.mp3
android/app/src/main/res/raw/stop_beep.mp3
```

Sound specs:
- `countdown_beep`: short tick (~100ms)
- `go_beep`: longer start sound (~300ms)
- `stop_beep`: microwave-style ding (~300ms), distinct from countdown

iOS format must be `.caf`, `.aiff`, or `.wav` (not `.mp3`). Android uses `.mp3` or `.ogg`.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/*.caf android/app/src/main/res/raw/*.mp3
git commit -m "chore: add flutter_local_notifications + timer beep sound files"
```

---

### Task 2: Configure Android manifest

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add permissions before `<application>`**

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

- [ ] **Step 2: Add notification receivers inside `<application>`**

```xml
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
    <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
  </intent-filter>
</receiver>
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "chore: add notification permissions and receivers for timer beeps"
```

---

### Task 3: Create `BeepScheduler`

**Files:**
- Create: `lib/services/beep_scheduler.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum BeepType { countdown, go, stop }

class ScheduledBeep {
  final DateTime at;
  final BeepType type;
  const ScheduledBeep({required this.at, required this.type});
}

class BeepScheduler {
  // Notification IDs 100–163 (64 slots = iOS per-app limit for pending notifications).
  // Each app has its own independent quota — other apps (WhatsApp etc.) do not count
  // against this limit.
  static const _baseId = 100;
  static const _maxBeeps = 64;

  final FlutterLocalNotificationsPlugin _plugin;
  BeepScheduler(this._plugin);

  /// Call once at app startup. Initialises the plugin and requests permission.
  Future<void> init() async {
    tz.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestSoundPermission: true,
          requestAlertPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  /// Cancels all pending beeps, then schedules [beeps] in chronological order.
  /// Capped at [_maxBeeps] (iOS per-app limit). If the session has more beeps than
  /// the budget allows, the list is silently truncated — beeps stop mid-session
  /// until the user unlocks their phone, triggering reconcileAfterBackground()
  /// which reschedules the remaining beeps from the new position.
  Future<void> scheduleAll(List<ScheduledBeep> beeps) async {
    await cancelAll();
    final capped = beeps.take(_maxBeeps).toList();
    for (var i = 0; i < capped.length; i++) {
      final beep = capped[i];
      if (beep.at.isBefore(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        _baseId + i,
        null,
        null,
        tz.TZDateTime.from(beep.at, tz.local),
        _detailsFor(beep.type),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Cancels all pending beep notifications.
  Future<void> cancelAll() async {
    for (var i = 0; i < _maxBeeps; i++) {
      await _plugin.cancel(_baseId + i);
    }
  }

  NotificationDetails _detailsFor(BeepType type) {
    final sound = switch (type) {
      BeepType.countdown => 'countdown_beep',
      BeepType.go        => 'go_beep',
      BeepType.stop      => 'stop_beep',
    };
    return NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: false,
        presentBanner: false,
        presentBadge: false,
        presentSound: true,
        sound: '$sound.caf',
      ),
      android: AndroidNotificationDetails(
        'timer_beeps',
        'Timer Beeps',
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(sound),
        playSound: true,
        enableVibration: false,
        visibility: NotificationVisibility.public,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

```bash
flutter analyze lib/services/beep_scheduler.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/services/beep_scheduler.dart
git commit -m "feat: add BeepScheduler service for pre-scheduled timer beeps"
```

---

### Task 4: Refactor `SessionStateProvider`

**Files:**
- Modify: `lib/providers/session_state_provider.dart`

This task has three parts: (a) switch to elapsed-time timer, (b) add beep simulation + scheduling, (c) wire all call sites.

- [ ] **Step 1: Add new fields after existing timer fields**

After `TimerPhase _rememberCurrentPhaseForPausing`:

```dart
// Wall-clock time of the last ticker callback. Used to measure real elapsed time
// instead of assuming exactly 1 s per tick. Preserved across OS isolate suspension
// so the next tick can catch up after the screen is locked.
DateTime? _lastTickAt;

// Injected scheduler — null until setBeepScheduler() is called.
BeepScheduler? _beepScheduler;
```

Add public setter:
```dart
void setBeepScheduler(BeepScheduler scheduler) => _beepScheduler = scheduler;
```

- [ ] **Step 2: Replace `_startTicker()` with elapsed-time version**

Replace the existing `_startTicker()` body entirely:

```dart
void _startTicker() {
  _ticker?.cancel();
  // Stamp the current wall-clock time so the first tick can measure a real elapsed delta.
  _lastTickAt = DateTime.now();
  _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (_isPaused || _progress.phase == TimerPhase.workoutComplete) return;
    final now = DateTime.now();
    // Use actual wall-clock elapsed instead of a fixed 1s decrement.
    // When the OS suspends the isolate (screen locked), the ticker stops firing
    // but _lastTickAt is preserved. The next tick after the isolate resumes will
    // have a large elapsed value (e.g. 45 s), which _advanceByElapsed handles by
    // fast-forwarding through however many phases elapsed during that gap.
    _advanceByElapsed(now.difference(_lastTickAt!));
    _lastTickAt = now;
    _scheduleAllFutureBeeps();
    notifyListeners();
  });
}
```

- [ ] **Step 3: Add `_advanceByElapsed()` after `_startTicker()`**

```dart
void _advanceByElapsed(Duration elapsed) {
  // Subtract the real elapsed time. If the isolate was suspended (screen locked),
  // elapsed can be many seconds in a single call, making _remaining go deeply negative.
  _remaining -= elapsed;

  // Loop because a single large elapsed value can skip through multiple phases.
  // e.g. locked for 45 s during a 10 s getReady → blows past getReady, setRest, into rep.
  while (_remaining <= Duration.zero) {
    // Manual exercises wait for the user to tap advanceManually() — never auto-advance.
    if (_activeSession != null) {
      final exercise = _activeSession!
          .workouts[_progress.workoutIndex].exercises[_progress.exerciseIndex];
      if (exercise.type == ExerciseType.manual && _progress.phase == TimerPhase.rep) {
        _remaining = Duration.zero;
        return;
      }
    }
    final next = _calculateNextState(_progress);
    if (next == null) {
      _progress = _progress.copyWith(phase: TimerPhase.workoutComplete);
      _remaining = Duration.zero;
      return;
    }
    // _remaining is negative here (the overshoot past phase end).
    // Adding the next phase's full duration keeps the overshoot as a debt,
    // so rapid successive phases consume the correct total elapsed time.
    _remaining = _getDurationForPhase(next) + _remaining;
    _progress = next;
  }
}
```

- [ ] **Step 4: Add beep simulation methods after `_advanceByElapsed()`**

```dart
/// Cancels all pending beeps and reschedules from the current position.
/// No-op if beep scheduler is not set or session is paused/inactive.
void _scheduleAllFutureBeeps() {
  if (_beepScheduler == null || _isPaused || _activeSession == null) {
    _beepScheduler?.cancelAll();
    return;
  }
  final beeps = _calculateFutureBeeps();
  _beepScheduler!.scheduleAll(beeps);
}

/// Simulates the remaining state machine from the current position and returns
/// a chronological list of beeps to schedule. Stops at 64 entries (iOS limit)
/// or when a manual rep phase is reached (unknown duration).
List<ScheduledBeep> _calculateFutureBeeps() {
  final beeps = <ScheduledBeep>[];
  var simProgress = _progress;
  var phaseEndAt = DateTime.now().add(_remaining);

  while (true) {
    _addBeepsForPhase(beeps, simProgress, phaseEndAt);
    if (beeps.length >= BeepScheduler.maxBeeps) break;

    final next = _calculateNextState(simProgress);
    if (next == null) break;

    // Manual rep phase: duration unknown — cannot predict further.
    if (_activeSession != null) {
      final exercise = _activeSession!
          .workouts[next.workoutIndex].exercises[next.exerciseIndex];
      if (exercise.type == ExerciseType.manual && next.phase == TimerPhase.rep) break;
    }

    phaseEndAt = phaseEndAt.add(_getDurationForPhase(next));
    simProgress = next;
  }

  return beeps;
}

void _addBeepsForPhase(
  List<ScheduledBeep> beeps,
  SessionProgress p,
  DateTime phaseEndAt,
) {
  final now = DateTime.now();
  switch (p.phase) {
    case TimerPhase.rep:
      // Stop beep (microwave-style ding) when the rep duration ends.
      if (phaseEndAt.isAfter(now)) {
        beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.stop));
      }
    case TimerPhase.getReady:
    case TimerPhase.setRest:
      // Countdown beeps at 3 / 2 / 1 s before phase end, then go beep at phase end.
      for (final offset in [3, 2, 1]) {
        final t = phaseEndAt.subtract(Duration(seconds: offset));
        if (t.isAfter(now)) {
          beeps.add(ScheduledBeep(at: t, type: BeepType.countdown));
        }
      }
      if (phaseEndAt.isAfter(now)) {
        beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.go));
      }
    case TimerPhase.repRest:
      // No countdown for inter-rep rests, but go beep fires at the start of each rep.
      if (phaseEndAt.isAfter(now)) {
        beeps.add(ScheduledBeep(at: phaseEndAt, type: BeepType.go));
      }
    default:
      break; // exerciseRest, workoutComplete, paused — no beeps
  }
}
```

> **Note:** expose `_maxBeeps` as a public static on `BeepScheduler` (`static const int maxBeeps = 64;`) so the provider can reference it without duplicating the constant.

- [ ] **Step 5: Add `reconcileAfterBackground()` after the timer controls section**

```dart
/// Called when the app returns to foreground. Catches any time gap the ticker
/// missed while the isolate was suspended, then reschedules beeps from the
/// new position.
void reconcileAfterBackground() {
  if (_isPaused || _activeSession == null || _lastTickAt == null) return;
  final now = DateTime.now();
  _advanceByElapsed(now.difference(_lastTickAt!));
  _lastTickAt = now;
  _scheduleAllFutureBeeps();
  notifyListeners();
}
```

- [ ] **Step 6: Update `pause()`, `reset()`, and all navigation methods**

In `pause()`, add after `_isPaused = true`:
```dart
_lastTickAt = null;
_scheduleAllFutureBeeps(); // will cancel because _isPaused is true
```

In `reset()`, add after `_ticker?.cancel()`:
```dart
_lastTickAt = null;
_beepScheduler?.cancelAll();
```

Add `_scheduleAllFutureBeeps()` call at the end of each of these methods (after updating `_remaining`):
- `start()` — after `_startTicker()`
- `resume()` — after `_startTicker()`
- `jumpToWorkout()`
- `jumpToExercise()` — add to all three branches that set `_remaining`
- `jumpToSet()` — add to both branches that set `_remaining`
- `advanceManually()`

- [ ] **Step 7: Add import at top of file**

```dart
import 'package:flash_forward/services/beep_scheduler.dart';
```

- [ ] **Step 8: Verify no analysis errors**

```bash
flutter analyze lib/providers/session_state_provider.dart
```

Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/providers/session_state_provider.dart
git commit -m "feat: switch timer to wall-clock elapsed time and add beep scheduling"
```

---

### Task 5: Update `session_active_screen.dart`

**Files:**
- Modify: `lib/presentation/screens/session_flow/session_active_screen.dart`

- [ ] **Step 1: Add `WidgetsBindingObserver` mixin**

Change the class declaration from:
```dart
class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
```
to:
```dart
class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with WidgetsBindingObserver {
```

- [ ] **Step 2: Add `initState()` and `dispose()` overrides**

Add after the `_timerInitialized` field:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // Catch up the timer and reschedule beeps for time elapsed while locked.
    context.read<SessionStateProvider>().reconcileAfterBackground();
  }
}
```

- [ ] **Step 3: Verify no analysis errors**

```bash
flutter analyze lib/presentation/screens/session_flow/session_active_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/session_flow/session_active_screen.dart
git commit -m "feat: reconcile timer and beeps when app returns to foreground"
```

---

### Task 6: Wire up `BeepScheduler` in `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import**

```dart
import 'package:flash_forward/services/beep_scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
```

- [ ] **Step 2: Initialize `BeepScheduler` before `runApp()`**

```dart
WidgetsFlutterBinding.ensureInitialized();

final beepScheduler = BeepScheduler(FlutterLocalNotificationsPlugin());
await beepScheduler.init();
```

- [ ] **Step 3: Inject into `SessionStateProvider` after providers are created**

```dart
// After the MultiProvider / ChangeNotifierProvider setup, get the provider
// and inject the scheduler.
final sessionStateProvider = SessionStateProvider();
sessionStateProvider.setBeepScheduler(beepScheduler);
```

Ensure `sessionStateProvider` is the same instance passed to `ChangeNotifierProvider`.

- [ ] **Step 4: Verify app starts without errors**

```bash
flutter run
```

Expected: app launches, no crash on startup.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: initialize BeepScheduler and inject into SessionStateProvider"
```

---

### Task 7: Full verification

- [ ] **Step 1: Timer continuity — short lock**

Start a session during `getReady`. Lock the screen for 30 s. Unlock. Confirm the timer has advanced ~30 s and shows the correct phase.

- [ ] **Step 2: Timer continuity — multi-phase lock**

Start a session. Lock the screen for longer than one complete phase (e.g. longer than `getReady` duration). Unlock. Confirm the correct phase is displayed with correct remaining time.

- [ ] **Step 3: Beeps in foreground**

Run a session with the screen on. Confirm:
- Countdown beeps at 3, 2, 1 s during `getReady` and `setRest` phases
- Go beep when rep starts
- Stop beep (ding) when rep ends
- No countdown during `repRest`, but go beep fires at each rep start

- [ ] **Step 4: Beeps with screen locked**

Start a session with a short `getReady` (or adjust in debug). Lock the screen before the phase ends. Confirm beeps fire while screen is off.

- [ ] **Step 5: Pause and resume**

Pause mid-rest. Confirm no beeps fire. Resume. Confirm beeps are rescheduled from the new remaining time.

- [ ] **Step 6: Navigation reschedules**

During an active session, use jump-to-exercise or jump-to-set. Confirm old beep schedule is cancelled and new beeps are scheduled for the updated position.

- [ ] **Step 7: Session end**

Complete or abandon a session. Confirm no beep notifications fire after reset.

- [ ] **Step 8: Manual exercises**

Run a session with a manual exercise. Confirm no stop beep fires during manual reps and that beep scheduling stops at the first manual rep phase.
