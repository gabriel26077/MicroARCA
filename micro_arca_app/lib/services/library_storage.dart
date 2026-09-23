import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedLibrary {
  const SavedLibrary({
    required this.name,
    required this.code,
    required this.updatedAt,
  });

  final String name;
  final String code;
  final DateTime updatedAt;

  int get byteLength => utf8.encode(code).length;

  factory SavedLibrary.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final code = json['code'];
    final updatedAt = json['updatedAt'];
    if (name is! String || code is! String || updatedAt is! String) {
      throw const FormatException('Biblioteca salva inválida.');
    }
    return SavedLibrary(
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

abstract interface class LibraryStorage {
  Future<List<SavedLibrary>> loadLibraries();

  Future<void> saveLibrary(SavedLibrary library);

  Future<void> deleteLibrary(String name);
}

class LocalLibraryStorage implements LibraryStorage {
  LocalLibraryStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _storageKey = 'arca.saved_libraries.v1';
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<List<SavedLibrary>> loadLibraries() async {
    final encoded = await _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Biblioteca local inválida.');
    }
    final libraries = decoded.map((item) {
      if (item is! Map) {
        throw const FormatException('Biblioteca salva inválida.');
      }
      return SavedLibrary.fromJson(item.cast<String, Object?>());
    }).toList(growable: true);
    libraries.sort(_compareNames);
    return libraries;
  }

  @override
  Future<void> saveLibrary(SavedLibrary library) async {
    final libraries = await loadLibraries();
    final normalizedName = library.name.toLowerCase();
    libraries.removeWhere(
      (item) => item.name.toLowerCase() == normalizedName,
    );
    libraries.add(library);
    libraries.sort(_compareNames);
    await _save(libraries);
  }

  @override
  Future<void> deleteLibrary(String name) async {
    final libraries = await loadLibraries();
    final normalizedName = name.toLowerCase();
    libraries.removeWhere(
      (item) => item.name.toLowerCase() == normalizedName,
    );
    await _save(libraries);
  }

  Future<void> _save(List<SavedLibrary> libraries) => _prefs.setString(
        _storageKey,
        jsonEncode(libraries.map((item) => item.toJson()).toList()),
      );

  static int _compareNames(SavedLibrary a, SavedLibrary b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

final RegExp _moduleName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*\.py$');
const reservedLibraryNames = {
  'boot.py',
  'main.py',
  'user.py',
  'arca_ble.py',
  'arca_runtime.py',
  'arca_files.py',
};

bool isValidLibraryName(String name) =>
    _moduleName.hasMatch(name) &&
    !reservedLibraryNames.contains(name.toLowerCase());

String? libraryNameError(String name) {
  if (!name.endsWith('.py')) return 'Selecione um arquivo Python (.py).';
  if (!isValidLibraryName(name)) {
    if (reservedLibraryNames.contains(name.toLowerCase())) {
      return 'Esse nome é reservado pela infraestrutura do kit.';
    }
    return 'Use apenas letras, números e _, começando por letra ou _.';
  }
  return null;
}
