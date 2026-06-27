import 'package:isar/isar.dart';

part 'shift.g.dart';

enum ShiftStatus { scheduled, clockedIn, clockedOut, cancelled }

@collection
class Shift {
  Id id = Isar.autoIncrement; // Internal DB ID
  
  @Index(unique: true)
  late String uuid; // Unique ID for sync/notification mapping

  // UTC Times (Store ONLY in UTC)
  late DateTime plannedStartUtc;
  late DateTime plannedEndUtc;
  
  DateTime? actualStartUtc;
  DateTime? actualEndUtc;

  // Pay & Role Info
  late double baseHourlyRate;
  late double otMultiplier; // e.g., 1.5
  String? roleTitle;
  String? locationName;

  // Status
  @enumerated
  late ShiftStatus status;

  // Metadata
  late DateTime createdAtUtc;
  DateTime? updatedAtUtc;

  // Helpers for UI (Not stored, computed)
  bool get isCompleted => status == ShiftStatus.clockedOut || status == ShiftStatus.cancelled;
}
