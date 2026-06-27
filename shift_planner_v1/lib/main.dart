import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shift_planner_v1/providers/app_providers.dart';
import 'package:shift_planner_v1/screens/command_center_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Database before running app
  await AppProviders.initializeDatabase();

  runApp(
    const ProviderScope(
      child: ShiftPlannerApp(),
    ),
  );
}

class ShiftPlannerApp extends ConsumerWidget {
  const ShiftPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Shift Planner V1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const CommandCenterScreen(),
    );
  }
}
