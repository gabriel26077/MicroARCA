import 'package:flutter/material.dart';

/// Página para as configurações do aplicativo.
///
/// Segue a convenção de nomenclatura de classes PascalCase.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Aqui você construirá a interface das configurações
    return const Center(
      child: Text(
        'Página de Configurações',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
