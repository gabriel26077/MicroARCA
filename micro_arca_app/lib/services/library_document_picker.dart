import 'dart:convert';

import 'package:flutter/services.dart';

import 'library_storage.dart';

class LibraryDocumentPicker {
  static const _channel = MethodChannel('arca/document_picker');

  Future<SavedLibrary?> pick() async {
    final result =
        await _channel.invokeMapMethod<String, Object?>('pickPython');
    if (result == null) return null;
    final name = result['name'];
    final bytes = result['bytes'];
    if (name is! String || bytes is! Uint8List) {
      throw const FormatException('Arquivo selecionado inválido.');
    }
    final error = libraryNameError(name);
    if (error != null) throw FormatException(error);
    if (bytes.length > 65536) {
      throw const FormatException('A biblioteca deve ter no máximo 64 KiB.');
    }
    final code = const Utf8Decoder(allowMalformed: false).convert(bytes);
    return SavedLibrary(name: name, code: code, updatedAt: DateTime.now());
  }
}
