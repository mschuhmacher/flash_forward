# Hybrid Sound System: In-App Audio + Background Notifications

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the notification-only beep system with a hybrid approach: `just_audio` for clean in-app audio when the app is foregrounded, falling back to `flutter_local_notifications` only when backgrounded. Add a four-option sound mode setting with a platform-aware info popup.

**Architecture:** `AudioBeepPlayer` wraps `just_audio` and preloads three sound files. `SessionStateProvider` gains `_isForegrounded` and `_soundMode` fields. The ticker drives in-app audio (countdown threshold crossing + phase-transition beeps). `setForegrounded(bool)` switches between audio and notification delivery on lifecycle changes. `SettingsProvider` adds `SoundMode` enum with SharedPreferences persistence. The settings drawer gets a four-segment toggle + `(i)` info button with iOS/Android-specific copy.

**Tech Stack:** Flutter, just_audio, flutter_local_notifications, Provider, SharedPreferences, dart:io (Platform)

---

## Key design decisions

**Why four modes, not three:**
| Mode | Foreground | Background | Use case |
|------|-----------|------------|----------|
| `both` (default) | In-app audio | Local notifications | Full coverage |
| `soundsOnly` | In-app audio | Silent | No notification artifacts ever |
| `notificationsOnly` | Silent | Local notifications | Screen-off workouts, no foreground sound |
| `none` | Silent | Silent | Silent timer |

**Why the iOS/Android info popup differs:**
Android notifications play only the app's custom sound file. iOS notification delivery obeys the device's global notification settings — which typically include vibration regardless of the `enableVibration: false` flag (iOS does not expose per-notification vibration control). Users need to know this before choosing a mode.

**In-app audio dispatch (ticker):**
- Play in-app audio only when `_isForegrounded && (_soundMode == SoundMode.soundsOnly || _soundMode == SoundMode.both)`
- **Countdown**: triggers when `_remaining` crosses from > 3 s to ≤ 3 s during a `getReady` or `setRest` phase (compare `previousRemaining` vs `_remaining`)
- **Go**: triggers on phase transition into `rep`
- **Stop**: triggers on phase transition out of `rep` into rest/complete

**Notification dispatch (`_rescheduleSound`):**
| Mode | Foregrounded | Action |
|------|-------------|--------|
| `none` | either | cancel all notifications |
| `soundsOnly` | either | cancel all notifications |
| `notificationsOnly` | `true` | cancel all notifications (silent in foreground) |
| `notificationsOnly` | `false` | schedule all future beeps as notifications |
| `both` | `true` | cancel all notifications (audio covers it) |
| `both` | `false` | schedule all future beeps as notifications |

**Asset sound files:** The same `.mp3` files used for Android raw resources are copied to `assets/sounds/` for `just_audio`. The platform-specific copies (`ios/Runner/*.caf`, `android/.../res/raw/*.mp3`) stay for notifications.

---

## File Map

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `just_audio: ^0.9.40`; add `assets/sounds/` to flutter assets |
| `assets/sounds/countdown_beep.mp3` | **New** — copied from Android raw resources |
| `assets/sounds/go_beep.mp3` | **New** — copied from Android raw resources |
| `assets/sounds/stop_beep.mp3` | **New** — copied from Android raw resources |
| `lib/services/audio_beep_player.dart` | **New** — `just_audio` wrapper, preloads three players |
| `lib/providers/settings_provider.dart` | Add `SoundMode` enum + field + getter + setter + persistence |
| `lib/presentation/screens/root_screen.dart` | Add sound mode `SegmentedButton` + `(i)` info dialog to `SettingsDrawer` |
| `lib/providers/session_state_provider.dart` | Add `_audioPlayer`, `_isForegrounded`, `_soundMode`; rename `_scheduleAllFutureBeeps` → `_rescheduleSound`; add in-app beep logic to ticker |
| `lib/presentation/screens/session_flow/session_active_screen.dart` | Update `WidgetsBindingObserver` to call `setForegrounded()`; sync sound mode at session start |
| `lib/main.dart` | Initialize `AudioBeepPlayer`, inject into `SessionStateProvider` |

---

## Tasks

### Step 1 — Add `just_audio` and asset sound files

- [ ] In `pubspec.yaml`, add `just_audio: ^0.9.40` under `dependencies`
- [ ] In `pubspec.yaml` `flutter.assets`, add `- assets/sounds/`
- [ ] Create `assets/sounds/` directory
- [ ] Copy `android/app/src/main/res/raw/countdown_beep.mp3` → `assets/sounds/countdown_beep.mp3`
- [ ] Copy `android/app/src/main/res/raw/go_beep.mp3` → `assets/sounds/go_beep.mp3`
- [ ] Copy `android/app/src/main/res/raw/stop_beep.mp3` → `assets/sounds/stop_beep.mp3`
- [ ] Run `flutter pub get` to install `just_audio`

