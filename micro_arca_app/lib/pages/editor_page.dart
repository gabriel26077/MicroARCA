import 'dart:async';

import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'package:highlight/languages/python.dart';

import '../services/micropython_repl_service.dart';
import '../services/library_storage.dart';
import '../services/program_storage.dart';
import '../widgets/python_indent_modifier.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.storage});

  final ProgramStorage? storage;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _service = MicroPythonREPLService();
  late final CodeController _code;
  late final ProgramStorage _storage;
  String? _uploadedCode;
  String? _uploadedName;
  int? _uploadedSession;
  String? _programName;
  String? _savedCode;
  String? _notice;
  String? _noticeActionLabel;
  VoidCallback? _noticeAction;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? LocalProgramStorage();
    _code = CodeController(
      language: python,
      params: const EditorParams(tabSpaces: 4),
      modifiers: const [PythonIndentModifier(), TabModifier()],
      text: '''from machine import Pin
import time

led = Pin(33, Pin.OUT)
while True:
    print("LED ligado")
    led.on()
    time.sleep(0.5)
    led.off()
    time.sleep(0.5)
''',
    );
    _programName = 'main.py';
    _code.addListener(_changed);
    unawaited(_migrateLegacyLibraries());
  }

  Future<void> _migrateLegacyLibraries() async {
    try {
      final existing = await _storage.loadPrograms();
      final names = existing.map((item) => item.name.toLowerCase()).toSet();
      final legacyStorage = LocalLibraryStorage();
      final legacy = await legacyStorage.loadLibraries();
      for (final library in legacy) {
        if (isValidWorkspaceFileName(library.name)) {
          if (names.add(library.name.toLowerCase())) {
            await _storage.saveProgram(
              SavedProgram(
                name: library.name,
                code: library.code,
                updatedAt: library.updatedAt,
              ),
            );
          }
          await legacyStorage.deleteLibrary(library.name);
        }
      }
    } catch (_) {
      // A migração é oportunista e nunca impede o editor de abrir.
    }
  }

  void _changed() => setState(() {});

  String _normalizedProgramName(String value) {
    final trimmed = value.trim();
    return trimmed.toLowerCase().endsWith('.py') ? trimmed : '$trimmed.py';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeActionLabel = null;
      _noticeAction = null;
    });
  }

  Future<String?> _askProgramName({
    String title = 'Salvar arquivo',
    String actionLabel = 'Salvar',
    String? initialName,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ProgramNameDialog(
        title: title,
        actionLabel: actionLabel,
        initialName: initialName ?? _programName ?? '',
      ),
    );
    return result == null ? null : _normalizedProgramName(result);
  }

  Future<bool> _confirmOverwrite(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Substituir arquivo?'),
            content: Text('Já existe um arquivo chamado $name.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Substituir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveProgram({bool saveAs = false}) async {
    final name = _programName == null || saveAs
        ? await _askProgramName(
            title: saveAs ? 'Salvar como no celular' : 'Salvar no celular',
            initialName: _programName,
          )
        : _programName;
    if (name == null || !mounted) return;
    if (saveAs && name.toLowerCase() == _programName?.toLowerCase()) {
      _showMessage('Escolha um nome diferente para salvar como novo arquivo.');
      return;
    }
    final nameError = workspaceFileNameError(name);
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }

    try {
      final programs = await _storage.loadPrograms();
      final exists = programs.any(
        (program) => program.name.toLowerCase() == name.toLowerCase(),
      );
      final isCurrent = _programName?.toLowerCase() == name.toLowerCase();
      if (exists && !isCurrent && !await _confirmOverwrite(name)) return;

      final code = _code.text;
      await _storage.saveProgram(
        SavedProgram(name: name, code: code, updatedAt: DateTime.now()),
      );
      if (!mounted) return;
      setState(() {
        _programName = name;
        _savedCode = code;
      });
      _showMessage('$name salvo no celular.');
    } catch (_) {
      _showMessage('Não foi possível salvar o programa.');
    }
  }

  Future<bool> _confirmDelete(String name, String location) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir programa?'),
            content: Text('$name será removido $location.'),
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
        ) ??
        false;
  }

  Future<bool> _renameLocalProgram(SavedProgram program) async {
    final newName = await _askProgramName(
      title: 'Renomear no celular',
      actionLabel: 'Renomear',
      initialName: program.name,
    );
    if (newName == null || !mounted) return false;
    if (newName.toLowerCase() == program.name.toLowerCase()) {
      _showMessage('Escolha um nome diferente.');
      return false;
    }
    final programs = await _storage.loadPrograms();
    final exists = programs.any(
      (item) => item.name.toLowerCase() == newName.toLowerCase(),
    );
    if (exists && !await _confirmOverwrite(newName)) return false;
    await _storage.saveProgram(
      SavedProgram(
        name: newName,
        code: program.code,
        updatedAt: DateTime.now(),
      ),
    );
    await _storage.deleteProgram(program.name);
    if (!mounted) return false;
    if (_programName?.toLowerCase() == program.name.toLowerCase()) {
      setState(() {
        _programName = newName;
        _savedCode = program.code;
        _uploadedName = null;
        _uploadedCode = null;
        _uploadedSession = null;
      });
    }
    _showMessage('${program.name} renomeado para $newName no celular.');
    return true;
  }

  Future<bool> _renameDeviceProgram(WorkspaceFile file) async {
    final newName = await _askProgramName(
      title: 'Renomear no ESP32',
      actionLabel: 'Renomear',
      initialName: file.name,
    );
    if (newName == null || !mounted) return false;
    if (newName.toLowerCase() == file.name.toLowerCase()) {
      _showMessage('Escolha um nome diferente.');
      return false;
    }
    final success = await _service.renameWorkspaceFile(file.name, newName);
    if (!mounted || !success) {
      if (mounted) _showMessage(_service.status);
      return false;
    }
    if (_programName?.toLowerCase() == file.name.toLowerCase()) {
      setState(() {
        _programName = newName;
        _savedCode = null;
        _uploadedName = newName;
      });
    }
    _showMessage(_service.status);
    return true;
  }

  Future<SavedProgram?> _chooseLocalProgram(
    List<SavedProgram> initialPrograms,
  ) {
    var programs = initialPrograms;
    return showDialog<SavedProgram>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Arquivos no celular'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: programs.isEmpty
                ? const Center(child: Text('Nenhum arquivo salvo no celular'))
                : ListView(
                    children: [
                      for (final program in programs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined),
                          title: Text(program.name),
                          subtitle: Text(
                            '${'\n'.allMatches(program.code).length + 1} linhas',
                          ),
                          onTap: () => Navigator.pop(dialogContext, program),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Ações de ${program.name}',
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  leading:
                                      Icon(Icons.drive_file_rename_outline),
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
                            onSelected: (action) async {
                              if (action == 'rename') {
                                if (!await _renameLocalProgram(program)) return;
                              } else {
                                if (!await _confirmDelete(
                                  program.name,
                                  'do celular',
                                )) {
                                  return;
                                }
                                await _storage.deleteProgram(program.name);
                              }
                              programs = await _storage.loadPrograms();
                              if (!dialogContext.mounted) return;
                              setDialogState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<WorkspaceFile?> _chooseDeviceFile(
    List<WorkspaceFile> initialFiles,
  ) {
    var files = initialFiles;
    return showDialog<WorkspaceFile>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Arquivos no ESP32'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(
              children: [
                for (final file in files)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      file.name.toLowerCase() == 'main.py'
                          ? Icons.play_circle_outline
                          : Icons.description_outlined,
                    ),
                    title: Text(file.name),
                    subtitle: Text('/app/${file.name} • ${file.size} bytes'),
                    onTap: () => Navigator.pop(dialogContext, file),
                    trailing: file.name.toLowerCase() == 'main.py'
                        ? const Tooltip(
                            message: 'Entrypoint do projeto',
                            child: Icon(Icons.lock_outline),
                          )
                        : PopupMenuButton<String>(
                            tooltip: 'Ações de ${file.name}',
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  leading:
                                      Icon(Icons.drive_file_rename_outline),
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
                            onSelected: (action) async {
                              if (action == 'rename') {
                                if (!await _renameDeviceProgram(file)) return;
                              } else {
                                if (!await _confirmDelete(
                                  file.name,
                                  'do ESP32',
                                )) {
                                  return;
                                }
                                if (!await _service
                                    .deleteWorkspaceFile(file.name)) {
                                  return;
                                }
                              }
                              files = await _service.listWorkspaceFiles();
                              if (!dialogContext.mounted) return;
                              setDialogState(() {});
                            },
                          ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLocalProgram() async {
    try {
      final programs = await _storage.loadPrograms();
      if (!mounted) return;
      final selected = await _chooseLocalProgram(programs);
      if (selected == null || !mounted) return;
      _code.value = TextEditingValue(
        text: selected.code,
        selection: TextSelection.collapsed(offset: selected.code.length),
      );
      setState(() {
        _programName = selected.name;
        _savedCode = selected.code;
        _uploadedName = null;
        _uploadedCode = null;
        _uploadedSession = null;
      });
      _showMessage('${selected.name} carregado.');
    } catch (_) {
      _showMessage('Não foi possível abrir os arquivos do celular.');
    }
  }

  Future<void> _openDeviceProgram() async {
    if (!_service.isReady || !_service.workspaceManagerAvailable) return;
    try {
      final files = await _service.listWorkspaceFiles();
      if (!mounted) return;
      final selected = await _chooseDeviceFile(files);
      if (selected == null || !mounted) return;
      final content = await _service.readWorkspaceFile(selected);
      if (content == null || !mounted) return;
      _code.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
      setState(() {
        _programName = selected.name;
        _savedCode = null;
        _uploadedName = selected.name;
        _uploadedCode = content;
        _uploadedSession = _service.sessionId;
      });
      _showMessage('${selected.name} aberto do ESP32.');
    } catch (_) {
      _showMessage('Não foi possível abrir os arquivos do ESP32.');
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final savedSomewhere = _savedCode == _code.text ||
        (_uploadedName == _programName &&
            _uploadedCode == _code.text &&
            _uploadedSession == _service.sessionId);
    if (_code.text.isEmpty || savedSomewhere) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Criar novo arquivo?'),
            content: const Text(
              'O código atual possui alterações que ainda não foram salvas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Descartar e criar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _newFile() async {
    if (!await _confirmDiscardChanges() || !mounted) return;
    _code.value = const TextEditingValue();
    setState(() {
      _programName = null;
      _savedCode = null;
      _uploadedName = null;
      _uploadedCode = null;
      _uploadedSession = null;
      _notice = null;
      _noticeActionLabel = null;
      _noticeAction = null;
    });
  }

  Future<void> _send({bool saveAs = false}) async {
    var name = _programName;
    if (name == null || saveAs) {
      name = await _askProgramName(
        title: saveAs ? 'Salvar como no ESP32' : 'Salvar no ESP32',
        initialName: _programName,
      );
      if (name == null || !mounted) return;
    }
    if (saveAs && name.toLowerCase() == _programName?.toLowerCase()) {
      _showMessage('Escolha um nome diferente para salvar como novo arquivo.');
      return;
    }
    if (saveAs) {
      final files = await _service.listWorkspaceFiles();
      if (!mounted) return;
      final exists = files.any(
        (file) => file.name.toLowerCase() == name!.toLowerCase(),
      );
      if (exists && !await _confirmOverwrite(name)) return;
    }
    final content = _code.text;
    final session = _service.sessionId;
    final success = await _service.saveWorkspaceFile(name, content);
    if (mounted && success) {
      setState(() {
        _programName = name;
        if (saveAs) _savedCode = null;
        _uploadedName = name;
        _uploadedCode = content;
        _uploadedSession = session;
      });
    }
  }

  Future<void> _runProject() async {
    final uploaded = _uploadedName == _programName &&
        _uploadedCode == _code.text &&
        _uploadedSession == _service.sessionId;
    if (!uploaded) {
      await _send();
      if (!mounted ||
          _uploadedName != _programName ||
          _uploadedCode != _code.text ||
          _uploadedSession != _service.sessionId) {
        return;
      }
    }
    await _service.runWorkspaceMain();
  }

  @override
  void dispose() {
    _code.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final uploaded = _uploadedName == _programName &&
            _uploadedCode == _code.text &&
            _uploadedSession == _service.sessionId;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _service.status,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_notice != null)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline),
                    title: Text(_notice!),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        if (_noticeAction != null)
                          TextButton(
                            onPressed: _noticeAction,
                            child: Text(_noticeActionLabel!),
                          ),
                        IconButton(
                          tooltip: 'Fechar aviso',
                          onPressed: () {
                            setState(() {
                              _notice = null;
                              _noticeActionLabel = null;
                              _noticeAction = null;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_service.state == KitState.uploading ||
                  _service.state == KitState.managingLibraries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: _service.progress),
                ),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Tooltip(
                          message: 'Arquivos do celular',
                          child: Icon(Icons.phone_android_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Abrir arquivo do celular',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: _openLocalProgram,
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                        IconButton(
                          tooltip: 'Salvar arquivo no celular',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: _saveProgram,
                          icon: const Icon(Icons.save_outlined),
                        ),
                        IconButton(
                          tooltip: 'Salvar como no celular',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: () => _saveProgram(saveAs: true),
                          icon: const Icon(Icons.drive_file_rename_outline),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Novo arquivo em branco',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 40,
                    ),
                    padding: const EdgeInsets.all(6),
                    onPressed: _newFile,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: 'Arquivos do ESP32',
                          child: Icon(
                            Icons.developer_board_outlined,
                            size: 20,
                            color: _service.isConnected ? null : Colors.grey,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Abrir arquivo do ESP32',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: _service.isReady &&
                                  _service.workspaceManagerAvailable
                              ? _openDeviceProgram
                              : null,
                          icon: const Icon(Icons.folder_open_outlined),
                        ),
                        IconButton(
                          tooltip: 'Salvar arquivo no ESP32',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: _service.isReady &&
                                  _service.workspaceManagerAvailable
                              ? _send
                              : null,
                          icon: const Icon(Icons.save_outlined),
                        ),
                        IconButton(
                          tooltip: 'Salvar como no ESP32',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 40,
                          ),
                          padding: const EdgeInsets.all(6),
                          onPressed: _service.isReady &&
                                  _service.workspaceManagerAvailable
                              ? () => _send(saveAs: true)
                              : null,
                          icon: const Icon(Icons.drive_file_rename_outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                '${_programName ?? 'Novo arquivo'}'
                '${_savedCode == _code.text ? '' : ' • não salvo no celular'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      child: CodeTheme(
                        data: const CodeThemeData(styles: a11yLightTheme),
                        child: CodeField(
                          controller: _code,
                          textStyle: const TextStyle(
                            fontFamily: 'FiraCode',
                            fontSize: 14,
                          ),
                          wrap: true,
                          minLines: 12,
                          maxLines: null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                uploaded
                    ? '${_programName ?? 'Arquivo'} sincronizado com /app.'
                    : 'Executar salva o arquivo atual e inicia main.py.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _service.isReady &&
                            _service.workspaceManagerAvailable &&
                            _programName != null
                        ? _runProject
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Executar'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _service.state == KitState.running ||
                            _service.state == KitState.waitingForInput
                        ? _service.stop
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Parar'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramNameDialog extends StatefulWidget {
  const _ProgramNameDialog({
    required this.title,
    required this.actionLabel,
    required this.initialName,
  });

  final String title;
  final String actionLabel;
  final String initialName;

  @override
  State<_ProgramNameDialog> createState() => _ProgramNameDialogState();
}

class _ProgramNameDialogState extends State<_ProgramNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  void _submit() {
    var name = _controller.text.trim();
    if (name.isNotEmpty && !name.toLowerCase().endsWith('.py')) {
      name = '$name.py';
    }
    final error =
        name.isEmpty ? 'Informe um nome.' : workspaceFileNameError(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
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
          hintText: 'exemplo.py',
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
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
