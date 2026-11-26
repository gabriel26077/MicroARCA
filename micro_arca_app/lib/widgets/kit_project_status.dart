import 'package:flutter/material.dart';

import '../services/micropython_repl_service.dart';
import '../services/project_storage.dart';

/// Relação entre o projeto aberto e o que o kit executa ao ligar.
enum KitProjectRelation { unknown, none, current, currentOutdated, other }

KitProjectRelation kitProjectRelation(
  MicroPythonREPLService service,
  ProjectSummary project,
) {
  final autorun = service.autorun;
  if (!service.isConnected || !service.autorunAvailable || autorun == null) {
    return KitProjectRelation.unknown;
  }
  if (!autorun.active) return KitProjectRelation.none;
  final installed = autorun.project;
  if (installed == null || installed.id != project.id) {
    return KitProjectRelation.other;
  }
  return installed.revision == project.revision
      ? KitProjectRelation.current
      : KitProjectRelation.currentOutdated;
}

class KitProjectStatus extends StatelessWidget {
  const KitProjectStatus({super.key, required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final service = MicroPythonREPLService();
    final theme = Theme.of(context);
    final installed = service.autorun?.project;
    final (icon, text) = switch (kitProjectRelation(service, project)) {
      KitProjectRelation.unknown => (
          Icons.developer_board_off_outlined,
          service.isConnected
              ? 'Executar envia o projeto ao kit e roda agora.'
              : 'Conecte o kit pelo botão Bluetooth da tela inicial.',
        ),
      KitProjectRelation.none => (
          Icons.power_settings_new,
          'O kit não executa nada ao ligar.',
        ),
      KitProjectRelation.current => (
          Icons.bolt,
          'Gravado no kit: roda sempre que ele ligar.',
        ),
      KitProjectRelation.currentOutdated => (
          Icons.bolt,
          'Gravado no kit, mas há alterações não gravadas.',
        ),
      KitProjectRelation.other => (
          Icons.power_settings_new,
          installed == null
              ? 'O kit roda outro programa ao ligar.'
              : 'Ao ligar, o kit roda "${installed.name}".',
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

Future<bool> confirmInstallOnKit(BuildContext context, String name) async {
  final service = MicroPythonREPLService();
  final current = service.autorun;
  final replaces = current != null &&
      current.active &&
      current.project != null &&
      current.project!.name != name;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Gravar no kit?'),
          content: Text(
            '"$name" vai rodar sempre que o kit ligar, mesmo sem o celular. '
            'Edições futuras só valem depois de gravar de novo.'
            '${replaces ? '\n\nSubstitui "${current.project!.name}".' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Gravar'),
            ),
          ],
        ),
      ) ??
      false;
}
