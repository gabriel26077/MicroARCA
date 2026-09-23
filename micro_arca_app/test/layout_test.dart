import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

void main() {
  for (final width in [320.0, 412.0]) {
    testWidgets('abas cabem em tela de $width e editor com teclado',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Executar'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.text('Console'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Saída do programa'), findsOneWidget);
      await tester.tap(find.text('Kits'));
      await tester.pumpAndSettle();
      expect(find.text('Procurar kits'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
