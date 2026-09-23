import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/editor_page.dart';
import 'package:micro_arca_app/services/library_storage.dart';
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

class MemoryLibraryStorage implements LibraryStorage {
  final List<SavedLibrary> libraries = [];

  @override
  Future<void> deleteLibrary(String name) async {
    libraries.removeWhere(
      (library) => library.name.toLowerCase() == name.toLowerCase(),
    );
  }

  @override
  Future<List<SavedLibrary>> loadLibraries() async => List.of(libraries);

  @override
  Future<void> saveLibrary(SavedLibrary library) async {
    await deleteLibrary(library.name);
    libraries.add(library);
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

  testWidgets('salva o código atual do editor como biblioteca', (tester) async {
    final programs = MemoryProgramStorage();
    final libraries = MemoryLibraryStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(
            storage: programs,
            libraryStorage: libraries,
          ),
        ),
      ),
    );

    final editor = tester.widget<CodeField>(find.byType(CodeField));
    const code = 'def somar(a, b):\n    return a + b\n';
    editor.controller.text = code;
    await tester.pump();

    await tester.tap(find.byTooltip('Salvar código como biblioteca'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'minha lib');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pump();
    expect(find.textContaining('Use apenas letras'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'minha_lib');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(libraries.libraries, hasLength(1));
    expect(libraries.libraries.single.name, 'minha_lib.py');
    expect(libraries.libraries.single.code, code);
    expect(find.text('minha_lib.py salva como biblioteca.'), findsOneWidget);
  });
}
