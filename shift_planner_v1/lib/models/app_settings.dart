import 'package:isar/isar.dart';

part 'app_settings.g.dart';

@collection
class AppSettings {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String key = 'global_settings';

  // Notification Preferences (in minutes before/after)
  int preShiftReminderMinutes = 30;
  int forgotClockInDelayMinutes = 5;
  int forgotClockOutDelayMinutes = 5;

  // Defaults
  double defaultHourlyRate = 20.0;
  double defaultOtMultiplier = 1.5;
  int payWeekStartDay = 6; // 0=Monday, 6=Sunday (ISO Week starts Monday, but US often Sunday)

  // UX
  bool hapticFeedbackEnabled = true;
  
  DateTime lastUpdatedUtc = DateTime.now().toUtc();
}
