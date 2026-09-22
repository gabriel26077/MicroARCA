import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/micropython_repl_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('arca/bluetooth_permissions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = MicroPythonREPLService();

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await service.disconnect();
  });

  test('cancelar durante a permissão não inicia BLE quando a resposta chega',
      () async {
    final permission = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => permission.future);
    final scanning = service.startScan();
    expect(service.state, KitState.scanning);
    await service.stopScan();
    permission.complete(true);
    await scanning;
    expect(service.state, KitState.disconnected);
    expect(service.devices, isEmpty);
  });

  test('permissão negada encerra o indicador de busca e explica o motivo',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    await service.startScan();
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('Permita o acesso ao Bluetooth'));
  });

  test('duplo toque não cria duas solicitações de permissão', () async {
    final permission = Completer<bool>();
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      requests++;
      return permission.future;
    });
    final first = service.startScan();
    final second = service.startScan();
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    permission.complete(false);
    await Future.wait([first, second]);
    expect(service.state, KitState.disconnected);
  });
}
