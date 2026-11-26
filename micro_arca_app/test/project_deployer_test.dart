import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/micropython_repl_service.dart';
import 'package:micro_arca_app/services/project_deployer.dart';
import 'package:micro_arca_app/services/project_storage.dart';

// Simula apenas o serviço: não exercita rádio BLE nem uma placa real.
class FakeKit implements MicroPythonREPLService {
  @override
  bool isConnected = true;
  @override
  bool isReady = true;
  @override
  bool workspaceManagerAvailable = true;
  @override
  bool autorunAvailable = true;
  final events = <String>[];
  final saved = <String, String>{};
  List<WorkspaceFile> existing = [];
  String? failedSave;
  bool deleteSucceeds = true;
  bool metadataSucceeds = true;
  KitProjectInfo? metadata;

  @override
  Future<List<WorkspaceFile>> listWorkspaceFiles() async => existing;
  @override
  Future<bool> deleteWorkspaceFile(String name) async {
    events.add('delete:$name');
    return deleteSucceeds;
  }

  @override
  Future<bool> saveWorkspaceFile(String name, String content) async {
    events.add('save:$name');
    if (name == failedSave) return false;
    saved[name] = content;
    return true;
  }

  @override
  Future<bool> setKitProject(KitProjectInfo info) async {
    events.add('metadata');
    metadata = info;
    return metadataSucceeds;
  }

  @override
  Future<void> runWorkspaceMain() async => events.add('run');
  @override
  Future<bool> enableAutorun() async {
    events.add('autorun');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final project = ProjectSummary(
    id: 'projeto-teste',
    name: 'Importação',
    kind: ProjectKind.python,
    updatedAt: DateTime.utc(2026, 11, 9),
  );
  const files = {
    'main.py': 'from ajuda import somar\nprint(somar(2, 3))\n',
    'ajuda.py': 'def somar(a, b):\n    return a + b\n',
  };
  late FakeKit kit;
  late ProjectDeployer deployer;
  setUp(() {
    kit = FakeKit();
    deployer = ProjectDeployer(kit);
  });

  test('envia módulo antes da entrada e preserva conteúdo e identidade',
      () async {
    expect(await deployer.send(project, files), isTrue);
    expect(kit.events, ['save:ajuda.py', 'save:main.py', 'metadata']);
    expect(kit.saved, files);
    expect(kit.metadata!.toJson(), {
      'id': project.id,
      'name': project.name,
      'kind': 'python',
      'revision': project.revision,
    });
  });

  test('remove módulo antigo, mas preserva entrada e módulo reutilizado',
      () async {
    kit.existing = const [
      WorkspaceFile(name: 'main.py', size: 1),
      WorkspaceFile(name: 'ajuda.py', size: 1),
      WorkspaceFile(name: 'antigo.py', size: 1),
    ];
    expect(await deployer.send(project, files), isTrue);
    expect(kit.events,
        ['delete:antigo.py', 'save:ajuda.py', 'save:main.py', 'metadata']);
  });

  test('falha de remoção impede envio e execução', () async {
    kit.existing = const [WorkspaceFile(name: 'antigo.py', size: 1)];
    kit.deleteSucceeds = false;
    expect(await deployer.run(project, files), isFalse);
    expect(kit.events, ['delete:antigo.py']);
  });

  test('falha no módulo impede nova entrada, metadados e execução', () async {
    kit.failedSave = 'ajuda.py';
    expect(await deployer.run(project, files), isFalse);
    expect(kit.events, ['save:ajuda.py']);
  });

  test('falha na entrada impede ativação do autorun', () async {
    kit.failedSave = 'main.py';
    expect(await deployer.install(project, files), isFalse);
    expect(kit.events, ['save:ajuda.py', 'save:main.py']);
  });

  test('falha nos metadados impede execução', () async {
    kit.metadataSucceeds = false;
    expect(await deployer.run(project, files), isFalse);
    expect(kit.events, ['save:ajuda.py', 'save:main.py', 'metadata']);
  });

  test('executar só inicia após concluir o envio', () async {
    expect(await deployer.run(project, files), isTrue);
    expect(kit.events, ['save:ajuda.py', 'save:main.py', 'metadata', 'run']);
  });

  test('gravar no kit ativa autorun após envio, sem chamar executar', () async {
    expect(await deployer.install(project, files), isTrue);
    expect(
        kit.events, ['save:ajuda.py', 'save:main.py', 'metadata', 'autorun']);
  });

  test('sem suporte a autorun permite envio, mas recusa instalação', () async {
    kit.autorunAvailable = false;
    expect(await deployer.install(project, files), isFalse);
    expect(kit.events, isEmpty);
    expect(await deployer.send(project, files), isTrue);
    expect(kit.events, ['save:ajuda.py', 'save:main.py']);
  });

  test('recusa projeto sem entrada e kit desconectado, ocupado ou incompatível',
      () async {
    expect(await deployer.send(project, {'ajuda.py': files['ajuda.py']!}),
        isFalse);
    kit.isConnected = false;
    expect(await deployer.send(project, files), isFalse);
    kit.isConnected = true;
    kit.isReady = false;
    expect(await deployer.send(project, files), isFalse);
    kit.isReady = true;
    kit.workspaceManagerAvailable = false;
    expect(await deployer.send(project, files), isFalse);
    expect(kit.events, isEmpty);
  });
}
