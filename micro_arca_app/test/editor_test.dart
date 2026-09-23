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
  Future<void> createBlankFile(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Novo arquivo em branco'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Descartar e criar'));
    await tester.pumpAndSettle();
  }

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

  testWidgets('salva e carrega um arquivo do celular', (tester) async {
    final storage = MemoryProgramStorage();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorPage(storage: storage))),
    );

    expect(find.byTooltip('Abrir arquivo do celular'), findsOneWidget);
    expect(find.byTooltip('Salvar arquivo no celular'), findsOneWidget);
    expect(find.byTooltip('Salvar como no celular'), findsOneWidget);
    expect(find.byTooltip('Novo arquivo em branco'), findsOneWidget);
    expect(find.byTooltip('Abrir arquivo do ESP32'), findsOneWidget);
    expect(find.byTooltip('Salvar arquivo no ESP32'), findsOneWidget);
    expect(find.byTooltip('Salvar como no ESP32'), findsOneWidget);

    await createBlankFile(tester);
    await tester.tap(find.byTooltip('Salvar arquivo no celular'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'piscar_led');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(storage.programs, hasLength(1));
    expect(storage.programs.single.name, 'piscar_led.py');
    final originalCode = storage.programs.single.code;

    tester.widget<CodeField>(find.byType(CodeField)).controller.text =
        'print("alterado")';
    await tester.pump();
    expect(
      find.text('piscar_led.py • não salvo no celular'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Abrir arquivo do celular'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'piscar_led.py'));
    await tester.pumpAndSettle();

    final editor = tester.widget<CodeField>(find.byType(CodeField));
    expect(editor.controller.text, originalCode);
    expect(find.text('piscar_led.py'), findsOneWidget);
  });

  testWidgets('salva o código atual como arquivo Python editável',
      (tester) async {
    final programs = MemoryProgramStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(storage: programs),
        ),
      ),
    );

    final editor = tester.widget<CodeField>(find.byType(CodeField));
    const code = 'def somar(a, b):\n    return a + b\n';
    editor.controller.text = code;
    await tester.pump();

    await createBlankFile(tester);
    tester.widget<CodeField>(find.byType(CodeField)).controller.text = code;
    await tester.pump();
    await tester.tap(find.byTooltip('Salvar arquivo no celular'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'minha lib');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar'),
      ),
    );
    await tester.pump();
    expect(
      find.text('Use letras, números e _, começando por letra ou _.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'minha_lib');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(programs.programs, hasLength(1));
    expect(programs.programs.single.name, 'minha_lib.py');
    expect(programs.programs.single.code, code);
    expect(find.text('minha_lib.py salvo no celular.'), findsOneWidget);
  });

  testWidgets('salva como e renomeia arquivo no celular', (tester) async {
    final storage = MemoryProgramStorage()
      ..programs.add(
        SavedProgram(
          name: 'helper.py',
          code: 'VALUE = 1\n',
          updatedAt: DateTime(2026),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EditorPage(storage: storage))),
    );

    await tester.tap(find.byTooltip('Abrir arquivo do celular'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'helper.py'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Salvar como no celular'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'copia.py');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Salvar'),
      ),
    );
    await tester.pumpAndSettle();
    expect(storage.programs.map((item) => item.name),
        containsAll(['helper.py', 'copia.py']));

    await tester.tap(find.byTooltip('Abrir arquivo do celular'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ações de copia.py'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'renomeado.py');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.widgetWithText(FilledButton, 'Renomear'),
      ),
    );
    await tester.pumpAndSettle();

    expect(storage.programs.map((item) => item.name),
        containsAll(['helper.py', 'renomeado.py']));
    expect(
        storage.programs.map((item) => item.name), isNot(contains('copia.py')));
  });
}
