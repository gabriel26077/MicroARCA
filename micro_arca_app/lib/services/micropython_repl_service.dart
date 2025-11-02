// lib/services/micropython_repl_service.dart
import 'dart:async';
import 'dart:io' as io;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:math'; // Para a função min()

class MicroPythonREPLService {
  // Singleton instance
  static final MicroPythonREPLService _instance = MicroPythonREPLService._internal();
  factory MicroPythonREPLService() => _instance;
  MicroPythonREPLService._internal();
  
  io.Socket? _socket;
  bool _isConnected = false;
  bool _isAuthenticated = false; // ✅ NOVO: Estado separado para autenticação
  bool _handshakeCompleted = false;
  
  // Variáveis para transferência de arquivos
  int _binaryState = 0;
  String? _putFileName;
  Uint8List? _putFileData;

  // Streams para comunicação com a UI
  final StreamController<String> _messageController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  final StreamController<String> _statusController = StreamController.broadcast();
  final StreamController<bool> _authenticationController = StreamController.broadcast(); // ✅ NOVO
  
  // Getters para os streams
  Stream<String> get onMessage => _messageController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  Stream<String> get onStatusUpdate => _statusController.stream;
  Stream<bool> get onAuthenticationChanged => _authenticationController.stream; // ✅ NOVO
  
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated; // ✅ NOVO

