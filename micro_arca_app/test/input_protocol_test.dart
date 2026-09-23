import 'package:flutter_test/flutter_test.dart';
import 'package:micro_arca_app/services/input_protocol.dart';

void main() {
  test('remove o marcador e avisa que o programa pediu entrada', () {
    final output = StringBuffer();
    var requests = 0;
    final decoder = InputProtocolDecoder(
      onOutput: output.write,
      onInputRequested: () => requests++,
    );

    decoder.add('digite um número$arcaInputMarker');
    decoder.close();

    expect(output.toString(), 'digite um número');
    expect(requests, 1);
  });

  test('reconhece o marcador em qualquer fronteira de pacote BLE', () {
    for (var split = 0; split <= arcaInputMarker.length; split++) {
      final output = StringBuffer();
      var requests = 0;
      final decoder = InputProtocolDecoder(
        onOutput: output.write,
        onInputRequested: () => requests++,
      );

      const transmission = 'antes$arcaInputMarker depois';
      final boundary = 'antes'.length + split;
      decoder.add(transmission.substring(0, boundary));
      decoder.add(transmission.substring(boundary));
      decoder.close();

      expect(output.toString(), 'antes depois', reason: 'corte $split');
      expect(requests, 1, reason: 'corte $split');
    }
  });

  test('aceita várias solicitações e preserva marcador incompleto no fim', () {
    final output = StringBuffer();
    var requests = 0;
    final decoder = InputProtocolDecoder(
      onOutput: output.write,
      onInputRequested: () => requests++,
    );

    decoder.add('a${arcaInputMarker}b${arcaInputMarker}c\x1eARCA');
    decoder.close();

    expect(output.toString(), 'abc\x1eARCA');
    expect(requests, 2);
  });
}
