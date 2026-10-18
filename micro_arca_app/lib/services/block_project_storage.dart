import 'dart:convert';

const int maxBlockWorkspaceBytes = 512 * 1024;
const int maxGeneratedProgramBytes = 64 * 1024;

enum BlockVariableType {
  number('Number'),
  text('String'),
  boolean('Boolean');

  const BlockVariableType(this.bridgeName);

  final String bridgeName;

  static BlockVariableType? fromBridgeName(String value) {
    for (final type in values) {
      if (type.bridgeName == value) return type;
    }
    return null;
  }
}

class BlockVariable {
  const BlockVariable({required this.name, required this.type});

  final String name;
  final BlockVariableType type;
}

class BlockProgramSnapshot {
  const BlockProgramSnapshot({
    required this.workspace,
    required this.python,
    required this.requirements,
    required this.variables,
    required this.usesConsoleInput,
  });

  final String workspace;
  final String python;
  final List<String> requirements;
  final List<BlockVariable> variables;
  final bool usesConsoleInput;

  factory BlockProgramSnapshot.fromBridgeMessage(String message) {
    if (utf8.encode(message).length >
        maxBlockWorkspaceBytes + maxGeneratedProgramBytes) {
      throw const FormatException('Mensagem do editor de blocos muito grande.');
    }
    final decoded = jsonDecode(message);
    if (decoded is! Map || decoded['type'] != 'state') {
      throw const FormatException('Mensagem do editor de blocos inválida.');
    }
    final workspace = decoded['workspace'];
    final python = decoded['python'];
    final requirements = decoded['requirements'] ?? const <Object?>[];
    final variables = decoded['variables'] ?? const <Object?>[];
    final usesConsoleInput = decoded['usesConsoleInput'] ?? false;
    if (workspace is! String ||
        python is! String ||
        requirements is! List ||
        requirements.any((value) =>
            value is! String ||
            !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*@\d+\.\d+\.\d+$')
                .hasMatch(value)) ||
        requirements.toSet().length != requirements.length ||
        variables is! List ||
        usesConsoleInput is! bool ||
        variables.length > 100 ||
        !_validVariables(variables)) {
      throw const FormatException('Projeto de blocos inválido.');
    }
    if (utf8.encode(workspace).length > maxBlockWorkspaceBytes) {
      throw const FormatException('Projeto de blocos muito grande.');
    }
    if (utf8.encode(python).length > maxGeneratedProgramBytes) {
      throw const FormatException('Código gerado muito grande.');
    }
    if (jsonDecode(workspace) is! Map) {
      throw const FormatException('Workspace Blockly inválido.');
    }
    return BlockProgramSnapshot(
      workspace: workspace,
      python: python,
      requirements: List.unmodifiable(
        requirements.cast<String>().toList()..sort(),
      ),
      variables: List.unmodifiable(_parseVariables(variables)),
      usesConsoleInput: usesConsoleInput,
    );
  }
}

bool _validVariableName(String value) =>
    value.trim().isNotEmpty &&
    utf8.encode(value).length <= 128 &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

bool _validVariables(List<Object?> values) {
  final names = <String>{};
  for (final value in values) {
    // Workspaces created before typed variables reported names as strings.
    if (value is String) {
      if (!_validVariableName(value) || !names.add(value)) return false;
      continue;
    }
    if (value is! Map) return false;
    final variable = value.cast<Object?, Object?>();
    final name = variable['name'];
    final type = variable['type'];
    if (variable.length != 2 ||
        name is! String ||
        !_validVariableName(name) ||
        type is! String ||
        BlockVariableType.fromBridgeName(type) == null ||
        !names.add(name)) {
      return false;
    }
  }
  return true;
}

List<BlockVariable> _parseVariables(List<Object?> values) {
  final variables = values.map((value) {
    if (value is String) {
      return BlockVariable(name: value, type: BlockVariableType.number);
    }
    final variable = (value as Map).cast<Object?, Object?>();
    return BlockVariable(
      name: variable['name']! as String,
      type: BlockVariableType.fromBridgeName(variable['type']! as String)!,
    );
  }).toList()
    ..sort((left, right) => left.name.compareTo(right.name));
  return variables;
}

abstract interface class BlockProjectStorage {
  Future<String?> loadWorkspace();

  Future<void> saveWorkspace(String workspace);
}
