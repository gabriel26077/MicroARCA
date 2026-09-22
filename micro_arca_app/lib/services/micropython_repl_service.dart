import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_transport.dart';
import 'raw_repl.dart';

enum KitState {
  disconnected,
  scanning,
  connecting,
  ready,
  uploading,
  running,
  stopping,
}

/// Estado compartilhado pelo editor, console e lista de kits.
class MicroPythonREPLService extends ChangeNotifier {
  static final MicroPythonREPLService _instance = MicroPythonREPLService._();
  factory MicroPythonREPLService() => _instance;
  MicroPythonREPLService._();

  late final FlutterReactiveBle _ble = FlutterReactiveBle();
  static const _permissions = MethodChannel('arca/bluetooth_permissions');
  final _messages = StreamController<String>.broadcast();
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<BleStatus>? _adapter;
  Timer? _scanTimer;
  BleTransport? _transport;
  RawRepl? _repl;
  Future<void>? _activeRun;
  Future<void> _closing = Future<void>.value();
  int _epoch = 0;
  KitState state = KitState.disconnected;
  String status = 'Selecione seu kit na aba Kits';
  DiscoveredDevice? device;
  double progress = 0;

  Stream<String> get onMessage => _messages.stream;
  bool get isConnected => _repl != null && state != KitState.connecting;
  bool get isReady => state == KitState.ready;
  int get sessionId => _epoch;
  List<DiscoveredDevice> get devices =>
      _devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  void _set(KitState value, String message) {
    state = value;
    status = message;
    notifyListeners();
  }

  Future<bool> _checkBluetooth(int epoch) async {
    final allowed = await _permissions
        .invokeMethod<bool>('request')
        .then((v) => v ?? false);
    if (epoch != _epoch) return false;
    if (!allowed) {
      throw StateError('Permita o acesso ao Bluetooth para procurar seu kit.');
    }
    _adapter ??= _ble.statusStream.listen((value) {
      if (value != BleStatus.ready &&
          value != BleStatus.unknown &&
          (_transport != null || _connection != null || _scan != null)) {
        unawaited(disconnect(message: _adapterMessage(value)));
      }
    });
    final adapter = _ble.status == BleStatus.ready
        ? BleStatus.ready
        : await _ble.statusStream
            .firstWhere(
              (s) => s != BleStatus.unknown && s != BleStatus.unauthorized,
            )
            .timeout(const Duration(seconds: 5));
    if (adapter != BleStatus.ready) throw StateError(_adapterMessage(adapter));
    return true;
  }

  String _adapterMessage(BleStatus value) {
    switch (value) {
      case BleStatus.poweredOff:
        return 'Ative o Bluetooth do celular.';
      case BleStatus.unauthorized:
        return 'Permita o acesso ao Bluetooth nas configurações do Android.';
      case BleStatus.locationServicesDisabled:
        return 'Neste Android, ative a localização para buscar kits Bluetooth.';
      case BleStatus.unsupported:
        return 'Este celular não oferece suporte a BLE.';
      default:
        return 'Bluetooth indisponível. Tente novamente.';
    }
  }

  Future<void> startScan() async {
    if (isConnected ||
        state == KitState.connecting ||
        state == KitState.scanning) {
      return;
    }
    final epoch = ++_epoch;
    _devices.clear();
    _set(KitState.scanning, 'Preparando Bluetooth…');
    try {
      await _closing;
      if (epoch != _epoch || !await _checkBluetooth(epoch)) return;
      if (epoch != _epoch) return;
      _set(KitState.scanning, 'Procurando kits ARCA…');
      _scan = _ble.scanForDevices(
        withServices: [arcaServiceId],
        scanMode: ScanMode.lowLatency,
      ).listen(
        (found) {
          if (epoch != _epoch) return;
          _devices[found.id] = found;
          notifyListeners();
        },
        onError: (Object error) {
          if (epoch == _epoch) {
            unawaited(disconnect(message: 'Falha na busca: $error'));
          }
        },
      );
      _scanTimer = Timer(const Duration(seconds: 10), () {
        if (epoch == _epoch) unawaited(stopScan());
      });
    } catch (error) {
      if (epoch == _epoch) await disconnect(message: '$error');
    }
  }

  Future<void> stopScan() async {
    if (state == KitState.scanning) ++_epoch;
    _scanTimer?.cancel();
    _scanTimer = null;
    final scan = _scan;
    _scan = null;
    await scan?.cancel();
    if (state == KitState.scanning) {
      _set(
        KitState.disconnected,
        _devices.isEmpty
            ? 'Nenhum kit encontrado. Confira se a placa está ligada e com o firmware BLE.'
            : 'Selecione seu kit',
      );
    }
  }

