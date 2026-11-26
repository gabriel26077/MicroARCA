import 'dart:async';

import 'micropython_repl_service.dart';
import 'project_storage.dart';

/// Envia um projeto do celular para o kit. O /app do ESP32 é só a área de
/// trabalho do app: passa a conter exatamente os arquivos do projeto.
class ProjectDeployer {
  ProjectDeployer([MicroPythonREPLService? service])
      : service = service ?? MicroPythonREPLService();

  final MicroPythonREPLService service;

  /// Mensagem para quando o kit não pode receber projetos agora, ou null.
  String? get unavailableReason {
    if (!service.isConnected) {
      return 'Conecte o kit pelo botão Bluetooth da tela inicial.';
    }
    if (!service.workspaceManagerAvailable) {
      return 'Atualize arca_files.py no kit para enviar projetos.';
    }
    if (!service.isReady) return 'Aguarde o kit terminar a tarefa atual.';
    return null;
  }

  /// [files] precisa conter main.py. Para blocos, é o Python gerado.
  Future<bool> send(ProjectSummary project, Map<String, String> files) async {
    if (unavailableReason != null || !files.containsKey('main.py')) {
      return false;
    }
    // Módulos de outro projeto ficariam importáveis e confundiriam o novo.
    final wanted = files.keys.map((name) => name.toLowerCase()).toSet();
    for (final file in await service.listWorkspaceFiles()) {
      final name = file.name.toLowerCase();
      if (name != 'main.py' && !wanted.contains(name)) {
        if (!await service.deleteWorkspaceFile(file.name)) return false;
      }
    }
    // main.py por último: um envio interrompido não deixa um main.py novo
    // importando módulos que ainda não chegaram.
    final names = files.keys.toList()
      ..sort((a, b) => (a == 'main.py' ? 1 : 0) - (b == 'main.py' ? 1 : 0));
    for (final name in names) {
      if (!await service.saveWorkspaceFile(name, files[name]!)) return false;
    }
    if (service.autorunAvailable &&
        !await service.setKitProject(KitProjectInfo.of(project))) {
      return false;
    }
    return true;
  }

  /// Retorna assim que o programa começa; ele pode rodar para sempre.
  Future<bool> run(ProjectSummary project, Map<String, String> files) async {
    if (!await send(project, files)) return false;
    unawaited(service.runWorkspaceMain());
    return true;
  }

  /// Envia e congela o projeto para rodar sempre que o kit ligar.
  Future<bool> install(
      ProjectSummary project, Map<String, String> files) async {
    if (!service.autorunAvailable) return false;
    if (!await send(project, files)) return false;
    return service.enableAutorun();
  }
}
