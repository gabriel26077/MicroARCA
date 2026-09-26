import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/block_project_storage.dart';

void main() {
  test('aceita estado Blockly e MicroPython gerado', () {
    final workspace = jsonEncode({
      'blocks': {
        'languageVersion': 0,
        'blocks': <Object>[],
      },
    });
    final snapshot = BlockProgramSnapshot.fromBridgeMessage(
      jsonEncode({
        'type': 'state',
        'workspace': workspace,
        'python': 'while True:\n    pass\n',
        'requirements': ['oled-pintor@1.1.0'],
        'variables': [
          {'name': 'contador', 'type': 'Number'},
          {'name': 'mensagem', 'type': 'String'},
        ],
      }),
    );

    expect(snapshot.workspace, workspace);
    expect(snapshot.python, 'while True:\n    pass\n');
    expect(snapshot.requirements, ['oled-pintor@1.1.0']);
    expect(
      snapshot.variables.map((variable) => variable.name),
      ['contador', 'mensagem'],
    );
    expect(snapshot.variables.first.type, BlockVariableType.number);
    expect(snapshot.variables.last.type, BlockVariableType.text);
  });

  test('rejeita mensagens, workspaces e programas inválidos', () {
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage('{"type":"ready"}'),
      throwsFormatException,
    );
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage(
        jsonEncode({
          'type': 'state',
          'workspace': '{}',
          'python': 'pass\n',
          'requirements': ['../pacote@1.0.0'],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage(
        jsonEncode({
          'type': 'state',
          'workspace': '{}',
          'python': 'pass\n',
          'variables': [
            {'name': 'contador', 'type': 'Number'},
            {'name': 'contador', 'type': 'String'},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage(
        jsonEncode({
          'type': 'state',
          'workspace': '{}',
          'python': 'pass\n',
          'variables': [
            {'name': 'contador', 'type': 'Objeto'},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage(
        jsonEncode({
          'type': 'state',
          'workspace': '[]',
          'python': 'pass\n',
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BlockProgramSnapshot.fromBridgeMessage(
        jsonEncode({
          'type': 'state',
          'workspace': '{}',
          'python': 'x' * (maxGeneratedProgramBytes + 1),
        }),
      ),
      throwsFormatException,
    );
  });

  test('migra lista legada de nomes de variáveis como números', () {
    final snapshot = BlockProgramSnapshot.fromBridgeMessage(
      jsonEncode({
        'type': 'state',
        'workspace': '{}',
        'python': 'contador = 0\n',
        'variables': ['contador'],
      }),
    );

    expect(snapshot.variables.single.name, 'contador');
    expect(snapshot.variables.single.type, BlockVariableType.number);
  });
}
