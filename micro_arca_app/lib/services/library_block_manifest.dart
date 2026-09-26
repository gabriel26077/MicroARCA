import 'dart:convert';
import 'dart:typed_data';

import 'library_catalog.dart';

enum LibraryBlockFieldType { identifier, integer, text, value }

class LibraryBlockField {
  const LibraryBlockField({
    required this.name,
    required this.type,
    required this.defaultValue,
    this.minimum,
    this.maximum,
  });

  final String name;
  final LibraryBlockFieldType type;
  final Object defaultValue;
  final int? minimum;
  final int? maximum;

  Map<String, Object> toBridgeJson() => {
        'name': name,
        'type': type.name,
        'default': defaultValue,
        if (minimum != null) 'min': minimum!,
        if (maximum != null) 'max': maximum!,
      };
}

class LibraryBlockDefinition {
  const LibraryBlockDefinition({
    required this.type,
    required this.name,
    required this.description,
    required this.label,
    required this.fields,
    required this.imports,
    required this.template,
  });

  final String type;
  final String name;
  final String description;
  final String label;
  final List<LibraryBlockField> fields;
  final List<String> imports;
  final String template;

  Map<String, Object> toBridgeJson() => {
        'type': type,
        'name': name,
        'description': description,
        'label': label,
        'fields': fields.map((field) => field.toBridgeJson()).toList(),
        'python': {'imports': imports, 'template': template},
      };
}

class LibraryBlockManifest {
  const LibraryBlockManifest({
    required this.packageId,
    required this.packageVersion,
    required this.categoryName,
    required this.color,
    required this.blocks,
  });

  final String packageId;
  final String packageVersion;
  final String categoryName;
  final String color;
  final List<LibraryBlockDefinition> blocks;

  String get packageKey => '$packageId@$packageVersion';

  Map<String, Object> toBridgeJson() => {
        'package': {'id': packageId, 'version': packageVersion},
        'category': {'name': categoryName, 'color': color},
        'blocks': blocks.map((block) => block.toBridgeJson()).toList(),
      };

  factory LibraryBlockManifest.parse(
    Uint8List bytes,
    CatalogPackage package,
  ) {
    if (bytes.isEmpty || bytes.length > maximumBlockManifestBytes) {
      throw const FormatException('Manifesto de blocos fora do limite.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(
        const Utf8Decoder(allowMalformed: false).convert(bytes),
      );
    } on Object {
      throw const FormatException(
          'Manifesto de blocos não contém JSON UTF-8 válido.');
    }
    if (decoded is! Map) {
      throw const FormatException('Manifesto de blocos inválido.');
    }
    final root = decoded.cast<String, Object?>();
    _requireKeys(root, {'schema', 'package', 'category', 'blocks'});
    if (root['schema'] != 1 ||
        root['package'] is! Map ||
        root['category'] is! Map) {
      throw const FormatException('Schema de blocos não suportado.');
    }
    final identity = (root['package'] as Map).cast<String, Object?>();
    _requireKeys(identity, {'id', 'version'});
    if (identity['id'] != package.id ||
        identity['version'] != package.version) {
      throw const FormatException(
          'Manifesto de blocos pertence a outro pacote.');
    }
    final category = (root['category'] as Map).cast<String, Object?>();
    _requireKeys(category, {'name', 'color'});
    final categoryName = category['name'];
    final color = category['color'];
    if (categoryName is! String ||
        categoryName.isEmpty ||
        categoryName.length > 64 ||
        color is! String ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      throw const FormatException('Categoria de blocos inválida.');
    }
    final blocksJson = root['blocks'];
    if (blocksJson is! List || blocksJson.isEmpty || blocksJson.length > 32) {
      throw const FormatException('Lista de blocos inválida.');
    }
    final prefix = '${package.id.replaceAll('-', '_')}_';
    final seenTypes = <String>{};
    final blocks = <LibraryBlockDefinition>[];
    for (final item in blocksJson) {
      if (item is! Map) throw const FormatException('Bloco inválido.');
      final block = item.cast<String, Object?>();
      _requireKeys(
        block,
        {'type', 'name', 'description', 'label', 'fields', 'python'},
      );
      final type = block['type'];
      final name = block['name'];
      final description = block['description'];
      final label = block['label'];
      final fieldsJson = block['fields'];
      final pythonJson = block['python'];
      if (type is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{2,63}$').hasMatch(type) ||
          !type.startsWith(prefix) ||
          !seenTypes.add(type) ||
          name is! String ||
          name.isEmpty ||
          name.length > 64 ||
          description is! String ||
          description.isEmpty ||
          description.length > 240 ||
          label is! String ||
          label.isEmpty ||
          label.length > 240 ||
          fieldsJson is! List ||
          fieldsJson.length > 8 ||
          pythonJson is! Map) {
        throw FormatException('Definição de bloco inválida em ${package.key}.');
      }
      final fields = _parseFields(fieldsJson, type);
      final names = fields.map((field) => field.name).toList();
      if (!_sameNames(_placeholders(label), names)) {
        throw FormatException('Campos não correspondem ao rótulo de $type.');
      }
      final python = pythonJson.cast<String, Object?>();
      _requireKeys(python, {'imports', 'template'});
      final importsJson = python['imports'];
      final template = python['template'];
      if (importsJson is! List ||
          importsJson.length > 8 ||
          importsJson.any(
              (value) => value is! String || !_validImport.hasMatch(value)) ||
          importsJson.toSet().length != importsJson.length ||
          template is! String ||
          template.length > 2000 ||
          template.contains('\r') ||
          !template.endsWith('\n') ||
          '\n'.allMatches(template).length != 1 ||
          _placeholders(template)
              .toSet()
              .difference(names.toSet())
              .isNotEmpty ||
          names
              .toSet()
              .difference(_placeholders(template).toSet())
              .isNotEmpty) {
        throw FormatException('Gerador Python inválido em $type.');
      }
      blocks.add(
        LibraryBlockDefinition(
          type: type,
          name: name,
          description: description,
          label: label,
          fields: List.unmodifiable(fields),
          imports: List.unmodifiable(importsJson.cast<String>()),
          template: template,
        ),
      );
    }
    return LibraryBlockManifest(
      packageId: package.id,
      packageVersion: package.version,
      categoryName: categoryName,
      color: color,
      blocks: List.unmodifiable(blocks),
    );
  }
}

