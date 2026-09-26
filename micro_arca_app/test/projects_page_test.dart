import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/projects_page.dart';
import 'package:micro_arca_app/services/console_log.dart';
import 'package:micro_arca_app/services/project_storage.dart';

import 'memory_project_storage.dart';

Future<void> pumpProjects(
    WidgetTester tester, MemoryProjectStorage storage) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ProjectsPage(storage: storage))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista vazia convida a criar um projeto', (tester) async {
    await pumpProjects(tester, MemoryProjectStorage());
    expect(find.textContaining('Nenhum projeto ainda'), findsOneWidget);
  });

  testWidgets('cria projeto Python, edita arquivos e volta à lista',
      (tester) async {
    final storage = MemoryProjectStorage();
    await pumpProjects(tester, storage);

    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar'));
    await tester.pump();
    expect(find.text('Informe um nome.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Sensor');
    await tester.tap(find.text('Python'));
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    // Abriu o editor do projeto com main.py.
    expect(find.text('Sensor'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'main.py'), findsOneWidget);
    final project = storage.projects.values.single;
    expect(project.kind, ProjectKind.python);
    expect(project.files['main.py'], defaultPythonMain);

    // Novo módulo.
    await tester.tap(find.widgetWithText(ActionChip, 'Arquivo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ajuda');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'ajuda.py'), findsOneWidget);
    expect(storage.projects[project.id]!.files.keys, contains('ajuda.py'));

    // Não aceita nome repetido nem main.py.
    await tester.tap(find.widgetWithText(ActionChip, 'Arquivo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'main');
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('main.py já é o arquivo principal.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // O console abre por cima do projeto, com o histórico, e voltar retorna
    // ao mesmo projeto.
    ConsoleLog()
      ..clear()
      ..append('saída anterior\n');
    await tester.tap(find.byTooltip('Console'));
    await tester.pumpAndSettle();
    expect(find.text('Saída do programa'), findsOneWidget);
    expect(find.text('saída anterior\n'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'ajuda.py'), findsOneWidget);
    ConsoleLog().clear();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sensor'), findsOneWidget);
    expect(find.textContaining('Python •'), findsOneWidget);
  });

  testWidgets('renomeia e exclui projetos', (tester) async {
    final storage = MemoryProjectStorage();
    final project = ArcaProject(
      id: 'p',
      name: 'Semáforo',
      kind: ProjectKind.blocks,
      updatedAt: DateTime(2026, 9, 25, 21, 5),
    );
    await storage.save(project);
    await pumpProjects(tester, storage);
    expect(find.textContaining('Blocos • 25/09 21:05'), findsOneWidget);

    await tester.tap(find.byTooltip('Ações de Semáforo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Farol');
    await tester.tap(find.widgetWithText(FilledButton, 'Renomear'));
    await tester.pumpAndSettle();
    expect(find.text('Farol'), findsOneWidget);
    expect(storage.projects['p']!.revision, project.revision);

    await tester.tap(find.byTooltip('Ações de Farol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(storage.projects, isEmpty);
    expect(find.textContaining('Nenhum projeto ainda'), findsOneWidget);
  });
}