  // Conectar com handshake WebSocket manual sobre TCP
  Future<bool> connect(String ip, String password) async {
    try {
      print('🚀 [DEBUG] Tentando conectar com WebSocket manual...');
      print('📡 [DEBUG] IP: $ip');
      print('🔑 [DEBUG] Senha: ${password.isNotEmpty ? "***${password.substring(password.length ~/ 2)}***" : "Nenhuma"}');
      
      final cleanIp = ip.trim();
      
      // ✅ RESETAR ESTADOS
      _isAuthenticated = false;
      _authenticationController.add(false);
      
      _statusController.add('Conectando ao $cleanIp...');
      
      // 1. Conectar via TCP
      _socket = await io.Socket.connect(cleanIp, 8266, timeout: const Duration(seconds: 10));
      
      print('✅ [DEBUG] Conexão TCP estabelecida!');
      _statusController.add('TCP conectado. Fazendo handshake WebSocket...\r\n');
      
      // 2. Enviar handshake WebSocket
      await _sendWebSocketHandshake(cleanIp);
      
      print('✅ [DEBUG] Handshake WebSocket enviado');
      _statusController.add('Handshake enviado. Aguardando resposta...\r\n');
      
      // 3. Configurar listener para receber dados
      _socket!.listen(
        (data) async {
          if (!_handshakeCompleted) {
            // Processar resposta do handshake
            _processHandshakeResponse(data);
          } else {
            // Processar frames WebSocket
            await _processWebSocketFrames(data);
          }
        },
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
      
      // Aguardar handshake ser completado
      await _waitForHandshake();
      
      print('✅ [DEBUG] WebSocket conectado!');
      _isConnected = true;
      _connectionController.add(true);
      _statusController.add('WebREPL conectado! Autenticando...\r\n');
      
      // 4. Enviar senha após handshake bem-sucedido
      if (password.isNotEmpty) {
        Timer(const Duration(milliseconds: 1000), () {
          _sendWebSocketText('$password\r');
          print('✅ [DEBUG] Senha enviada via WebSocket');
          
          // ✅ ENVIAR STATUS APENAS SE AINDA NÃO ESTIVER AUTENTICADO
          if (!_isAuthenticated) {
            _statusController.add('Senha enviada...\r\n');
          }
        });
      } else {
        // Sem senha - considerar autenticado
        _isAuthenticated = true;
        _authenticationController.add(true);
        _statusController.add('✅ Conectado (sem senha)\r\n');
      }
      
      return true;
      
    } catch (e) {
      print('❌ [DEBUG] ERRO NA CONEXÃO:');
      print('❌ [DEBUG] Tipo: ${e.runtimeType}');
      print('❌ [DEBUG] Mensagem: $e');
      
      _statusController.add('Erro de conexão: $e');
      _isConnected = false;
      _isAuthenticated = false;
      _connectionController.add(false);
      _authenticationController.add(false);
      return false;
    }
  }

  // Upload de arquivo - protocolo WebREPL
  Future<bool> uploadFile(String filename, String content) async {
    if (!_isConnected || _socket == null) {
      print('❌ [DEBUG] Não conectado para upload');
      return false;
    }

    // ✅ VERIFICAR SE ESTÁ AUTENTICADO
    if (!_isAuthenticated) {
      print('❌ [DEBUG] Não autenticado para upload');
      _statusController.add('❌ Não autenticado - faça login primeiro\r\n');
      return false;
    }

    try {
      print('📁 [DEBUG] Preparando upload do arquivo: $filename');
      _statusController.add('Preparando upload de $filename...\r\n');

      _putFileName = filename;
      _putFileData = utf8.encode(content);

      print('📁 [DEBUG] Tamanho do arquivo: ${_putFileData!.length} bytes');
    
      if (_putFileData!.length > 10000) {
        print('⚠️ [DEBUG] Arquivo grande detectado: ${_putFileData!.length} bytes');
        _statusController.add('Arquivo grande, enviando em chunks...\r\n');
      }

      // Criar comando de upload (protocolo WebREPL - igual ao JavaScript)
      final rec = Uint8List(2 + 1 + 1 + 8 + 4 + 2 + 64);
      
      // Header 'WA'
      rec[0] = 'W'.codeUnitAt(0);
      rec[1] = 'A'.codeUnitAt(0);
      
      // Comando PUT (1)
      rec[2] = 1;
      rec[3] = 0; // Flags
      
      // Reserved (8 bytes zeros)
      for (int i = 4; i < 12; i++) {
        rec[i] = 0;
      }
      
      // Tamanho do arquivo (4 bytes little-endian)
      rec[12] = _putFileData!.length & 0xFF;
      rec[13] = (_putFileData!.length >> 8) & 0xFF;
      rec[14] = (_putFileData!.length >> 16) & 0xFF;
      rec[15] = (_putFileData!.length >> 24) & 0xFF;
      
      // Tamanho do nome do arquivo (2 bytes)
      rec[16] = filename.length & 0xFF;
      rec[17] = (filename.length >> 8) & 0xFF;
      
      // Nome do arquivo (64 bytes max)
      for (int i = 0; i < 64; ++i) {
        if (i < filename.length) {
          rec[18 + i] = filename.codeUnitAt(i);
        } else {
          rec[18 + i] = 0;
        }
      }

      // Iniciar put
      _binaryState = 11;
      _statusController.add('Enviando $filename...\r\n');
      
      print('📤 [DEBUG] Enviando comando de upload (binary_state=11)...');
      _sendWebSocketBinary(rec);

      return true;

    } catch (e) {
      print('❌ [DEBUG] Erro no upload: $e');
      _statusController.add('Erro ao enviar arquivo: $e\r\n');
      _binaryState = 0;
      return false;
    }
  }

  // Processar frames WebSocket - VERSÃO CORRIGIDA

Future<void> _processWebSocketFrames(List<int> data) async {
  try {
    print('📦 [DEBUG] Recebido ${data.length} bytes WebSocket');
    
    // ✅✅✅ CORREÇÃO CRÍTICA: VERIFICAR PRIMEIRO SE É RESPOSTA DE ARQUIVO
    if (data.length >= 4 && data[0] == 'W'.codeUnitAt(0) && data[1] == 'B'.codeUnitAt(0)) {
      final responseCode = data[2] | (data[3] << 8);
      print('📦 [DEBUG] Resposta de arquivo recebida: código $responseCode, binary_state=$_binaryState');
      
      // PROCESSAR CONFORME O ESTADO - IGUAL AO JAVASCRIPT
      switch (_binaryState) {
        case 11:
          if (responseCode == 0) {
            print('✅ [DEBUG] Primeira resposta OK, enviando chunks...');
            
            final chunkSize = 512;
            final totalChunks = (_putFileData!.length / chunkSize).ceil();
            
            for (var offset = 0; offset < _putFileData!.length; offset += chunkSize) {
              final chunk = _putFileData!.sublist(
                offset, 
                offset + chunkSize < _putFileData!.length ? offset + chunkSize : _putFileData!.length
              );
              
              final chunkNumber = (offset / chunkSize).floor() + 1;
              print('📤 [DEBUG] Enviando chunk $chunkNumber/$totalChunks: ${chunk.length} bytes');
              
              _sendWebSocketBinary(Uint8List.fromList(chunk));
              
              final delay = chunk.length > 100 ? const Duration(milliseconds: 30) : const Duration(milliseconds: 10);
              await Future.delayed(delay);
            }
            
            _binaryState = 12;
            print('✅ [DEBUG] Todos os $totalChunks chunks enviados, aguardando resposta final');
          } else {
            print('❌ [DEBUG] Erro na primeira resposta: $responseCode');
            _statusController.add('Erro ao iniciar envio do arquivo\r\n');
            _binaryState = 0;
          }
          return; // ✅ IMPORTANTE: Não processar como frame WebSocket normal
          
        case 12:
          if (responseCode == 0) {
            print('✅ [DEBUG] Upload completo! Arquivo ${_putFileName} enviado, ${_putFileData!.length} bytes');
            _statusController.add('✅ Arquivo ${_putFileName} enviado com sucesso! (${_putFileData!.length} bytes)\r\n');
          } else {
            print('❌ [DEBUG] Falha ao enviar ${_putFileName}');
            _statusController.add('❌ Falha ao enviar ${_putFileName}\r\n');
          }
          _binaryState = 0;
          return; // ✅ IMPORTANTE: Não processar como frame WebSocket normal
          
        default:
          print('⚠️ [DEBUG] Resposta de arquivo inesperada no estado $_binaryState');
          _binaryState = 0;
          return; // ✅ IMPORTANTE: Não processar como frame WebSocket normal
      }
    }
    
    // ✅✅✅ NOVO: TENTAR DECODIFICAÇÃO DIRETA PRIMEIRO (PARA MENSAGENS SIMPLES)
    try {
      final textDirect = utf8.decode(data);
      if (textDirect.trim().isNotEmpty && 
          !textDirect.contains('�') && // Não é texto corrompido
          textDirect.length < 100) { // Não é binário grande
        print('📥 [DEBUG] Mensagem WebSocket (decode direto): "$textDirect"');
        _messageController.add(textDirect); // ✅ JÁ EXISTIA
        _analyzeResponse(textDirect);
        return; // ✅ Processado com sucesso, sair
      }
    } catch (e) {
      // Não é UTF-8 válido, continuar com o parser normal
    }
    
    // ✅✅✅ ADICIONADO: TENTAR ASCII MESMO ANTES DO PARSER COMPLEXO
    final asciiText = String.fromCharCodes(
      data.where((b) => b >= 32 && b <= 126) // Só caracteres imprimíveis
    );
    if (asciiText.isNotEmpty && asciiText.length >= 2) {
      print('📥 [DEBUG] Mensagem ASCII (pré-parser): "$asciiText"');
      _messageController.add(asciiText); // ✅ NOVO: Enviar ASCII também
      _analyzeResponse(asciiText);
      return;
    }
    
    // ✅✅✅ PROCESSAMENTO NORMAL DE FRAMES WEBSOCKET (SEU CÓDIGO ORIGINAL)
    if (data.length >= 2) {
      final firstByte = data[0];
      final secondByte = data[1];
      
      final opcode = firstByte & 0x0F;
      final isMasked = (secondByte & 0x80) != 0;
      var payloadLength = secondByte & 0x7F;
      
      print('🔍 [DEBUG FRAME] Opcode: $opcode, Masked: $isMasked, PayloadLength: $payloadLength');
      
      var offset = 2;
      
      // Extended payload length
      if (payloadLength == 126) {
        if (data.length >= 4) {
          payloadLength = (data[2] << 8) | data[3];
          offset += 2;
        }
      } else if (payloadLength == 127) {
        if (data.length >= 10) {
          // Ignorar frames muito grandes por enquanto
          payloadLength = 0;
          offset += 8;
        }
      }
      
      print('🔍 [DEBUG FRAME] Final payloadLength: $payloadLength, offset: $offset');
      
      // ✅ SE NÃO HOUVE MASK, PROCESSAR DIRETAMENTE COMO TEXTO
      if (!isMasked && data.length >= offset + payloadLength && payloadLength > 0) {
        final payload = data.sublist(offset, offset + payloadLength);
        
        try {
          final text = utf8.decode(payload);
          print('📥 [DEBUG] Mensagem WebSocket (sem mask): "$text"');
          _messageController.add(text); // ✅ JÁ EXISTIA
          _analyzeResponse(text);
        } catch (e) {
          print('❌ [DEBUG] Erro ao decodificar UTF-8: $e');
          // ✅✅✅ ADICIONADO: Tentar ASCII mesmo com erro UTF-8
          final asciiFallback = String.fromCharCodes(
            payload.where((b) => b >= 32 && b <= 126)
          );
          if (asciiFallback.isNotEmpty) {
            print('📥 [DEBUG] Fallback UTF-8 para ASCII: "$asciiFallback"');
            _messageController.add(asciiFallback);
          }
        }
        return;
      }
      
      // ✅ PROCESSAR COM MASK (se houver)
      if (isMasked && data.length >= offset + 4 + payloadLength) {
        final maskingKey = data.sublist(offset, offset + 4);
        offset += 4;
        
        final payload = data.sublist(offset, offset + payloadLength);
        final unmaskedPayload = List<int>.generate(
          payload.length,
          (i) => payload[i] ^ maskingKey[i % 4],
        );
        
        if (opcode == 0x1) { // Text frame
          try {
            final text = utf8.decode(unmaskedPayload);
            print('📥 [DEBUG] Mensagem WebSocket: "$text"');
            _messageController.add(text); // ✅ JÁ EXISTIA
            _analyzeResponse(text);
          } catch (e) {
            print('❌ [DEBUG] Erro ao decodificar UTF-8: $e');
            // ✅✅✅ ADICIONADO: Tentar ASCII mesmo com erro UTF-8
            final asciiFallback = String.fromCharCodes(
              unmaskedPayload.where((b) => b >= 32 && b <= 126)
            );
            if (asciiFallback.isNotEmpty) {
              print('📥 [DEBUG] Fallback UTF-8 para ASCII (masked): "$asciiFallback"');
              _messageController.add(asciiFallback);
            }
          }
        }
      }
    }
    
  } catch (e) {
    print('❌ [DEBUG] Erro ao processar frame WebSocket: $e');
    
    // ✅✅✅ FALLBACK MELHORADO: Tentar mostrar algo útil
    try {
      // Tentar extrair caracteres ASCII/printáveis
      final asciiText = String.fromCharCodes(
        data.where((b) => b >= 32 && b <= 126) // Só caracteres imprimíveis
      );
      if (asciiText.isNotEmpty) {
        print('📥 [DEBUG] Fallback ASCII: "$asciiText"');
        _messageController.add(asciiText); // ✅ JÁ EXISTIA
      }
    } catch (e2) {
      print('❌ [DEBUG] Também falhou fallback: $e2');
    }
  }
}

  // Enviar dados binários via WebSocket
  void _sendWebSocketBinary(Uint8List data) {
    Uint8List frame;
    
    if (data.length <= 125) {
      frame = Uint8List(2 + data.length);
      frame[0] = 0x82;
      frame[1] = data.length;
      frame.setRange(2, frame.length, data);
    } else if (data.length <= 65535) {
      frame = Uint8List(4 + data.length);
      frame[0] = 0x82;
      frame[1] = 126;
      frame[2] = (data.length >> 8) & 0xFF;
      frame[3] = data.length & 0xFF;
      frame.setRange(4, frame.length, data);
    } else {
      frame = Uint8List(10 + data.length);
      frame[0] = 0x82;
      frame[1] = 127;
      for (int i = 0; i < 8; i++) {
        frame[9 - i] = (data.length >> (8 * i)) & 0xFF;
      }
      frame.setRange(10, frame.length, data);
    }
    
    _socket!.add(frame);
    print('📤 [DEBUG] Enviado frame binário: ${data.length} bytes');
  }


// NO MÉTODO _analyzeResponse, ADICIONE:
void _analyzeResponse(String message) {
  print('🔍 [DEBUG] Analisando resposta: "$message"');
  print('🔍 [DEBUG] Codes: ${message.codeUnits}');
  
  // ✅ MAIS PADRÕES POSSÍVEIS
  if (message.contains('Password:') || message.contains('password') || message.trim() == 'Password:') {
    _statusController.add('Senha solicitada...\r\n');
  } 
  else if (message.contains('WebREPL connected') || message.contains('WebREPL') || message.contains('connected')) {
    if (!_isAuthenticated) {
      _isAuthenticated = true;
      _authenticationController.add(true);
      print('✅ [DEBUG] AUTENTICADO! WebREPL connected detectado');
      _statusController.add('✅ Autenticado com sucesso!\r\n');
      
      // ✅✅✅ NOVO: ENVIAR COMANDOS AUTOMATICAMENTE APÓS AUTENTICAÇÃO
      _sendPostAuthenticationCommands();
    }
  }
  else if (message.contains('Login incorrect') || message.contains('invalid') || message.contains('incorrect')) {
    _isAuthenticated = false;
    _authenticationController.add(false);
    print('❌ [DEBUG] SENHA INCORRETA!');
    _statusController.add('❌ Senha incorreta!\r\n');
  }
  else if (message.contains('>>>') || message.trim().isEmpty) {
    // Resposta vazia ou prompt pode significar sucesso
    if (!_isAuthenticated) {
      _isAuthenticated = true;
      _authenticationController.add(true);
      print('✅ [DEBUG] AUTENTICADO! (prompt ou resposta vazia)');
      _statusController.add('✅ Autenticado com sucesso!\r\n');
      
      // ✅✅✅ NOVO: ENVIAR COMANDOS AUTOMATICAMENTE APÓS AUTENTICAÇÃO
      _sendPostAuthenticationCommands();
    }
  }
  else {
    print('❓ [DEBUG] Mensagem não reconhecida: "$message"');
  }
}

// ✅✅✅ MÉTODO: ENVIAR COMANDOS PÓS-AUTENTICAÇÃO (SEM Ctrl+C)
void _sendPostAuthenticationCommands() {
  print('🚀 [DEBUG] Iniciando sequência pós-autenticação...');
  
  // ✅ REMOVIDO: Ctrl+C automático após autenticação
  
  // Aguardar e importar o main
  Timer(const Duration(milliseconds: 800), () {
    print('📦 [DEBUG] Importando execute_main...');
    _sendWebSocketText('from main import execute_main\r');
    _statusController.add('Importando módulo principal...\r\n');
    
    // Aguardar e finalizar
    Timer(const Duration(milliseconds: 500), () {
      print('⚡ [DEBUG] tudo pronto');
      _statusController.add('Tudo pronto!');
    });
  });
}


  void _processHandshakeResponse(List<int> data) {
    try {
      final response = utf8.decode(data);
      print('📥 [DEBUG] Resposta handshake: "$response"');
      
      if (response.contains('HTTP/1.1 101') || response.contains('Switching Protocols')) {
        print('✅ [DEBUG] Handshake WebSocket aceito!');
        _handshakeCompleted = true;
      }
    } catch (e) {
      print('⚠️ [DEBUG] Erro ao decodificar handshake: $e');
    }
  }
  
  // Aguardar handshake ser completado
  Future<void> _waitForHandshake() async {
    final startTime = DateTime.now();
    while (!_handshakeCompleted) {
      if (DateTime.now().difference(startTime) > const Duration(seconds: 5)) {
        throw TimeoutException('Timeout aguardando handshake WebSocket');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
  
  // Enviar handshake WebSocket manual
  Future<void> _sendWebSocketHandshake(String host) async {
    final key = _generateWebSocketKey();
    final handshake = 
        'GET / HTTP/1.1\r\n'
        'Host: $host:8266\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: $key\r\n'
        'Sec-WebSocket-Version: 13\r\n'
        'Origin: http://$host:8266\r\n'
        '\r\n';
    
    print('🔧 [DEBUG] Enviando handshake WebSocket...');
    _socket!.write(handshake);
  }
  
  // Enviar frame WebSocket de texto
  void _sendWebSocketText(String text) {
    final data = utf8.encode(text);
    
    final frame = [
      0x81,
      data.length,
      ...data,
    ];
    
    _socket!.add(frame);
    print('📤 [DEBUG] Enviado frame WebSocket: "$text"');
  }
  
  // Enviar pong (resposta para ping)
  void _sendWebSocketPong() {
    final frame = [0x8A, 0x00];
    _socket!.add(frame);
  }
  
  // Gerar chave WebSocket
  String _generateWebSocketKey() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64.encode(values);
  }
  
  void _handleError(error) {
    print('💥 [DEBUG] ERRO NO SOCKET:');
    print('💥 [DEBUG] Mensagem: $error');
    
    _statusController.add('Erro: $error');
    _isConnected = false;
    _isAuthenticated = false;
    _connectionController.add(false);
    _authenticationController.add(false);
  }
  
  void _handleDisconnect() {
    print('🔌 [DEBUG] Socket desconectado');
    
    _isConnected = false;
    _isAuthenticated = false;
    _handshakeCompleted = false;
    _binaryState = 0;
    _connectionController.add(false);
    _authenticationController.add(false);
    _statusController.add('Desconectado');
  }
  
  // Enviar comando via WebSocket
  void sendCommand(String command) {
    if (_isConnected && _socket != null && _isAuthenticated) {
      print('📤 [DEBUG] Enviando comando: "$command"');
      _sendWebSocketText('$command\r');
      //_statusController.add('Comando enviado: $command\r\n');
    } else {
      print('⚠️ [DEBUG] Tentativa de enviar comando sem conexão/autenticação: $command');
      if (!_isConnected) {
        _statusController.add('❌ ERRO: Não conectado\r\n');
      } else if (!_isAuthenticated) {
        _statusController.add('❌ ERRO: Não autenticado\r\n');
      }
    }
  }
  
  // Desconectar
  void disconnect() {
    print('👋 [DEBUG] Desconectando manualmente');
    _socket?.close();
    _isConnected = false;
    _isAuthenticated = false;
    _handshakeCompleted = false;
    _binaryState = 0;
    _connectionController.add(false);
    _authenticationController.add(false);
    _statusController.add('Conexão fechada');
  }
  
  void dispose() {
    print('♻️ [DEBUG] Dispose do MicroPythonREPLService');
    disconnect();
    _messageController.close();
    _connectionController.close();
    _statusController.close();
    _authenticationController.close();
  }
}