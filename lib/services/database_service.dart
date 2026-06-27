import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/shift_model.dart';

/// Service layer for interacting with the local Isar database.
class DatabaseService {
  late final Isar _isar;

  /// Initialize the database instance.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    
    _isar = await Isar.open(
      [ShiftSchema, AppSettingsSchema],
      directory: dir.path,
      inspector: true, // Enable for debugging
    );

    // Ensure default settings exist
    if (_isar.settings.count() == 0) {
      final defaultSettings = AppSettings();
      await _isar.writeTxn(() => _isar.settings.put(defaultSettings));
    }
  }

  Isar get db => _isar;

  // --- Shift CRUD Operations ---

  /// Get all shifts ordered by start time.
  Future<List<Shift>> getAllShifts() async {
    return await _isar.shifts.filter().sortByPlannedStartUtc();
  }

  /// Get shifts within a specific date range (UTC).
  Future<List<Shift>> getShiftsInRange(DateTime startUtc, DateTime endUtc) async {
    return await _isar.shifts
        .filter()
        .plannedStartUtcBetween(startUtc, endUtc)
        .findAll();
  }

  /// Get a single shift by UUID.
  Future<Shift?> getShiftById(String uuid) async {
    return await _isar.shifts.filter().uuidEqualTo(uuid).findFirst();
  }

  /// Insert or update a shift.
  Future<void> saveShift(Shift shift) async {
    await _isar.writeTxn(() => _isar.shifts.put(shift));
  }

  /// Update an existing shift.
  Future<void> updateShift(Shift shift) async {
    await _isar.writeTxn(() => _isar.shifts.put(shift));
  }

  /// Delete a shift.
  Future<void> deleteShift(String uuid) async {
    final shift = await getShiftById(uuid);
    if (shift != null) {
      await _isar.writeTxn(() => _isar.shifts.delete(shift.id));
    }
  }

  // --- Settings Operations ---

  /// Get current app settings.
  Future<AppSettings> getSettings() async {
    final settings = await _isar.settings.get(0);
    return settings ?? AppSettings();
  }

  /// Update app settings.
  Future<void> updateSettings(AppSettings settings) async {
    await _isar.writeTxn(() => _isar.settings.put(settings));
  }
}

// Extension to access the 'settings' box easily
extension on Isar {
  IsarCollection<AppSettings> get settings => collection<AppSettings>();
  IsarCollection<Shift> get shifts => collection<Shift>();
}
