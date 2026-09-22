import 'dart:async';

import 'package:flutter/material.dart';

import '../services/micropython_repl_service.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});
  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _service = MicroPythonREPLService();
  final _scroll = ScrollController();
  final _command = TextEditingController();
  late final StreamSubscription<String> _subscription;
  late final Timer _timer;
  String _text = '';
  String _pending = '';
  bool _truncated = false;
  static const _limit = 64000;

  @override
  void initState() {
    super.initState();
    _subscription = _service.onMessage.listen(_append);
    // Uma atualização visual por lote, em vez de reconstruir por pacote BLE.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _flush());
  }

  void _append(String text) {
    _pending += text.replaceAll('\r', '');
    if (_pending.length > _limit) {
      _pending = _pending.substring(_pending.length - _limit);
      _truncated = true;
    }
  }

  void _flush() {
    if (_pending.isEmpty || !mounted) return;
    final follow = !_scroll.hasClients || _scroll.position.extentAfter < 60;
    setState(() {
      _text += _pending;
      _pending = '';
      if (_text.length > _limit) {
        _text = _text.substring(_text.length - _limit);
        _truncated = true;
      }
    });
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _send() {
    if (!_service.isReady || _command.text.trim().isEmpty) return;
    final source = _command.text;
    _command.clear();
    _append('\n>>> $source\n');
    unawaited(_service.runCommand(source));
  }

  @override
  void dispose() {
    _subscription.cancel();
    _timer.cancel();
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
                onPressed: () => setState(() {
                  _text = '';
                  _pending = '';
                  _truncated = false;
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (_truncated)
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
                  _text.isEmpty ? 'A saída do kit aparecerá aqui.' : _text,
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
            builder: (context, _) => Column(
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
                        enabled: _service.isReady,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'Ex.: print("Olá!")',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Enviar comando',
                      onPressed: _service.isReady ? _send : null,
                      icon: const Icon(Icons.send),
                    ),
                    IconButton(
                      tooltip: 'Interromper programa',
                      onPressed: _service.state == KitState.running
                          ? _service.stop
                          : null,
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
