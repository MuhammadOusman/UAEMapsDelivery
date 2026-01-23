import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme helper (persisted preference)
class AppTheme {
  static const _prefKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'dark') mode.value = ThemeMode.dark;
      else if (saved == 'light') mode.value = ThemeMode.light;
      else mode.value = ThemeMode.system;
    } catch (e) {
      // ignore
    }
  }

  static Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = (m == ThemeMode.dark) ? 'dark' : (m == ThemeMode.light) ? 'light' : 'system';
      await prefs.setString(_prefKey, s);
    } catch (e) {}
  }
}
