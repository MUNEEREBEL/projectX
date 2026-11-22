import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/alert_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_setup_screen.dart';
import 'main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background local notification engine for expiry alerts
  await AlertService.instance.init();

  final prefs = await SharedPreferences.getInstance();
  final isOnboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(
    ProviderScope(
      child: PrivDocApp(isOnboardingCompleted: isOnboardingCompleted),
    ),
  );
}

class PrivDocApp extends StatelessWidget {
  final bool isOnboardingCompleted;

  const PrivDocApp({super.key, required this.isOnboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivDoc AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: isOnboardingCompleted
          ? const MainNavigationShell()
          : const OnboardingSetupScreen(),
    );
  }
}