### Step 2 — New `lib/services/audio_beep_player.dart`

- [ ] Create the file with an `AudioBeepPlayer` class:
  - `final _players = <BeepType, AudioPlayer>{}`
  - `Future<void> init()` — iterates `BeepType.values`, creates one `AudioPlayer` per type, calls `setAsset()` with the matching `assets/sounds/*.mp3` path
  - `Future<void> play(BeepType type)` — seeks to `Duration.zero`, then plays. No-op if player not found.
  - `Future<void> dispose()` — disposes all players, clears map
- [ ] Import `package:just_audio/just_audio.dart` and `package:flash_forward/services/beep_scheduler.dart` (for `BeepType`)

### Step 3 — Add `SoundMode` to `SettingsProvider`

- [ ] Add `enum SoundMode { both, soundsOnly, notificationsOnly, none }` at the top of `lib/providers/settings_provider.dart` (outside the class)
- [ ] Add `static const _keySoundMode = 'pref_sound_mode'` to `SettingsProvider`
- [ ] Add `SoundMode _soundMode = SoundMode.both` field
- [ ] Add `SoundMode get soundMode => _soundMode` getter
- [ ] Add `Future<void> setSoundMode(SoundMode mode)` — updates field, calls `notifyListeners()`, persists `mode.name` to SharedPreferences
- [ ] In `init()`, load `_soundMode` from SharedPreferences using `SoundMode.values.byName(stored)` with a `both` fallback

### Step 4 — Sound mode UI in `SettingsDrawer` (`root_screen.dart`)

- [ ] After the grade system section (before the `SizedBox(height: 6)` + grade system note text), add `SizedBox(height: 20)` + a new "Sound" section
- [ ] The section header is a `Row` with:
  - `Text('Sound', style: context.titleMedium)`
  - `const SizedBox(width: 4)`
  - `IconButton` with `icon: const Icon(Icons.info_outline_rounded)`, `iconSize: 18`, `padding: EdgeInsets.zero`, `constraints: BoxConstraints()`, `onPressed:` opens info dialog
