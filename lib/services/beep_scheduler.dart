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
  // Notification IDs 100–163 (64 slots = iOS per-app limit for pending
  // scheduled notifications). Each app has its own independent quota —
  // other apps (WhatsApp etc.) do not count against this limit.
  static const int maxBeeps = 64;
  static const int _baseId = 100;

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
  ///
  /// Capped at [maxBeeps] (iOS per-app limit). If the session has more beeps
  /// than the budget allows, the list is silently truncated — beeps stop
  /// mid-session until the user unlocks their phone, triggering
  /// reconcileAfterBackground() which reschedules the remaining beeps from
  /// the new position.
  Future<void> scheduleAll(List<ScheduledBeep> beeps) async {
    await cancelAll();
    final capped = beeps.take(maxBeeps).toList();
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
    for (var i = 0; i < maxBeeps; i++) {
      await _plugin.cancel(_baseId + i);
    }
  }

  NotificationDetails _detailsFor(BeepType type) {
    final sound = switch (type) {
      BeepType.countdown => 'countdown_beep',
      BeepType.go => 'go_beep',
      BeepType.stop => 'stop_beep',
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
