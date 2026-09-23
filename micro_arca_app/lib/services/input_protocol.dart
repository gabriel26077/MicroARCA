const arcaInputMarker = '\x1eARCA_INPUT\x1f';

/// Separa da saída visível o marcador enviado pelo wrapper de `input()`.
///
/// Como um pacote BLE pode terminar no meio do marcador, o sufixo que ainda
/// pode formar o começo dele fica guardado até o próximo trecho.
class InputProtocolDecoder {
  InputProtocolDecoder({
    required this.onOutput,
    required this.onInputRequested,
  });

  final void Function(String) onOutput;
  final void Function() onInputRequested;
  String _pending = '';
  bool _closed = false;

  void add(String chunk) {
    if (_closed) throw StateError('Decodificador já foi encerrado');
    var text = _pending + chunk;
    _pending = '';

    while (text.isNotEmpty) {
      final marker = text.indexOf(arcaInputMarker);
      if (marker >= 0) {
        if (marker > 0) onOutput(text.substring(0, marker));
        onInputRequested();
        text = text.substring(marker + arcaInputMarker.length);
        continue;
      }

      final suffixLength = _markerPrefixSuffixLength(text);
      final visibleLength = text.length - suffixLength;
      if (visibleLength > 0) onOutput(text.substring(0, visibleLength));
      _pending = text.substring(visibleLength);
      return;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_pending.isNotEmpty) onOutput(_pending);
    _pending = '';
  }

  int _markerPrefixSuffixLength(String text) {
    final maximum = text.length < arcaInputMarker.length - 1
        ? text.length
        : arcaInputMarker.length - 1;
    for (var length = maximum; length > 0; length--) {
      if (text.endsWith(arcaInputMarker.substring(0, length))) return length;
    }
    return 0;
  }
}
