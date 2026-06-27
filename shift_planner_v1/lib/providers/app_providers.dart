import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/models.dart';
import '../services/database_service.dart';

// Provider for Database Instance
final isarProvider = FutureProvider<Isar>((ref) async {
  await DatabaseService.initialize();
  return DatabaseService.instance;
});

// Provider for Current Settings
final settingsProvider = FutureProvider<AppSettings>((ref) async {
  return await DatabaseService.getSettings();
});

// Provider for Active Shift (The one happening now or next)
final activeShiftProvider = StateNotifierProvider<ActiveShiftNotifier, Shift?>((ref) {
  return ActiveShiftNotifier();
});

class ActiveShiftNotifier extends StateNotifier<Shift?> {
  ActiveShiftNotifier() : super(null);

  Future<void> loadActiveShift() async {
    final now = DateTime.now().toUtc();
    // Look for shifts that are scheduled or clocked in around now
    final shifts = await DatabaseService.getShiftsInRange(
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(days: 1)),
    );

    // Priority: ClockedIn > Scheduled (closest future)
    final clockedIn = shifts.where((s) => s.status == ShiftStatus.clockedIn).toList();
    if (clockedIn.isNotEmpty) {
      state = clockedIn.first;
      return;
    }

    final upcoming = shifts
        .where((s) => s.status == ShiftStatus.scheduled && s.plannedStartUtc.isAfter(now))
        .toList()
      ..sort((a, b) => a.plannedStartUtc.compareTo(b.plannedStartUtc));

    state = upcoming.isNotEmpty ? upcoming.first : null;
  }

  Future<void> clockIn(String uuid) async {
    // Optimistic UI Update
    final currentShift = state;
    if (currentShift != null && currentShift.uuid == uuid) {
      currentShift.status = ShiftStatus.clockedIn;
      currentShift.actualStartUtc = DateTime.now().toUtc();
      state = currentShift; 
    }

    // Persist to DB
    await DatabaseService.updateShiftStatus(uuid, ShiftStatus.clockedIn);
  }

  Future<void> clockOut(String uuid) async {
    // Optimistic UI Update
    final currentShift = state;
    if (currentShift != null && currentShift.uuid == uuid) {
      currentShift.status = ShiftStatus.clockedOut;
      currentShift.actualEndUtc = DateTime.now().toUtc();
      state = currentShift;
    }

    // Persist to DB
    await DatabaseService.updateShiftStatus(uuid, ShiftStatus.clockedOut);
  }
}

// Stream provider for all shifts in a range (for Calendar)
final shiftsInRangeProvider = StreamProvider.family<List<Shift>, DateTimeRange>((ref, range) {
  return DatabaseService.instance.shifts
      .filter()
      .plannedStartUtcBetween(range.start.toUtc(), range.end.toUtc())
      .sortByPlannedStartUtc()
      .watch();
});
