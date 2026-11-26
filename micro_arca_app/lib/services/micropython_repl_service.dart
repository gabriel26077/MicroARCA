import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_transport.dart';
import 'companion_devices.dart';
import 'input_protocol.dart';
import 'library_storage.dart';
import 'project_storage.dart';
import 'raw_repl.dart';
import 'workspace_run_command.dart';

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

class WorkspaceFile {
  const WorkspaceFile({required this.name, required this.size});

  final String name;
  final int size;
}

/// Projeto do app registrado no kit: o que foi enviado ou gravado.
class KitProjectInfo {
  const KitProjectInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.revision,
  });

  factory KitProjectInfo.of(ProjectSummary project) => KitProjectInfo(
        id: project.id,
        name: project.name,
        kind: project.kind,
        revision: project.revision,
      );

  static KitProjectInfo? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['revision'] is! int) {
      return null;
    }
    try {
      return KitProjectInfo(
        id: value['id'] as String,
        name: value['name'] as String,
        kind: ProjectKind.fromId(value['kind']),
        revision: value['revision'] as int,
      );
    } on FormatException {
      return null;
    }
  }

  final String id;
  final String name;
  final ProjectKind kind;
  final int revision;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.id,
        'revision': revision,
      };
}

/// Programa congelado que o firmware executa ao ligar a placa.
class AutorunStatus {
  const AutorunStatus({
    required this.enabled,
    required this.installed,
    required this.tripped,
    required this.files,
    this.project,
  });

  factory AutorunStatus.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Estado inválido.');
    final files = value['files'];
    return AutorunStatus(
      enabled: value['enabled'] == true,
      installed: value['installed'] == true,
      tripped: value['tripped'] == true,
      files: files is List ? files.whereType<String>().toList() : const [],
      project: KitProjectInfo.fromJson(value['project']),
    );
  }

  final bool enabled;
  final bool installed;

  /// Desligado pelo firmware após reinícios seguidos sem estabilizar.
  final bool tripped;
  final List<String> files;

  /// Projeto gravado; null se foi gravado por um app sem projetos.
  final KitProjectInfo? project;

  bool get active => enabled && installed;
}

/// Estado compartilhado pelo editor, console e lista de kits.
class MicroPythonREPLService extends ChangeNotifier {
  static final MicroPythonREPLService _instance = MicroPythonREPLService._();
  factory MicroPythonREPLService() => _instance;
  MicroPythonREPLService._();

  late final FlutterReactiveBle _ble = FlutterReactiveBle();
  static const _permissions = MethodChannel('arca/bluetooth_permissions');
  final _companion = CompanionDevices();
  KitDiscoveryMode? _discoveryMode;
  int? _companionPickerEpoch;
  int? _bluetoothEnableEpoch;
  bool get usesCompanionDiscovery =>
      _discoveryMode == KitDiscoveryMode.companion;

  Future<List<AssociatedKit>> associatedKits() async {
    _discoveryMode = await _companion.mode();
    notifyListeners();
    return usesCompanionDiscovery ? _companion.list() : [];
  }

  Future<void> forgetKit(AssociatedKit kit) async {
    if (state == KitState.scanning || state == KitState.connecting) {
      throw StateError(
          'Termine a seleção ou conexão antes de esquecer um kit.');
    }
    if (device?.id.toUpperCase() == kit.id) await disconnect();
    await _companion.forget(kit.id);
    _devices.remove(kit.id);
    notifyListeners();
  }

  DiscoveredDevice _associatedDevice(AssociatedKit kit) => DiscoveredDevice(
        id: kit.id,
        name: kit.name,
        serviceData: const {},
        manufacturerData: Uint8List(0),
        rssi: 0,
        serviceUuids: [arcaServiceId],
      );

  Future<void> connectAssociatedKit(AssociatedKit kit) =>
      connect(_associatedDevice(kit));
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
  String status = 'Selecione seu kit pelo botão Bluetooth';
  DiscoveredDevice? device;
  double progress = 0;
  bool libraryManagerAvailable = false;
  int libraryManagerVersion = 0;
  AutorunStatus? autorun;

