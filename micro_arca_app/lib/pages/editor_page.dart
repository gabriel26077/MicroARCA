// lib/pages/editor_page.dart
import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'dart:async';
import '../widgets/custom_action_bar.dart';
import '../services/micropython_repl_service.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  CodeController? _codeController;
  bool _keyboardVisible = false;
  
  final MicroPythonREPLService _replService = MicroPythonREPLService();

  // Estados para controle de UI
  bool _isSendingCode = false;
  bool _isRunningCode = false;
  String _statusMessage = 'Pronto';
  bool _isConnected = false;
  bool _isStoppingCode = false; // ✅ NOVO: Estado para o botão Stop

  final String _initialCode = """from machine import Pin
import time

blink_delay = 0.5


led = Pin(33, Pin.OUT)

while(True):
    print("led")
    led.on()
    time.sleep(blink_delay)
    led.off()
    time.sleep(blink_delay)
    
""";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codeController = CodeController(
      text: _initialCode,
      language: python,
    );
    
    _setupServiceListeners();
  }

  void _setupServiceListeners() {
    _replService.onStatusUpdate.listen((status) {
      if (mounted) {
        setState(() {
          _statusMessage = status;
          
          // ✅ DETECTAR AUTENTICAÇÃO BEM-SUCEDIDA
          if (status.contains('>>>') || 
              status.contains('autenticado') || 
              status.contains('Pronto para comandos')) {
            _statusMessage = '✅ Conectado e autenticado!';
          }
          
          // ✅ DETECTAR ERRO DE AUTENTICAÇÃO
          if (status.contains('incorrect') || status.contains('incorreta')) {
            _statusMessage = '❌ Senha incorreta!';
          }
        });
      }
    });
    
    _replService.onConnectionChanged.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        
        // ✅ ATUALIZAR STATUS QUANDO CONECTAR/DESCONECTAR
        if (connected) {
          _statusMessage = 'Conectando...';
        } else {
          _statusMessage = '🔌 Desconectado';
        }
      }
    });
    
    // ✅ OUVIR MENSAGENS DO REPL TAMBÉM
    _replService.onMessage.listen((message) {
      if (mounted) {
        // Detectar prompt do MicroPython (autenticação bem-sucedida)
        if (message.contains('>>>')) {
          setState(() {
            _statusMessage = '✅ Conectado e autenticado!';
          });
        }
        
        // Detectar erro de autenticação
        if (message.contains('Login incorrect')) {
          setState(() {
            _statusMessage = '❌ Senha incorreta!';
          });
        }
      }
    });
  }

  // Enviar código como arquivo user.py
  Future<void> _sendCodeToDevice() async {
    if (!_replService.isConnected) {
      //_showSnackBar('Não conectado ao dispositivo');
      return;
    }

    final code = _codeController?.text ?? '';
    if (code.trim().isEmpty) {
      //_showSnackBar('Nenhum código para enviar');
      return;
    }

    setState(() {
      _isSendingCode = true;
      _statusMessage = 'Enviando arquivo user.py...';
    });

    try {
      final success = await _replService.uploadFile('user.py', code);
      
      if (success) {
        //_showSnackBar('Arquivo user.py enviado com sucesso!');
        setState(() => _statusMessage = '✅ Arquivo user.py enviado!');
      } else {
        //_showSnackBar('Erro ao enviar arquivo');
        setState(() => _statusMessage = '❌ Erro no envio do arquivo');
      }
    } catch (e) {
      //_showSnackBar('Erro ao enviar código: $e');
      setState(() => _statusMessage = '❌ Erro no envio');
    } finally {
      setState(() => _isSendingCode = false);
    }
  }
