import 'dart:convert';
import 'dart:typed_data';

import 'library_storage.dart';

const officialCatalogUri =
    'https://libs-microarca.traceedu.com.br/v1/catalog.json';
const maximumCatalogBytes = 1024 * 1024;
const maximumLibraryBytes = 65536;

final RegExp _packageId = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final RegExp _version = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');

class CatalogDependency {
  const CatalogDependency({required this.id, required this.version});

  final String id;
  final String version;

  String get key => '$id@$version';

  Map<String, Object> toJson() => {'id': id, 'version': version};

  factory CatalogDependency.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['version'];
    if (id is! String ||
        !_packageId.hasMatch(id) ||
        version is! String ||
        !_version.hasMatch(version)) {
      throw const FormatException('Dependência inválida no catálogo.');
    }
    return CatalogDependency(id: id, version: version);
  }
}

class CatalogFile {
  const CatalogFile({
    required this.name,
    required this.url,
    required this.uri,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String url;
  final Uri uri;
  final int size;
  final String sha256;
}

class CatalogCompatibility {
  const CatalogCompatibility({
    required this.micropython,
    required this.boards,
  });

  final String micropython;
  final List<String> boards;
}

class CatalogPackage {
  const CatalogPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.license,
    required this.licenseUri,
    required this.provenanceUri,
    required this.compatibility,
    required this.dependencies,
    required this.files,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String license;
  final Uri licenseUri;
  final Uri? provenanceUri;
  final CatalogCompatibility compatibility;
  final List<CatalogDependency> dependencies;
  final List<CatalogFile> files;

  String get key => '$id@$version';
}

class LibraryCatalog {
  LibraryCatalog._(this.baseUri, this.packages, this._byKey);

  final Uri baseUri;
  final List<CatalogPackage> packages;
  final Map<String, CatalogPackage> _byKey;

  factory LibraryCatalog.parse(Uint8List bytes, Uri catalogUri) {
    if (bytes.length > maximumCatalogBytes) {
      throw const FormatException('O catálogo excede o limite de 1 MiB.');
    }
    final Object? decoded;
    try {
      decoded =
          jsonDecode(const Utf8Decoder(allowMalformed: false).convert(bytes));
    } on Object {
      throw const FormatException('O catálogo não contém JSON UTF-8 válido.');
    }
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['packages'] is! List) {
      throw const FormatException('Formato de catálogo não suportado.');
    }

    final result = <CatalogPackage>[];
    final byKey = <String, CatalogPackage>{};
    for (final value in decoded['packages'] as List) {
      if (value is! Map) {
        throw const FormatException('Pacote inválido no catálogo.');
      }
      final package = _parsePackage(
        value.cast<String, Object?>(),
        catalogUri,
      );
      if (byKey.putIfAbsent(package.key, () => package) != package) {
        throw FormatException('Pacote duplicado: ${package.key}.');
      }
      result.add(package);
    }
    final catalog = LibraryCatalog._(
      catalogUri,
      List.unmodifiable(result),
      Map.unmodifiable(byKey),
    );
    for (final package in result) {
      catalog.resolve(
          [CatalogDependency(id: package.id, version: package.version)]);
    }
    return catalog;
  }

  CatalogPackage? find(String id, String version) => _byKey['$id@$version'];

  List<CatalogPackage> versionsOf(String id) {
    final versions = packages.where((item) => item.id == id).toList();
    versions.sort((a, b) => _compareVersions(b.version, a.version));
    return versions;
  }

  List<CatalogPackage> resolve(List<CatalogDependency> roots) {
    final selected = <String, String>{};
    final visiting = <String>{};
    final visited = <String>{};
    final ordered = <CatalogPackage>[];

    void visit(CatalogDependency dependency, List<String> trail) {
      final selectedVersion = selected[dependency.id];
      if (selectedVersion != null && selectedVersion != dependency.version) {
        throw PackageResolutionException(
          'Conflito: ${dependency.id} é exigida nas versões '
          '$selectedVersion e ${dependency.version}.',
        );
      }
      selected[dependency.id] = dependency.version;
      final package = find(dependency.id, dependency.version);
      if (package == null) {
        throw PackageResolutionException(
          'Dependência ausente: ${dependency.key}.',
        );
      }
      if (visiting.contains(package.key)) {
        throw PackageResolutionException(
          'Ciclo de dependências: ${[...trail, package.key].join(' → ')}.',
        );
      }
      if (visited.contains(package.key)) return;
      visiting.add(package.key);
      for (final child in package.dependencies) {
        visit(child, [...trail, package.key]);
      }
      visiting.remove(package.key);
      visited.add(package.key);
      ordered.add(package);
    }

    for (final root in roots) {
      visit(root, const []);
    }
    return List.unmodifiable(ordered);
  }

  static CatalogPackage _parsePackage(
    Map<String, Object?> json,
    Uri catalogUri,
  ) {
    String requiredString(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Campo obrigatório inválido: $name.');
      }
      return value;
    }

    final id = requiredString('id');
    final version = requiredString('version');
    if (!_packageId.hasMatch(id) || !_version.hasMatch(version)) {
      throw FormatException('Identificação de pacote inválida: $id@$version.');
    }
    final compatibilityJson = json['compatibility'];
    final dependenciesJson = json['dependencies'];
    final filesJson = json['files'];
    if (compatibilityJson is! Map ||
        dependenciesJson is! List ||
        filesJson is! List ||
        filesJson.isEmpty) {
      throw FormatException('Metadados incompletos em $id@$version.');
    }
    final compatibility = compatibilityJson.cast<String, Object?>();
    final micropython = compatibility['micropython'];
    final boards = compatibility['boards'];
    if (micropython is! String ||
        micropython.isEmpty ||
        boards is! List ||
        boards.isEmpty ||
        boards.any((value) => value is! String || value.isEmpty)) {
      throw FormatException('Compatibilidade inválida em $id@$version.');
    }
    final files = <CatalogFile>[];
    final names = <String>{};
    for (final value in filesJson) {
      if (value is! Map) {
        throw FormatException('Arquivo inválido em $id@$version.');
      }
      final file = value.cast<String, Object?>();
      final name = file['name'];
      final url = file['url'];
      final size = file['size'];
      final digest = file['sha256'];
      if (name is! String ||
          !isValidLibraryName(name) ||
          url is! String ||
          size is! int ||
          size < 0 ||
          size > maximumLibraryBytes ||
          digest is! String ||
          !_digest.hasMatch(digest)) {
        throw FormatException('Arquivo inseguro em $id@$version.');
      }
      if (!names.add(name.toLowerCase())) {
        throw FormatException('Arquivo duplicado em $id@$version: $name.');
      }
      final uri = _validatedUri(
        url,
        catalogUri,
        'packages/$id/$version/$name',
      );
      files.add(CatalogFile(
        name: name,
        url: url,
        uri: uri,
        size: size,
        sha256: digest,
      ));
    }
    final dependencies = dependenciesJson.map((value) {
      if (value is! Map) {
        throw FormatException('Dependência inválida em $id@$version.');
      }
      return CatalogDependency.fromJson(value.cast<String, Object?>());
    }).toList(growable: false);
    final licenseUrl = requiredString('license_url');
    final provenanceValue = json['provenance_url'];
    if (provenanceValue != null && provenanceValue is! String) {
      throw FormatException('Proveniência inválida em $id@$version.');
    }
    final provenanceUrl = provenanceValue as String?;
    return CatalogPackage(
      id: id,
      name: requiredString('name'),
      version: version,
      description: requiredString('description'),
      author: requiredString('author'),
      license: requiredString('license'),
      licenseUri: _validatedUri(
        licenseUrl,
        catalogUri,
        'packages/$id/$version/LICENSE',
      ),
      provenanceUri: provenanceUrl == null
          ? null
          : _validatedUri(
              provenanceUrl,
              catalogUri,
              'packages/$id/$version/UPSTREAM.json',
            ),
      compatibility: CatalogCompatibility(
        micropython: micropython,
        boards: List<String>.unmodifiable(boards.cast<String>()),
      ),
      dependencies: List.unmodifiable(dependencies),
      files: List.unmodifiable(files),
    );
  }

  static Uri _validatedUri(String value, Uri catalogUri, String expected) {
    final relative = Uri.tryParse(value);
    if (relative == null ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasQuery ||
        relative.hasFragment ||
        Uri.decodeComponent(value) != value ||
        value.startsWith('/')) {
      throw const FormatException('URL insegura no catálogo.');
    }
    final uri = catalogUri.resolve(value);
    final expectedUri = catalogUri.resolve(expected);
    if (uri.scheme != 'https' ||
        uri.scheme != catalogUri.scheme ||
        uri.host != catalogUri.host ||
        uri.port != catalogUri.port ||
        uri.path != expectedUri.path) {
      throw const FormatException('URL fora da origem ou caminho esperado.');
    }
    return uri;
  }

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map(int.parse).toList();
    final right = b.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      final comparison = left[index].compareTo(right[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}

class PackageResolutionException implements Exception {
  const PackageResolutionException(this.message);
  final String message;
  @override
  String toString() => message;
}
