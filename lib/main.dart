import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/alert_service.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_setup_screen.dart';
import 'features/overlay/assistive_ball_widget.dart';
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

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely attempt to load .env if available, fallback to .env.example
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    try {
      await dotenv.load(fileName: ".env.example");
    } catch (_) {
      // Handled cleanly by AppConfig fallbacks
    }
  }

  // Initialize background local notification engine for expiry alerts
  await AlertService.instance.init();

  final prefs = await SharedPreferences.getInstance();
  final isOnboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(
    ProviderScope(
      child: ProjectXApp(isOnboardingCompleted: isOnboardingCompleted),
    ),
  );
}

class ProjectXApp extends StatelessWidget {
  final bool isOnboardingCompleted;

  const ProjectXApp({super.key, required this.isOnboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Project X',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      navigatorObservers: [RouteKeyboardDismissObserver()],
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: AssistiveBallWidget(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: isOnboardingCompleted
          ? const MainNavigationShell()
          : const OnboardingSetupScreen(),
    );
  }
}
