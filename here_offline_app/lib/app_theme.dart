import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';

/// App-wide theme helper (persisted preference)
class AppTheme {
  static const _prefKey = 'theme_mode';
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'dark') {
        mode.value = ThemeMode.dark;
      } else if (saved == 'light') {
        mode.value = ThemeMode.light;
      } else {
        mode.value = ThemeMode.system;
      }
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

// Riverpod provider for theme
final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('theme_mode');
      if (saved == 'dark') {
        state = ThemeMode.dark;
      } else if (saved == 'light') {
        state = ThemeMode.light;
      } else {
        state = ThemeMode.system;
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = (mode == ThemeMode.dark) ? 'dark' : (mode == ThemeMode.light) ? 'light' : 'system';
      await prefs.setString('theme_mode', s);
    } catch (e) {}
  }
}
