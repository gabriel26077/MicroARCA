import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_catalog.dart';

const microArcaIdeVersion = '0.1.0';
const microArcaUserAgent = 'MicroARCA/$microArcaIdeVersion';

class CatalogSnapshot {
  const CatalogSnapshot({
    required this.catalog,
    required this.fromCache,
    this.warning,
  });

  final LibraryCatalog catalog;
  final bool fromCache;
  final String? warning;
}

class VerifiedFile {
  const VerifiedFile({required this.metadata, required this.bytes});
  final CatalogFile metadata;
  final Uint8List bytes;
}

class VerifiedPackage {
  const VerifiedPackage({required this.package, required this.files});
  final CatalogPackage package;
  final List<VerifiedFile> files;
}

abstract interface class LibraryCatalogRepository {
  Future<CatalogSnapshot> fetchCatalog();

  Future<List<CatalogPackage>> downloadedPackages(LibraryCatalog catalog);

  Future<void> removeDownloadedPackage(
    LibraryCatalog catalog,
    CatalogPackage package,
  );

  Future<List<VerifiedPackage>> download(
    List<CatalogPackage> packages, {
    void Function(int received, int total)? onProgress,
  });
}

class LibraryCatalogClient implements LibraryCatalogRepository {
  LibraryCatalogClient({
    Uri? catalogUri,
    CatalogTransport? transport,
    CatalogCache? cache,
  })  : catalogUri = catalogUri ?? Uri.parse(officialCatalogUri),
        _transport = transport ?? NativeCatalogTransport(),
        _cache = cache ?? SharedPreferencesCatalogCache();

