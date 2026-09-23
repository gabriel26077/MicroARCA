import 'dart:async';
import 'dart:convert';

abstract class ReplTransport {
  Stream<List<int>> get input;
  Future<void> write(List<int> bytes);
}

class ReplResult {
  const ReplResult(this.error);
  final String error;
  bool get succeeded => error.isEmpty;
}

/// Parser de bytes do raw REPL. Fronteiras BLE nunca são fronteiras de texto.
class RawRepl {
  RawRepl(this.transport) {
    _subscription = transport.input.listen(
      _inbox.add,
      onError: _inbox.fail,
      onDone: () => _inbox.fail(StateError('Bluetooth desconectado')),
    );
  }

  final ReplTransport transport;
  final _ByteInbox _inbox = _ByteInbox();
  late final StreamSubscription<List<int>> _subscription;
  bool _busy = false;
  bool _synchronized = false;

  Future<void> waitForHello() => _inbox.untilPattern(
        ascii.encode('ARCA-BLE/1\n'),
        const Duration(milliseconds: 500),
      );

  Future<void> synchronize() async {
    if (_busy) throw StateError('Operação em andamento');
    _inbox._check();
    _synchronized = false;
    _inbox.clear();
    await transport.write([3, 3, 2]); // Interrompe e volta ao friendly REPL.
    await _inbox.untilPattern(ascii.encode('>>> '), const Duration(seconds: 5));
    await transport.write([1]);
    await _inbox.untilPattern(
      ascii.encode('raw REPL; CTRL-B to exit\r\n>'),
      const Duration(seconds: 5),
    );
    _synchronized = true;
  }

  Future<ReplResult> execute(
    String source, {
    void Function(String)? onOutput,
    Duration? timeout = const Duration(seconds: 10),
  }) async {
    if (_busy) throw StateError('Aguarde a operação atual');
    if (!_synchronized) throw StateError('REPL precisa ser reconectado');
    _inbox._check();
    final bytes = utf8.encode(source);
    if (bytes.length > 1024 || bytes.any((b) => b < 32 && b != 10 && b != 9)) {
      throw ArgumentError('Comando inválido ou maior que 1024 bytes');
    }
    _busy = true;
    try {
      final operation = _execute(bytes, onOutput);
      // No timeout, invalida também a leitura pendente: não pode consumir a
      // resposta de uma operação futura depois de o chamador desistir.
      return await (timeout == null ? operation : operation.timeout(timeout));
    } catch (error) {
      _synchronized = false;
      _inbox.fail(error);
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<ReplResult> _execute(
    List<int> source,
    void Function(String)? onOutput,
  ) async {
    await transport.write([...source, 4]);
    final ack = await _inbox.exact(2).timeout(const Duration(seconds: 10));
    if (ack[0] != 79 || ack[1] != 75) {
      throw StateError('Resposta inesperada do MicroPython');
    }
    await _readOutput(onOutput ?? (_) {});
    final error = StringBuffer();
    await _readOutput((text) {
      if (error.length < 8192) error.write(text);
      onOutput?.call(text);
    });
    final prompt = await _inbox.exact(1);
    if (prompt.single != 62) throw StateError('Prompt raw REPL ausente');
    return ReplResult(error.toString());
  }

  Future<void> _readOutput(void Function(String) output) async {
    final decoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(_TextSink(output));
    try {
      while (true) {
        final part = await _inbox.throughDelimiter(4);
        decoder.add(part.$1);
        if (part.$2) break;
      }
    } finally {
      decoder.close();
    }
  }

  Future<void> interrupt() => transport.write([3]);

  /// Envia uma linha ao stdin enquanto o código atual continua em execução.
  Future<void> sendInputLine(String value) async {
    if (!_busy) throw StateError('Nenhum programa aguardando entrada');
    if (!_synchronized) throw StateError('REPL precisa ser reconectado');
    final bytes = utf8.encode(value);
    if (bytes.length > 1024 || bytes.any((byte) => byte < 32 || byte == 127)) {
      throw ArgumentError('Resposta inválida ou maior que 1024 bytes');
    }
    await transport.write([...bytes, 13]);
  }

  Future<void> close() async {
    _synchronized = false;
    _inbox.fail(StateError('Sessão encerrada'));
    await _subscription.cancel();
  }
}

class _TextSink extends StringConversionSinkBase {
  _TextSink(this.output);
  final void Function(String) output;
  @override
  void add(String str) => output(str);
  @override
  void addSlice(String str, int start, int end, bool isLast) {
    add(str.substring(start, end));
    if (isLast) close();
  }

  @override
  void close() {}
}

class _ByteInbox {
  final List<int> _bytes = [];
  Completer<void>? _changed;
  Object? _error;

  void add(List<int> bytes) {
    if (_error != null) return;
    if (_bytes.length + bytes.length > 32768) {
      fail(StateError('Saída excedeu o buffer. Reduza a frequência de print.'));
      return;
    }
    _bytes.addAll(bytes);
    _wake();
  }

  void clear() => _bytes.clear();
  void fail(Object error) {
    _error ??= error;
    _wake();
  }

  void _wake() {
    final changed = _changed;
    _changed = null;
    changed?.complete();
  }

  void _check() {
    if (_error != null) throw _error!;
  }

  Future<void> _wait() {
    _check();
    return (_changed ??= Completer<void>()).future;
  }

  Future<List<int>> exact(int count) async {
    while (_bytes.length < count) {
      await _wait();
    }
    _check();
    final result = _bytes.sublist(0, count);
    _bytes.removeRange(0, count);
    return result;
  }

  Future<void> untilPattern(List<int> pattern, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      _check();
      for (var i = 0; i <= _bytes.length - pattern.length; i++) {
        var matches = true;
        for (var j = 0; j < pattern.length; j++) {
          if (_bytes[i + j] != pattern[j]) {
            matches = false;
            break;
          }
        }
        if (matches) {
          _bytes.removeRange(0, i + pattern.length);
          return;
        }
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Sem resposta do kit');
      }
      await _wait().timeout(remaining);
    }
  }

  Future<(List<int>, bool)> throughDelimiter(int delimiter) async {
    while (_bytes.isEmpty) {
      await _wait();
    }
    _check();
    final end = _bytes.indexOf(delimiter);
    if (end < 0) {
      final result = List<int>.of(_bytes);
      _bytes.clear();
      return (result, false);
    }
    final result = _bytes.sublist(0, end);
    _bytes.removeRange(0, end + 1);
    return (result, true);
  }
}
