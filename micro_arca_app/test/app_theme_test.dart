import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro_arca_app/services/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tema segue o sistema por padrão e preserva a escolha salva', () async {
    SharedPreferences.setMockInitialValues({});
    await AppTheme.instance.load();
    expect(AppTheme.instance.mode, ThemeMode.system);
    await AppTheme.instance.setMode(ThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('appearance.theme'), 'dark');
    await AppTheme.instance.load();
    expect(AppTheme.instance.mode, ThemeMode.dark);
    await AppTheme.instance.setMode(ThemeMode.light);
    await AppTheme.instance.load();
    expect(AppTheme.instance.mode, ThemeMode.light);
  });

  test('preferência desconhecida usa o tema do sistema', () async {
    SharedPreferences.setMockInitialValues({'appearance.theme': 'invalido'});
    await AppTheme.instance.load();
    expect(AppTheme.instance.mode, ThemeMode.system);
  });
}