final _validImport = RegExp(
  r'^(?:import [A-Za-z_][A-Za-z0-9_.]*|from [A-Za-z_][A-Za-z0-9_.]* import [A-Za-z_][A-Za-z0-9_]*(?:, [A-Za-z_][A-Za-z0-9_]*)*)$',
);
final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _fieldName = RegExp(r'^[A-Z][A-Z0-9_]{0,31}$');
final _placeholder = RegExp(r'\{([A-Z][A-Z0-9_]*)\}');
const _pythonKeywords = {
  'False',
  'None',
  'True',
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'try',
  'while',
  'with',
  'yield',
};

List<LibraryBlockField> _parseFields(List<dynamic> values, String blockType) {
  final fields = <LibraryBlockField>[];
  final names = <String>{};
  for (final item in values) {
    if (item is! Map) throw FormatException('Campo inválido em $blockType.');
    final field = item.cast<String, Object?>();
    _requireKeys(field, {'name', 'type', 'default'}, {'min', 'max'});
    final name = field['name'];
    final type = field['type'];
    final defaultValue = field['default'];
    if (name is! String || !_fieldName.hasMatch(name) || !names.add(name)) {
      throw FormatException('Nome de campo inválido em $blockType.');
    }
    switch (type) {
      case 'identifier':
        if (defaultValue is! String ||
            !_identifier.hasMatch(defaultValue) ||
            _pythonKeywords.contains(defaultValue) ||
            field.containsKey('min') ||
            field.containsKey('max')) {
          throw FormatException('Identificador inválido em $blockType.');
        }
        fields.add(LibraryBlockField(
          name: name,
          type: LibraryBlockFieldType.identifier,
          defaultValue: defaultValue,
        ));
      case 'text':
        if (defaultValue is! String ||
            defaultValue.length > 240 ||
            field.containsKey('min') ||
            field.containsKey('max')) {
          throw FormatException('Texto inválido em $blockType.');
        }
        fields.add(LibraryBlockField(
          name: name,
          type: LibraryBlockFieldType.text,
          defaultValue: defaultValue,
        ));
      case 'integer':
        final minimum = field['min'];
        final maximum = field['max'];
        if (defaultValue is! int ||
            minimum is! int ||
            maximum is! int ||
            minimum < -1000000 ||
            maximum > 1000000 ||
            minimum > defaultValue ||
            defaultValue > maximum) {
          throw FormatException('Inteiro inválido em $blockType.');
        }
        fields.add(LibraryBlockField(
          name: name,
          type: LibraryBlockFieldType.integer,
          defaultValue: defaultValue,
          minimum: minimum,
          maximum: maximum,
        ));
      case 'value':
        final validDefault = defaultValue is bool ||
            defaultValue is num &&
                defaultValue >= -1000000 &&
                defaultValue <= 1000000 ||
            defaultValue is String && defaultValue.length <= 240;
        if (!validDefault ||
            field.containsKey('min') ||
            field.containsKey('max')) {
          throw FormatException('Valor exibível inválido em $blockType.');
        }
        fields.add(LibraryBlockField(
          name: name,
          type: LibraryBlockFieldType.value,
          defaultValue: defaultValue!,
        ));
      default:
        throw FormatException('Tipo de campo inválido em $blockType.');
    }
  }
  return fields;
}

List<String> _placeholders(String value) {
  final names = _placeholder
      .allMatches(value)
      .map((match) => match.group(1)!)
      .toList(growable: false);
  final remainder = value.replaceAll(_placeholder, '');
  if (remainder.contains('{') || remainder.contains('}')) {
    throw const FormatException('Placeholder inválido no manifesto de blocos.');
  }
  return names;
}

bool _sameNames(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  final counts = <String, int>{};
  for (final value in left) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  for (final value in right) {
    final count = counts[value];
    if (count == null || count == 0) return false;
    counts[value] = count - 1;
  }
  return counts.values.every((count) => count == 0);
}

void _requireKeys(
  Map<String, Object?> value,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    throw const FormatException('Campos desconhecidos no manifesto de blocos.');
  }
}
