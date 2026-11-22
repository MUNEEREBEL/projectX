import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/alert_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_setup_screen.dart';
import 'main_navigation_shell.dart';

/// Observer that automatically dismisses the software keyboard on any route navigation
class RouteKeyboardDismissObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely attempt to load .env if available
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // If .env is missing or cannot be parsed, fallback mechanisms in AppConfig handle it
  }

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
      navigatorObservers: [RouteKeyboardDismissObserver()],
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: isOnboardingCompleted
          ? const MainNavigationShell()
          : const OnboardingSetupScreen(),
    );
  }
}
