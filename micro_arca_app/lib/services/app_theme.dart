import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência de aparência, independente da conexão com a placa.
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final instance = AppTheme._();
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('appearance.theme');
    _mode = ThemeMode.values.firstWhere((mode) => mode.name == saved,
        orElse: () => ThemeMode.system);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('appearance.theme', mode.name);
  }
}
