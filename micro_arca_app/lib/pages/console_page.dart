import 'dart:async';

import 'package:flutter/material.dart';

import '../services/console_log.dart';
import '../services/micropython_repl_service.dart';

/// Abre o console por cima da tela atual; voltar retorna a ela.
Future<void> openConsole(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Console')),
          body: const SafeArea(child: ConsolePage()),
        ),
      ),
    );

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});
  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _service = MicroPythonREPLService();
  final _log = ConsoleLog();
  final _scroll = ScrollController();
  final _command = TextEditingController();

  @override
  void initState() {
    super.initState();
    _log.addListener(_changed);
    // Ao abrir, mostra o fim da saída.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  void _jumpToEnd() {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  void _changed() {
    if (!mounted) return;
    // Só acompanha o fim se o usuário não rolou para cima para ler.
    final follow = !_scroll.hasClients || _scroll.position.extentAfter < 60;
    setState(() {});
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _send() {
    final value = _command.text;
    if (_service.state == KitState.waitingForInput) {
      _command.clear();
      unawaited(_service.sendInputLine(value));
      return;
    }
    if (!_service.isReady || value.trim().isEmpty) return;
    _command.clear();
    _log.append('\n>>> $value\n');
    unawaited(_service.runCommand(value));
  }

  @override
  void dispose() {
    _log.removeListener(_changed);
    _scroll.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.terminal),
              const SizedBox(width: 8),
              const Expanded(child: Text('Saída do programa')),
              IconButton(
                tooltip: 'Limpar console',
                onPressed: _log.clear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (_log.truncated)
            const Text(
              'Histórico antigo removido para limitar o uso de memória.',
            ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                controller: _scroll,
                child: SelectableText(
                  _log.text.isEmpty
                      ? 'A saída do kit aparecerá aqui.'
                      : _log.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'FiraCode',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _service,
            builder: (context, _) {
              final waiting = _service.state == KitState.waitingForInput;
              final canType = _service.isReady || waiting;
              final canStop = _service.state == KitState.running || waiting;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _service.status,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _command,
                          enabled: canType,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: waiting
                                ? 'Resposta para o programa'
                                : _service.isReady
                                    ? 'Ex.: print("Olá!")'
                                    : _service.state == KitState.running ||
                                            _service.state == KitState.stopping
                                        ? 'Programa executando…'
                                        : 'Conecte um kit para usar o console',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton(
                        tooltip: waiting ? 'Enviar resposta' : 'Enviar comando',
                        onPressed: canType ? _send : null,
                        icon: const Icon(Icons.send),
                      ),
                      IconButton(
                        tooltip: 'Interromper programa',
                        onPressed: canStop ? _service.stop : null,
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
