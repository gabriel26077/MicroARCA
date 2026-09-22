import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/editor_page.dart';
import 'package:micro_arca_app/services/program_storage.dart';
import 'package:micro_arca_app/widgets/python_indent_modifier.dart';

class MemoryProgramStorage implements ProgramStorage {
  final List<SavedProgram> programs = [];

  @override
  Future<void> deleteProgram(String name) async {
    programs.removeWhere(
      (program) => program.name.toLowerCase() == name.toLowerCase(),
    );
  }

  @override
  Future<List<SavedProgram>> loadPrograms() async => List.of(programs);

  @override
  Future<void> saveProgram(SavedProgram program) async {
    await deleteProgram(program.name);
    programs.add(program);
  }
}

void main() {
  CodeController controller(String text) {
    final code = CodeController(
        text: text,
        params: const EditorParams(tabSpaces: 4),
        modifiers: const [PythonIndentModifier(), TabModifier()]);
    code.selection = TextSelection.collapsed(offset: text.length);
    addTearDown(code.dispose);
    return code;
  }

  test('Enter abre um bloco Python e mantém a indentação na linha seguinte',
      () {
    final code = controller('if True:');
    code.value = const TextEditingValue(
        text: 'if True:\n', selection: TextSelection.collapsed(offset: 9));
    expect(code.text, 'if True:\n    ');
    code.value = TextEditingValue(
        text: '${code.text}print(1)',
        selection: const TextSelection.collapsed(offset: 21));
    code.value = TextEditingValue(
        text: '${code.text}\n',
        selection: TextSelection.collapsed(offset: code.text.length + 1));
    expect(code.text, 'if True:\n    print(1)\n    ');
  });

  test('colar código preserva os espaços originais sem duplicar indentação',
      () {
    final code = controller('');
    const text = 'while True:\n    print("ação")\n';
    code.value = const TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    expect(code.text, text);
  });

  testWidgets('salva e carrega um programa da biblioteca local',
      (tester) async {
    final storage = MemoryProgramStorage();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorPage(storage: storage))),
    );

    await tester.tap(find.byTooltip('Salvar programa no celular'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'piscar_led');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(storage.programs, hasLength(1));
    expect(storage.programs.single.name, 'piscar_led.py');
    final originalCode = storage.programs.single.code;

    tester.widget<CodeField>(find.byType(CodeField)).controller.text =
        'print("alterado")';
    await tester.pump();
    expect(find.text('piscar_led.py • não salvo'), findsOneWidget);

    await tester.tap(find.byTooltip('Abrir programa salvo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'piscar_led.py'));
    await tester.pumpAndSettle();

    final editor = tester.widget<CodeField>(find.byType(CodeField));
    expect(editor.controller.text, originalCode);
    expect(find.text('piscar_led.py'), findsOneWidget);
  });
}
