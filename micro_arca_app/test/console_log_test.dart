import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/console_log.dart';

void main() {
  test('guarda a saída, remove \\r e limita o tamanho', () {
    final log = ConsoleLog()..clear();
    log.append('linha 1\r\nlinha 2\n');
    expect(log.text, 'linha 1\nlinha 2\n');
    expect(log.truncated, isFalse);

    log.append('x' * ConsoleLog.limit);
    expect(log.text.length, ConsoleLog.limit);
    expect(log.truncated, isTrue);

    log.clear();
    expect(log.text, isEmpty);
    expect(log.truncated, isFalse);
  });

  test('é compartilhado entre as telas', () {
    ConsoleLog().clear();
    ConsoleLog().append('ok');
    expect(identical(ConsoleLog(), ConsoleLog()), isTrue);
    expect(ConsoleLog().text, 'ok');
    ConsoleLog().clear();
  });
}
