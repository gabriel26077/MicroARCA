import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'block_project_storage.dart';

final RegExp _workspaceFileName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\.py$');
const _reservedWorkspaceFileNames = {
  'boot.py',
  'user.py',
  'arca_ble.py',
  'arca_runtime.py',
  'arca_files.py',
};

bool isValidWorkspaceFileName(String name) =>
    _workspaceFileName.hasMatch(name) &&
    !_reservedWorkspaceFileNames.contains(name.toLowerCase());

String? workspaceFileNameError(String name) {
  if (!name.toLowerCase().endsWith('.py')) {
    return 'O arquivo deve terminar em .py.';
  }
  if (_reservedWorkspaceFileNames.contains(name.toLowerCase())) {
    return 'Esse nome é reservado pela infraestrutura do kit.';
  }
  if (!isValidWorkspaceFileName(name)) {
    return 'Use letras, números e _, começando por letra ou _.';
  }
  return null;
}

const maxProjectNameLength = 40;

String? projectNameError(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Informe um nome.';
  if (trimmed.length > maxProjectNameLength) {
    return 'Use no máximo $maxProjectNameLength caracteres.';
  }
  if (trimmed.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    return 'O nome não pode ter caracteres de controle.';
  }
  return null;
}

enum ProjectKind {
  blocks('blocks', 'Blocos'),
  python('python', 'Python');

  const ProjectKind(this.id, this.label);

  /// Nome estável gravado no celular e no kit.
  final String id;
  final String label;

  static ProjectKind fromId(Object? id) => values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => throw const FormatException('Tipo de projeto inválido.'),
      );
}

const defaultPythonMain = '''from machine import Pin
import time

led = Pin(2, Pin.OUT)
while True:
    led.on()
    time.sleep(0.5)
    led.off()
    time.sleep(0.5)
''';

/// Dados de listagem; o conteúdo fica em [ArcaProject].
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.updatedAt,
  });

  factory ProjectSummary.fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['updatedAt'] is! int) {
      throw const FormatException('Projeto salvo inválido.');
    }
    return ProjectSummary(
      id: value['id'] as String,
      name: value['name'] as String,
      kind: ProjectKind.fromId(value['kind']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(value['updatedAt'] as int),
    );
  }

  final String id;
  final String name;
  final ProjectKind kind;
  final DateTime updatedAt;

  /// Identifica o conteúdo enviado ao kit; muda a cada edição salva.
  int get revision => updatedAt.millisecondsSinceEpoch;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.id,
        'updatedAt': revision,
      };
}

/// Projeto do celular: blocos (um workspace Blockly) ou Python (arquivos).
class ArcaProject extends ProjectSummary {
  const ArcaProject({
    required super.id,
    required super.name,
    required super.kind,
    required super.updatedAt,
    this.files = const {},
    this.blocksWorkspace,
  });

  factory ArcaProject.create(String name, ProjectKind kind) {
    final random = Random.secure();
    final suffix = List.generate(6, (_) => random.nextInt(36))
        .map((value) => value.toRadixString(36))
        .join();
    return ArcaProject(
      id: '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$suffix',
      name: name.trim(),
      kind: kind,
      updatedAt: DateTime.now(),
      files: kind == ProjectKind.python
          ? const {'main.py': defaultPythonMain}
          : const {},
    );
  }

