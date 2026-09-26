import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/libraries_page.dart';
import 'package:micro_arca_app/services/library_block_manifest.dart';
import 'package:micro_arca_app/services/library_catalog.dart';
import 'package:micro_arca_app/services/library_catalog_client.dart';

class EmptyCatalogRepository implements LibraryCatalogRepository {
  @override
  Future<List<LibraryBlockManifest>> cachedBlockManifests() async => const [];

  @override
  Future<CatalogSnapshot> fetchCatalog() async => CatalogSnapshot(
        catalog: LibraryCatalog.parse(
          Uint8List.fromList(utf8.encode('{"schema":1,"packages":[]}')),
          Uri.parse(officialCatalogUri),
        ),
        fromCache: false,
      );

  @override
  Future<List<CatalogPackage>> downloadedPackages(
    LibraryCatalog catalog,
  ) async =>
      const [];

  @override
  Future<List<LibraryBlockManifest>> downloadedBlockManifests(
    LibraryCatalog catalog,
  ) async =>
      const [];

  @override
  Future<void> removeDownloadedPackage(
    LibraryCatalog catalog,
    CatalogPackage package,
  ) async {}

  @override
  Future<List<VerifiedPackage>> download(
    List<CatalogPackage> packages, {
    void Function(int received, int total)? onProgress,
  }) async =>
      const [];
}

class DownloadedCatalogRepository implements LibraryCatalogRepository {
  DownloadedCatalogRepository()
      : catalog = LibraryCatalog.parse(
          Uint8List.fromList(
            utf8.encode(
              '{"schema":1,"packages":[{'
              '"id":"teste","name":"Biblioteca teste",'
              '"version":"1.0.0","description":"Teste",'
              '"author":"ARCA","license":"MIT",'
              '"license_url":"packages/teste/1.0.0/LICENSE",'
              '"compatibility":{"micropython":">=1.24",'
              '"boards":["ESP32_GENERIC"]},"dependencies":[],'
              '"files":[{"name":"teste.py",'
              '"url":"packages/teste/1.0.0/teste.py","size":0,'
              '"sha256":"e3b0c44298fc1c149afbf4c8996fb924'
              '27ae41e4649b934ca495991b7852b855"}]}]}',
            ),
          ),
          Uri.parse(officialCatalogUri),
        );

  final LibraryCatalog catalog;
  bool downloaded = true;

  @override
  Future<List<LibraryBlockManifest>> cachedBlockManifests() async => const [];

  @override
  Future<CatalogSnapshot> fetchCatalog() async =>
      CatalogSnapshot(catalog: catalog, fromCache: false);

  @override
  Future<List<CatalogPackage>> downloadedPackages(
    LibraryCatalog catalog,
  ) async =>
      downloaded ? [catalog.packages.single] : const [];

  @override
  Future<List<LibraryBlockManifest>> downloadedBlockManifests(
    LibraryCatalog catalog,
  ) async =>
      const [];

  @override
  Future<void> removeDownloadedPackage(
    LibraryCatalog catalog,
    CatalogPackage package,
  ) async {
    downloaded = false;
  }

  @override
  Future<List<VerifiedPackage>> download(
    List<CatalogPackage> packages, {
    void Function(int received, int total)? onProgress,
  }) async =>
      const [];
}

void main() {
  testWidgets('gerenciador cabe em tela estreita e protege a raiz',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LibrariesPage(catalogRepository: EmptyCatalogRepository()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Celular'));
    await tester.pumpAndSettle();
    expect(find.text('Pacotes oficiais no celular'), findsOneWidget);
    expect(find.textContaining('explorador do Editor'), findsOneWidget);
    expect(find.text('Nenhum pacote baixado do catálogo'), findsOneWidget);

    await tester.tap(find.text('Dispositivo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Conecte um kit'), findsOneWidget);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.textContaining('boot.py'),
      200,
      scrollable: scrollable,
    );
    expect(find.textContaining('boot.py'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marca e remove pacote baixado no celular', (tester) async {
    final repository = DownloadedCatalogRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: LibrariesPage(catalogRepository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No celular'), findsOneWidget);
    await tester.tap(find.text('Celular'));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteca teste'), findsOneWidget);

    await tester.tap(find.byTooltip('Apagar do celular'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(repository.downloaded, isFalse);
    expect(find.text('Nenhum pacote baixado do catálogo'), findsOneWidget);
    expect(find.text('Biblioteca teste removida do celular.'), findsOneWidget);
  });
}
