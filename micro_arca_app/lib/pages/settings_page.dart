import 'package:flutter/material.dart';

import 'libraries_page.dart';
import '../services/micropython_repl_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MicroPythonREPLService();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final scanning = service.state == KitState.scanning;
        final connecting = service.state == KitState.connecting;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Conectar ao seu kit',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ligue a placa e procure o nome ARCA correspondente ao seu kit.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.bluetooth, size: 32),
                    const SizedBox(height: 8),
                    Text(service.status),
                    if (service.device != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        service.device!.name.isEmpty
                            ? service.device!.id
                            : service.device!.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                    if (scanning || connecting) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    if (service.isConnected || connecting)
                      OutlinedButton.icon(
                        onPressed: () => service.disconnect(),
                        icon: const Icon(Icons.bluetooth_disabled),
                        label: Text(
                          connecting ? 'Cancelar conexão' : 'Desconectar',
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed:
                            scanning ? service.stopScan : service.startScan,
                        icon: Icon(scanning ? Icons.stop : Icons.search),
                        label: Text(scanning ? 'Parar busca' : 'Procurar kits'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_library_outlined),
                title: const Text('Bibliotecas'),
                subtitle: Text(
                  service.isConnected
                      ? 'Catálogo oficial, instalação e remoção no kit'
                      : 'Instale e organize pacotes oficiais',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LibrariesPage(),
                  ),
                ),
              ),
            ),
            if (!service.isConnected && !connecting) ...[
              const SizedBox(height: 16),
              for (final kit in service.devices)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.memory),
                    title: Text(kit.name.isEmpty ? 'Kit ARCA' : kit.name),
                    subtitle: Text('${kit.id}\nSinal: ${kit.rssi} dBm'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => service.connect(kit),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Conectar prepara o console e interrompe qualquer programa anterior. '
                'Um kit atende um celular por vez.',
              ),
            ],
            if (service.isConnected) ...[
              const SizedBox(height: 16),
              const Text(
                'Use Parar no editor antes de desconectar se quiser interromper o programa. '
                'Desconectar não desliga os motores ou a placa.',
              ),
            ],
          ],
        );
      },
    );
  }
}
