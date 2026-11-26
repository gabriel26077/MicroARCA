import 'package:flutter/material.dart';

import '../services/micropython_repl_service.dart';
import '../services/project_storage.dart';
import '../widgets/kit_project_status.dart';
import 'blocks_page.dart';
import 'python_project_page.dart';

/// Lista única de projetos; cada um abre no editor do seu tipo.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, this.storage});

  final ProjectStorage? storage;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late final ProjectStorage _storage = widget.storage ?? LocalProjectStorage();
  final _service = MicroPythonREPLService();
  List<ProjectSummary>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await _storage.list();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível ler os projetos.');
    }
  }

  Route<void> _routeFor(ArcaProject project) => MaterialPageRoute<void>(
        builder: (_) => switch (project.kind) {
          ProjectKind.blocks => BlocksPage(
              project: project,
              projectStorage: _storage,
              onOpenProject: _replaceWith,
            ),
          ProjectKind.python => PythonProjectPage(
              project: project,
              storage: _storage,
            ),
        },
      );

  void _replaceWith(ArcaProject project) {
    Navigator.of(context)
        .pushReplacement(_routeFor(project))
        .then((_) => _load());
  }

  Future<void> _open(ProjectSummary summary) async {
    final project = await _storage.load(summary.id);
    if (!mounted) return;
    if (project == null) {
      await _load();
      return;
    }
    await Navigator.of(context).push(_routeFor(project));
    await _load();
  }

  Future<void> _create() async {
    final created = await showDialog<ArcaProject>(
      context: context,
      builder: (_) => const _NewProjectDialog(),
    );
    if (created == null || !mounted) return;
    try {
      await _storage.save(created);
    } catch (_) {
      _showMessage('Não foi possível criar o projeto.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(_routeFor(created));
    await _load();
  }

  Future<void> _rename(ProjectSummary summary) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ProjectNameDialog(initial: summary.name),
    );
    if (name == null || name == summary.name) return;
    final project = await _storage.load(summary.id);
    if (project == null) return;
    await _storage.save(project.renamed(name));
    await _load();
  }

  Future<void> _delete(ProjectSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir "${summary.name}"?'),
        content: const Text(
          'O projeto sai do celular. O que já foi gravado no kit continua lá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.delete(summary.id);
    await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Meus projetos',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Novo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!)
          else if (projects == null)
            const Center(child: CircularProgressIndicator())
          else if (projects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Nenhum projeto ainda. Toque em Novo e escolha entre blocos '
                'e Python.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final project in projects)
              _ProjectTile(
                project: project,
                relation: kitProjectRelation(_service, project),
                onTap: () => _open(project),
                onRename: () => _rename(project),
                onDelete: () => _delete(project),
              ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.relation,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ProjectSummary project;
  final KitProjectRelation relation;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final blocks = project.kind == ProjectKind.blocks;
    final kit = switch (relation) {
      KitProjectRelation.current => ' • ⚡ gravado no kit',
      KitProjectRelation.currentOutdated => ' • ⚡ no kit, com alterações',
      _ => '',
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              blocks ? const Color(0xffd06b22) : const Color(0xff1565c0),
          foregroundColor: Colors.white,
          child: Icon(blocks ? Icons.extension_outlined : Icons.code),
        ),
        title: Text(project.name),
        subtitle: Text(
          '${project.kind.label} • ${_formatDate(project.updatedAt)}$kit',
        ),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          tooltip: 'Ações de ${project.name}',
          onSelected: (action) => action == 'rename' ? onRename() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('Renomear'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Excluir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _controller = TextEditingController();
  ProjectKind _kind = ProjectKind.blocks;
  String? _error;

  void _submit() {
    final error = projectNameError(_controller.text);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, ArcaProject.create(_controller.text, _kind));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo projeto'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxProjectNameLength,
            decoration: InputDecoration(
              labelText: 'Nome',
              hintText: 'Semáforo',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ProjectKind>(
            segments: const [
              ButtonSegment(
                value: ProjectKind.blocks,
                icon: Icon(Icons.extension_outlined),
                label: Text('Blocos'),
              ),
              ButtonSegment(
                value: ProjectKind.python,
                icon: Icon(Icons.code),
                label: Text('Python'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (kinds) => setState(() => _kind = kinds.single),
          ),
          const SizedBox(height: 8),
          Text(
            'O tipo não muda depois. Um projeto de blocos pode ser convertido '
            'em um novo projeto Python.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Criar')),
      ],
    );
  }
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({required this.initial});

  final String initial;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  void _submit() {
    final error = projectNameError(_controller.text);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renomear projeto'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxProjectNameLength,
        decoration: InputDecoration(labelText: 'Nome', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Renomear')),
      ],
    );
  }
}