void _handleRun() {
  if (_replService.isConnected) {
    setState(() {
      _isRunningCode = true;
      _statusMessage = '🛑 Interrompendo loop atual...';
    });

    // ✅ PRIMEIRO: Enviar Ctrl+C para parar qualquer loop em execução
    _replService.sendCommand(String.fromCharCode(0x03)); // Ctrl+C
    
    // ✅ SEGUNDO: Aguardar um pouco e executar o código
    Timer(const Duration(milliseconds: 800), () {
      setState(() {
        _statusMessage = '⚡ Executando código...';
      });
      
      _replService.sendCommand('execute_main()');
      
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isRunningCode = false;
            _statusMessage = '✅ Execução concluída';
          });
        }
      });
    });
    
  } else {
    setState(() {
      _statusMessage = '❌ Dispositivo não conectado';
    });
  }
}
  // void _showSnackBar(String message) {
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: Text(message),
  //       duration: const Duration(seconds: 2),
  //       behavior: SnackBarBehavior.floating,
  //     ),
  //   );
  // }



  // ✅ NOVO MÉTODO: HANDLE STOP (Ctrl+C)
  void _handleStop() {
    if (_replService.isConnected) {
      setState(() {
        _isStoppingCode = true;
        _statusMessage = '🛑 Parando execução...';
      });

      // Enviar Ctrl+C para interromper a execução
      _replService.sendCommand(String.fromCharCode(0x03)); // Ctrl+C
      
      // Feedback visual
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isStoppingCode = false;
            _isRunningCode = false;
            _statusMessage = '⏹️ Execução interrompida';
          });
        }
      });
      
      // Resetar status após alguns segundos
      Timer(const Duration(seconds: 3), () {
        if (mounted && _statusMessage.contains('interrompida')) {
          setState(() {
            _statusMessage = '✅ Pronto para novos comandos';
          });
        }
      });
      
    } else {
      setState(() {
        _statusMessage = '❌ Dispositivo não conectado';
      });
    }
  }



  void _handleLoad() {
    //_showSnackBar('Load - Em desenvolvimento');
  }

  void _handleSave() {
    //_showSnackBar('Save - Em desenvolvimento');
  }

  void _handleSend() {
    _sendCodeToDevice();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    final newValue = bottomInset > 0;
    if (newValue != _keyboardVisible) {
      setState(() => _keyboardVisible = newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Barra de status
              _buildStatusBar(),
              const SizedBox(height: 16),
              
              // Editor de código
              Expanded(
                child: CodeTheme(
                  data: const CodeThemeData(styles: a11yLightTheme),
                  child: MicroArcaEditor(controller: _codeController),
                ),
              ),
            ],
          ),
        ),
      ),

      bottomNavigationBar: _keyboardVisible
          ? const SizedBox.shrink()
          : CustomActionBar(
              onLoad: _handleLoad,
              onSave: _handleSave,
              onSend: _handleSend,
              onRun: _handleRun,
              onStop: _handleStop, // ✅ NOVO: Adicionar o callback do Stop
              isSendLoading: _isSendingCode,
              isRunLoading: _isRunningCode,
              isStopLoading: _isStoppingCode, // ✅ NOVO: Estado de loading do Stop
              
            ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _getStatusColor(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getStatusBorderColor(),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(),
            color: _getStatusIconColor(),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getDisplayStatus(),
              style: TextStyle(
                color: _getStatusTextColor(),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isSendingCode || _isRunningCode)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ MÉTODO NOVO PARA STATUS MAIS DESCRITIVO
  String _getDisplayStatus() {
    if (!_replService.isConnected) return '🔌 Desconectado';
    if (_statusMessage.contains('✅')) return _statusMessage;
    if (_statusMessage.contains('autenticado')) return '✅ Conectado e autenticado!';
    if (_statusMessage.contains('>>>')) return '✅ Conectado e autenticado!';
    if (_statusMessage.contains('incorreta')) return '❌ Senha incorreta!';
    if (_statusMessage.contains('incorrect')) return '❌ Senha incorreta!';
    if (_isSendingCode) return '📤 Enviando arquivo...';
    if (_isRunningCode) return '⚡ Executando código...';
    if (_isStoppingCode) return '🛑 Parando execução...'; // ✅ NOVO
    return _statusMessage;
  }

  Color _getStatusColor() {
    if (!_replService.isConnected) return const Color(0xFFFFEBEE);
    if (_statusMessage.contains('✅')) return const Color(0xFFE8F5E8);
    if (_statusMessage.contains('❌')) return const Color(0xFFFFEBEE);
    if (_isSendingCode) return const Color(0xFFFFF8E1);
    if (_isRunningCode) return const Color(0xFFFFF8E1);
    if (_isStoppingCode) return const Color(0xFFFFF8E1); // ✅ NOVO
    return const Color(0xFFE3F2FD);
  }

  Color _getStatusBorderColor() {
    if (!_replService.isConnected) return const Color(0xFFF44336);
    if (_statusMessage.contains('✅')) return const Color(0xFF4CAF50);
    if (_statusMessage.contains('❌')) return const Color(0xFFF44336);
    if (_isSendingCode) return const Color(0xFFFFC107);
    if (_isRunningCode) return const Color(0xFFFFC107);
    if (_isStoppingCode) return const Color(0xFFFFC107); // ✅ NOVO
    return const Color(0xFF2196F3);
  }

  Color _getStatusTextColor() {
    if (!_replService.isConnected) return const Color(0xFFC62828);
    if (_statusMessage.contains('✅')) return const Color(0xFF2E7D32);
    if (_statusMessage.contains('❌')) return const Color(0xFFC62828);
    if (_isSendingCode) return const Color(0xFFF57C00);
    if (_isRunningCode) return const Color(0xFFF57C00);
     if (_isStoppingCode) return const Color(0xFFF57C00); // ✅ NOVO
    return const Color(0xFF1565C0);
  }

  Color _getStatusIconColor() {
    if (!_replService.isConnected) return const Color(0xFFF44336);
    if (_statusMessage.contains('✅')) return const Color(0xFF4CAF50);
    if (_statusMessage.contains('❌')) return const Color(0xFFF44336);
    if (_isSendingCode) return const Color(0xFFFFC107);
    if (_isRunningCode) return const Color(0xFFFFC107);
     if (_isStoppingCode) return const Color(0xFFFFC107); // ✅ NOVO
    return const Color(0xFF2196F3);
  }

  IconData _getStatusIcon() {
    if (!_replService.isConnected) return Icons.error_outline;
    if (_statusMessage.contains('✅')) return Icons.check_circle;
    if (_statusMessage.contains('❌')) return Icons.error_outline;
    if (_isSendingCode) return Icons.upload;
    if (_isRunningCode) return Icons.play_arrow;
    if (_isStoppingCode) return Icons.stop; // ✅ NOVO
    return Icons.info_outline;
  }
}

class MicroArcaEditor extends StatefulWidget {
  const MicroArcaEditor({
    super.key,
    required this.controller,
  });

  final CodeController? controller;

  @override
  State<MicroArcaEditor> createState() => _MicroArcaEditorState();
}

class _MicroArcaEditorState extends State<MicroArcaEditor> {
  final FocusNode _focusNode = FocusNode();
  String _lastText = "";

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller?.text ?? "";
    widget.controller?.addListener(_scrollToCursor);
  }

  void _scrollToCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {});
    });
  }

  void _handleAutoIndent(String newText) {
    final controller = widget.controller;
    if (controller == null) return;

    if (newText.length > _lastText.length && newText.contains('\n')) {
      final newLineIndex = _findNewLineIndex(_lastText, newText);
      if (newLineIndex != -1) {
        _applyIndentation(controller, newText, newLineIndex);
      }
    }

    _lastText = newText;
  }

  int _findNewLineIndex(String oldText, String newText) {
    for (int i = 0; i < newText.length; i++) {
      if (i >= oldText.length || oldText[i] != newText[i]) {
        if (newText[i] == '\n') {
          return i;
        }
        break;
      }
    }
    return -1;
  }

  void _applyIndentation(CodeController controller, String text, int newLineIndex) {
    int lineStart = newLineIndex - 1;
    while (lineStart >= 0 && text[lineStart] != '\n') {
      lineStart--;
    }
    lineStart++;

    final String previousLine = text.substring(lineStart, newLineIndex);
    final String trimmedLine = previousLine.trim();

    final int currentIndent = _getIndentation(previousLine);
    final bool shouldIndent = _shouldIndentNextLine(trimmedLine);

    final int newIndent = currentIndent + (shouldIndent ? 4 : 0);
    final String indentSpaces = ' ' * newIndent;

    if (newIndent > 0) {
      final updatedText = text.replaceRange(
        newLineIndex + 1,
        newLineIndex + 1,
        indentSpaces,
      );
      controller.value = controller.value.copyWith(
        text: updatedText,
        selection: TextSelection.collapsed(
          offset: newLineIndex + 1 + indentSpaces.length,
        ),
      );
    }
  }

  bool _shouldIndentNextLine(String line) {
    final lineWithoutComments = line.split('#').first.trim();
    if (lineWithoutComments.isEmpty) return false;
    if (lineWithoutComments.endsWith(':')) return true;

    final indentKeywords = [
      'def', 'class', 'if', 'elif', 'else', 'while', 'for',
      'try', 'except', 'finally', 'with', 'async def', 'async for', 'async with'
    ];

    for (final keyword in indentKeywords) {
      if (lineWithoutComments.startsWith('$keyword ') ||
          lineWithoutComments == keyword) {
        return true;
      }
    }

    return false;
  }

  int _getIndentation(String line) {
    int indent = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        indent++;
      } else if (line[i] == '\t') {
        indent += 4;
      } else {
        break;
      }
    }
    return indent;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_scrollToCursor);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: CodeField(
          controller: widget.controller!,
          focusNode: _focusNode,
          lineNumbers: true,
          textStyle: const TextStyle(
            fontFamily: 'FiraCode',
            fontSize: 14,
          ),
          wrap: true,
          minLines: null,
          maxLines: null,
          onChanged: _handleAutoIndent,
        ),
      ),
    );
  }
}