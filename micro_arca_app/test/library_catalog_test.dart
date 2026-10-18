import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/library_block_manifest.dart';
import 'package:micro_arca_app/services/library_catalog.dart';
import 'package:micro_arca_app/services/library_catalog_client.dart';
import 'package:micro_arca_app/services/package_installation_storage.dart';

final catalogUri = Uri.parse(officialCatalogUri);

Map<String, Object?> packageJson({
  required String id,
  String version = '1.0.0',
  List<Map<String, String>> dependencies = const [],
  String? fileName,
  String? digest,
  int? size,
  String? url,
  Map<String, Object?>? blocks,
}) {
  final name = fileName ?? '${id.replaceAll('-', '_')}.py';
  return {
    'id': id,
    'name': id,
    'version': version,
    'description': 'Biblioteca $id',
    'author': 'ARCA',
    'license': 'MIT',
    'license_url': 'packages/$id/$version/LICENSE',
    'compatibility': {
      'micropython': '>=1.24',
      'boards': ['ESP32_GENERIC'],
    },
    'dependencies': dependencies,
    if (blocks != null) 'blocks': blocks,
    'files': [
      {
        'name': name,
        'url': url ?? 'packages/$id/$version/$name',
        'size': size ?? 0,
        'sha256': digest ?? sha256.convert(const <int>[]).toString(),
      },
    ],
  };
}

Uint8List blockManifestBytes({
  String id = 'oled-pintor',
  String version = '1.1.0',
  String template = '{TELA}.limpa()\n',
  Map<String, Object?> field = const {
    'name': 'TELA',
    'type': 'identifier',
    'default': 'tela',
  },
}) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 1,
          'package': {'id': id, 'version': version},
          'category': {'name': 'Tela OLED', 'color': '#D96C18'},
          'blocks': [
            {
              'type': 'oled_pintor_limpar',
              'name': 'Limpar tela',
              'description': 'Apaga o conteúdo da tela.',
              'label': 'limpar tela {TELA}',
              'fields': [field],
              'python': {'imports': <String>[], 'template': template},
            },
          ],
        }),
      ),
    );

Uint8List catalogBytes(List<Map<String, Object?>> packages) =>
    Uint8List.fromList(
      utf8.encode(jsonEncode({'schema': 1, 'packages': packages})),
    );

class MemoryCatalogCache implements CatalogCache {
  CachedCatalog? catalog;
  final files = <String, Uint8List>{};
  Set<String>? downloadedPackageKeys;

  @override
  Future<CachedCatalog?> loadCatalog() async => catalog;
  @override
  Future<void> saveCatalog(CachedCatalog value) async => catalog = value;
  @override
  Future<Uint8List?> loadFile(String digest) async => files[digest];
  @override
  Future<void> saveFile(String digest, Uint8List bytes) async {
    files[digest] = bytes;
  }

  @override
  Future<void> deleteFile(String digest) async {
    files.remove(digest);
  }

  @override
  Future<Set<String>?> loadDownloadedPackageKeys() async =>
      downloadedPackageKeys == null ? null : Set.of(downloadedPackageKeys!);
  @override
  Future<void> saveDownloadedPackageKeys(Set<String> keys) async {
    downloadedPackageKeys = Set.of(keys);
  }
}

class FakeCatalogTransport implements CatalogTransport {
  final responses = <Object>[];
  final requests = <({Uri uri, Map<String, String> headers, int maximum})>[];

  @override
  Future<CatalogResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maximumBytes,
  }) async {
    requests.add((uri: uri, headers: Map.of(headers), maximum: maximumBytes));
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response as CatalogResponse;
  }
}

