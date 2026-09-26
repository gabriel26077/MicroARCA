import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

import 'memory_project_storage.dart';

void main() {
  for (final width in [320.0, 412.0]) {
    testWidgets('abas cabem em tela de $width e com teclado', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(home: MainScreen(projectStorage: MemoryProjectStorage())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Meus projetos'), findsOneWidget);
      expect(find.byTooltip('Projetos'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.byTooltip('Console'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Saída do programa'), findsOneWidget);
      await tester.tap(find.byTooltip('Kits'));
      await tester.pumpAndSettle();
      expect(find.text('Procurar kits'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
