import 'package:flutter/material.dart';

/// O container em formato de pílula que agrupa as abas de navegação.
class TopNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const TopNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color:  const Color.fromARGB(248, 219, 250, 255),
        borderRadius: BorderRadius.circular(50.0),
        border: Border.all(color: Color.fromARGB(248, 183, 245, 255), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(158, 158, 158, 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _NavTab(
            text: 'Editor',
            icon: Icons.code,
            isSelected: selectedIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavTab(
            text: 'Console',
            icon: Icons.terminal,
            isSelected: selectedIndex == 1,
            onTap: () => onTap(1),
          ),
          _NavTab(
            text: 'Configs',
            icon: Icons.settings,
            isSelected: selectedIndex == 2,
            onTap: () => onTap(2),
          ),
        ],
      ),
    );
  }
}

/// A aba individual clicável dentro da TopNavBar.
/// O _ no início a torna privada a este arquivo.
class _NavTab extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTab({
    required this.text,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = const Color.fromARGB(255, 7, 207, 233);
    final Color inactiveColor = Colors.grey[700]!;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(50.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : inactiveColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? Colors.white : inactiveColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
