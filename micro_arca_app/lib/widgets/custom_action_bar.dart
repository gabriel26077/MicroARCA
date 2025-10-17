import 'package:flutter/material.dart';

// Constante para a cor primária (cian/turquesa) - Ajuste este valor se necessário
// Este é um exemplo de um turquesa
const Color primaryColor = Color(0xFF00BCD4); 

// Constante para a cor amarela dos círculos
// Este é o amarelo padrão do Material Design
const Color accentColor = Color(0xFFFFC107); 

// === 1. WIDGET DE BOTÃO INDIVIDUAL (ActionButton) ===
// Representa o círculo com ícone e o rótulo de texto.
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // InkWell permite o efeito de toque (ripple) e captura o evento
    return InkWell(
      onTap: onTap,
      // Column para empilhar o círculo e o texto
      child: Column(
        mainAxisSize: MainAxisSize.min, // Ocupa o mínimo de espaço vertical
        children: <Widget>[
          // CircleAvatar para o círculo amarelo
          CircleAvatar(
            radius: 24, // Tamanho do círculo
            backgroundColor: accentColor, // Fundo amarelo
            child: Icon(
              icon,
              color: Colors.black87, // Ícone escuro para contraste
              size: 20,
            ),
          ),
          const SizedBox(height: 4), // Espaçamento entre círculo e texto
          // Texto para o rótulo
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87, // Texto escuro para contraste
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// === 2. WIDGET DA BARRA PRINCIPAL (CustomActionBar) ===
// O container que será usado no bottomNavigationBar do Scaffold.
class CustomActionBar extends StatelessWidget {
  const CustomActionBar({Key? key}) : super(key: key);

  // Função para lidar com o toque de cada botão (deve ser substituída pela lógica real)
  void _handleTap(String action) {
    // Você pode usar 'print' ou 'debugPrint' durante o desenvolvimento
    debugPrint('Ação acionada: $action');
    // Implemente a lógica de Load, Save, Send, Run aqui
  }

  @override
  Widget build(BuildContext context) {
    // Container para definir a cor de fundo e as bordas arredondadas
    return Container(
      // Padding interno para que os botões não fiquem colados nas bordas
      padding: const EdgeInsets.only(
          top: 10, bottom: 10, left: 20, right: 20), 
      decoration: const BoxDecoration(
        color: primaryColor, // Cor de fundo primária (cian/turquesa)
        // Bordas arredondadas apenas no topo
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      // Row para alinhar os quatro botões horizontalmente
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround, // Distribuição uniforme
        children: <Widget>[
          // Botão 1: Load
          ActionButton(
            icon: Icons.folder_open_outlined,
            label: 'Load',
            onTap: () => _handleTap('Load'),
          ),
          // Botão 2: Save
          ActionButton(
            icon: Icons.save_alt_outlined,
            label: 'Save',
            onTap: () => _handleTap('Save'),
          ),
          // Botão 3: Send
          ActionButton(
            icon: Icons.send,
            label: 'Send',
            onTap: () => _handleTap('Send'),
          ),
          // Botão 4: Run
          ActionButton(
            icon: Icons.play_arrow,
            label: 'Run',
            onTap: () => _handleTap('Run'),
          ),
        ],
      ),
    );
  }
}