import 'package:isar/isar.dart';

part 'shift_model.g.dart';

/// Enum representing the current status of a shift.
enum ShiftStatus {
  scheduled,
  clockedIn,
  clockedOut,
  cancelled,
}

/// The core Shift model stored in Isar.
/// ALL time fields are stored in UTC. Conversion to local time happens ONLY in UI.
@collection
class Shift {
  Id id; // UUID stored as string, but Isar Id is int/string compatible depending on setup. Using String for UUID.

  @Index()
  String uuid; // Explicit UUID string for logic consistency

  // Planned Times (UTC)
  @Index()
  DateTime plannedStartUtc;

  @Index()
  DateTime plannedEndUtc;

  // Actual Times (UTC) - Nullable until action performed
  DateTime? actualStartUtc;
  DateTime? actualEndUtc;

  // Shift Details
  String type; // e.g., "Morning", "Night", "Custom"
  String? note;

  // Status
  @Index()
  ShiftStatus status;

  // Pay Rules (Snapshot at time of creation to allow historical rate changes)
  double baseHourlyRate;
  double otMultiplier; // e.g., 1.5
  int payWeekStartDay; // 1=Monday, 7=Sunday (ISO 8601 style or custom)

  Shift({
    required this.uuid,
    required this.plannedStartUtc,
    required this.plannedEndUtc,
    this.actualStartUtc,
    this.actualEndUtc,
    required this.type,
    this.note,
    this.status = ShiftStatus.scheduled,
    required this.baseHourlyRate,
    required this.otMultiplier,
    required this.payWeekStartDay,
    Id? id,
  }) : id = id ?? Isar.generateId();

  // Helper to get a copy with changes (for immutability patterns)
  Shift copyWith({
    String? uuid,
    DateTime? plannedStartUtc,
    DateTime? plannedEndUtc,
    DateTime? actualStartUtc,
    DateTime? actualEndUtc,
    String? type,
    String? note,
    ShiftStatus? status,
    double? baseHourlyRate,
    double? otMultiplier,
    int? payWeekStartDay,
  }) {
    return Shift(
      uuid: uuid ?? this.uuid,
      plannedStartUtc: plannedStartUtc ?? this.plannedStartUtc,
      plannedEndUtc: plannedEndUtc ?? this.plannedEndUtc,
      actualStartUtc: actualStartUtc ?? this.actualStartUtc,
      actualEndUtc: actualEndUtc ?? this.actualEndUtc,
      type: type ?? this.type,
      note: note ?? this.note,
      status: status ?? this.status,
      baseHourlyRate: baseHourlyRate ?? this.baseHourlyRate,
      otMultiplier: otMultiplier ?? this.otMultiplier,
      payWeekStartDay: payWeekStartDay ?? this.payWeekStartDay,
      id: id,
    );
  }
}

/// App Settings stored locally.
@collection
class AppSettings {
  Id id = 0; // Singleton pattern, always ID 0

  // Notification Preferences (in minutes)
  int preShiftReminderMinutes;
  int forgotClockInDelayMinutes;
  int forgotClockOutDelayMinutes;

  // Defaults
  double defaultHourlyRate;
  double defaultOtMultiplier;
  int defaultPayWeekStartDay;

  AppSettings({
    this.preShiftReminderMinutes = 30,
    this.forgotClockInDelayMinutes = 5,
    this.forgotClockOutDelayMinutes = 5,
    this.defaultHourlyRate = 20.0,
    this.defaultOtMultiplier = 1.5,
    this.defaultPayWeekStartDay = 7, // Sunday
  });
}
