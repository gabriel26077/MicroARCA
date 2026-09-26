import 'dart:async';

import 'package:flutter/foundation.dart';

import 'micropython_repl_service.dart';

/// Saída do kit desde que o app abriu. Compartilhada por todas as telas de
/// console, então abrir o console por cima de um projeto mostra o histórico
/// inteiro.
class ConsoleLog extends ChangeNotifier {
  factory ConsoleLog() => _instance;

  ConsoleLog._() {
    MicroPythonREPLService().onMessage.listen(append);
  }

  static final ConsoleLog _instance = ConsoleLog._();
  static const limit = 64000;

  String _text = '';
  bool _truncated = false;
  Timer? _notify;

  String get text => _text;

  /// Parte do início foi descartada para limitar o uso de memória.
  bool get truncated => _truncated;

  void append(String text) {
    _text += text.replaceAll('\r', '');
    if (_text.length > limit) {
      _text = _text.substring(_text.length - limit);
      _truncated = true;
    }
    // Uma atualização visual por lote, em vez de reconstruir por pacote BLE.
    _notify ??= Timer(const Duration(milliseconds: 100), () {
      _notify = null;
      notifyListeners();
    });
  }

  void clear() {
    _notify?.cancel();
    _notify = null;
    _text = '';
    _truncated = false;
    notifyListeners();
  }
}
