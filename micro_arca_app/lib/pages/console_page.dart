import 'package:flutter/material.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final ScrollController _scrollController = ScrollController();
  final List<ConsoleMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _addExampleMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void addMessage(String text, ConsoleMessageType type) {
    setState(() {
      _messages.add(ConsoleMessage(
        timestamp: DateTime.now(),
        text: text,
        type: type,
      ));
    });
    _scrollToBottom();
  }

  void addSuccessMessage(String text) {
    addMessage(text, ConsoleMessageType.success);
  }

  void addInfoMessage(String text) {
    addMessage(text, ConsoleMessageType.info);
  }

  void addErrorMessage(String text) {
    addMessage(text, ConsoleMessageType.error);
  }

  void clearConsole() {
    setState(() {
      _messages.clear();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addExampleMessages() {
    addInfoMessage('');
    addSuccessMessage('Connected successfully!');
    addInfoMessage('');
    addInfoMessage('');
    addInfoMessage('');
    addInfoMessage('Hello from ESP32! 🎉');
    addInfoMessage('');
    addInfoMessage('');
    addInfoMessage('');
    addErrorMessage("Error: NameError: name 'x' is not defined");
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildConsoleHeader(),
              Expanded(
                child: _buildConsoleContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      decoration: const BoxDecoration(
        color: Color(0xFF00BCD4),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.0),
          topRight: Radius.circular(12.0),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'ESP32 Console',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),

          /*
          // Botões de teste (TEMPORÁRIOS - remover depois)
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.white, size: 20),
            onPressed: () => addSuccessMessage('Conectado com sucesso!'),
            tooltip: 'Testar Sucesso (Verde)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info, color: Colors.white, size: 20),
            onPressed: () => addInfoMessage('Mensagem de log normal'),
            tooltip: 'Testar Info (Branco)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.error, color: Colors.white, size: 20),
            onPressed: () => addErrorMessage('Erro de conexão!'),
            tooltip: 'Testar Erro (Vermelho)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          */
          
          
          // Botão de limpar console
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: clearConsole,
            tooltip: 'Limpar console',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleContent() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: _messages.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageLine(_messages[index]);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'Aguardando mensagens do ESP32...',
        style: TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildMessageLine(ConsoleMessage message) {
    Color textColor;
    switch (message.type) {
      case ConsoleMessageType.success:
        textColor = const Color(0xFF4CAF50);
        break;
      case ConsoleMessageType.error:
        textColor = const Color(0xFFF44336);
        break;
      case ConsoleMessageType.info:
        textColor = const Color(0xFFE0E0E0);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${_formatTimestamp(message.timestamp)}]',
            style: const TextStyle(
              color: Color(0xFF757575),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.text,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

enum ConsoleMessageType {
  success,
  info,
  error,
}

class ConsoleMessage {
  final DateTime timestamp;
  final String text;
  final ConsoleMessageType type;

  ConsoleMessage({
    required this.timestamp,
    required this.text,
    required this.type,
  });
}
