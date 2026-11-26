import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sobre e privacidade')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('MicroARCA', style: Theme.of(context).textTheme.headlineSmall),
            const Text('Programação e robótica educacional a partir de 9 anos, '
                'com acompanhamento de um adulto para crianças e adolescentes.'),
            const SizedBox(height: 20),
            for (final entry in const {
              'privacidade': 'Política de Privacidade',
              'termos': 'Termos de Uso',
            }.entries)
              Card(
                child: ListTile(
                  leading: Icon(entry.key == 'privacidade'
                      ? Icons.privacy_tip_outlined
                      : Icons.description_outlined),
                  title: Text(entry.value),
                  subtitle: const Text('Disponível também sem internet'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _LegalDocumentPage(
                        document: entry.key, title: entry.value),
                  )),
                ),
              ),
            const SizedBox(height: 20),
            const SelectableText(
                'Contato e privacidade:\ngabrielsebastiao321dev@gmail.com'),
            const SizedBox(height: 12),
            const Text('Projetos ficam no celular e na placa escolhida. '
                'Para ajuda com dados de uma criança ou adolescente, '
                'peça a um responsável para entrar em contato.'),
          ]),
        ),
      );
}

class _LegalDocumentPage extends StatelessWidget {
  const _LegalDocumentPage({required this.document, required this.title});

  final String document;
  final String title;
  static const _channel = MethodChannel('arca/legal_documents');

  Future<void> _openWebsite(BuildContext context) async {
    try {
      await _channel.invokeMethod<void>('open', {'document': document});
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Não foi possível abrir o navegador. O texto está disponível nesta tela.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
            child: FutureBuilder<String>(
          future: rootBundle.loadString('assets/legal/$document.txt'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Não foi possível abrir o documento.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openWebsite(context),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir versão publicada no navegador'),
                    ),
                    const SizedBox(height: 20),
                    SelectableText(snapshot.data!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(height: 1.5)),
                  ]),
            );
          },
        )),
      );
}
