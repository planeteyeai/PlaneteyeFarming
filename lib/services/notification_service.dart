import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'streak_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  NOTIFICATION SERVICE
//  Wraps flutter_local_notifications for streak reminder alerts.
//
//  Usage:
//    await NotificationService.instance.init();
//    await NotificationService.instance.scheduleStreakReminder();
// ═══════════════════════════════════════════════════════════════════════════

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'cropeye_streak';
  static const _channelName = 'Farm Streak Reminders';
  static const _channelDesc =
      'Daily reminders to keep your CropEye streak alive';

  bool _initialized = false;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  // ── Show an immediate reminder if the user hasn't opened today ───────────
  /// Call once on app launch.  Shows nothing if the user already opened today.
  Future<void> scheduleStreakReminder() async {
    await init();
    final message = await StreakService.instance.reminderMessage();
    if (message == null) return; // opened today — no reminder needed

    final streak = StreakService.instance.currentStreak;
    final emoji  = StreakService.streakEmoji(streak);

    await _plugin.show(
      1001, // fixed ID so it replaces itself if triggered multiple times
      '$emoji CropEye Farm Alert',
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(message),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Cancel all streak notifications ──────────────────────────────────────
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
