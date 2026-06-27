import 'package:intl/intl.dart';

class DateUtils {
  /// Converts UTC DateTime to Local Time for UI display
  static DateTime toLocal(DateTime utc) {
    return utc.toLocal();
  }

  /// Formats DateTime to "Mon, Jan 1"
  static String formatDateShort(DateTime dt) {
    return DateFormat('EEE, MMM d').format(dt.toLocal());
  }

  /// Formats DateTime to "09:00 AM"
  static String formatTime(DateTime dt) {
    return DateFormat('hh:mm a').format(dt.toLocal());
  }

  /// Gets the start of the week based on settings (Sunday or Monday)
  static DateTime getWeekStart(DateTime date, int startDay) {
    // startDay: 0=Monday, 6=Sunday (ISO standard is Monday=1)
    // Adjusting for Dart where Sunday=0, Monday=1...
    final weekday = date.weekday; // 1=Monday, 7=Sunday
    
    int daysToSubtract = weekday - 1; // Default to Monday start
    
    if (startDay == 6) { 
      // If user wants Sunday start
      // Sunday is 7 in weekday, we want it to be 0 offset
      daysToSubtract = (weekday % 7); 
    }
    
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysToSubtract));
  }
}
