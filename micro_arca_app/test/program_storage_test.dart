import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/program_storage.dart';

void main() {
  test('aceita arquivos Python do projeto e o entrypoint main.py', () {
    expect(isValidWorkspaceFileName('main.py'), isTrue);
    expect(isValidWorkspaceFileName('sensor_temperatura.py'), isTrue);
    expect(workspaceFileNameError('meu_modulo.py'), isNull);
  });

  test('rejeita infraestrutura, caminhos e nomes que não são módulos', () {
    for (final name in [
      'boot.py',
      'user.py',
      'arca_ble.py',
      'arca_runtime.py',
      'arca_files.py',
      '../main.py',
      'pasta/modulo.py',
      'dois nomes.py',
      '1sensor.py',
      'sensor.txt',
      'módulo.py',
    ]) {
      expect(
        isValidWorkspaceFileName(name),
        isFalse,
        reason: '$name deveria ser rejeitado',
      );
      expect(workspaceFileNameError(name), isNotNull);
    }
  });
}
