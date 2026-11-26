import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/companion_devices.dart';
import 'package:micro_arca_app/services/micropython_repl_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('arca/bluetooth_permissions');
  final service = MicroPythonREPLService();
  const kit = AssociatedKit(id: 'AA:BB:CC:DD:EE:FF', name: 'ARCA-TESTE');
  late List<String> calls;
  late Future<Object?> Function(MethodCall) native;

  setUp(() {
    calls = [];
    native = (call) async => switch (call.method) {
          'mode' => 'companion',
          'adapterState' => 'ready',
          'select' => null,
          'isAssociated' => false,
          'list' => [],
          _ => null,
        };
    messenger.setMockMethodCallHandler(CompanionDevices.channel, (call) {
      calls.add(call.method);
      return native(call);
    });
    messenger.setMockMethodCallHandler(permissions, (_) async => true);
  });

  tearDown(() async {
    await service.disconnect();
    messenger.setMockMethodCallHandler(CompanionDevices.channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
  });

  test('cancelar a janela do Android encerra a busca sem iniciar BLE',
      () async {
    await service.startScan();
    expect(calls, ['mode', 'adapterState', 'select']);
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('cancelada'));
    expect(service.devices, isEmpty);
  });

  test('CDM indisponível bloqueia busca sem recorrer ao scanner legado',
      () async {
    native = (_) async => 'unavailable';
    var permissionRequests = 0;
    messenger.setMockMethodCallHandler(permissions, (_) async {
      permissionRequests++;
      return true;
    });
    await service.startScan();
    expect(calls, ['mode']);
    expect(permissionRequests, 0);
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('não oferece a seleção'));
  });

  test('recusar ativação encerra busca sem abrir seletor', () async {
    native = (call) async => switch (call.method) {
          'mode' => 'companion',
          'adapterState' => 'poweredOff',
          'requestEnable' => false,
          _ => null,
        };
    await service.startScan();
    expect(calls, ['mode', 'adapterState', 'requestEnable']);
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('Ativação do Bluetooth cancelada'));
  });

  test('ativar Bluetooth continua automaticamente para seleção', () async {
    var enabled = false;
    final fallback = native;
    native = (call) async {
      if (call.method == 'adapterState') {
        return enabled ? 'ready' : 'poweredOff';
      }
      if (call.method == 'requestEnable') {
        enabled = true;
        return true;
      }
      return fallback(call);
    };
    await service.startScan();
    expect(calls,
        ['mode', 'adapterState', 'requestEnable', 'adapterState', 'select']);
  });

  test('cancelar durante ativação ignora aceite tardio', () async {
    final enabled = Completer<bool>();
    final opened = Completer<void>();
    final fallback = native;
    native = (call) {
      if (call.method == 'adapterState') return Future.value('poweredOff');
      if (call.method == 'requestEnable') {
        opened.complete();
        return enabled.future;
      }
      return fallback(call);
    };
    final scan = service.startScan();
    await opened.future;
    await service.startScan();
    expect(calls.where((c) => c == 'requestEnable'), hasLength(1));
    await service.stopScan();
    enabled.complete(true);
    await scan;
    expect(calls, contains('cancel'));
    expect(calls, isNot(contains('select')));
    expect(service.state, KitState.disconnected);
  });

  test('toques repetidos abrem apenas uma janela', () async {
    final selected = Completer<Object?>();
    final opened = Completer<void>();
    final fallback = native;
    native = (call) {
      if (call.method == 'select') {
        opened.complete();
        return selected.future;
      }
      return fallback(call);
    };
    final first = service.startScan();
    await opened.future;
    await service.startScan();
    expect(calls.where((c) => c == 'select'), hasLength(1));
    selected.complete(null);
    await first;
  });

  test('cancelar ignora seleção tardia e não conecta o kit', () async {
    final selected = Completer<Object?>();
    final opened = Completer<void>();
    final fallback = native;
    native = (call) {
      if (call.method == 'select') {
        opened.complete();
        return selected.future;
      }
      return fallback(call);
    };
    final scan = service.startScan();
    await opened.future;
    await service.stopScan();
    selected.complete({'id': kit.id, 'name': kit.name});
    await scan;
    expect(calls, contains('cancel'));
    expect(calls, isNot(contains('isAssociated')));
    expect(service.state, KitState.disconnected);
    expect(service.devices, isEmpty);
  });

  test('resposta antiga não apaga uma nova seleção em andamento', () async {
    final firstResult = Completer<Object?>();
    final secondResult = Completer<Object?>();
    final firstOpened = Completer<void>();
    final secondOpened = Completer<void>();
    final fallback = native;
    var count = 0;
    native = (call) {
      if (call.method == 'select') {
        if (++count == 1) {
          firstOpened.complete();
          return firstResult.future;
        }
        secondOpened.complete();
        return secondResult.future;
      }
      return fallback(call);
    };
    final first = service.startScan();
    await firstOpened.future;
    await service.stopScan();
    final second = service.startScan();
    await secondOpened.future;
    firstResult.complete(null);
    await first;
    await service.stopScan();
    expect(calls.where((c) => c == 'cancel'), hasLength(2));
    secondResult.complete(null);
    await second;
    expect(service.state, KitState.disconnected);
  });

  test('falha ao fechar janela não deixa a busca ativa', () async {
    final selected = Completer<Object?>();
    final opened = Completer<void>();
    final fallback = native;
    native = (call) {
      if (call.method == 'select') {
        opened.complete();
        return selected.future;
      }
      if (call.method == 'cancel') {
        throw PlatformException(code: 'activity_destroyed');
      }
      return fallback(call);
    };
    final scan = service.startScan();
    await opened.future;
    await service.stopScan();
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('Feche a janela'));
    selected.complete(null);
    await scan;
  });

  test('seleção sem associação confirmada não inicia conexão GATT', () async {
    final fallback = native;
    native = (call) async => call.method == 'select'
        ? {'id': kit.id, 'name': kit.name}
        : await fallback(call);
    await service.startScan();
    expect(calls, contains('isAssociated'));
    expect(service.state, KitState.disconnected);
    expect(service.status, contains('autorize o kit'));
    expect(service.isConnected, isFalse);
  });

  test('reconexão confere autorização atual antes de usar endereço salvo',
      () async {
    await service.connectAssociatedKit(kit);
    expect(calls, ['mode', 'adapterState', 'isAssociated']);
    expect(service.status, contains('autorize o kit'));
  });

  test('lista e esquecimento usam as associações do sistema', () async {
    final fallback = native;
    native = (call) async {
      if (call.method == 'list') {
        return [
          {'id': kit.id, 'name': kit.name}
        ];
      }
      if (call.method == 'forget') expect(call.arguments, {'id': kit.id});
      return fallback(call);
    };
    final saved = await service.associatedKits();
    expect(saved.single.name, kit.name);
    await service.forgetKit(saved.single);
    expect(calls, ['mode', 'list', 'forget']);
  });

  test('endereço inválido retornado pelo Android é recusado', () {
    expect(() => AssociatedKit.fromMap({'id': '', 'name': 'ARCA'}),
        throwsFormatException);
    expect(AssociatedKit.fromMap({'id': 'aa:bb:cc:dd:ee:ff', 'name': ''}).id,
        kit.id);
  });
}
