import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/micropython_repl_service.dart';

void main() {
  test('lê o estado do programa de inicialização enviado pelo firmware', () {
    final status = AutorunStatus.fromJson({
      'enabled': true,
      'installed': true,
      'tripped': false,
      'boots': 1,
      'files': ['main.py', 'ajuda.py', 7],
    });
    expect(status.enabled, isTrue);
    expect(status.installed, isTrue);
    expect(status.tripped, isFalse);
    expect(status.files, ['main.py', 'ajuda.py']);
  });

  test('trata campos ausentes como desligado', () {
    final status = AutorunStatus.fromJson(<String, Object?>{});
    expect(status.enabled, isFalse);
    expect(status.installed, isFalse);
    expect(status.tripped, isFalse);
    expect(status.files, isEmpty);
  });

  test('rejeita resposta que não é um objeto', () {
    expect(() => AutorunStatus.fromJson('ligado'), throwsFormatException);
  });
}
