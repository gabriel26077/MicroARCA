import 'dart:async';
import 'dart:math';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'raw_repl.dart';

final arcaServiceId = Uuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final arcaRxId = Uuid.parse('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
final arcaTxId = Uuid.parse('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
final arcaControlId = Uuid.parse('6e400004-b5a3-f393-e0a9-e50e24dcca9e');

class BleTransport implements ReplTransport {
  BleTransport(this.ble, this.deviceId, {required this.onFailure});
  final FlutterReactiveBle ble;
  final String deviceId;
  final void Function(Object) onFailure;
  final _input = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;
  Future<void> _writes = Future<void>.value();
  bool _closed = false;
  int _packetSize = 20;

  @override
  Stream<List<int>> get input => _input.stream;

  QualifiedCharacteristic _characteristic(Uuid id) => QualifiedCharacteristic(
      serviceId: arcaServiceId, characteristicId: id, deviceId: deviceId);

  void subscribe() {
    _subscription =
        ble.subscribeToCharacteristic(_characteristic(arcaTxId)).listen(
      (bytes) {
        if (!_closed) _input.add(bytes);
      },
      onError: (Object error) {
        if (!_closed) {
          _input.addError(error);
          onFailure(error);
        }
      },
      onDone: () {
        if (!_closed) {
          unawaited(_input.close());
          onFailure(StateError('Canal de saída Bluetooth encerrado'));
        }
      },
    );
  }

  Future<void> control(int byte) => _queue(arcaControlId, [byte]);

  Future<void> negotiateMtu() async {
    try {
      final mtu = await ble
          .requestMtu(deviceId: deviceId, mtu: 247)
          .timeout(const Duration(seconds: 3));
      _packetSize = max(20, min(128, mtu - 3));
    } on Exception {
      // Continua válido com MTU 23. Não pressupõe que a negociação funcionou.
      _packetSize = 20;
    }
  }

  @override
  Future<void> write(List<int> bytes) => _queue(arcaRxId, List<int>.of(bytes));

  Future<void> _queue(Uuid id, List<int> bytes) {
    final task = _writes.then((_) async {
      for (var offset = 0; offset < bytes.length; offset += _packetSize) {
        if (_closed) throw StateError('Transporte encerrado');
        await ble
            .writeCharacteristicWithResponse(_characteristic(id),
                value: bytes.sublist(
                    offset, min(offset + _packetSize, bytes.length)))
            .timeout(const Duration(seconds: 5));
      }
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    unawaited(_input.close());
  }
}