void main() {
  group('catálogo', () {
    test('resolve dependências na ordem de instalação', () {
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'oled-pintor',
            fileName: 'lib_oled_pintor.py',
            dependencies: [
              {'id': 'ssd1306', 'version': '1.0.0'},
            ],
          ),
          packageJson(id: 'ssd1306'),
        ]),
        catalogUri,
      );
      final resolved = catalog.resolve(const [
        CatalogDependency(id: 'oled-pintor', version: '1.0.0'),
      ]);
      expect(resolved.map((item) => item.id), ['ssd1306', 'oled-pintor']);
    });

    test('rejeita dependência ausente, ciclo e conflito de versões', () {
      expect(
        () => LibraryCatalog.parse(
          catalogBytes([
            packageJson(
              id: 'a',
              dependencies: [
                {'id': 'missing', 'version': '1.0.0'},
              ],
            ),
          ]),
          catalogUri,
        ),
        throwsA(isA<PackageResolutionException>()),
      );
      expect(
        () => LibraryCatalog.parse(
          catalogBytes([
            packageJson(
              id: 'a',
              dependencies: [
                {'id': 'b', 'version': '1.0.0'},
              ],
            ),
            packageJson(
              id: 'b',
              dependencies: [
                {'id': 'a', 'version': '1.0.0'},
              ],
            ),
          ]),
          catalogUri,
        ),
        throwsA(isA<PackageResolutionException>()),
      );
      final conflict = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'a',
            dependencies: [
              {'id': 'shared', 'version': '1.0.0'},
            ],
          ),
          packageJson(
            id: 'b',
            dependencies: [
              {'id': 'shared', 'version': '2.0.0'},
            ],
          ),
          packageJson(id: 'shared'),
          packageJson(id: 'shared', version: '2.0.0'),
        ]),
        catalogUri,
      );
      expect(
        () => conflict.resolve(const [
          CatalogDependency(id: 'a', version: '1.0.0'),
          CatalogDependency(id: 'b', version: '1.0.0'),
        ]),
        throwsA(isA<PackageResolutionException>()),
      );
    });

    test('rejeita caminho externo, traversal, nome reservado e arquivo grande',
        () {
      for (final package in [
        packageJson(id: 'unsafe', url: 'https://evil.test/x.py'),
        packageJson(id: 'unsafe', url: '../unsafe.py'),
        packageJson(id: 'unsafe', fileName: 'boot.py'),
        packageJson(id: 'unsafe', size: maximumLibraryBytes + 1),
      ]) {
        expect(
          () => LibraryCatalog.parse(catalogBytes([package]), catalogUri),
          throwsFormatException,
        );
      }
    });

    test('aceita descritor de blocos somente no caminho canônico', () {
      final bytes = blockManifestBytes();
      final digest = sha256.convert(bytes).toString();
      final valid = packageJson(
        id: 'oled-pintor',
        version: '1.1.0',
        blocks: {
          'url': 'packages/oled-pintor/1.1.0/blocks.json',
          'size': bytes.length,
          'sha256': digest,
        },
      );
      final catalog = LibraryCatalog.parse(catalogBytes([valid]), catalogUri);
      expect(catalog.packages.single.blocks?.sha256, digest);

      valid['blocks'] = {
        'url': 'packages/outro/1.1.0/blocks.json',
        'size': bytes.length,
        'sha256': digest,
      };
      expect(
        () => LibraryCatalog.parse(catalogBytes([valid]), catalogUri),
        throwsFormatException,
      );
    });

    test('valida manifesto declarativo sem JavaScript', () {
      final bytes = blockManifestBytes();
      final digest = sha256.convert(bytes).toString();
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'oled-pintor',
            version: '1.1.0',
            blocks: {
              'url': 'packages/oled-pintor/1.1.0/blocks.json',
              'size': bytes.length,
              'sha256': digest,
            },
          ),
        ]),
        catalogUri,
      );
      final manifest = LibraryBlockManifest.parse(
        bytes,
        catalog.packages.single,
      );
      expect(manifest.packageKey, 'oled-pintor@1.1.0');
      expect(manifest.blocks.single.type, 'oled_pintor_limpar');

      expect(
        () => LibraryBlockManifest.parse(
          blockManifestBytes(template: '<script>alert(1)</script>\n'),
          catalog.packages.single,
        ),
        throwsFormatException,
      );
    });

    test('aceita campo exibível e rejeita valor fora dos tipos básicos', () {
      final package = LibraryCatalog.parse(
        catalogBytes([packageJson(id: 'oled-pintor', version: '1.1.0')]),
        catalogUri,
      ).packages.single;
      final manifest = LibraryBlockManifest.parse(
        blockManifestBytes(
          field: const {
            'name': 'TELA',
            'type': 'value',
            'default': 'Olá!',
          },
        ),
        package,
      );
      expect(
        manifest.blocks.single.fields.single.type,
        LibraryBlockFieldType.value,
      );

      expect(
        () => LibraryBlockManifest.parse(
          blockManifestBytes(
            field: const {
              'name': 'TELA',
              'type': 'value',
              'default': <String>['não permitido'],
            },
          ),
          package,
        ),
        throwsFormatException,
      );
    });
  });

  test('seletor declarativo valida opções, padrão e serialização', () {
    final package = LibraryCatalog.parse(
      catalogBytes([packageJson(id: 'oled-pintor', version: '1.1.0')]),
      catalogUri,
    ).packages.single;
    final field = <String, Object?>{
      'name': 'TELA',
      'type': 'dropdown',
      'default': 'A',
      'options': [
        ['Dó', 'C'],
        ['Lá', 'A']
      ],
    };
    final parsed = LibraryBlockManifest.parse(
      blockManifestBytes(field: field),
      package,
    ).blocks.single.fields.single;
    expect(parsed.type, LibraryBlockFieldType.dropdown);
    expect(parsed.toBridgeJson()['options'], field['options']);
    for (final invalid in <Map<String, Object?>>[
      {...field, 'default': 'B'},
      {...field, 'options': <Object>[]},
      {
        ...field,
        'options': [
          ['Dó', 'C'],
          ['Outra', 'C']
        ]
      },
      {
        ...field,
        'options': [
          ['Dó', 1]
        ]
      },
      {
        ...field,
        'options': [
          ['Dó', 'C', 'extra']
        ]
      },
      {...field, 'min': 0},
      {...field, 'type': 'text'},
    ]) {
      expect(
          () => LibraryBlockManifest.parse(
                blockManifestBytes(field: invalid),
                package,
              ),
          throwsFormatException);
    }
  });

  group('cliente', () {
    test('usa ETag e reutiliza somente catálogo validado após 304', () async {
      final transport = FakeCatalogTransport();
      final cache = MemoryCatalogCache();
      final bytes = catalogBytes([packageJson(id: 'sensor')]);
      transport.responses.add(
        CatalogResponse(
          statusCode: 200,
          headers: const {'etag': '"abc"'},
          bytes: bytes,
        ),
      );
      transport.responses.add(
        CatalogResponse(
          statusCode: 304,
          headers: const {},
          bytes: Uint8List(0),
        ),
      );
      final client = LibraryCatalogClient(transport: transport, cache: cache);
      expect((await client.fetchCatalog()).fromCache, isFalse);
      expect((await client.fetchCatalog()).fromCache, isTrue);
      expect(transport.requests.last.headers['If-None-Match'], '"abc"');
      expect(transport.requests.first.maximum, maximumCatalogBytes);
    });

    test('confere bytes e SHA-256 antes de aceitar download', () async {
      final expected = Uint8List.fromList(utf8.encode('VALUE = 1\n'));
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'sensor',
            size: expected.length,
            digest: sha256.convert(expected).toString(),
          ),
        ]),
        catalogUri,
      );
      final transport = FakeCatalogTransport()
        ..responses.add(
          CatalogResponse(
            statusCode: 200,
            headers: const {},
            bytes: Uint8List.fromList(utf8.encode('CORROMPIDO')),
          ),
        );
      final client = LibraryCatalogClient(
        transport: transport,
        cache: MemoryCatalogCache(),
      );
      await expectLater(
        client.download(catalog.packages),
        throwsA(isA<CatalogIntegrityException>()),
      );
    });

    test('usa arquivo offline somente depois de verificar o cache', () async {
      final expected = Uint8List.fromList(utf8.encode('VALUE = 1\n'));
      final digest = sha256.convert(expected).toString();
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(id: 'sensor', size: expected.length, digest: digest),
        ]),
        catalogUri,
      );
      final cache = MemoryCatalogCache()..files[digest] = expected;
      final transport = FakeCatalogTransport();
      final client = LibraryCatalogClient(transport: transport, cache: cache);
      final downloaded = await client.download(catalog.packages);
      expect(downloaded.single.files.single.bytes, expected);
      expect(transport.requests, isEmpty);
    });

    test('baixa, valida e lista os blocos associados ao pacote', () async {
      final blocks = blockManifestBytes();
      final blocksDigest = sha256.convert(blocks).toString();
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'oled-pintor',
            version: '1.1.0',
            blocks: {
              'url': 'packages/oled-pintor/1.1.0/blocks.json',
              'size': blocks.length,
              'sha256': blocksDigest,
            },
          ),
        ]),
        catalogUri,
      );
      final transport = FakeCatalogTransport()
        ..responses.add(
          CatalogResponse(
            statusCode: 200,
            headers: const {},
            bytes: Uint8List(0),
          ),
        )
        ..responses.add(
          CatalogResponse(
            statusCode: 200,
            headers: const {},
            bytes: blocks,
          ),
        );
      final client = LibraryCatalogClient(
        transport: transport,
        cache: MemoryCatalogCache(),
      );

      final verified = await client.download(catalog.packages);
      expect(verified.single.blockManifest?.blocks.length, 1);
      final available = await client.downloadedBlockManifests(catalog);
      expect(available.single.packageKey, 'oled-pintor@1.1.0');
      expect(transport.requests.last.maximum, maximumBlockManifestBytes);
    });

    test('lista downloads e preserva arquivo compartilhado ao apagar',
        () async {
      final expected = Uint8List.fromList(utf8.encode('VALUE = 1\n'));
      final digest = sha256.convert(expected).toString();
      final catalog = LibraryCatalog.parse(
        catalogBytes([
          packageJson(
            id: 'primeira',
            fileName: 'primeira.py',
            size: expected.length,
            digest: digest,
          ),
          packageJson(
            id: 'segunda',
            fileName: 'segunda.py',
            size: expected.length,
            digest: digest,
          ),
        ]),
        catalogUri,
      );
      final cache = MemoryCatalogCache()..files[digest] = expected;
      final client = LibraryCatalogClient(
        transport: FakeCatalogTransport(),
        cache: cache,
      );

      await client.download(catalog.packages);
      expect(
        (await client.downloadedPackages(catalog)).map((item) => item.id),
        ['primeira', 'segunda'],
      );

      await client.removeDownloadedPackage(catalog, catalog.packages.first);
      expect(cache.files, contains(digest));
      expect(
        (await client.downloadedPackages(catalog)).map((item) => item.id),
        ['segunda'],
      );

      await client.removeDownloadedPackage(catalog, catalog.packages.last);
      expect(cache.files, isNot(contains(digest)));
      expect(await client.downloadedPackages(catalog), isEmpty);
    });

    test('rejeita redirecionamento', () async {
      final transport = FakeCatalogTransport()
        ..responses.add(
          CatalogResponse(
            statusCode: 302,
            headers: const {'location': 'https://other.test/catalog.json'},
            bytes: Uint8List(0),
          ),
        );
      final client = LibraryCatalogClient(
        transport: transport,
        cache: MemoryCatalogCache(),
      );
      await expectLater(
        client.fetchCatalog(),
        throwsA(isA<CatalogNetworkException>()),
      );
    });
  });

  test('planejamento preserva dependência usada por outro pacote', () {
    final catalog = LibraryCatalog.parse(
      catalogBytes([
        packageJson(
          id: 'oled',
          dependencies: [
            {'id': 'shared', 'version': '1.0.0'},
          ],
        ),
        packageJson(id: 'shared'),
      ]),
      catalogUri,
    );
    final empty = DevicePackageRegistry.empty('kit-1');
    final first = const PackageInstallationPlanner().install(
      catalog: catalog,
      current: empty,
      root: catalog.find('oled', '1.0.0')!,
      filesOnDevice: const {},
    );
    final withSharedRoot = const PackageInstallationPlanner().install(
      catalog: catalog,
      current: first.nextRegistry,
      root: catalog.find('shared', '1.0.0')!,
      filesOnDevice: {'oled.py', 'shared.py'},
    );
    final removal = const PackageInstallationPlanner().remove(
      current: withSharedRoot.nextRegistry,
      rootId: 'oled',
    );
    expect(removal.filesToRemove, ['oled.py']);
    expect(removal.nextRegistry.packages, contains('shared'));
  });
}
