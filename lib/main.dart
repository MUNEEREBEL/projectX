import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/alert_service.dart';
import 'core/theme/app_theme.dart';
import 'main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background local notification engine for expiry alerts
  await AlertService.instance.init();

  runApp(
    const ProviderScope(
      child: PrivDocApp(),
    ),
  );
}

class PrivDocApp extends StatelessWidget {
  const PrivDocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivDoc AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const MainNavigationShell(),
    );
  }
}
