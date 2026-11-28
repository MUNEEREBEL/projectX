import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _prefApiKey = 'gemini_api_key';
  static const String _prefGroqApiKey = 'groq_api_key';

  /// In-memory or pre-compiled fallback key
  static String staticFallbackKey = '';

  /// Retrieve the active Groq API Key if configured
  static Future<String?> getGroqApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = prefs.getString(_prefGroqApiKey);
      if (prefKey != null && prefKey.trim().isNotEmpty) {
        return prefKey.trim();
      }
      final generalKey = prefs.getString(_prefApiKey);
      if (generalKey != null && generalKey.trim().startsWith('gsk_')) {
        return generalKey.trim();
      }
    } catch (_) {}

    try {
      final envKey = dotenv.maybeGet('GROQ_API_KEY');
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}

    return null;
  }

  static Future<void> setGroqApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGroqApiKey, key.trim());
  }

  /// Retrieve all available Gemini API keys (Primary and Fallback Key 2)
  static Future<List<String>> getGeminiApiKeys() async {
    final keys = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = prefs.getString(_prefApiKey);
      if (prefKey != null && prefKey.trim().isNotEmpty && !prefKey.trim().startsWith('gsk_')) {
        keys.add(prefKey.trim());
      }
    } catch (_) {}

    try {
      final k1 = dotenv.maybeGet('GEMINI_API_KEY');
      if (k1 != null && k1.trim().isNotEmpty && !keys.contains(k1.trim())) {
        keys.add(k1.trim());
      }
      final k2 = dotenv.maybeGet('GEMINI_API_KEY_2');
      if (k2 != null && k2.trim().isNotEmpty && !keys.contains(k2.trim())) {
        keys.add(k2.trim());
      }
    } catch (_) {}

    if (keys.isEmpty && staticFallbackKey.trim().isNotEmpty) {
      keys.add(staticFallbackKey.trim());
    }
    return keys;
  }

  /// Retrieve the active Gemini API key in order of priority:
  /// 1. User entered in Settings/Onboarding (SharedPreferences)
  /// 2. Loaded from .env file
  /// 3. Injected via --dart-define=GEMINI_API_KEY=...
  /// 4. Hardcoded static fallback (if configured)
  static Future<String?> getApiKey() async {
    final keys = await getGeminiApiKeys();
    return keys.isNotEmpty ? keys.first : null;
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key.trim();
    if (trimmed.startsWith('gsk_')) {
      await prefs.setString(_prefGroqApiKey, trimmed);
    }
    await prefs.setString(_prefApiKey, trimmed);
  }

  static Future<bool> hasValidApiKey() async {
    final key = await getApiKey();
    final groqKey = await getGroqApiKey();
    return (key != null && key.trim().isNotEmpty) || (groqKey != null && groqKey.trim().isNotEmpty);
  }
}
