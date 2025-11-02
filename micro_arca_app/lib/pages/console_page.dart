import 'dart:async';
import 'package:flutter/material.dart';
import '../services/micropython_repl_service.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final ScrollController _scrollController = ScrollController();
  final List<ConsoleMessage> _messages = [];
  final MicroPythonREPLService _replService = MicroPythonREPLService();
  final TextEditingController _commandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupServiceListeners();
    _addWelcomeMessage();
  }

  void _setupServiceListeners() {
    print('🎯 [CONSOLE] Conectado ao service');
    
    _replService.onMessage.listen((message) {
      print('🎯 [CONSOLE] Recebido: "$message"');
      addInfoMessage(message);
    });

    _replService.onStatusUpdate.listen((status) {
      if (status.trim().isNotEmpty) {
        addInfoMessage(status);
      }
    });

    _replService.onConnectionChanged.listen((connected) {
      if (connected) {
        addSuccessMessage('🌐 Conectado ao ESP32!');
      } else {
        addErrorMessage('🔌 Desconectado do ESP32');
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _commandController.dispose();
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
    _addWelcomeMessage();
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

  void _addWelcomeMessage() {
    addInfoMessage('🚀 Console ESP32 iniciado');
    addInfoMessage('💡 Digite comandos na área abaixo');
    addInfoMessage('⏳ Aguardando conexão...');
  }

  // ✅ NOVO MÉTODO: ENVIAR COMANDO
// ✅ MÉTODO CORRIGIDO: ENVIAR COMANDO SEM DUPLICAÇÃO
void _sendCommand() {
  final command = _commandController.text.trim();
  if (command.isEmpty) return;

  if (!_replService.isConnected) {
    addErrorMessage('❌ Não conectado ao ESP32');
    return;
  }

  // ✅ MOSTRAR APENAS O COMANDO (sem "Comando enviado:")
  addInfoMessage('>>> $command');
  
  // ✅ Enviar comando para o ESP32 (SEM mostrar status duplicado)
  _replService.sendCommand(command);
  
  // Limpar campo de texto
  _commandController.clear();
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
              // ✅ NOVA ÁREA: INPUT DE COMANDOS
              _buildCommandInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        color: Color(0xFF00BCD4),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.0),
          topRight: Radius.circular(12.0),
        ),
      ),
      child: Row(
        children: [
          // Status da conexão
          StreamBuilder<bool>(
            stream: _replService.onConnectionChanged,
            initialData: _replService.isConnected,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              return Row(
                children: [
                  Icon(
                    isConnected ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'CONECTADO' : 'DESCONECTADO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
          
          const Spacer(),
          
          // Status da autenticação
          StreamBuilder<bool>(
            stream: _replService.onAuthenticationChanged,
            initialData: _replService.isAuthenticated,
            builder: (context, snapshot) {
              final isAuthenticated = snapshot.data ?? false;
              if (isAuthenticated) {
                return Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'AUTENTICADO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
          
          const SizedBox(width: 16),
          
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: clearConsole,
            tooltip: 'Limpar console',
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, color: Color(0xFF757575), size: 48),
          SizedBox(height: 16),
          Text(
            'Console ESP32 pronto',
            style: TextStyle(
              color: Color(0xFF757575),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Conecte-se ao ESP32 para ver as mensagens',
            style: TextStyle(
              color: Color(0xFF757575),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NOVO WIDGET: ÁREA DE INPUT DE COMANDOS
  Widget _buildCommandInput() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12.0),
          bottomRight: Radius.circular(12.0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commandController,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Digite um comando... (ex: print("Hello"))',
                hintStyle: TextStyle(color: Color(0xFF757575)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (_) => _sendCommand(),
            ),
          ),
          const SizedBox(width: 8),
          StreamBuilder<bool>(
            stream: _replService.onConnectionChanged,
            initialData: _replService.isConnected,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              return IconButton(
                icon: Icon(
                  Icons.send,
                  color: isConnected ? Color(0xFF00BCD4) : Color(0xFF757575),
                ),
                onPressed: isConnected ? _sendCommand : null,
                tooltip: 'Enviar comando',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageLine(ConsoleMessage message) {
    Color textColor;
    IconData? icon;
    
    switch (message.type) {
      case ConsoleMessageType.success:
        textColor = const Color(0xFF4CAF50);
        icon = Icons.check_circle;
        break;
      case ConsoleMessageType.error:
        textColor = const Color(0xFFF44336);
        icon = Icons.error;
        break;
      case ConsoleMessageType.info:
        textColor = const Color(0xFFE0E0E0);
        icon = Icons.info;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: textColor,
            size: 12,
          ),
          const SizedBox(width: 8),
          Text(
            '[${_formatTimestamp(message.timestamp)}]',
            style: const TextStyle(
              color: Color(0xFF757575),
              fontSize: 11,
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
                height: 1.3,
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