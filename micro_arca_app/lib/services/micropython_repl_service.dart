import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_transport.dart';
import 'input_protocol.dart';
import 'library_storage.dart';
import 'raw_repl.dart';

enum KitState {
  disconnected,
  scanning,
  connecting,
  ready,
  uploading,
  managingLibraries,
  running,
  waitingForInput,
  stopping,
}

class InstalledLibrary {
  const InstalledLibrary({required this.name, required this.size});

  final String name;
  final int size;
}

class LibraryUpload {
  const LibraryUpload({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
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
  int _inputRequestVersion = 0;
  KitState state = KitState.disconnected;
  String status = 'Selecione seu kit na aba Kits';
  DiscoveredDevice? device;
  double progress = 0;
  bool libraryManagerAvailable = false;
  int libraryManagerVersion = 0;

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
      final filesCheck = await repl.execute('import arca_files as _arca_files');
      libraryManagerAvailable = filesCheck.succeeded;
      if (libraryManagerAvailable) {
        final version = await _jsonCommand(
          repl,
          "getattr(_arca_files, 'VERSION', 1)",
        );
        libraryManagerVersion = version is int ? version : 1;
      } else {
        libraryManagerVersion = 0;
      }
      final inputCheck = await repl.execute(
        "if '_arca_builtin_input' not in globals(): _arca_builtin_input = input\n"
        "def _arca_input(_prompt=''):\n"
        " print(_prompt, end='')\n"
        " print('\\x1eARCA_INPUT\\x1f', end='')\n"
        " return _arca_builtin_input()\n"
        'input = _arca_input',
      );
      if (!inputCheck.succeeded) throw StateError(inputCheck.error);
      if (epoch == _epoch) {
        _set(
          KitState.ready,
          libraryManagerAvailable
              ? 'Kit pronto'
              : 'Kit pronto — instale arca_files.py para usar bibliotecas',
        );
      }
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

  Future<List<InstalledLibrary>> listLibraries() async {
    if (!isReady || !libraryManagerAvailable) return const [];
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Lendo bibliotecas do kit…');
    try {
      final decoded = await _jsonCommand(repl, '_arca_files.list_files()');
      if (decoded is! List) {
        throw const FormatException('Resposta inválida do kit.');
      }
      final libraries = decoded.map((item) {
        if (item is! Map || item['name'] is! String || item['size'] is! int) {
          throw const FormatException(
              'Biblioteca inválida na resposta do kit.');
        }
        return InstalledLibrary(
          name: item['name'] as String,
          size: item['size'] as int,
        );
      }).toList(growable: false);
      if (epoch == _epoch) _set(KitState.ready, 'Bibliotecas atualizadas');
      return libraries;
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(
          message: 'Não foi possível ler as bibliotecas: $error',
        );
      }
      return const [];
    }
  }

  Future<bool> installLibrary(String name, String content) async {
    if (!isReady || !libraryManagerAvailable) return false;
    final nameError = libraryNameError(name);
    if (nameError != null) {
      _set(KitState.ready, nameError);
      return false;
    }
    final bytes = utf8.encode(content);
    if (bytes.length > 65536) {
      _set(KitState.ready, 'A biblioteca deve ter no máximo 64 KiB.');
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Instalando $name…');
    try {
      final filesystem =
          await _jsonCommand(repl, '_arca_files.filesystem_info()');
      if (filesystem is! Map || filesystem['free'] is! int) {
        throw const FormatException('Espaço livre não informado pelo kit.');
      }
      const safetyMargin = 4096;
      if ((filesystem['free'] as int) < bytes.length + safetyMargin) {
        if (epoch == _epoch) {
          _set(
            KitState.ready,
            'Espaço insuficiente no kit para instalar $name.',
          );
        }
        return false;
      }
      await _command(
        repl,
        "_arca_files.begin('$name', ${bytes.length}, '${sha256.convert(bytes)}')",
      );
      for (var offset = 0; offset < bytes.length; offset += 128) {
        final chunk = bytes.sublist(offset, min(offset + 128, bytes.length));
        final hex =
            chunk.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        await _command(repl, "_arca_files.append('$hex')");
        if (epoch != _epoch) return false;
        progress = (offset + chunk.length) / bytes.length;
        notifyListeners();
      }
      await _command(repl, '_arca_files.finish()');
      if (epoch != _epoch) return false;
      progress = 1;
      _set(KitState.ready, '$name instalada e verificada');
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(message: 'Falha ao instalar $name: $error');
      }
      return false;
    }
  }

  Future<bool> installLibrariesAtomically(List<LibraryUpload> uploads) async {
    if (!isReady || !libraryManagerAvailable || uploads.isEmpty) return false;
    if (libraryManagerVersion < 2) {
      _set(
        KitState.ready,
        'Atualize arca_files.py no kit para instalar pacotes do catálogo.',
      );
      return false;
    }
    final names = <String>{};
    var totalBytes = 0;
    for (final upload in uploads) {
      final error = libraryNameError(upload.name);
      if (error != null || !names.add(upload.name.toLowerCase())) {
        _set(KitState.ready, error ?? 'Pacote contém arquivo duplicado.');
        return false;
      }
      if (upload.bytes.length > 65536) {
        _set(KitState.ready, '${upload.name} excede o limite de 64 KiB.');
        return false;
      }
      totalBytes += upload.bytes.length;
    }
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Preparando pacote no kit…');
    try {
      final filesystem =
          await _jsonCommand(repl, '_arca_files.filesystem_info()');
      if (filesystem is! Map || filesystem['free'] is! int) {
        throw const FormatException('Espaço livre não informado pelo kit.');
      }
      const safetyMargin = 4096;
      if ((filesystem['free'] as int) < totalBytes + safetyMargin) {
        _set(KitState.ready, 'Espaço insuficiente no kit para este pacote.');
        return false;
      }
      await _command(repl, '_arca_files.transaction_begin()');
      var sent = 0;
      for (final upload in uploads) {
        final digest = sha256.convert(upload.bytes).toString();
        await _command(
          repl,
          "_arca_files.transaction_stage('${upload.name}', "
          "${upload.bytes.length}, '$digest')",
        );
        for (var offset = 0; offset < upload.bytes.length; offset += 128) {
          final chunk = upload.bytes.sublist(
            offset,
            min(offset + 128, upload.bytes.length),
          );
          final hex = chunk
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join();
          await _command(repl, "_arca_files.append('$hex')");
          if (epoch != _epoch) return false;
          sent += chunk.length;
          progress = totalBytes == 0 ? 0.9 : sent / totalBytes * 0.9;
          notifyListeners();
        }
        await _command(repl, '_arca_files.transaction_finish_file()');
      }
      _set(KitState.managingLibraries, 'Confirmando pacote…');
      await _command(repl, '_arca_files.transaction_commit()');
      if (epoch != _epoch) return false;
      progress = 1;
      _set(KitState.ready, 'Pacote instalado e verificado');
      return true;
    } catch (error) {
      if (epoch != _epoch) return false;
      try {
        await _command(repl, '_arca_files.abort()');
        if (epoch == _epoch) {
          _set(
            KitState.ready,
            'Instalação cancelada sem substituir o pacote: $error',
          );
        }
      } catch (_) {
        if (epoch == _epoch) {
          await disconnect(message: 'Falha na instalação do pacote: $error');
        }
      }
      return false;
    }
  }

  Future<bool> deleteLibrariesAtomically(List<String> names) async {
    if (!isReady ||
        !libraryManagerAvailable ||
        libraryManagerVersion < 2 ||
        names.isEmpty ||
        names.any((name) => !isValidLibraryName(name))) {
      return false;
    }
    final unique = names.toSet().toList()..sort();
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Removendo pacote…');
    try {
      final encoded = jsonEncode(unique);
      await _command(repl, '_arca_files.delete_many($encoded)');
      if (epoch != _epoch) return false;
      progress = 1;
      _set(KitState.ready, 'Pacote removido do kit');
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível remover o pacote: $error');
      }
      return false;
    }
  }

