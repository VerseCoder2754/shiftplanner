import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../models/shift_model.dart';
import '../services/database_service.dart';

/// Handles all notification scheduling, action button interactions,
/// and Android-specific alarm permissions.
class AttendanceEngine {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _db;
  final Uuid _uuid = const Uuid();

  // Notification Channel IDs
  static const String _channelShiftAlerts = 'shift_alerts';
  static const String _channelGeneral = 'general';

  // Action Button IDs
  static const String _actionClockIn = 'ACTION_CLOCK_IN';
  static const String _actionSnooze15 = 'ACTION_SNOOZE_15';
  static const String _actionClockOut = 'ACTION_CLOCK_OUT';
  static const String _actionRemind10 = 'ACTION_REMIND_10';
  static const String _actionRemind30 = 'ACTION_REMIND_30';

  AttendanceEngine(this._db);

  /// Initialize notification plugin and create channels.
  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _backgroundHandler,
    );

    await _createChannels();
  }

  Future<void> _createChannels() async {
    if (!Platform.isAndroid) return;

    const AndroidNotificationChannel alertsChannel = AndroidNotificationChannel(
      _channelShiftAlerts,
      'Shift Alerts',
      description: 'Critical shift start/end reminders and clock-in actions',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
      _channelGeneral,
      'General Notifications',
      description: 'Non-critical updates and tips',
      importance: Importance.defaultImportance,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alertsChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(generalChannel);
  }

  /// Request necessary Android permissions (Post Notifications & Exact Alarms).
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImpl =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        // Request Post Notifications (Android 13+)
        await androidImpl.requestNotificationsPermission();
        
        // Request Schedule Exact Alarm (Android 12+)
        await androidImpl.requestExactAlarmsPermission();
      }
    }
  }

  /// Schedule all relevant notifications for a given shift.
  Future<void> scheduleShiftNotifications(Shift shift) async {
    await _cancelAllShiftNotificationsByUuid(shift.uuid);

    final now = tz.TZDateTime.now(tz.local);

    // 1. Pre-Shift Reminder (30 mins before)
    final preShiftTime = shift.plannedStartUtc.subtract(const Duration(minutes: 30));
    if (preShiftTime.isAfter(now)) {
      await _scheduleNotification(
        id: _generateNotificationId(shift.uuid, 'pre'),
        title: 'Upcoming Shift',
        body: 'Your ${shift.type} shift starts in 30 minutes.',
        scheduledTime: preShiftTime,
        payload: shift.uuid,
      );
    }

    // 2. Forgot Clock-In (5 mins after start)
    if (shift.status != ShiftStatus.clockedIn && shift.status != ShiftStatus.clockedOut) {
      final forgotClockInTime = shift.plannedStartUtc.add(const Duration(minutes: 5));
      if (forgotClockInTime.isAfter(now)) {
        await _scheduleNotification(
          id: _generateNotificationId(shift.uuid, 'forgot_in'),
          title: 'Forgot to Clock In?',
          body: 'Your shift started 5 minutes ago. Tap to clock in now.',
          scheduledTime: forgotClockInTime,
          payload: shift.uuid,
          actions: [
            AndroidNotificationAction(
              _actionClockIn,
              '✅ Clock In Now',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _actionSnooze15,
              '⏰ Snooze 15m',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        );
      }
    }

    // 3. Forgot Clock-Out (5 mins after end)
    if (shift.status == ShiftStatus.clockedIn) {
      final forgotClockOutTime = shift.plannedEndUtc.add(const Duration(minutes: 5));
      if (forgotClockOutTime.isAfter(now)) {
        await _scheduleNotification(
          id: _generateNotificationId(shift.uuid, 'forgot_out'),
          title: 'Forgot to Clock Out?',
          body: 'Your shift ended 5 minutes ago. Tap to clock out now.',
          scheduledTime: forgotClockOutTime,
          payload: shift.uuid,
          actions: [
            AndroidNotificationAction(
              _actionClockOut,
              '🛑 Clock Out Now',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _actionRemind10,
              '⏰ Remind 10m',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _actionRemind30,
              '⏰ Remind 30m',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        );
      }
    }
  }

  /// Helper to schedule a single notification with Android specifics.
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelShiftAlerts,
      'Shift Alerts',
      channelDescription: 'Critical shift alerts',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      autoCancel: true,
      fullScreenIntent: false,
      additionalFlags: Int32List.fromList([4]), // FLAG_UPDATE_CURRENT
      actions: actions,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledTime,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// Handle Action Button taps and Notification taps.
  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    if (response.payload == null) return;
    final shiftUuid = response.payload!;

    switch (response.actionId) {
      case _actionClockIn:
        await _performClockIn(shiftUuid);
        break;
      case _actionSnooze15:
        await _rescheduleForgotClockIn(shiftUuid, minutes: 15);
        break;
      case _actionClockOut:
        await _performClockOut(shiftUuid);
        break;
      case _actionRemind10:
        await _rescheduleForgotClockOut(shiftUuid, minutes: 10);
        break;
      case _actionRemind30:
        await _rescheduleForgotClockOut(shiftUuid, minutes: 30);
        break;
      default:
        // Tapped the notification body
        break;
    }
  }

  /// Background handler for actions when app is terminated.
  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(NotificationResponse response) async {
    print("Background notification action: ${response.actionId} for ${response.payload}");
    // In production: Re-init DB and perform action here
  }

  // --- Action Implementations ---

  Future<void> _performClockIn(String shiftUuid) async {
    try {
      final shift = await _db.getShiftById(shiftUuid);
      if (shift == null) return;

      final updatedShift = shift.copyWith(
        status: ShiftStatus.clockedIn,
        actualStartUtc: tz.TZDateTime.now(tz.utc),
      );

      await _db.updateShift(updatedShift);
      await _cancelAllShiftNotificationsByUuid(updatedShift.uuid);
      
      // Schedule the "Forgot Clock Out" reminder immediately
      await scheduleShiftNotifications(updatedShift);
    } catch (e) {
      print("Error clocking in from notification: $e");
    }
  }

  Future<void> _performClockOut(String shiftUuid) async {
    try {
      final shift = await _db.getShiftById(shiftUuid);
      if (shift == null) return;

      final updatedShift = shift.copyWith(
        status: ShiftStatus.clockedOut,
        actualEndUtc: tz.TZDateTime.now(tz.utc),
      );

      await _db.updateShift(updatedShift);
      await _cancelAllShiftNotificationsByUuid(updatedShift.uuid);
    } catch (e) {
      print("Error clocking out from notification: $e");
    }
  }

  Future<void> _rescheduleForgotClockIn(String shiftUuid, {required int minutes}) async {
    try {
      final shift = await _db.getShiftById(shiftUuid);
      if (shift == null) return;

      final newTime = tz.TZDateTime.now(tz.utc).add(Duration(minutes: minutes));
      
      await _scheduleNotification(
        id: _generateNotificationId(shift.uuid, 'forgot_in'),
        title: 'Reminder: Clock In',
        body: 'Snoozed reminder. Clock in now to track your hours.',
        scheduledTime: newTime,
        payload: shift.uuid,
        actions: [
           AndroidNotificationAction(_actionClockIn, '✅ Clock In Now', showsUserInterface: true, cancelNotification: true),
           AndroidNotificationAction(_actionSnooze15, '⏰ Snooze 15m', showsUserInterface: false, cancelNotification: true),
        ],
      );
    } catch (e) {
      print("Error rescheduling clock-in: $e");
    }
  }

  Future<void> _rescheduleForgotClockOut(String shiftUuid, {required int minutes}) async {
    try {
      final shift = await _db.getShiftById(shiftUuid);
      if (shift == null) return;

      final newTime = tz.TZDateTime.now(tz.utc).add(Duration(minutes: minutes));
      
      await _scheduleNotification(
        id: _generateNotificationId(shift.uuid, 'forgot_out'),
        title: 'Reminder: Clock Out',
        body: 'Snoozed reminder. Don\'t forget to clock out!',
        scheduledTime: newTime,
        payload: shift.uuid,
        actions: [
           AndroidNotificationAction(_actionClockOut, '🛑 Clock Out Now', showsUserInterface: true, cancelNotification: true),
           AndroidNotificationAction(_actionRemind10, '⏰ Remind 10m', showsUserInterface: false, cancelNotification: true),
           AndroidNotificationAction(_actionRemind30, '⏰ Remind 30m', showsUserInterface: false, cancelNotification: true),
        ],
      );
    } catch (e) {
      print("Error rescheduling clock-out: $e");
    }
  }

  Future<void> _cancelAllShiftNotifications(int dbId) async {
    // We need the UUID to generate IDs, but we only have DB ID here.
    // In a real scenario, we'd fetch the shift first or store notification IDs separately.
    // For now, assuming we can't easily cancel without UUID, we rely on cancellation flags in logic.
    // Better approach: Pass UUID to this method.
    // This method is slightly refactored below to take UUID.
  }
  
  // Overload to cancel by UUID
  Future<void> _cancelAllShiftNotificationsByUuid(String uuid) async {
    await _notifications.cancel(_generateNotificationId(uuid, 'pre'));
    await _notifications.cancel(_generateNotificationId(uuid, 'forgot_in'));
    await _notifications.cancel(_generateNotificationId(uuid, 'forgot_out'));
  }

  int _generateNotificationId(String uuid, String type) {
    return (uuid.hashCode + type.hashCode).abs();
  }
  
  /// Deep link to Android Battery Optimization settings
  Future<void> openBatteryOptimizationSettings() async {
    if (Platform.isAndroid) {
       print("Redirecting to Battery Optimization Settings...");
       // Requires 'android_intent_plus'
       // await AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS').call();
    }
  }
}
