import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _prefApiKey = 'gemini_api_key';

  /// In-memory or pre-compiled fallback key
  static String staticFallbackKey = '';

  /// Retrieve the active Gemini API key in order of priority:
  /// 1. User entered in Settings/Onboarding (SharedPreferences)
  /// 2. Loaded from .env file
  /// 3. Injected via --dart-define=GEMINI_API_KEY=...
  /// 4. Hardcoded static fallback (if configured)
  static Future<String?> getApiKey() async {
    // 1. SharedPreferences user override
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = prefs.getString(_prefApiKey);
      if (prefKey != null && prefKey.trim().isNotEmpty) {
        return prefKey.trim();
      }
    } catch (_) {}

    // 2. flutter_dotenv (.env file)
    try {
      final envKey = dotenv.maybeGet('GEMINI_API_KEY');
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}

    // 3. Dart-define environment variable
    const dartDefineKey = String.fromEnvironment('GEMINI_API_KEY');
    if (dartDefineKey.isNotEmpty) {
      return dartDefineKey.trim();
    }

    // 4. Static fallback
    if (staticFallbackKey.trim().isNotEmpty) {
      return staticFallbackKey.trim();
    }

    return null;
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, key.trim());
  }

  static Future<bool> hasValidApiKey() async {
    final key = await getApiKey();
    return key != null && key.trim().isNotEmpty;
  }
}
