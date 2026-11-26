import 'package:flutter/material.dart';
import '../pages/settings_page.dart';
import '../pages/legal_page.dart';
import '../services/app_theme.dart';
import '../services/micropython_repl_service.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MicroPythonREPLService();
    final light = Theme.of(context).brightness == Brightness.light;
    return AppBar(
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✨ MicroArca ✨',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('Editor de MicroPython para ESP32',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      centerTitle: true,
      backgroundColor: light ? const Color.fromARGB(255, 7, 207, 233) : null,
      foregroundColor: light ? Colors.white : null,
      elevation: light ? 10 : null,
      shadowColor: light ? const Color.fromARGB(255, 122, 142, 145) : null,
      leading: PopupMenuButton<ThemeMode>(
        tooltip: 'Aparência',
        icon: const Icon(Icons.brightness_6_outlined),
        initialValue: AppTheme.instance.mode,
        onSelected: (mode) async {
          try {
            await AppTheme.instance.setMode(mode);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Não foi possível salvar a aparência.'),
              ));
            }
          }
        },
        itemBuilder: (_) => [
          for (final entry in const {
            ThemeMode.system: 'Seguir o sistema',
            ThemeMode.light: 'Claro',
            ThemeMode.dark: 'Escuro',
          }.entries)
            CheckedPopupMenuItem(
              value: entry.key,
              checked: AppTheme.instance.mode == entry.key,
              child: Text(entry.value),
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Sobre e privacidade',
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LegalPage()),
          ),
        ),
        ListenableBuilder(
          listenable: service,
          builder: (context, _) => IconButton(
            tooltip: service.isConnected ? 'Kit conectado' : 'Conectar ao kit',
            icon: Icon(service.isConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Conexão e kit')),
                        body: const SafeArea(child: SettingsPage()),
                      )),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
