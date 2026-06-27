import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'database_service.dart';

class AttendanceEngine {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static const Uuid _uuid = Uuid();

  // Notification Channel IDs
  static const String _channelShiftAlerts = 'shift_alerts';
  static const String _channelGeneral = 'general';

  // Action Button IDs
  static const String _actionClockIn = 'ACTION_CLOCK_IN';
  static const String _actionSnooze15 = 'ACTION_SNOOZE_15';
  static const String _actionClockOut = 'ACTION_CLOCK_OUT';
  static const String _actionRemind10 = 'ACTION_REMIND_10';
  static const String _actionRemind30 = 'ACTION_REMIND_30';

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    await _createChannels();
    
    // Request Permissions (Android 13+)
    if (Platform.isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      
      // Note: SCHEDULE_EXACT_ALARM should be requested via a dedicated permission handler in UI
    }
  }

  static Future<void> _createChannels() async {
    const shiftChannel = AndroidNotificationChannel(
      _channelShiftAlerts,
      'Shift Alerts',
      description: 'Critical shift start/end reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const generalChannel = AndroidNotificationChannel(
      _channelGeneral,
      'General Notifications',
      description: 'App updates and non-critical info',
      importance: Importance.defaultImportance,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(shiftChannel);
        
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(generalChannel);
  }

  static void _handleNotificationResponse(NotificationResponse response) async {
    if (response.actionId != null) {
      // Handle Action Button Taps
      final shiftUuid = response.payload;
      if (shiftUuid == null) return;

      switch (response.actionId) {
        case _actionClockIn:
          await DatabaseService.updateShiftStatus(shiftUuid, ShiftStatus.clockedIn);
          await cancelNotificationForShift(shiftUuid, 'forgot_clock_in');
          await scheduleClockOutReminder(shiftUuid);
          break;
        case _actionSnooze15:
          await scheduleForgotClockInReminder(shiftUuid, delayMinutes: 15);
          await cancelNotificationForShift(shiftUuid, 'forgot_clock_in');
          break;
        case _actionClockOut:
          await DatabaseService.updateShiftStatus(shiftUuid, ShiftStatus.clockedOut);
          await cancelNotificationForShift(shiftUuid, 'forgot_clock_out');
          break;
        case _actionRemind10:
          await scheduleForgotClockOutReminder(shiftUuid, delayMinutes: 10);
          await cancelNotificationForShift(shiftUuid, 'forgot_clock_out');
          break;
        case _actionRemind30:
          await scheduleForgotClockOutReminder(shiftUuid, delayMinutes: 30);
          await cancelNotificationForShift(shiftUuid, 'forgot_clock_out');
          break;
      }
    } else {
      // Handle Notification Tap (Open App)
      // In a real app, navigate to specific screen using response.payload
    }
  }

  // --- Scheduling Logic ---

  static Future<void> schedulePreShiftReminder(Shift shift, int minutesBefore) async {
    final scheduledTime = shift.plannedStartUtc.subtract(Duration(minutes: minutesBefore));
    
    // Don't schedule if time is in past
    if (scheduledTime.isBefore(DateTime.now().toUtc())) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelShiftAlerts,
        'Shift Alerts',
        channelDescription: 'Critical shift reminders',
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
      ),
    );

    await _notifications.zonedSchedule(
      shift.id.hashCode + 100, // Unique ID offset for Pre-Shift
      'Upcoming Shift',
      'Your shift starts in $minutesBefore minutes.',
      tz.TZDateTime.from(scheduledTime, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: shift.uuid,
    );
  }

  static Future<void> scheduleForgotClockInReminder(String shiftUuid, {int delayMinutes = 5}) async {
    // This is typically called immediately when shift starts if not clocked in
    // Or rescheduled with a specific delay from "now"
    final now = DateTime.now().toUtc();
    final scheduledTime = now.add(Duration(minutes: delayMinutes));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelShiftAlerts,
        'Shift Alerts',
        channelDescription: 'Critical shift reminders',
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(_actionClockIn, 'Clock In Now', showsUserInterface: true),
          AndroidNotificationAction(_actionSnooze15, 'Snooze 15m'),
        ],
      ),
    );

    await _notifications.zonedSchedule(
      shiftUuid.hashCode + 200, // Unique ID offset for Forgot Clock In
      'Forgot to Clock In?',
      'Your shift has started. Did you forget to clock in?',
      tz.TZDateTime.from(scheduledTime, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: shiftUuid,
    );
  }

  static Future<void> scheduleClockOutReminder(String shiftUuid) async {
    // Called when user clocks in, to remind them to clock out later
    // Logic handled by checking status at plannedEnd + delay
    final shift = await DatabaseService.getShiftByUuid(shiftUuid);
    if (shift == null) return;

    final scheduledTime = shift.plannedEndUtc.add(Duration(minutes: 5)); // Default 5 mins after end

    if (scheduledTime.isBefore(DateTime.now().toUtc())) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelShiftAlerts,
        'Shift Alerts',
        channelDescription: 'Critical shift reminders',
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(_actionClockOut, 'Clock Out Now', showsUserInterface: true),
          AndroidNotificationAction(_actionRemind10, 'Remind 10m'),
          AndroidNotificationAction(_actionRemind30, 'Remind 30m'),
        ],
      ),
    );

    await _notifications.zonedSchedule(
      shiftUuid.hashCode + 300, // Unique ID offset for Forgot Clock Out
      'Forgot to Clock Out?',
      'Your shift ended. Don\'t forget to clock out!',
      tz.TZDateTime.from(scheduledTime, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: shiftUuid,
    );
  }

  static Future<void> scheduleForgotClockOutReminder(String shiftUuid, {int delayMinutes = 5}) async {
    final now = DateTime.now().toUtc();
    final scheduledTime = now.add(Duration(minutes: delayMinutes));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelShiftAlerts,
        'Shift Alerts',
        channelDescription: 'Critical shift reminders',
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(_actionClockOut, 'Clock Out Now', showsUserInterface: true),
          AndroidNotificationAction(_actionRemind10, 'Remind 10m'),
          AndroidNotificationAction(_actionRemind30, 'Remind 30m'),
        ],
      ),
    );

    await _notifications.zonedSchedule(
      shiftUuid.hashCode + 300,
      'Forgot to Clock Out?',
      'You are still clocked in. Clock out now?',
      tz.TZDateTime.from(scheduledTime, tz.UTC),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: shiftUuid,
    );
  }

  static Future<void> cancelNotificationForShift(String shiftUuid, String type) async {
    int id;
    switch (type) {
      case 'pre_shift': id = shiftUuid.hashCode + 100; break;
      case 'forgot_clock_in': id = shiftUuid.hashCode + 200; break;
      case 'forgot_clock_out': id = shiftUuid.hashCode + 300; break;
      default: return;
    }
    await _notifications.cancel(id);
  }

  static Future<void> cancelAllForShift(String shiftUuid) async {
    await _notifications.cancel(shiftUuid.hashCode + 100);
    await _notifications.cancel(shiftUuid.hashCode + 200);
    await _notifications.cancel(shiftUuid.hashCode + 300);
  }
}