  Stream<String> get onMessage => _messages.stream;
  bool get autorunAvailable =>
      libraryManagerAvailable && libraryManagerVersion >= 5;
  bool get isConnected => _repl != null && state != KitState.connecting;
  bool get isReady => state == KitState.ready;
  bool get workspaceManagerAvailable =>
      libraryManagerAvailable && libraryManagerVersion >= 3;
  int get sessionId => _epoch;
  List<DiscoveredDevice> get devices =>
      _devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  void _set(KitState value, String message) {
    state = value;
    status = message;
    notifyListeners();
  }

  Future<bool> _checkBluetooth(int epoch, KitDiscoveryMode mode) async {
    final allowed = await _permissions
        .invokeMethod<bool>('request')
        .then((v) => v ?? false);
    if (epoch != _epoch) return false;
    if (!allowed) {
      throw StateError('Permita o acesso ao Bluetooth para procurar seu kit.');
    }
    var adapterState = await _companion.adapterState();
    if (epoch != _epoch) return false;
    if (adapterState == 'poweredOff') {
      _set(state, 'Aguardando ativação do Bluetooth…');
      _bluetoothEnableEpoch = epoch;
      bool enabled;
      try {
        enabled = await _companion.requestEnable();
      } finally {
        if (_bluetoothEnableEpoch == epoch) _bluetoothEnableEpoch = null;
      }
      if (epoch != _epoch) return false;
      if (!enabled) {
        await disconnect(message: 'Ativação do Bluetooth cancelada.');
        return false;
      }
      adapterState = await _companion.adapterState();
      if (epoch != _epoch) return false;
    }
    if (adapterState != 'ready') {
      throw StateError(adapterState == 'poweredOff'
          ? 'Não foi possível ativar o Bluetooth. Tente novamente.'
          : 'Este celular não oferece suporte a BLE.');
    }
    if (mode == KitDiscoveryMode.companion) {
      // O status do scanner da biblioteca exige permissões de busca que o
      // CDM dispensa. Aqui verificamos apenas o adaptador e a conexão.
      return true;
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
      if (epoch != _epoch) return;
      final mode = await _companion.mode();
      _discoveryMode = mode;
      if (epoch != _epoch || !await _checkBluetooth(epoch, mode)) return;
      if (epoch != _epoch) return;
      if (mode == KitDiscoveryMode.companion) {
        _set(KitState.scanning, 'Escolha o kit na janela do Android.');
        _companionPickerEpoch = epoch;
        AssociatedKit? selected;
        try {
          selected = await _companion.select();
        } finally {
          if (_companionPickerEpoch == epoch) _companionPickerEpoch = null;
        }
        if (epoch != _epoch) return;
        if (selected == null) {
          _set(KitState.disconnected, 'Seleção do kit cancelada.');
          return;
        }
        final kit = _associatedDevice(selected);
        _devices[kit.id] = kit;
        await connect(kit);
        return;
      }
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
    final companionActive =
        _companionPickerEpoch != null || _bluetoothEnableEpoch != null;
    var closeChooserFailed = false;
    if (state == KitState.scanning) ++_epoch;
    if (companionActive) {
      _companionPickerEpoch = null;
      _bluetoothEnableEpoch = null;
      try {
        await _companion.cancel();
      } on PlatformException {
        closeChooserFailed = true;
      }
    }
    _scanTimer?.cancel();
    _scanTimer = null;
    final scan = _scan;
    _scan = null;
    await scan?.cancel();
    if (state == KitState.scanning) {
      _set(
        KitState.disconnected,
        closeChooserFailed
            ? 'Busca encerrada. Feche a janela do Android se ela permanecer aberta.'
            : companionActive
                ? 'Seleção do kit cancelada.'
                : _devices.isEmpty
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
      if (epoch != _epoch) return;
      final mode = await _companion.mode();
      _discoveryMode = mode;
      if (epoch != _epoch || !await _checkBluetooth(epoch, mode)) return;
      if (mode == KitDiscoveryMode.companion) {
        final associated = await _companion.isAssociated(selected.id);
        if (epoch != _epoch) return;
        if (!associated) {
          throw StateError(
              'Selecione e autorize o kit pela janela do Android.');
        }
      }
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
      if (autorunAvailable) {
        // Conectar prova que o kit está acessível: zera a proteção contra
        // reinícios seguidos antes de ler o estado.
        await _command(repl, '_arca_files.autorun_mark_healthy()');
        autorun = AutorunStatus.fromJson(
          await _jsonCommand(repl, '_arca_files.autorun_status()'),
        );
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
          !libraryManagerAvailable
              ? 'Kit pronto — instale arca_files.py para usar bibliotecas'
              : libraryManagerVersion < 3
                  ? 'Kit pronto — atualize arca_files.py para editar arquivos'
                  : 'Kit pronto',
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

  Future<List<WorkspaceFile>> listWorkspaceFiles() async {
    if (!isReady || !workspaceManagerAvailable) return const [];
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.managingLibraries, 'Lendo arquivos do projeto…');
    try {
      final decoded = await _jsonCommand(repl, '_arca_files.workspace_list()');
      if (decoded is! List) {
        throw const FormatException('Resposta inválida do kit.');
      }
      final files = decoded.map((item) {
        if (item is! Map || item['name'] is! String || item['size'] is! int) {
          throw const FormatException('Arquivo inválido na resposta do kit.');
        }
        return WorkspaceFile(
          name: item['name'] as String,
          size: item['size'] as int,
        );
      }).toList(growable: false);
      if (epoch == _epoch) _set(KitState.ready, 'Arquivos atualizados');
      return files;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível ler os arquivos: $error');
      }
      return const [];
    }
  }

  Future<String?> readWorkspaceFile(WorkspaceFile file) async {
    if (!isReady || !workspaceManagerAvailable) return null;
    final nameError = workspaceFileNameError(file.name);
    if (nameError != null || file.size < 0 || file.size > 65536) {
      _set(KitState.ready, nameError ?? 'Tamanho de arquivo inválido.');
      return null;
    }
    final epoch = _epoch;
    final repl = _repl!;
    final bytes = <int>[];
    progress = 0;
    _set(KitState.managingLibraries, 'Abrindo ${file.name}…');
    try {
      for (var offset = 0; offset < file.size; offset += 128) {
        final value = await _jsonCommand(
          repl,
          "_arca_files.workspace_read_chunk('${file.name}', $offset, 128)",
        );
        if (value is! String || value.length.isOdd) {
          throw const FormatException('Conteúdo inválido recebido do kit.');
        }
        for (var index = 0; index < value.length; index += 2) {
          bytes.add(int.parse(value.substring(index, index + 2), radix: 16));
        }
        if (epoch != _epoch) return null;
        progress = file.size == 0 ? 1 : bytes.length / file.size;
        notifyListeners();
      }
      if (bytes.length != file.size) {
        throw const FormatException('Leitura incompleta do arquivo.');
      }
      final content = utf8.decode(bytes);
      if (epoch == _epoch) _set(KitState.ready, '${file.name} aberto');
      return content;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível abrir ${file.name}: $error');
      }
      return null;
    }
  }

  Future<bool> saveWorkspaceFile(String name, String content) async {
    if (!isReady || !workspaceManagerAvailable) return false;
    final nameError = workspaceFileNameError(name);
    if (nameError != null) {
      _set(KitState.ready, nameError);
      return false;
    }
    final bytes = utf8.encode(content);
    if (bytes.length > 65536) {
      _set(KitState.ready, 'O arquivo deve ter no máximo 64 KiB.');
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    progress = 0;
    _set(KitState.uploading, 'Salvando $name no kit…');
    try {
      await _command(
        repl,
        "_arca_files.workspace_begin('$name', ${bytes.length}, '${sha256.convert(bytes)}')",
      );
      for (var offset = 0; offset < bytes.length; offset += 128) {
        final chunk = bytes.sublist(offset, min(offset + 128, bytes.length));
        final hex =
            chunk.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        await _command(repl, "_arca_files.workspace_append('$hex')");
        if (epoch != _epoch) return false;
        progress = bytes.isEmpty ? 0.9 : (offset + chunk.length) / bytes.length;
        notifyListeners();
      }
      await _command(repl, '_arca_files.workspace_finish()');
      if (epoch != _epoch) return false;
      progress = 1;
      _set(KitState.ready, '$name salvo e verificado no kit');
      return true;
    } catch (error) {
      if (epoch != _epoch) return false;
      try {
        await _command(repl, '_arca_files.workspace_abort()');
        if (epoch == _epoch) {
          _set(KitState.ready, 'Envio cancelado sem substituir $name: $error');
        }
      } catch (_) {
        if (epoch == _epoch) {
          await disconnect(message: 'Falha ao salvar $name: $error');
        }
      }
      return false;
    }
  }

  Future<bool> deleteWorkspaceFile(String name) async {
    if (!isReady ||
        !workspaceManagerAvailable ||
        name.toLowerCase() == 'main.py' ||
        !isValidWorkspaceFileName(name)) {
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    _set(KitState.managingLibraries, 'Excluindo $name…');
    try {
      await _command(repl, "_arca_files.workspace_delete('$name')");
      if (epoch != _epoch) return false;
      _set(KitState.ready, '$name excluído do kit');
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível excluir $name: $error');
      }
      return false;
    }
  }

  Future<bool> renameWorkspaceFile(String oldName, String newName) async {
    if (!isReady ||
        !workspaceManagerAvailable ||
        oldName.toLowerCase() == 'main.py' ||
        !isValidWorkspaceFileName(oldName) ||
        !isValidWorkspaceFileName(newName) ||
        oldName.toLowerCase() == newName.toLowerCase()) {
      return false;
    }
    final epoch = _epoch;
    final repl = _repl!;
    _set(KitState.managingLibraries, 'Renomeando $oldName…');
    try {
      await _command(
        repl,
        "_arca_files.workspace_rename('$oldName', '$newName')",
      );
      if (epoch != _epoch) return false;
      _set(KitState.ready, '$oldName renomeado para $newName');
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível renomear $oldName: $error');
      }
      return false;
    }
  }

  /// Registra no kit qual projeto está em /app. O firmware copia esse registro
  /// ao gravar o programa de inicialização.
  Future<bool> setKitProject(KitProjectInfo info) async {
    if (!isReady || !autorunAvailable) return false;
    final epoch = _epoch;
    try {
      // JSON duplamente codificado é um literal de string válido em Python.
      await _command(
        _repl!,
        'import json; _arca_files.project_set('
        'json.loads(${jsonEncode(jsonEncode(info.toJson()))}))',
      );
      return epoch == _epoch;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível registrar o projeto: $error');
      }
      return false;
    }
  }

  /// Congela o projeto salvo em /app para rodar sempre que a placa ligar.
  Future<bool> enableAutorun() => _changeAutorun(
        '_arca_files.autorun_enable()',
        working: 'Gravando programa de inicialização…',
        done: 'Programa gravado: roda sempre que o kit ligar',
      );

  Future<bool> disableAutorun() => _changeAutorun(
        '_arca_files.autorun_disable()',
        working: 'Desligando programa de inicialização…',
        done: 'O kit não executa mais nada ao ligar',
      );

  Future<bool> _changeAutorun(
    String expression, {
    required String working,
    required String done,
  }) async {
    if (!isReady || !autorunAvailable) return false;
    final epoch = _epoch;
    _set(KitState.uploading, working);
    try {
      // Copiar e conferir o projeto inteiro na flash pode passar de 10 s.
      final status = AutorunStatus.fromJson(
        await _jsonCommand(
          _repl!,
          expression,
          timeout: const Duration(seconds: 60),
        ),
      );
      if (epoch != _epoch) return false;
      autorun = status;
      _set(KitState.ready, done);
      return true;
    } catch (error) {
      if (epoch == _epoch) {
        _set(KitState.ready, 'Não foi possível alterar: $error');
      }
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

  Future<Object?> _jsonCommand(
    RawRepl repl,
    String expression, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final output = StringBuffer();
    final result = await repl.execute(
      "import json; print('ARCA_JSON:' + json.dumps($expression))",
      onOutput: output.write,
      timeout: timeout,
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

  Future<void> runWorkspaceMain() => runCommand(workspaceRunCommand);

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
    autorun = null;
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
