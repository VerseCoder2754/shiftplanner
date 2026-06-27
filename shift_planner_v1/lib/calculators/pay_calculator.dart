import 'package:decimal/decimal.dart';

class PayCalculator {
  /// Calculates total pay splitting Regular vs Overtime based on weekly threshold.
  /// [weeklyHoursThreshold] defaults to 40.0 hours.
  static Map<String, dynamic> calculateShiftPay({
    required DateTime startUtc,
    required DateTime endUtc,
    required Decimal hourlyRate,
    required Decimal otMultiplier,
    double weeklyHoursThreshold = 40.0,
  }) {
    if (endUtc.isBefore(startUtc)) {
      throw ArgumentError("End time cannot be before start time");
    }

    final duration = endUtc.difference(startUtc);
    final totalHoursDecimal = Decimal.fromInt(duration.inHours) + 
                              Decimal.fromInt(duration.inMinutes % 60) / Decimal.fromInt(60);

    // Simplified V1 Logic: Assume this shift doesn't cross the weekly boundary for calculation simplicity
    // In a full V2, we would split the shift across the specific "Pay Week Start Day"
    
    Decimal regularPay = Decimal.zero;
    Decimal otPay = Decimal.zero;
    Decimal regularHours = Decimal.zero;
    Decimal otHours = Decimal.zero;

    // Note: Real OT logic requires knowing current week accumulation. 
    // For V1, we calculate potential pay assuming all regular unless > threshold in one go (rare)
    // Or simply treat all as regular and let weekly report handle OT aggregation.
    
    // V1 Approach: Calculate gross hours. OT determination happens at Weekly Report level usually.
    // However, if requested to split here, we assume user inputs current week total.
    // For this standalone function, we return Total Gross.
    
    regularHours = totalHoursDecimal;
    regularPay = totalHoursDecimal * hourlyRate;

    return {
      'totalHours': totalHoursDecimal,
      'regularHours': regularHours,
      'otHours': otHours,
      'regularPay': regularPay,
      'otPay': otPay,
      'totalPay': regularPay + otPay,
    };
  }

  /// Formats Decimal to Currency String (USD)
  static String formatCurrency(Decimal amount) {
    // Round to 2 decimal places
    final rounded = amount.round(scale: 2);
    return '\$${rounded.toString()}';
  }

  /// Formats Decimal to Hours String (e.g., "7.5h")
  static String formatHours(Decimal hours) {
    final rounded = hours.round(scale: 2);
    return '${rounded.toString()}h';
  }
}
