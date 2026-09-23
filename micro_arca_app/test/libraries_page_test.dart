import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/libraries_page.dart';
import 'package:micro_arca_app/services/library_catalog.dart';
import 'package:micro_arca_app/services/library_catalog_client.dart';
import 'package:micro_arca_app/services/library_storage.dart';

class MemoryLibraryStorage implements LibraryStorage {
  MemoryLibraryStorage(this.libraries);

  final List<SavedLibrary> libraries;

  @override
  Future<void> deleteLibrary(String name) async {
    libraries.removeWhere((item) => item.name == name);
  }

  @override
  Future<List<SavedLibrary>> loadLibraries() async => List.of(libraries);

  @override
  Future<void> saveLibrary(SavedLibrary library) async {
    await deleteLibrary(library.name);
    libraries.add(library);
  }
}

class EmptyCatalogRepository implements LibraryCatalogRepository {
  @override
  Future<CatalogSnapshot> fetchCatalog() async => CatalogSnapshot(
        catalog: LibraryCatalog.parse(
          Uint8List.fromList(utf8.encode('{"schema":1,"packages":[]}')),
          Uri.parse(officialCatalogUri),
        ),
        fromCache: false,
      );

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
    final storage = MemoryLibraryStorage([
      SavedLibrary(
        name: 'lib_oled_pintor.py',
        code: 'class PintorOLED:\n    pass\n',
        updatedAt: DateTime(2026),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: LibrariesPage(
          storage: storage,
          catalogRepository: EmptyCatalogRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('lib_oled_pintor.py'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('lib_oled_pintor.py'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Conecte um kit'),
      200,
      scrollable: scrollable,
    );
    expect(find.textContaining('Conecte um kit'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('boot.py'),
      200,
      scrollable: scrollable,
    );
    expect(find.textContaining('boot.py'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
