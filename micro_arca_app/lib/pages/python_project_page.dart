import 'dart:async';

import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart';
import 'package:highlight/languages/python.dart';

import '../services/micropython_repl_service.dart';
import 'console_page.dart';
import '../services/project_deployer.dart';
import '../services/project_storage.dart';
import '../widgets/kit_project_status.dart';
import '../widgets/python_indent_modifier.dart';

/// Editor de um projeto Python: vários arquivos, com main.py como entrada.
class PythonProjectPage extends StatefulWidget {
  const PythonProjectPage({
    super.key,
    required this.project,
    required this.storage,
  });

  final ArcaProject project;
  final ProjectStorage storage;

  @override
  State<PythonProjectPage> createState() => _PythonProjectPageState();
}

class _PythonProjectPageState extends State<PythonProjectPage> {
  final _service = MicroPythonREPLService();
  late final _deployer = ProjectDeployer(_service);
  late ArcaProject _project = widget.project.files.containsKey('main.py')
      ? widget.project
      : widget.project.copyWith(
          files: {...widget.project.files, 'main.py': ''},
        );
  late String _currentFile = 'main.py';
  late final CodeController _code = CodeController(
    language: python,
    params: const EditorParams(tabSpaces: 4),
    modifiers: const [PythonIndentModifier(), TabModifier()],
    text: _project.files['main.py'],
  );
  Timer? _saveTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_changed);
  }

  void _changed() {
    if (_code.text == _project.files[_currentFile]) return;
    _project = _project.copyWith(
      files: {..._project.files, _currentFile: _code.text},
    );
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
    setState(() {});
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    try {
      await widget.storage.save(_project);
    } catch (_) {
      _dirty = true;
      _showMessage('Não foi possível salvar o projeto no celular.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openFile(String name) {
    if (name == _currentFile) return;
    setState(() => _currentFile = name);
    final text = _project.files[name] ?? '';
    _code.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _replaceFiles(Map<String, String> files, String open) async {
    _project = _project.copyWith(files: files);
    _dirty = true;
    await _save();
    if (!mounted) return;
    _currentFile = '';
    _openFile(open);
  }

  Future<void> _newFile() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FileNameDialog(
        title: 'Novo arquivo',
        existing: _project.files.keys.toSet(),
      ),
    );
    if (name == null || !mounted) return;
    final module = name.substring(0, name.length - 3);
    await _replaceFiles(
      {
        ..._project.files,
        name: '# Módulo $module: importe com "import $module"\n'
      },
      name,
    );
  }

  Future<void> _renameFile() async {
    final old = _currentFile;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FileNameDialog(
        title: 'Renomear $old',
        initial: old,
        existing: _project.files.keys.where((item) => item != old).toSet(),
      ),
    );
    if (name == null || name == old || !mounted) return;
    final files = {..._project.files}..remove(old);
    files[name] = _project.files[old]!;
    await _replaceFiles(files, name);
  }

  Future<void> _deleteFile() async {
    final name = _currentFile;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir $name?'),
        content: const Text('O arquivo sai deste projeto no celular.'),
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
    if (confirmed != true || !mounted) return;
    await _replaceFiles({..._project.files}..remove(name), 'main.py');
  }

  Future<void> _run() async {
    final reason = _deployer.unavailableReason;
    if (reason != null) return _showMessage(reason);
    await _save();
    if (!await _deployer.run(_project, _project.files) && mounted) {
      _showMessage(_service.status);
    }
  }

  Future<void> _install() async {
    final reason = _deployer.unavailableReason ??
        (_service.autorunAvailable
            ? null
            : 'Atualize main.py e arca_files.py na placa, pelo cabo, para gravar.');
    if (reason != null) return _showMessage(reason);
    final confirmed = await confirmInstallOnKit(context, _project.name);
    if (!confirmed || !mounted) return;
    await _save();
    await _deployer.install(_project, _project.files);
    _showMessage(_service.status);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(widget.storage.save(_project));
    _code.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final running = _service.state == KitState.running ||
            _service.state == KitState.waitingForInput ||
            _service.state == KitState.stopping;
        final busy = _service.state == KitState.uploading ||
            _service.state == KitState.managingLibraries;
        return Scaffold(
          appBar: AppBar(
            title: Text(_project.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Console',
                onPressed: () => openConsole(context),
                icon: const Icon(Icons.terminal),
              ),
              PopupMenuButton<String>(
                tooltip: 'Arquivos',
                onSelected: (action) => switch (action) {
                  'new' => _newFile(),
                  'rename' => _renameFile(),
                  'delete' => _deleteFile(),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'new',
                    child: ListTile(
                      leading: Icon(Icons.note_add_outlined),
                      title: Text('Novo arquivo'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    enabled: _currentFile != 'main.py',
                    child: const ListTile(
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Renomear arquivo'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: _currentFile != 'main.py',
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Excluir arquivo'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final name in _project.fileNames)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(name),
                              avatar: name == 'main.py'
                                  ? const Icon(Icons.play_circle_outline)
                                  : null,
                              selected: name == _currentFile,
                              onSelected: (_) => _openFile(name),
                            ),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add),
                          label: const Text('Arquivo'),
                          onPressed: _newFile,
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    LinearProgressIndicator(value: _service.progress)
                  else
                    const SizedBox(height: 4),
                  const SizedBox(height: 4),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SingleChildScrollView(
                          child: CodeTheme(
                            data: CodeThemeData(
                              styles: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? a11yDarkTheme
                                  : a11yLightTheme,
                            ),
                            child: CodeField(
                              controller: _code,
                              textStyle: const TextStyle(
                                fontFamily: 'FiraCode',
                                fontSize: 14,
                              ),
                              wrap: false,
                              minLines: 12,
                              maxLines: null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  KitProjectStatus(project: _project),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      running
                          ? FilledButton.icon(
                              onPressed: _service.state == KitState.stopping
                                  ? null
                                  : _service.stop,
                              icon: const Icon(Icons.stop),
                              label: const Text('Parar'),
                            )
                          : FilledButton.icon(
                              onPressed: _run,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Executar'),
                            ),
                      OutlinedButton.icon(
                        onPressed: running ? null : _install,
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Gravar no kit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FileNameDialog extends StatefulWidget {
  const _FileNameDialog({
    required this.title,
    required this.existing,
    this.initial = '',
  });

  final String title;
  final Set<String> existing;
  final String initial;

  @override
  State<_FileNameDialog> createState() => _FileNameDialogState();
}

class _FileNameDialogState extends State<_FileNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  void _submit() {
    var name = _controller.text.trim();
    if (name.isNotEmpty && !name.toLowerCase().endsWith('.py')) {
      name = '$name.py';
    }
    final lower = name.toLowerCase();
    final error = name.isEmpty
        ? 'Informe um nome.'
        : lower == 'main.py'
            ? 'main.py já é o arquivo principal.'
            : widget.existing.any((item) => item.toLowerCase() == lower)
                ? 'Já existe um arquivo com esse nome.'
                : workspaceFileNameError(name);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(
          labelText: 'Nome do arquivo',
          hintText: 'sensores.py',
          helperText: 'Use letras, números e _.',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}
