import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/micropython_repl_service.dart';
import 'package:micro_arca_app/services/project_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'memory_project_storage.dart';

void main() {
  group('ArcaProject', () {
    test('projeto Python novo começa com main.py', () {
      final project = ArcaProject.create('  Semáforo  ', ProjectKind.python);
      expect(project.name, 'Semáforo');
      expect(project.files.keys, ['main.py']);
      expect(project.files['main.py'], defaultPythonMain);
    });

    test('projeto de blocos começa sem arquivos nem workspace', () {
      final project = ArcaProject.create('Robô', ProjectKind.blocks);
      expect(project.files, isEmpty);
      expect(project.blocksWorkspace, isNull);
    });

    test('ids são únicos', () {
      final ids = {
        for (var i = 0; i < 50; i++)
          ArcaProject.create('p', ProjectKind.blocks).id,
      };
      expect(ids, hasLength(50));
    });

    test('ida e volta em JSON preserva o conteúdo', () {
      final project = ArcaProject.create('Sensor', ProjectKind.python).copyWith(
          files: {'main.py': 'import ajuda\n', 'ajuda.py': 'X = 1\n'});
      final copy =
          ArcaProject.fromJson(jsonDecode(jsonEncode(project.toJson())));
      expect(copy.id, project.id);
      expect(copy.name, 'Sensor');
      expect(copy.kind, ProjectKind.python);
      expect(copy.revision, project.revision);
      expect(copy.files, project.files);
    });

    test('main.py vem primeiro na lista de arquivos', () {
      final project = ArcaProject.create('x', ProjectKind.python).copyWith(
        files: {'zeta.py': '', 'main.py': '', 'Alfa.py': ''},
      );
      expect(project.fileNames, ['main.py', 'Alfa.py', 'zeta.py']);
    });

    test('renomear mantém a revisão; editar muda', () async {
      final project = ArcaProject(
        id: 'p',
        name: 'A',
        kind: ProjectKind.blocks,
        updatedAt: DateTime(2026),
      );
      expect(project.renamed('B').revision, project.revision);
      expect(
        project.copyWith(blocksWorkspace: '{}').revision,
        isNot(project.revision),
      );
    });

    test('rejeita tipo desconhecido', () {
      expect(
        () => ArcaProject.fromJson({
          'id': 'p',
          'name': 'A',
          'kind': 'java',
          'updatedAt': 1,
        }),
        throwsFormatException,
      );
    });
  });

  test('valida nomes de projeto', () {
    expect(projectNameError('Semáforo'), isNull);
    expect(projectNameError('   '), isNotNull);
    expect(projectNameError('a' * (maxProjectNameLength + 1)), isNotNull);
    expect(projectNameError('linha\nquebrada'), isNotNull);
  });

  group('LocalProjectStorage', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('salva, lista do mais recente, carrega e exclui', () async {
      final storage =
          LocalProjectStorage(preferences: SharedPreferencesAsync());
      final older = ArcaProject(
        id: 'a',
        name: 'Antigo',
        kind: ProjectKind.blocks,
        updatedAt: DateTime(2026, 1),
      );
      final newer = ArcaProject(
        id: 'b',
        name: 'Novo',
        kind: ProjectKind.python,
        updatedAt: DateTime(2026, 2),
        files: const {'main.py': 'pass\n'},
      );
      await storage.save(older);
      await storage.save(newer);
      expect(
          (await storage.list()).map((item) => item.name), ['Novo', 'Antigo']);
      expect((await storage.load('b'))!.files['main.py'], 'pass\n');

      await storage.save(older.renamed('Renomeado'));
      final names = (await storage.list()).map((item) => item.name);
      expect(names, ['Novo', 'Renomeado']);

      await storage.delete('a');
      expect((await storage.list()).map((item) => item.id), ['b']);
      expect(await storage.load('a'), isNull);
    });
  });

  group('ProjectBlockStorage', () {
    test('salvar o mesmo workspace não muda a revisão', () async {
      final storage = MemoryProjectStorage();
      final project = ArcaProject(
        id: 'p',
        name: 'Blocos',
        kind: ProjectKind.blocks,
        updatedAt: DateTime(2026),
        blocksWorkspace: '{"blocks":{}}',
      );
      await storage.save(project);
      final blocks = ProjectBlockStorage(storage, 'p');
      expect(await blocks.loadWorkspace(), '{"blocks":{}}');

      await blocks.saveWorkspace('{"blocks":{}}');
      expect((await storage.load('p'))!.revision, project.revision);

      await blocks.saveWorkspace('{"blocks":{"languageVersion":0}}');
      final saved = await storage.load('p');
      expect(saved!.blocksWorkspace, '{"blocks":{"languageVersion":0}}');
      expect(saved.revision, isNot(project.revision));
    });

    test('rejeita workspace que não é um objeto', () async {
      final storage = MemoryProjectStorage();
      await storage.save(ArcaProject.create('p', ProjectKind.blocks));
      final blocks = ProjectBlockStorage(storage, storage.projects.keys.single);
      expect(() => blocks.saveWorkspace('[]'), throwsFormatException);
    });
  });

  test('registro do projeto no kit tem o formato aceito pelo firmware', () {
    final project = ArcaProject(
      id: 'p1',
      name: 'Semáforo',
      kind: ProjectKind.blocks,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(5),
    );
    final info = KitProjectInfo.of(project);
    expect(info.toJson(), {
      'id': 'p1',
      'name': 'Semáforo',
      'kind': 'blocks',
      'revision': 5,
    });
    final status = AutorunStatus.fromJson({
      'enabled': true,
      'installed': true,
      'project': info.toJson(),
    });
    expect(status.active, isTrue);
    expect(status.project!.name, 'Semáforo');
    expect(status.project!.kind, ProjectKind.blocks);
    expect(
      AutorunStatus.fromJson({
        'project': {'id': 'x'}
      }).project,
      isNull,
    );
  });
}