  final Uri catalogUri;
  final CatalogTransport _transport;
  final CatalogCache _cache;

  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    final cached = await _validatedCachedCatalog();
    try {
      final response = await _transport.get(
        catalogUri,
        headers: {
          if (cached?.etag != null) 'If-None-Match': cached!.etag!,
        },
        maximumBytes: maximumCatalogBytes,
      );
      if (response.statusCode == HttpStatus.notModified) {
        if (cached == null) {
          throw const CatalogNetworkException(
            'O servidor respondeu 304, mas não existe catálogo em cache.',
          );
        }
        return CatalogSnapshot(catalog: cached.catalog, fromCache: true);
      }
      _requireSuccess(response, 'catálogo');
      final catalog = LibraryCatalog.parse(response.bytes, catalogUri);
      await _cache.saveCatalog(
        CachedCatalog(
          bytes: response.bytes,
          etag: response.headers['etag'],
        ),
      );
      return CatalogSnapshot(catalog: catalog, fromCache: false);
    } catch (error) {
      if (cached != null) {
        return CatalogSnapshot(
          catalog: cached.catalog,
          fromCache: true,
          warning: 'Sem acesso ao catálogo atual. Usando a última cópia '
              'validada no celular.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<CatalogPackage>> downloadedPackages(
    LibraryCatalog catalog,
  ) async {
    var keys = await _cache.loadDownloadedPackageKeys();
    if (keys == null) {
      keys = <String>{};
      for (final package in catalog.packages) {
        if (await _packageIsCached(package)) keys.add(package.key);
      }
      await _cache.saveDownloadedPackageKeys(keys);
    }

    final valid = <String>{};
    final packages = <CatalogPackage>[];
    for (final key in keys) {
      final separator = key.lastIndexOf('@');
      if (separator <= 0) continue;
      final package = catalog.find(
        key.substring(0, separator),
        key.substring(separator + 1),
      );
      if (package != null && await _packageIsCached(package)) {
        valid.add(key);
        packages.add(package);
      }
    }
    if (valid.length != keys.length) {
      await _cache.saveDownloadedPackageKeys(valid);
    }
    packages.sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(packages);
  }

  @override
  Future<void> removeDownloadedPackage(
    LibraryCatalog catalog,
    CatalogPackage package,
  ) async {
    final keys = await _cache.loadDownloadedPackageKeys() ?? <String>{};
    keys.remove(package.key);
    final retainedHashes = <String>{};
    for (final key in keys) {
      final separator = key.lastIndexOf('@');
      if (separator <= 0) continue;
      final retained = catalog.find(
        key.substring(0, separator),
        key.substring(separator + 1),
      );
      if (retained != null) {
        retainedHashes.addAll(retained.files.map((file) => file.sha256));
      }
    }
    for (final file in package.files) {
      if (!retainedHashes.contains(file.sha256)) {
        await _cache.deleteFile(file.sha256);
      }
    }
    await _cache.saveDownloadedPackageKeys(keys);
  }

  Future<bool> _packageIsCached(CatalogPackage package) async {
    for (final file in package.files) {
      final bytes = await _cache.loadFile(file.sha256);
      if (bytes == null || !_matches(file, bytes)) return false;
    }
    return true;
  }

  @override
  Future<List<VerifiedPackage>> download(
    List<CatalogPackage> packages, {
    void Function(int received, int total)? onProgress,
  }) async {
    final total = packages.fold<int>(
      0,
      (sum, package) =>
          sum + package.files.fold<int>(0, (value, file) => value + file.size),
    );
    var received = 0;
    final result = <VerifiedPackage>[];
    for (final package in packages) {
      final files = <VerifiedFile>[];
      for (final file in package.files) {
        Uint8List? bytes = await _cache.loadFile(file.sha256);
        if (bytes != null && !_matches(file, bytes)) bytes = null;
        if (bytes == null) {
          final response = await _transport.get(
            file.uri,
            headers: const {},
            maximumBytes: maximumLibraryBytes,
          );
          _requireSuccess(response, file.name);
          bytes = response.bytes;
          if (!_matches(file, bytes)) {
            throw CatalogIntegrityException(
              'Integridade inválida em ${file.name}: tamanho ou SHA-256 '
              'não corresponde ao catálogo.',
            );
          }
          await _cache.saveFile(file.sha256, bytes);
        }
        files.add(VerifiedFile(metadata: file, bytes: bytes));
        received += bytes.length;
        onProgress?.call(received, total);
      }
      result.add(
        VerifiedPackage(package: package, files: List.unmodifiable(files)),
      );
    }
    final downloaded = await _cache.loadDownloadedPackageKeys() ?? <String>{};
    downloaded.addAll(packages.map((package) => package.key));
    await _cache.saveDownloadedPackageKeys(downloaded);
    return List.unmodifiable(result);
  }

  Future<_ParsedCachedCatalog?> _validatedCachedCatalog() async {
    final value = await _cache.loadCatalog();
    if (value == null) return null;
    try {
      return _ParsedCachedCatalog(
        catalog: LibraryCatalog.parse(value.bytes, catalogUri),
        etag: value.etag,
      );
    } on Object {
      return null;
    }
  }

  bool _matches(CatalogFile file, Uint8List bytes) =>
      bytes.length == file.size &&
      sha256.convert(bytes).toString() == file.sha256;

  void _requireSuccess(CatalogResponse response, String resource) {
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw CatalogNetworkException(
        'O servidor tentou redirecionar $resource. Redirecionamentos não são aceitos.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw CatalogNetworkException(
        'Não foi possível baixar $resource (HTTP ${response.statusCode}).',
      );
    }
  }
}

class _ParsedCachedCatalog {
  const _ParsedCachedCatalog({required this.catalog, this.etag});
  final LibraryCatalog catalog;
  final String? etag;
}

class CatalogResponse {
  const CatalogResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;
}

abstract interface class CatalogTransport {
  Future<CatalogResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maximumBytes,
  });
}

