import 'package:flutter/material.dart';

/// Provides theme state (dark / light) to the whole app.
/// Wrap your MaterialApp with ChangeNotifierProvider<ThemeProvider>.
class ThemeProvider extends ChangeNotifier {
  // Default = light mode
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool value) {
    if (_isDarkMode != value) {
      _isDarkMode = value;
      notifyListeners();
    }
  }

  /// Convenience getter: returns the matching ThemeData
  ThemeData get themeData => _isDarkMode ? darkTheme : lightTheme;

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F4FB),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF6C63FF),
      secondary: Color(0xFF43E97B),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F0E17),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF6C63FF),
      secondary: Color(0xFF43E97B),
    ),
  );
}