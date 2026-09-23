import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/a11y-light.dart';
import 'package:highlight/languages/python.dart';

import '../services/library_storage.dart';
import '../services/micropython_repl_service.dart';
import '../services/program_storage.dart';
import '../widgets/python_indent_modifier.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.storage, this.libraryStorage});

  final ProgramStorage? storage;
  final LibraryStorage? libraryStorage;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _service = MicroPythonREPLService();
  late final CodeController _code;
  late final ProgramStorage _storage;
  late final LibraryStorage _libraryStorage;
  String? _uploadedCode;
  int? _uploadedSession;
  String? _programName;
  String? _savedCode;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? LocalProgramStorage();
    _libraryStorage = widget.libraryStorage ?? LocalLibraryStorage();
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
    _code.addListener(_changed);
  }

  void _changed() => setState(() {});

  String _normalizedProgramName(String value) {
    final trimmed = value.trim();
    return trimmed.toLowerCase().endsWith('.py') ? trimmed : '$trimmed.py';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askProgramName() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ProgramNameDialog(initialName: _programName ?? ''),
    );
    return result == null ? null : _normalizedProgramName(result);
  }

  Future<bool> _confirmOverwrite(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Substituir programa?'),
            content: Text('Já existe um programa chamado $name.'),
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

  Future<void> _saveProgram() async {
    final name = await _askProgramName();
    if (name == null || !mounted) return;

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

  Future<void> _saveAsLibrary() async {
    final suggestedName =
        _programName != null && isValidLibraryName(_programName!)
            ? _programName!
            : '';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _LibraryNameDialog(initialName: suggestedName),
    );
    if (name == null || !mounted) return;

    final library = SavedLibrary(
      name: name,
      code: _code.text,
      updatedAt: DateTime.now(),
    );
    if (library.byteLength > 65536) {
      _showMessage('A biblioteca deve ter no máximo 64 KiB.');
      return;
    }

    try {
      final libraries = await _libraryStorage.loadLibraries();
      final exists = libraries.any(
        (item) => item.name.toLowerCase() == name.toLowerCase(),
      );
      if (exists && !await _confirmLibraryOverwrite(name)) return;
      await _libraryStorage.saveLibrary(library);
      if (!mounted) return;
      final canInstall = _service.isReady && _service.libraryManagerAvailable;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$name salva como biblioteca.'),
            action: canInstall
                ? SnackBarAction(
                    label: 'Instalar',
                    onPressed: () => _installSavedLibrary(library),
                  )
                : null,
          ),
        );
    } catch (_) {
      _showMessage('Não foi possível salvar a biblioteca.');
    }
  }

  Future<bool> _confirmLibraryOverwrite(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Substituir biblioteca?'),
            content: Text('Já existe uma biblioteca chamada $name.'),
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

  Future<void> _installSavedLibrary(SavedLibrary library) async {
    await _service.installLibrary(library.name, library.code);
    if (mounted) _showMessage(_service.status);
  }

  Future<bool> _confirmDelete(String name) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir programa?'),
            content: Text('$name será removido do celular.'),
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

  Future<SavedProgram?> _chooseProgram(List<SavedProgram> initialPrograms) {
    var programs = initialPrograms;
    return showDialog<SavedProgram>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Programas salvos'),
          content: SizedBox(
            width: double.maxFinite,
            child: programs.isEmpty
                ? const Text('Nenhum programa salvo.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: programs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final program = programs[index];
                      final lineCount =
                          '\n'.allMatches(program.code).length + 1;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          program.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('$lineCount linhas'),
                        onTap: () => Navigator.pop(dialogContext, program),
                        trailing: IconButton(
                          tooltip: 'Excluir ${program.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (!await _confirmDelete(program.name)) return;
                            try {
                              await _storage.deleteProgram(program.name);
                              if (!mounted) return;
                              if (_programName?.toLowerCase() ==
                                  program.name.toLowerCase()) {
                                setState(() {
                                  _programName = null;
                                  _savedCode = null;
                                });
                              }
                              programs = await _storage.loadPrograms();
                              if (!dialogContext.mounted) return;
                              setDialogState(() {});
                            } catch (_) {
                              _showMessage(
                                'Não foi possível excluir o programa.',
                              );
                            }
                          },
                        ),
                      );
                    },
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

  Future<void> _openProgram() async {
    try {
      final programs = await _storage.loadPrograms();
      if (!mounted) return;
      if (programs.isEmpty) {
        _showMessage('Nenhum programa salvo no celular.');
        return;
      }
      final selected = await _chooseProgram(programs);
      if (selected == null || !mounted) return;
      _code.value = TextEditingValue(
        text: selected.code,
        selection: TextSelection.collapsed(offset: selected.code.length),
      );
      setState(() {
        _programName = selected.name;
        _savedCode = selected.code;
      });
      _showMessage('${selected.name} carregado.');
    } catch (_) {
      _showMessage('Não foi possível carregar os programas.');
    }
  }

  Future<void> _send() async {
    final content = _code.text;
    final session = _service.sessionId;
    final success = await _service.uploadFile(content);
    if (mounted && success) {
      setState(() {
        _uploadedCode = content;
        _uploadedSession = session;
      });
    }
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
        final uploaded = _uploadedCode == _code.text &&
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
              if (_service.state == KitState.uploading ||
                  _service.state == KitState.managingLibraries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: _service.progress),
                ),
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_programName ?? 'Novo programa'}'
                      '${_savedCode == _code.text ? '' : ' • não salvo'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Abrir programa salvo',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openProgram,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                  IconButton(
                    tooltip: 'Salvar programa no celular',
                    visualDensity: VisualDensity.compact,
                    onPressed: _code.text.trim().isEmpty ? null : _saveProgram,
                    icon: const Icon(Icons.save_outlined),
                  ),
                  IconButton(
                    tooltip: 'Salvar código como biblioteca',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        _code.text.trim().isEmpty ? null : _saveAsLibrary,
                    icon: const Icon(Icons.local_library_outlined),
                  ),
                ],
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
                    ? 'Este código foi enviado ao kit.'
                    : 'Envie o código antes de executar.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _service.isReady && _code.text.trim().isNotEmpty
                        ? _send
                        : null,
                    icon: const Icon(Icons.upload),
                    label: const Text('Enviar'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _service.isReady && uploaded ? _service.runFile : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Executar'),
                  ),
                  OutlinedButton.icon(
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
  const _ProgramNameDialog({required this.initialName});

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
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = 'Informe um nome.');
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Salvar programa'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(
          labelText: 'Nome do programa',
          hintText: 'exemplo.py',
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

class _LibraryNameDialog extends StatefulWidget {
  const _LibraryNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_LibraryNameDialog> createState() => _LibraryNameDialogState();
}

class _LibraryNameDialogState extends State<_LibraryNameDialog> {
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
    final error = name.isEmpty ? 'Informe um nome.' : libraryNameError(name);
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
      title: const Text('Salvar como biblioteca'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(
          labelText: 'Nome do módulo',
          hintText: 'minha_biblioteca.py',
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