  Future<bool> deleteLibrary(String name) async {
    if (!isReady || !libraryManagerAvailable || !isValidLibraryName(name)) {
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Removendo $name…');
    try {
      await _command(repl, "_arca_files.delete('$name')");
      if (epoch != _epoch) return false;
      _set(KitState.ready, '$name removida do kit');
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(message: 'Falha ao remover $name: $error');
      }
      return false;
    }
  }

  Future<Object?> _jsonCommand(RawRepl repl, String expression) async {
    final output = StringBuffer();
    final result = await repl.execute(
      "import json; print('ARCA_JSON:' + json.dumps($expression))",
      onOutput: output.write,
    );
    if (!result.succeeded) throw StateError(result.error);
    const marker = 'ARCA_JSON:';
    final text = output.toString();
    final start = text.indexOf(marker);
    if (start < 0) throw const FormatException('Marcador ausente.');
    final valueStart = start + marker.length;
    final lineEnd = text.indexOf('\n', valueStart);
    final encoded =
        text.substring(valueStart, lineEnd < 0 ? text.length : lineEnd).trim();
    return jsonDecode(encoded);
  }

  Future<void> runFile() => runCommand(
        "exec(compile(open('user.py').read(), 'user.py', 'exec'), {'__name__': '__main__', 'input': _arca_input})",
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
    _inputRequestVersion = 0;
    _set(KitState.running, 'Executando…');
    final operation = _run(source, _epoch);
    _activeRun = operation;
    await operation;
    if (identical(_activeRun, operation)) _activeRun = null;
  }

  Future<void> _run(String source, int epoch) async {
    final decoder = InputProtocolDecoder(
      onOutput: _messages.add,
      onInputRequested: () {
        if (epoch == _epoch &&
            (state == KitState.running || state == KitState.waitingForInput)) {
          _inputRequestVersion++;
          _set(KitState.waitingForInput, 'Aguardando resposta…');
        }
      },
    );
    try {
      final result = await _repl!.execute(
        source,
        timeout: null,
        onOutput: decoder.add,
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
    } finally {
      decoder.close();
    }
  }

  Future<bool> sendInputLine(String value) async {
    if (state != KitState.waitingForInput ||
        _activeRun == null ||
        _repl == null) {
      return false;
    }
    final bytes = utf8.encode(value);
    if (bytes.length > 1024 || bytes.any((byte) => byte < 32 || byte == 127)) {
      _set(
        KitState.waitingForInput,
        'A resposta deve ter uma linha e no máximo 1024 bytes.',
      );
      return false;
    }
    final epoch = _epoch;
    final requestVersion = _inputRequestVersion;
    try {
      await _repl!.sendInputLine(value);
      if (epoch == _epoch &&
          state == KitState.waitingForInput &&
          requestVersion == _inputRequestVersion) {
        _set(KitState.running, 'Executando…');
      }
      return epoch == _epoch;
    } catch (error) {
      if (epoch == _epoch) {
        await disconnect(message: 'Não foi possível enviar a resposta: $error');
      }
      return false;
    }
  }

  Future<void> stop() async {
    if ((state != KitState.running && state != KitState.waitingForInput) ||
        _activeRun == null) {
      return;
    }
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
    _inputRequestVersion = 0;
    libraryManagerAvailable = false;
    libraryManagerVersion = 0;
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