  Future<void> connect(DiscoveredDevice selected) async {
    if (isConnected || state == KitState.connecting) return;
    final epoch = ++_epoch;
    device = selected;
    _set(KitState.connecting, 'Conectando a ${selected.name}…');
    await stopScan();
    final connected = Completer<void>();
    try {
      await _closing;
      if (epoch != _epoch || !await _checkBluetooth(epoch)) return;
      if (epoch != _epoch) return;
      _connection = _ble
          .connectToDevice(
        id: selected.id,
        servicesWithCharacteristicsToDiscover: {
          arcaServiceId: [arcaRxId, arcaTxId, arcaControlId],
        },
        connectionTimeout: const Duration(seconds: 10),
      )
          .listen(
        (update) {
          if (epoch != _epoch) return;
          if (update.connectionState == DeviceConnectionState.connected) {
            if (!connected.isCompleted) connected.complete();
          } else if (update.connectionState ==
              DeviceConnectionState.disconnected) {
            if (!connected.isCompleted) {
              connected.completeError(StateError('Kit desconectado'));
            } else {
              unawaited(
                disconnect(
                  message:
                      'Conexão perdida. A execução pode continuar na placa; reconecte para controlá-la.',
                ),
              );
            }
          }
        },
        onError: (Object error) {
          if (epoch != _epoch) return;
          if (!connected.isCompleted) {
            connected.completeError(error);
          } else {
            unawaited(disconnect(message: 'Erro Bluetooth: $error'));
          }
        },
      );
      await connected.future.timeout(const Duration(seconds: 12));
      if (epoch != _epoch) return;
      final transport = BleTransport(_ble, selected.id, onFailure: (error) {
        if (epoch == _epoch) {
          unawaited(disconnect(message: 'Falha no canal Bluetooth: $error'));
        }
      });
      final repl = RawRepl(transport);
      _transport = transport;
      _repl = repl;
      await transport.negotiateMtu();
      if (epoch != _epoch) return;
      transport.subscribe();
      var receivedHello = false;
      for (var attempt = 0; attempt < 10; attempt++) {
        await transport.control(82); // R: pede identificação após habilitar TX.
        try {
          await repl.waitForHello();
          receivedHello = true;
          break;
        } on TimeoutException {
          if (epoch != _epoch) return;
        }
      }
      if (!receivedHello) throw StateError('Firmware ARCA BLE não respondeu');
      await transport.control(65); // A: confirma o canal antes de usar o REPL.
      await repl.synchronize();
      final check = await repl.execute('import arca_runtime as _arca');
      if (!check.succeeded) throw StateError(check.error);
      if (epoch == _epoch) _set(KitState.ready, 'Kit pronto');
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(message: 'Não foi possível conectar: $error');
      }
    }
  }

  Future<bool> uploadFile(String content) async {
    if (!isReady) return false;
    final bytes = utf8.encode(content);
    if (bytes.length > 65536) {
      _set(KitState.ready, 'O programa deve ter no máximo 64 KiB.');
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.uploading, 'Enviando programa…');
    try {
      await _command(
        repl,
        "import arca_runtime as _arca; _arca.begin(${bytes.length}, '${sha256.convert(bytes)}')",
      );
      for (var offset = 0; offset < bytes.length; offset += 128) {
        final chunk = bytes.sublist(offset, min(offset + 128, bytes.length));
        final hex =
            chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await _command(repl, "_arca.append('$hex')");
        if (epoch != _epoch) return false;
        progress = (offset + chunk.length) / bytes.length;
        notifyListeners();
      }
      await _command(repl, '_arca.finish()');
      if (epoch != _epoch) return false;
      _set(KitState.ready, 'Programa enviado e verificado');
      return true;
    } catch (error) {
      // Reconexão sincroniza o REPL; o próximo begin descarta arquivo parcial.
      if (epoch == _epoch) await disconnect(message: 'Falha no envio: $error');
      return false;
    }
  }

  Future<void> _command(RawRepl repl, String command) async {
    final result = await repl.execute(command);
    if (!result.succeeded) throw StateError(result.error);
  }

  Future<void> runFile() => runCommand(
        "exec(compile(open('user.py').read(), 'user.py', 'exec'), {'__name__': '__main__'})",
      );

  Future<void> runCommand(String source) async {
    if (!isReady || source.trim().isEmpty) return;
    if (utf8.encode(source).length > 1024 ||
        source.codeUnits.any((b) => b < 32 && b != 10 && b != 9)) {
      _set(
        KitState.ready,
        'Comando inválido ou maior que 1024 bytes. Use o editor para enviar um arquivo.',
      );
      return;
    }
    _set(KitState.running, 'Executando…');
    final operation = _run(source, _epoch);
    _activeRun = operation;
    await operation;
    if (identical(_activeRun, operation)) _activeRun = null;
  }

  Future<void> _run(String source, int epoch) async {
    try {
      final result = await _repl!.execute(
        source,
        timeout: null,
        onOutput: _messages.add,
      );
      if (epoch != _epoch) return;
      final stopped = state == KitState.stopping &&
          result.error.contains('KeyboardInterrupt');
      _set(
        KitState.ready,
        stopped
            ? 'Execução interrompida'
            : result.succeeded
                ? 'Execução concluída'
                : 'Erro no programa — veja o console',
      );
    } catch (error) {
      if (epoch == _epoch) await disconnect(message: 'Erro na sessão: $error');
    }
  }

  Future<void> stop() async {
    if (state != KitState.running || _activeRun == null) return;
    final epoch = _epoch;
    final operation = _activeRun!;
    _set(KitState.stopping, 'Interrompendo…');
    try {
      await _repl!.interrupt();
      await operation.timeout(const Duration(seconds: 5));
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(
          message:
              'O kit não confirmou a parada. Use RESET na placa e reconecte.',
        );
      }
    }
  }

  Future<void> disconnect({String message = 'Desconectado'}) async {
    final epoch = ++_epoch;
    final repl = _repl;
    final transport = _transport;
    final connection = _connection;
    _repl = null;
    _transport = null;
    _connection = null;
    _activeRun = null;
    device = null;
    _set(KitState.disconnected, message);
    _closing = Future.wait<void>([
      _closing,
      stopScan(),
      if (repl != null) repl.close(),
      if (transport != null) transport.close(),
      if (connection != null) connection.cancel(),
    ]).then<void>((_) {}).catchError((Object error) {
      if (epoch == _epoch) {
        _set(KitState.disconnected,
            '$message. Falha ao encerrar Bluetooth: $error');
      }
    });
    await _closing;
  }
}
