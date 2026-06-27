import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class DatabaseService {
  static late Isar _isar;

  static Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    
    _isar = await Isar.open(
      [ShiftSchema, AppSettingsSchema],
      directory: dir.path,
    );

    // Initialize default settings if not exists
    final existingSettings = await _isar.appSettings.filter().keyEqualTo('global_settings').findFirst();
    if (existingSettings == null) {
      final defaultSettings = AppSettings();
      await _isar.writeTxn(() => _isar.appSettings.put(defaultSettings));
    }
  }

  static Isar get instance => _isar;

  // Shift CRUD
  static Future<void> saveShift(Shift shift) async {
    await _isar.writeTxn(() => _isar.shifts.put(shift));
  }

  static Future<List<Shift>> getShiftsInRange(DateTime startUtc, DateTime endUtc) async {
    return await _isar.shifts
        .filter()
        .plannedStartUtcBetween(startUtc, endUtc)
        .sortByPlannedStartUtc();
  }

  static Future<Shift?> getShiftByUuid(String uuid) async {
    return await _isar.shifts.filter().uuidEqualTo(uuid).findFirst();
  }

  static Future<void> updateShiftStatus(String uuid, ShiftStatus status, {DateTime? actualTime}) async {
    final shift = await getShiftByUuid(uuid);
    if (shift == null) throw Exception("Shift not found");

    shift.status = status;
    shift.updatedAtUtc = DateTime.now().toUtc();

    if (status == ShiftStatus.clockedIn) {
      shift.actualStartUtc = actualTime ?? DateTime.now().toUtc();
    } else if (status == ShiftStatus.clockedOut) {
      shift.actualEndUtc = actualTime ?? DateTime.now().toUtc();
    }

    await saveShift(shift);
  }

  // Settings
  static Future<AppSettings> getSettings() async {
    final settings = await _isar.appSettings.filter().keyEqualTo('global_settings').findFirst();
    return settings ?? AppSettings();
  }

  static Future<void> updateSettings(AppSettings settings) async {
    settings.lastUpdatedUtc = DateTime.now().toUtc();
    await _isar.writeTxn(() => _isar.appSettings.put(settings));
  }
}
