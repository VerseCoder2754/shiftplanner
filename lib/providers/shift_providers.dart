import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';
import '../models/shift_model.dart';
import '../services/database_service.dart';
import '../services/attendance_engine.dart';

// --- Providers ---

/// Provider for the DatabaseService singleton.
final databaseProvider = Provider<DatabaseService>((ref) {
  final db = DatabaseService();
  // Initialization should be called in main() before runApp
  return db;
});

/// Provider for the AttendanceEngine singleton.
final attendanceEngineProvider = Provider<AttendanceEngine>((ref) {
  final db = ref.watch(databaseProvider);
  return AttendanceEngine(db);
});

/// Stream provider that watches all shifts in the database.
/// Automatically rebuilds UI when data changes.
final shiftsStreamProvider = StreamProvider<List<Shift>>((ref) {
  final db = ref.watch(databaseProvider);
  // In a real Isar implementation, you'd use `db.isar.shifts.watch().findAll()`
  // For this V1 structure, we simulate a stream or use a polling approach if Isar watch isn't directly exposed
  // Ideally: return ref.watch(databaseProvider).isar.shifts.watch().findAll();
  
  // Placeholder implementation returning a future that could be converted to stream
  return Stream.fromFuture(db.getAllShifts());
});

/// Notifier provider for managing the current active shift state.
class ActiveShiftNotifier extends StateNotifier<Shift?> {
  final DatabaseService _db;

  ActiveShiftNotifier(this._db) : super(null);

  /// Load the currently active shift (ClockedIn or upcoming Scheduled).
  Future<void> loadActiveShift() async {
    final allShifts = await _db.getAllShifts();
    final now = DateTime.now().toUtc();

    // Priority 1: Currently Clocked In
    final clockedIn = allShifts.firstWhere(
      (s) => s.status == ShiftStatus.clockedIn,
      orElse: () => Shift(
        uuid: '', plannedStartUtc: now, plannedEndUtc: now,
        type: '', baseHourlyRate: 0, otMultiplier: 1, payWeekStartDay: 7,
      ),
    );

    if (clockedIn.uuid.isNotEmpty) {
      state = clockedIn;
      return;
    }

    // Priority 2: Next Scheduled Shift (today or future)
    final upcoming = allShifts
        .where((s) => s.status == ShiftStatus.scheduled && s.plannedStartUtc.isAfter(now))
        .toList()
      ..sort((a, b) => a.plannedStartUtc.compareTo(b.plannedStartUtc));

    if (upcoming.isNotEmpty) {
      state = upcoming.first;
    } else {
      state = null;
    }
  }

  /// Manually trigger a clock in.
  Future<void> clockIn(String uuid) async {
    final shift = await _db.getShiftById(uuid);
    if (shift == null) return;

    // Optimistic UI update
    final updated = shift.copyWith(
      status: ShiftStatus.clockedIn,
      actualStartUtc: DateTime.now().toUtc(),
    );
    
    state = updated; // Update UI immediately
    
    await _db.updateShift(updated);
    // AttendanceEngine will handle notifications separately via listener or explicit call
  }

  /// Manually trigger a clock out.
  Future<void> clockOut(String uuid) async {
    final shift = await _db.getShiftById(uuid);
    if (shift == null) return;

    // Optimistic UI update
    final updated = shift.copyWith(
      status: ShiftStatus.clockedOut,
      actualEndUtc: DateTime.now().toUtc(),
    );

    state = updated; // Update UI immediately

    await _db.updateShift(updated);
    
    // Reload to find next shift after short delay
    Future.delayed(const Duration(seconds: 1), loadActiveShift);
  }
}

final activeShiftProvider = StateNotifierProvider<ActiveShiftNotifier, Shift?>((ref) {
  final db = ref.watch(databaseProvider);
  return ActiveShiftNotifier(db);
});

/// Simple ValueNotifier wrapper for the countdown timer to avoid full screen rebuilds.
/// Usage: `ValueListenableBuilder` in UI.
final countdownTimerProvider = Provider<ValueNotifier<Duration>>((ref) {
  return ValueNotifier<Duration>(Duration.zero);
});