class NativeCatalogTransport implements CatalogTransport {
  NativeCatalogTransport({
    this.connectionTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 15),
    this.totalTimeout = const Duration(seconds: 60),
  });

  final Duration connectionTimeout;
  final Duration readTimeout;
  final Duration totalTimeout;

  @override
  Future<CatalogResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maximumBytes,
  }) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const CatalogNetworkException('Somente HTTPS é permitido.');
    }
    return _perform(uri, headers, maximumBytes).timeout(
      totalTimeout,
      onTimeout: () => throw const CatalogNetworkException(
        'A requisição excedeu o prazo total de 60 segundos.',
      ),
    );
  }

  Future<CatalogResponse> _perform(
    Uri uri,
    Map<String, String> headers,
    int maximumBytes,
  ) async {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.userAgentHeader, microArcaUserAgent);
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close().timeout(readTimeout);
      final declaredLength = response.contentLength;
      if (declaredLength > maximumBytes) {
        throw CatalogNetworkException(
          'O download excede o limite de $maximumBytes bytes.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(readTimeout)) {
        if (builder.length + chunk.length > maximumBytes) {
          throw CatalogNetworkException(
            'O download excede o limite de $maximumBytes bytes.',
          );
        }
        builder.add(chunk);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });
      return CatalogResponse(
        statusCode: response.statusCode,
        headers: Map.unmodifiable(responseHeaders),
        bytes: builder.takeBytes(),
      );
    } on TimeoutException {
      throw const CatalogNetworkException(
        'O servidor demorou mais de 15 segundos para responder.',
      );
    } on HandshakeException {
      throw const CatalogNetworkException('Certificado HTTPS inválido.');
    } on SocketException {
      throw const CatalogNetworkException('Sem conexão com o catálogo.');
    } finally {
      client.close(force: true);
    }
  }
}

class CachedCatalog {
  const CachedCatalog({required this.bytes, this.etag});
  final Uint8List bytes;
  final String? etag;
}

abstract interface class CatalogCache {
  Future<CachedCatalog?> loadCatalog();
  Future<void> saveCatalog(CachedCatalog catalog);
  Future<Uint8List?> loadFile(String sha256);
  Future<void> saveFile(String sha256, Uint8List bytes);
  Future<void> deleteFile(String sha256);
  Future<Set<String>?> loadDownloadedPackageKeys();
  Future<void> saveDownloadedPackageKeys(Set<String> keys);
}

class SharedPreferencesCatalogCache implements CatalogCache {
  SharedPreferencesCatalogCache({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _catalogKey = 'arca.catalog.bytes.v1';
  static const _etagKey = 'arca.catalog.etag.v1';
  static const _filePrefix = 'arca.catalog.file.v1.';
  static const _downloadedPackagesKey = 'arca.catalog.downloads.v1';
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<CachedCatalog?> loadCatalog() async {
    final encoded = await _prefs.getString(_catalogKey);
    if (encoded == null) return null;
    try {
      return CachedCatalog(
        bytes: base64Decode(encoded),
        etag: await _prefs.getString(_etagKey),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCatalog(CachedCatalog catalog) async {
    await _prefs.setString(_catalogKey, base64Encode(catalog.bytes));
    final etag = catalog.etag;
    if (etag == null) {
      await _prefs.remove(_etagKey);
    } else {
      await _prefs.setString(_etagKey, etag);
    }
  }

  @override
  Future<Uint8List?> loadFile(String sha256) async {
    final encoded = await _prefs.getString('$_filePrefix$sha256');
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveFile(String sha256, Uint8List bytes) =>
      _prefs.setString('$_filePrefix$sha256', base64Encode(bytes));

  @override
  Future<void> deleteFile(String sha256) =>
      _prefs.remove('$_filePrefix$sha256');

  @override
  Future<Set<String>?> loadDownloadedPackageKeys() async {
    final encoded = await _prefs.getString(_downloadedPackagesKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map ||
          decoded['schema'] != 1 ||
          decoded['packages'] is! List) {
        return null;
      }
      return (decoded['packages'] as List).whereType<String>().toSet();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveDownloadedPackageKeys(Set<String> keys) => _prefs.setString(
        _downloadedPackagesKey,
        jsonEncode({'schema': 1, 'packages': keys.toList()..sort()}),
      );
}

class CatalogNetworkException implements Exception {
  const CatalogNetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogIntegrityException implements Exception {
  const CatalogIntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}
