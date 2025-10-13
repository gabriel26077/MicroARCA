import 'package:flutter/material.dart';

/// Página principal para edição de código.
///
/// Segue a convenção de nomenclatura de classes PascalCase.
class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Aqui você construirá a interface do seu editor
    return const Center(
      child: Text(
        'Página do Editor',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
