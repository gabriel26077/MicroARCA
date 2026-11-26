import 'package:flutter/services.dart';

enum KitDiscoveryMode { companion, legacy }

class AssociatedKit {
  const AssociatedKit({required this.id, required this.name});

  factory AssociatedKit.fromMap(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        !RegExp(r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
            .hasMatch(value['id'] as String) ||
        value['name'] is! String) {
      throw const FormatException('O Android retornou um kit inválido.');
    }
    final name = (value['name'] as String).trim();
    return AssociatedKit(
      id: (value['id'] as String).toUpperCase(),
      name: name.isEmpty ? 'Kit ARCA' : name,
    );
  }

  final String id;
  final String name;
}

/// O Android decide o modo; falhas do CDM não autorizam scan direto.
class CompanionDevices {
  static const channel = MethodChannel('arca/companion_devices');

  Future<KitDiscoveryMode> mode() async =>
      switch (await channel.invokeMethod<String>('mode')) {
        'companion' => KitDiscoveryMode.companion,
        'legacy' => KitDiscoveryMode.legacy,
        _ => throw PlatformException(
            code: 'companion_unavailable',
            message:
                'Este aparelho não oferece a seleção de kits pelo Android.',
          ),
      };

  Future<AssociatedKit?> select() async {
    final result = await channel.invokeMethod<Object?>('select');
    return result == null ? null : AssociatedKit.fromMap(result);
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');

  Future<String?> adapterState() =>
      channel.invokeMethod<String>('adapterState');

  Future<bool> requestEnable() async =>
      await channel.invokeMethod<bool>('requestEnable') ?? false;

  Future<bool> isAssociated(String id) async =>
      await channel.invokeMethod<bool>('isAssociated', {'id': id}) ?? false;

  Future<List<AssociatedKit>> list() async {
    final values = await channel.invokeListMethod<Object?>('list') ?? [];
    return values.map(AssociatedKit.fromMap).toList(growable: false);
  }

  Future<void> forget(String id) =>
      channel.invokeMethod<void>('forget', {'id': id});
}
