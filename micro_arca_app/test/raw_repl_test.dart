import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/raw_repl.dart';

class FakeTransport implements ReplTransport {
  final controller = StreamController<List<int>>();
  final writes = <List<int>>[];
  void Function(List<int>)? onWrite;
  @override
  Stream<List<int>> get input => controller.stream;
  @override
  Future<void> write(List<int> bytes) async {
    writes.add(bytes);
    if (bytes.length == 3 && bytes.first == 3) {
      controller.add(ascii.encode('\r\n>>> '));
    } else if (bytes.length == 1 && bytes.first == 1) {
      controller.add(ascii.encode('raw REPL; CTRL-B to exit\r\n>'));
    } else {
      onWrite?.call(bytes);
    }
  }
}

void main() {
  late FakeTransport transport;
  late RawRepl repl;
  setUp(() async {
    transport = FakeTransport();
    repl = RawRepl(transport);
    await repl.synchronize();
  });
  tearDown(() async {
    await repl.close();
    await transport.controller.close();
  });

  test('reconstrói UTF-8 mesmo quando cada byte chega separadamente', () async {
    const output = 'ação 🚀\r\n>>> isto é saída\n';
    transport.onWrite = (_) {
      for (final byte in [
        ...ascii.encode('OK'),
        ...utf8.encode(output),
        4,
        4,
        62
      ]) {
        transport.controller.add([byte]);
      }
    };
    final received = StringBuffer();
    final result =
        await repl.execute('print("ação")', onOutput: received.write);
    expect(result.succeeded, isTrue);
    expect(received.toString(), output);
  });

  test('interpreta ACK, saída, erro e prompt agrupados em um pacote', () async {
    transport.onWrite = (_) => transport.controller.add([
          79,
          75,
          ...utf8.encode('antes\n'),
          4,
          ...utf8.encode('ValueError: falha\n'),
          4,
          62,
        ]);
    final received = StringBuffer();
    final result =
        await repl.execute('raise ValueError()', onOutput: received.write);
    expect(result.error, 'ValueError: falha\n');
    expect(received.toString(), 'antes\nValueError: falha\n');
  });

  test('não anuncia fim enquanto o programa roda e aceita Ctrl+C', () async {
    transport.onWrite = (bytes) {
      if (bytes.length == 1 && bytes.single == 3) {
        transport.controller
            .add([4, ...utf8.encode('KeyboardInterrupt\n'), 4, 62]);
      } else {
        transport.controller.add([79, 75, ...utf8.encode('rodando\n')]);
      }
    };
    var finished = false;
    final running =
        repl.execute('while True: pass', timeout: null).then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(finished, isFalse);
    await repl.interrupt();
    expect((await running).error, contains('KeyboardInterrupt'));
  });

  test('recusa operações simultâneas sem misturar respostas', () async {
    transport.onWrite = (_) => transport.controller.add([79, 75]);
    final first = repl.execute('while True: pass', timeout: null);
    await expectLater(repl.execute('print(2)'), throwsStateError);
    transport.controller.add([4, 4, 62]);
    expect((await first).succeeded, isTrue);
  });

  test('perda de conexão encerra uma execução pendente com erro', () async {
    transport.onWrite = (_) => transport.controller.add([79, 75]);
    final operation = repl.execute('while True: pass', timeout: null);
    final assertion = expectLater(operation, throwsStateError);
    await transport.controller.close();
    await assertion;
  });

  test(
      'timeout invalida a sessão e não deixa um leitor consumir a próxima resposta',
      () async {
    transport.onWrite = (_) => transport.controller.add([79, 75]);
    await expectLater(
        repl.execute('pass', timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()));
    await expectLater(repl.execute('print(2)'), throwsStateError);
  });

  test('limita memória quando o receptor recebe dados sem consumidor',
      () async {
    transport.controller.add(List.filled(32769, 65));
    await Future<void>.delayed(Duration.zero);
    final before = transport.writes.length;
    await expectLater(repl.execute('pass'), throwsStateError);
    expect(transport.writes.length, before);
  });

  test('rejeita caracteres de controle e comandos enormes antes do envio',
      () async {
    final before = transport.writes.length;
    await expectLater(repl.execute('print(1)\x04'), throwsArgumentError);
    await expectLater(repl.execute('x' * 1025), throwsArgumentError);
    expect(transport.writes.length, before);
  });

  test('erro Python não inutiliza a próxima operação', () async {
    transport.onWrite = (_) => transport.controller
        .add([79, 75, 4, ...utf8.encode('SyntaxError\n'), 4, 62]);
    expect((await repl.execute('bad syntax')).succeeded, isFalse);
    transport.onWrite = (_) => transport.controller.add([79, 75, 4, 4, 62]);
    expect((await repl.execute('pass')).succeeded, isTrue);
  });
}
