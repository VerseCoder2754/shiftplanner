import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import 'package:vibration/vibration.dart';
import '../providers/app_providers.dart';
import '../models/models.dart';
import '../calculators/pay_calculator.dart';
import '../services/attendance_engine.dart';

class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  ConsumerState<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen> {
  // ValueNotifier for efficient timer updates without full rebuilds
  final ValueNotifier<String> _timeDisplay = ValueNotifier('0h 0m');
  final ValueNotifier<Color> _themeColor = ValueNotifier(Colors.blue);
  
  DateTime? _shiftStart;
  ShiftStatus _currentStatus = ShiftStatus.scheduled;

  @override
  void initState() {
    super.initState();
    ref.read(activeShiftProvider.notifier).loadActiveShift();
  }

  @override
  void dispose() {
    _timeDisplay.dispose();
    _themeColor.dispose();
    super.dispose();
  }

  void _updateTimer(Shift? shift) {
    if (shift == null) {
      _timeDisplay.value = "No Shift";
      return;
    }

    final now = DateTime.now();
    
    if (shift.status == ShiftStatus.clockedIn) {
      final start = shift.actualStartUtc ?? shift.plannedStartUtc;
      final diff = now.difference(start.toLocal());
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      _timeDisplay.value = "${hours}h ${minutes}m";
      _themeColor.value = Colors.green;
      _currentStatus = ShiftStatus.clockedIn;
    } else if (shift.status == ShiftStatus.scheduled && shift.plannedStartUtc.isAfter(now)) {
      final diff = shift.plannedStartUtc.toLocal().difference(now);
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      _timeDisplay.value = "in ${hours}h ${minutes}m";
      _themeColor.value = Colors.blue;
      _currentStatus = ShiftStatus.scheduled;
    } else if (shift.status == ShiftStatus.clockedOut) {
      final start = shift.actualStartUtc ?? shift.plannedStartUtc;
      final end = shift.actualEndUtc ?? shift.plannedEndUtc;
      final diff = end.difference(start);
      final hours = diff.inHours + (diff.inMinutes % 60) / 60.0;
      _timeDisplay.value = "${hours.toStringAsFixed(1)}h Total";
      _themeColor.value = Colors.deepPurple;
      _currentStatus = ShiftStatus.clockedOut;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeShift = ref.watch(activeShiftProvider);

    // Setup periodic timer (1 minute)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTimer(activeShift);
      // In a real implementation, use Timer.periodic(Duration(minutes: 1), ...) here
      // and dispose it in dispose()
    });

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _themeColor.value.withOpacity(0.2),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Header
              Text(
                activeShift == null ? "No Upcoming Shifts" : "Your Shift",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 60),
              
              // Main Timer Display (ValueListenableBuilder for optimization)
              ValueListenableBuilder<String>(
                valueListenable: _timeDisplay,
                builder: (context, value, child) {
                  return Text(
                    value,
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: _themeColor.value,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
              
              const Spacer(),
              
              // Action Area
              if (activeShift != null) ...[
                _buildActionCard(activeShift),
                const SizedBox(height: 40),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(Shift shift) {
    if (shift.status == ShiftStatus.clockedOut || shift.status == ShiftStatus.cancelled) {
      // Post-Shift Summary
      final hours = PayCalculator.formatHours(Decimal.fromInt(8)); // Placeholder calculation
      final pay = PayCalculator.formatCurrency(Decimal.fromInt(160)); 
      
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.deepPurple, size: 48),
              const SizedBox(height: 16),
              Text("Shift Completed", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text("Hours: $hours"),
              Text("Est. Pay: $pay"),
            ],
          ),
        ),
      );
    } else if (shift.status == ShiftStatus.clockedIn) {
      // Active Shift - Massive Clock Out Button
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SizedBox(
          width: double.infinity,
          height: 72, // Massive tap target
          child: ElevatedButton.icon(
            icon: const Icon(Icons.power_settings_new, size: 32),
            label: const Text("CLOCK OUT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () async {
              if (ref.read(settingsProvider).value?.hapticFeedbackEnabled == true) {
                Vibration.vibrate(duration: 50);
              }
              await ref.read(activeShiftProvider.notifier).clockOut(shift.uuid);
              AttendanceEngine.cancelAllForShift(shift.uuid);
            },
          ),
        ),
      );
    } else {
      // Pre-Shift - Clock In Button
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: SizedBox(
          width: double.infinity,
          height: 72,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.login, size: 32),
            label: const Text("CLOCK IN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () async {
              if (ref.read(settingsProvider).value?.hapticFeedbackEnabled == true) {
                Vibration.vibrate(duration: 50);
              }
              await ref.read(activeShiftProvider.notifier).clockIn(shift.uuid);
              // Schedule clock out reminder
              AttendanceEngine.scheduleClockOutReminder(shift.uuid);
            },
          ),
        ),
      );
    }
  }
}