- [ ] The info dialog (`showDialog`) contains:
  - Title: "Sound modes"
  - Content: platform-specific `Text` (use `Platform.isIOS` from `dart:io`):

    **iOS:**
    > **Both**: Plays beeps in the app while your screen is on. Schedules notification sounds when the screen locks — note that iOS plays these with your device's notification settings, which may include vibration.
    >
    > **Sounds only**: Beeps play in the app while the screen is on. No notifications when backgrounded.
    >
    > **Notifications only**: No in-app sounds. Schedules notification sounds when the screen locks (with your device's notification settings, which may include vibration).
    >
    > **None**: All sounds disabled. The timer runs silently.

    **Android:**
    > **Both**: Plays beeps in the app while the screen is on. Schedules notification sounds when backgrounded — only the app's own sounds, no extra vibration.
    >
    > **Sounds only**: Beeps play in the app while the screen is on. No notifications when backgrounded.
    >
    > **Notifications only**: No in-app sounds. Schedules notification sounds when backgrounded — only the app's own sounds, no extra vibration.
    >
    > **None**: All sounds disabled. The timer runs silently.

  - One "Close" action button
- [ ] Below the header row, add `SizedBox(height: 8)` + `SizedBox(width: double.infinity, child: SegmentedButton<SoundMode>(...))`:
  - `visualDensity: VisualDensity.compact`
  - `showSelectedIcon: false`
  - Four `ButtonSegment` entries: `both`/`'Both'`, `soundsOnly`/`'Sounds only'`, `notificationsOnly`/`'Notifications only'`, `none`/`'None'`
  - `selected: {settings.soundMode}`
  - `onSelectionChanged: (s) => settings.setSoundMode(s.first)`
- [ ] Add `import 'dart:io' show Platform;` if not already present in `root_screen.dart`

### Step 5 — Core changes to `SessionStateProvider`

- [ ] Add imports: `package:flash_forward/services/audio_beep_player.dart`, `package:flash_forward/providers/settings_provider.dart`
- [ ] Add fields below the existing `BeepScheduler? _beepScheduler` line:
  ```dart
  AudioBeepPlayer? _audioPlayer;
  bool _isForegrounded = true;
  SoundMode _soundMode = SoundMode.both;
  ```
- [ ] Add public setter methods:
  - `void setAudioBeepPlayer(AudioBeepPlayer player) => _audioPlayer = player;`
  - `void setSoundMode(SoundMode mode) { _soundMode = mode; _rescheduleSound(); }`
- [ ] Add `setForegrounded(bool fg)` method:
  ```dart
  void setForegrounded(bool fg) {
    if (_isForegrounded == fg) return;
    _isForegrounded = fg;
    if (fg) {
      _beepScheduler?.cancelAll();
      reconcileAfterBackground();
    } else {
      _rescheduleSound();
    }
  }
  ```
- [ ] Rename `_scheduleAllFutureBeeps()` → `_rescheduleSound()` (replace all call sites too) and replace its body with the dispatch table logic:
  ```dart
  void _rescheduleSound() {
    // Notifications only needed when backgrounded and mode uses them.
    final useNotifications = !_isForegrounded &&
        (_soundMode == SoundMode.both || _soundMode == SoundMode.notificationsOnly);
    if (useNotifications && _beepScheduler != null && !_isPaused && _activeSession != null) {
      _beepScheduler!.scheduleAll(_calculateFutureBeeps());
    } else {
      _beepScheduler?.cancelAll();
    }
  }
  ```
- [ ] In `_startTicker()`, before `_advanceByElapsed`, save `previousRemaining`:
  ```dart
  final previousRemaining = _remaining;
  final prevProgress = _progress;
  ```
  (the `prevProgress` line already exists — just add `previousRemaining` alongside it)
- [ ] After `_advanceByElapsed` and before the `!identical` check, add in-app audio logic:
  ```dart
  final playInApp = _isForegrounded &&
      (_soundMode == SoundMode.soundsOnly || _soundMode == SoundMode.both);
  if (playInApp) {
    // Countdown: fires when remaining crosses from >3s to ≤3s in getReady/setRest
    if ((prevProgress.phase == TimerPhase.getReady || prevProgress.phase == TimerPhase.setRest) &&
        previousRemaining > const Duration(seconds: 3) &&
        _remaining <= const Duration(seconds: 3) &&
        _remaining > Duration.zero) {
      _audioPlayer?.play(BeepType.countdown);
    }
  }
  ```
- [ ] Inside the `if (!identical(_progress, prevProgress))` block, after `_rescheduleSound()`, add phase-transition beep logic:
  ```dart
  if (playInApp) {
    if (_progress.phase == TimerPhase.rep && prevProgress.phase != TimerPhase.rep) {
      _audioPlayer?.play(BeepType.go);
    } else if (prevProgress.phase == TimerPhase.rep && _progress.phase != TimerPhase.rep) {
      _audioPlayer?.play(BeepType.stop);
    }
  }
  ```

### Step 6 — Update `ActiveSessionScreen`

- [ ] In `didChangeAppLifecycleState`, replace the `reconcileAfterBackground()` call with `setForegrounded()`:
  ```dart
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<SessionStateProvider>();
    if (state == AppLifecycleState.resumed) {
      provider.setForegrounded(true);
    } else if (state == AppLifecycleState.paused) {
      provider.setForegrounded(false);
    }
  }
  ```
  (`reconcileAfterBackground` is now called inside `setForegrounded(true)`)
- [ ] In the `addPostFrameCallback`, after `sessionStateData.start(widget.session)`, sync the sound mode:
  ```dart
  final settings = context.read<SettingsProvider>();
  sessionStateData.setSoundMode(settings.soundMode);
  ```

### Step 7 — Wire up in `main.dart`

- [ ] Import `package:flash_forward/services/audio_beep_player.dart`
- [ ] After `BeepScheduler` initialization, add:
  ```dart
  final audioPlayer = AudioBeepPlayer();
  await audioPlayer.init();
  ```
- [ ] Inject into `SessionStateProvider` alongside `setBeepScheduler`:
  ```dart
  ..setAudioBeepPlayer(audioPlayer)
  ```

---

## Verification

1. **`both` mode — foreground**: Start session, keep app open → clean audio beeps, no notification banner or vibration
2. **`both` mode — background**: Lock screen mid-session → notification sounds fire on schedule
3. **`both` mode — transition**: Start foreground (audio), lock (notifications take over), unlock (audio resumes, no duplicate beeps)
4. **`soundsOnly` mode**: Lock screen → no sounds fire, timer catches up on return
5. **`notificationsOnly` mode**: Keep app open → silent. Lock screen → notification sounds fire
6. **`none` mode**: No sounds in any state, timer works
7. **Settings persistence**: Change mode, restart app → mode preserved
8. **Info popup**: Tapping (i) shows correct platform text; iOS text mentions vibration, Android text does not
9. **Mode change mid-session**: Change mode while session running → takes effect immediately (no crash, correct sound behavior)
