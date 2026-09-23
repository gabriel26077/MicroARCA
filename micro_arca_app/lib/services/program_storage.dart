import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

class SavedProgram {
  const SavedProgram({
    required this.name,
    required this.code,
    required this.updatedAt,
  });

  final String name;
  final String code;
  final DateTime updatedAt;

  factory SavedProgram.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final code = json['code'];
    final updatedAt = json['updatedAt'];
    if (name is! String || code is! String || updatedAt is! String) {
      throw const FormatException('Programa salvo inválido.');
    }
    return SavedProgram(
      name: name,
      code: code,
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  Map<String, Object> toJson() => {
        'name': name,
        'code': code,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

abstract interface class ProgramStorage {
  Future<List<SavedProgram>> loadPrograms();

  Future<void> saveProgram(SavedProgram program);

  Future<void> deleteProgram(String name);
}

class LocalProgramStorage implements ProgramStorage {
  LocalProgramStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _storageKey = 'arca.saved_programs.v1';
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<List<SavedProgram>> loadPrograms() async {
    final encoded = await _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Biblioteca de programas inválida.');
    }

    final programs = decoded.map((item) {
      if (item is! Map) {
        throw const FormatException('Programa salvo inválido.');
      }
      return SavedProgram.fromJson(item.cast<String, Object?>());
    }).toList(growable: true);
    programs.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return programs;
  }

  @override
  Future<void> saveProgram(SavedProgram program) async {
    final programs = await loadPrograms();
    final normalizedName = program.name.toLowerCase();
    programs.removeWhere((item) => item.name.toLowerCase() == normalizedName);
    programs.add(program);
    programs.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    await _prefs.setString(
      _storageKey,
      jsonEncode(programs.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<void> deleteProgram(String name) async {
    final programs = await loadPrograms();
    final normalizedName = name.toLowerCase();
    programs.removeWhere((item) => item.name.toLowerCase() == normalizedName);
    await _prefs.setString(
      _storageKey,
      jsonEncode(programs.map((item) => item.toJson()).toList()),
    );
  }
}
