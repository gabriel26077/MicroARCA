// lib/widgets/custom_action_bar.dart
import 'package:flutter/material.dart';

// Constante para a cor primária (cian/turquesa)
const Color primaryColor = Color(0xFF00BCD4);

// Constante para a cor amarela dos círculos
const Color accentColor = Color.fromARGB(255, 238, 255, 0);

// === 1. WIDGET DE BOTÃO INDIVIDUAL (ActionButton) ===
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: isLoading ? Colors.grey : accentColor,
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                    ),
                  )
                : Icon(icon, color: Colors.black87, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            isLoading ? '...' : label,
            style: TextStyle(
              color: isLoading ? Colors.grey : Colors.black87,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// === 2. WIDGET DA BARRA PRINCIPAL (CustomActionBar) ===
class CustomActionBar extends StatelessWidget {
  final VoidCallback onLoad;
  final VoidCallback onSave;
  final VoidCallback onSend;
  final VoidCallback onRun;
  final VoidCallback onStop; // Novo callback para o botão Stop
  final bool isSendLoading;
  final bool isRunLoading;
  final bool isStopLoading; // Novo parâmetro para loading do Stop

  const CustomActionBar({
    super.key,
    required this.onLoad,
    required this.onSave,
    required this.onSend,
    required this.onRun,
    required this.onStop, // Novo parâmetro obrigatório
    this.isSendLoading = false,
    this.isRunLoading = false,
    this.isStopLoading = false, // Novo parâmetro com valor padrão
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 10, left: 20, right: 20),
      decoration: const BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          // Botão 1: Load
          ActionButton(
            icon: Icons.folder_open_outlined,
            label: 'Load',
            onTap: onLoad,
          ),
          // Botão 2: Save
          ActionButton(
            icon: Icons.save_alt_outlined,
            label: 'Save',
            onTap: onSave,
          ),
          // Botão 5: Stop (novo botão)
          ActionButton(
            icon: Icons.stop,
            label: 'Stop',
            onTap: onStop,
            isLoading: isStopLoading,
          ),
          // Botão 3: Send
          ActionButton(
            icon: Icons.send,
            label: 'Send',
            onTap: onSend,
            isLoading: isSendLoading,
          ),
          // Botão 4: Run
          ActionButton(
            icon: Icons.play_arrow,
            label: 'Run',
            onTap: onRun,
            isLoading: isRunLoading,
          ),
        ],
      ),
    );
  }
}
