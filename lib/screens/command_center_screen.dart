import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:riverpod/riverpod.dart';
import 'package:intl/intl.dart';
import '../models/shift_model.dart';
import '../providers/shift_providers.dart';
import '../calculators/pay_calculator.dart';

/// The "Command Center" Home Screen.
/// Dynamic UI based on shift state: Pre-Shift, Active, Post-Shift.
class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Load initial active shift
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeShiftProvider.notifier).loadActiveShift();
    });
    
    // Start optimized timer
    _startTimer();
  }

  void _startTimer() {
    // Timer updates every minute to avoid excessive rebuilds
    Timer.periodic(const Duration(minutes: 1), (timer) {
      final notifier = ref.read(countdownTimerProvider);
      final activeShift = ref.read(activeShiftProvider);
      
      if (activeShift == null) {
        notifier.value = Duration.zero;
        return;
      }

      final now = DateTime.now();
      if (activeShift.status == ShiftStatus.scheduled) {
        final diff = activeShift.plannedStartUtc.difference(now);
        notifier.value = diff.isNegative ? Duration.zero : diff;
      } else if (activeShift.status == ShiftStatus.clockedIn) {
        final start = activeShift.actualStartUtc ?? activeShift.plannedStartUtc;
        final diff = now.difference(start);
        notifier.value = diff.isNegative ? Duration.zero : diff;
      } else {
        notifier.value = Duration.zero;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeShift = ref.watch(activeShiftProvider);
    final countdown = ref.watch(countdownTimerProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),
              _buildStatusHeader(activeShift),
              const SizedBox(height: 40),
              _buildMainDisplay(activeShift, countdown),
              const SizedBox(height: 40),
              _buildActionButtons(activeShift),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(Shift? shift) {
    String statusText;
    Color themeColor;

    if (shift == null) {
      statusText = "No upcoming shifts";
      themeColor = Colors.grey;
    } else {
      switch (shift.status) {
        case ShiftStatus.scheduled:
          statusText = "Pre-Shift";
          themeColor = Colors.blueAccent; // Cool Blue
          break;
        case ShiftStatus.clockedIn:
          statusText = "Active Shift";
          themeColor = Colors.green; // Massive Green
          break;
        case ShiftStatus.clockedOut:
        case ShiftStatus.cancelled:
          statusText = "Shift Completed";
          themeColor = Colors.deepPurpleAccent; // Relaxed Purple
          break;
      }
    }

    return Text(
      statusText,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: themeColor,
      ),
    );
  }

  Widget _buildMainDisplay(Shift? shift, ValueNotifier<Duration> countdown) {
    if (shift == null) {
      return const Text("Tap + to add a shift");
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: countdown,
      builder: (context, value, child) {
        String displayText;
        
        if (shift.status == ShiftStatus.scheduled) {
          // Countdown
          displayText = "${_formatDuration(value)} until start";
        } else if (shift.status == ShiftStatus.clockedIn) {
          // Elapsed Time
          displayText = "Elapsed: ${_formatDuration(value)}";
        } else {
          // Completed - Show Hours & Pay
          final hours = PayCalculator.calculateHours(shift);
          final pay = PayCalculator.calculatePay(
            shift: shift,
            hoursWorkedThisWeekBeforeShift: Decimal.zero, // Simplified for V1 demo
          );
          displayText = "${PayCalculator.formatHours(hours)}\n${PayCalculator.formatCurrency(pay)}";
        }

        return Column(
          children: [
            Text(
              displayText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
            if (shift.status == ShiftStatus.clockedIn)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: Icon(Icons.circle, color: Colors.green, size: 20), // Pulsing effect placeholder
              ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(Shift? shift) {
    if (shift == null) {
      return _buildAddShiftButton();
    }

    if (shift.status == ShiftStatus.scheduled) {
      return _buildClockInButton(shift.uuid);
    }

    if (shift.status == ShiftStatus.clockedIn) {
      return _buildClockOutButton(shift.uuid);
    }

    return const SizedBox.shrink();
  }

  Widget _buildAddShiftButton() {
    return ElevatedButton.icon(
      onPressed: () {
        HapticFeedback.mediumImpact();
        // Navigate to Add Shift Screen (V1 Scope: Tap Day -> Template -> Save)
      },
      icon: const Icon(Icons.add, size: 32),
      label: const Text("Add Shift", style: TextStyle(fontSize: 20)),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(200, 64), // Massive tap target
      ),
    );
  }

  Widget _buildClockInButton(String uuid) {
    return ElevatedButton(
      onPressed: () async {
        HapticFeedback.mediumImpact();
        await ref.read(activeShiftProvider.notifier).clockIn(uuid);
        // Trigger notification scheduling via AttendanceEngine
        ref.read(attendanceEngineProvider).scheduleShiftNotifications(
          await ref.read(databaseProvider).getShiftById(uuid) as Shift,
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        minimumSize: const Size(250, 72), // Massive tap target
      ),
      child: const Text("CLOCK IN", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildClockOutButton(String uuid) {
    return ElevatedButton(
      onPressed: () async {
        HapticFeedback.mediumImpact();
        await ref.read(activeShiftProvider.notifier).clockOut(uuid);
         // Trigger notification cancellation
        ref.read(attendanceEngineProvider).scheduleShiftNotifications(
           await ref.read(databaseProvider).getShiftById(uuid) as Shift,
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        minimumSize: const Size(250, 72), // Massive tap target
      ),
      child: const Text("CLOCK OUT", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return "${hours}h ${minutes}m";
    }
    return "${minutes}m";
  }
}