  factory ArcaProject.fromJson(Object? value) {
    final summary = ProjectSummary.fromJson(value);
    final map = value as Map;
    final files = map['files'];
    final workspace = map['blocksWorkspace'];
    if ((files != null && files is! Map) ||
        (workspace != null && workspace is! String)) {
      throw const FormatException('Projeto salvo inválido.');
    }
    return ArcaProject(
      id: summary.id,
      name: summary.name,
      kind: summary.kind,
      updatedAt: summary.updatedAt,
      files: {
        for (final entry in (files as Map? ?? const {}).entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      },
      blocksWorkspace: workspace as String?,
    );
  }

  /// Arquivos Python do projeto, sempre com main.py.
  final Map<String, String> files;
  final String? blocksWorkspace;

  /// main.py primeiro, depois os módulos em ordem alfabética.
  List<String> get fileNames => files.keys.toList()
    ..sort((a, b) {
      if (a == 'main.py') return -1;
      if (b == 'main.py') return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  /// Renomear não muda o conteúdo, então mantém a revisão.
  ArcaProject renamed(String name) => ArcaProject(
        id: id,
        name: name.trim(),
        kind: kind,
        updatedAt: updatedAt,
        files: files,
        blocksWorkspace: blocksWorkspace,
      );

  /// Uma edição: atualiza a revisão.
  ArcaProject copyWith({
    Map<String, String>? files,
    String? blocksWorkspace,
  }) =>
      ArcaProject(
        id: id,
        name: name,
        kind: kind,
        updatedAt: DateTime.now(),
        files: files ?? this.files,
        blocksWorkspace: blocksWorkspace ?? this.blocksWorkspace,
      );

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'files': files,
        if (blocksWorkspace != null) 'blocksWorkspace': blocksWorkspace,
      };
}

abstract interface class ProjectStorage {
  /// Mais recentes primeiro.
  Future<List<ProjectSummary>> list();
  Future<ArcaProject?> load(String id);
  Future<void> save(ArcaProject project);
  Future<void> delete(String id);
}

class LocalProjectStorage implements ProjectStorage {
  LocalProjectStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _indexKey = 'arca.projects.index.v1';
  static const _projectPrefix = 'arca.project.v1.';
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  Future<List<ProjectSummary>> _readIndex() async {
    final encoded = await _prefs.getString(_indexKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) throw const FormatException('Índice inválido.');
    final summaries = <ProjectSummary>[];
    for (final item in decoded) {
      try {
        summaries.add(ProjectSummary.fromJson(item));
      } on FormatException {
        // Um item corrompido não impede a lista de abrir.
      }
    }
    return summaries;
  }

  Future<void> _writeIndex(List<ProjectSummary> summaries) => _prefs.setString(
        _indexKey,
        jsonEncode(summaries.map((item) => item.toJson()).toList()),
      );

  @override
  Future<List<ProjectSummary>> list() async =>
      (await _readIndex())..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<ArcaProject?> load(String id) async {
    final encoded = await _prefs.getString('$_projectPrefix$id');
    if (encoded == null) return null;
    return ArcaProject.fromJson(jsonDecode(encoded));
  }

  @override
  Future<void> save(ArcaProject project) async {
    await _prefs.setString(
      '$_projectPrefix${project.id}',
      jsonEncode(project.toJson()),
    );
    final index = await _readIndex()
      ..removeWhere((item) => item.id == project.id)
      ..add(
        ProjectSummary(
          id: project.id,
          name: project.name,
          kind: project.kind,
          updatedAt: project.updatedAt,
        ),
      );
    await _writeIndex(index);
  }

  @override
  Future<void> delete(String id) async {
    await _prefs.remove('$_projectPrefix$id');
    final index = await _readIndex()
      ..removeWhere((item) => item.id == id);
    await _writeIndex(index);
  }
}

/// Liga o editor de blocos ao workspace de um projeto.
class ProjectBlockStorage implements BlockProjectStorage {
  ProjectBlockStorage(this.storage, this.projectId);

  final ProjectStorage storage;
  final String projectId;

  @override
  Future<String?> loadWorkspace() async =>
      (await storage.load(projectId))?.blocksWorkspace;

  @override
  Future<void> saveWorkspace(String workspace) async {
    if (utf8.encode(workspace).length > maxBlockWorkspaceBytes ||
        jsonDecode(workspace) is! Map) {
      throw const FormatException('Projeto de blocos inválido.');
    }
    final project = await storage.load(projectId);
    // Salvar o mesmo conteúdo não conta como edição: a revisão enviada ao kit
    // só muda quando os blocos mudam de fato.
    if (project == null || project.blocksWorkspace == workspace) return;
    await storage.save(project.copyWith(blocksWorkspace: workspace));
  }
}
