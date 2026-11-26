import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/pages/legal_page.dart';

void main() {
  testWidgets('documentos de privacidade e termos abrem sem rede',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalPage()));
    await tester.tap(find.text('Política de Privacidade'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('90 dias após'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Termos de Uso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não utilize o MicroARCA'), findsOneWidget);
  });
}
