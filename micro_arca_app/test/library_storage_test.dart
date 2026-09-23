import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/library_storage.dart';

void main() {
  test('valida nomes seguros de módulos Python', () {
    expect(isValidLibraryName('lib_oled_pintor.py'), isTrue);
    expect(isValidLibraryName('_sensor2.py'), isTrue);
    expect(isValidLibraryName('../boot.py'), isFalse);
    expect(isValidLibraryName('1sensor.py'), isFalse);
    expect(isValidLibraryName('duas palavras.py'), isFalse);
    expect(isValidLibraryName('modulo.mpy'), isFalse);
    expect(isValidLibraryName('boot.py'), isFalse);
    expect(isValidLibraryName('arca_files.py'), isFalse);
  });

  test('serializa biblioteca local preservando UTF-8', () {
    final updatedAt = DateTime.utc(2026, 9, 22, 12, 30);
    final library = SavedLibrary(
      name: 'sensor.py',
      code: 'MENSAGEM = "ação 🚀"\n',
      updatedAt: updatedAt,
    );
    final restored = SavedLibrary.fromJson(library.toJson());
    expect(restored.name, library.name);
    expect(restored.code, library.code);
    expect(restored.updatedAt, updatedAt);
    expect(restored.byteLength, utf8.encode(library.code).length);
  });
}
