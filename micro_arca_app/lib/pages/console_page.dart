import 'package:flutter/material.dart';

/// Página para exibir logs e saídas do console.
///
/// Segue a convenção de nomenclatura de classes PascalCase.
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Aqui você construirá a interface para o log do console
    return const Center(
      child: Text(
        'Página do Console',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
