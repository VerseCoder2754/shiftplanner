import 'package:decimal/decimal.dart';
import '../models/shift_model.dart';

/// Pure Dart calculator for shift hours and pay.
/// Uses `decimal` package to avoid floating point errors.
/// All rounding happens ONLY at the final UI display step.
class PayCalculator {
  /// Calculate total hours worked for a single shift.
  /// Returns Decimal hours (e.g., 8.5 hours).
  static Decimal calculateHours(Shift shift) {
    if (shift.actualStartUtc == null || shift.actualEndUtc == null) {
      // If not clocked out, calculate until now or planned end?
      // For V1, we return 0 if not fully completed, or calculate based on available data
      if (shift.actualStartUtc != null && shift.status == ShiftStatus.clockedIn) {
        // Currently working
        final start = shift.actualStartUtc!;
        final now = DateTime.now().toUtc();
        return _calculateDuration(start, now);
      }
      return Decimal.zero;
    }

    return _calculateDuration(shift.actualStartUtc!, shift.actualEndUtc!);
  }

  /// Calculate duration in hours between two UTC datetimes.
  static Decimal _calculateDuration(DateTime start, DateTime end) {
    final difference = end.difference(start);
    final totalMinutes = Decimal.fromInt(difference.inMinutes);
    // Convert minutes to hours: minutes / 60
    return totalMinutes / Decimal.fromInt(60);
  }

  /// Calculate total pay for a shift, handling Overtime rules.
  /// [payWeekStartDay] defines when the pay week resets (e.g., Sunday 00:00).
  /// This method assumes the caller provides the cumulative hours for the current pay week
  /// to correctly determine if this shift crosses into OT territory.
  /// 
  /// For V1 simplicity, we calculate per-shift OT based on a standard 40h week assumption
  /// passed as [hoursWorkedThisWeekBeforeShift].
  static Decimal calculatePay({
    required Shift shift,
    required Decimal hoursWorkedThisWeekBeforeShift,
  }) {
    final totalHours = calculateHours(shift);
    if (totalHours == Decimal.zero) return Decimal.zero;

    final baseRate = Decimal.parse(shift.baseHourlyRate.toStringAsFixed(2));
    final otMultiplier = Decimal.parse(shift.otMultiplier.toStringAsFixed(2));
    
    // Standard 40 hour work week limit
    const weeklyOtLimit = Decimal.fromInt(40);

    Decimal regularPay = Decimal.zero;
    Decimal otPay = Decimal.zero;

    // Determine how many hours of THIS shift are Regular vs OT
    Decimal regularHours = Decimal.zero;
    Decimal otHours = Decimal.zero;

    Decimal runningTotal = hoursWorkedThisWeekBeforeShift;

    // We iterate minute by minute conceptually, but mathematically:
    // 1. Hours until we hit 40
    // 2. Hours after 40
    
    if (runningTotal >= weeklyOtLimit) {
      // Already in OT before this shift started
      otHours = totalHours;
    } else if (runningTotal + totalHours <= weeklyOtLimit) {
      // Entire shift is regular
      regularHours = totalHours;
    } else {
      // Shift crosses the boundary
      regularHours = weeklyOtLimit - runningTotal;
      otHours = totalHours - regularHours;
    }

    regularPay = regularHours * baseRate;
    otPay = otHours * baseRate * otMultiplier;

    return regularPay + otPay;
  }

  /// Format Decimal to currency string (e.g., "$123.45").
  /// Rounding happens HERE, not in calculations.
  static String formatCurrency(Decimal amount, {String symbol = '\$'}) {
    // Round to 2 decimal places
    final rounded = amount.toScale(2);
    return '$symbol${rounded.toString()}';
  }

  /// Format Decimal to time string (e.g., "7h 30m").
  static String formatHours(Decimal hours) {
    final totalMinutes = (hours * Decimal.fromInt(60)).toInt();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }
  
  /// Calculate cumulative hours for a list of shifts (completed only).
  static Decimal calculateWeeklyHours(List<Shift> shifts) {
    Decimal total = Decimal.zero;
    for (final shift in shifts) {
      if (shift.status == ShiftStatus.clockedOut) {
        total += calculateHours(shift);
      }
    }
    return total;
  }
}
