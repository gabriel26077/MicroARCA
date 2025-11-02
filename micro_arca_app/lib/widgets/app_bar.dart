import 'package:flutter/material.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '✨ MicroArca ✨', // Título principal
            style: TextStyle(
              fontSize: 20.00,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Editor de MicroPython para ESP32',
            style: TextStyle(
              fontSize: 14.00,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      centerTitle: true,
      backgroundColor: const Color.fromARGB(255, 7, 207, 233),
      foregroundColor: Colors.white,
      elevation: 10.00,
      shadowColor: const Color.fromARGB(255, 122, 142, 145),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}