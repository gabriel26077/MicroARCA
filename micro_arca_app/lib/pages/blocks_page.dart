import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/block_project_storage.dart';
import '../services/library_block_manifest.dart';
import '../services/library_catalog_client.dart';
import '../services/micropython_repl_service.dart';
import '../services/package_installation_storage.dart';
import '../services/project_deployer.dart';
import '../services/project_storage.dart';
import '../widgets/kit_project_status.dart';
import 'console_page.dart';

const _variableBlockTypes = {
  'variables_set_dynamic',
  'variables_get_dynamic',
  'microarca_variable_change',
};

const _pythonKeywords = {
  'False',
  'None',
  'True',
  'and',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'class',
  'continue',
  'def',
  'del',
  'elif',
  'else',
  'except',
  'finally',
  'for',
  'from',
  'global',
  'if',
  'import',
  'in',
  'is',
  'lambda',
  'nonlocal',
  'not',
  'or',
  'pass',
  'raise',
  'return',
  'try',
  'while',
  'with',
  'yield',
};

class BlocksPage extends StatefulWidget {
  const BlocksPage({
    super.key,
    required this.project,
    required this.projectStorage,
    this.onOpenProject,
    this.catalogRepository,
    this.packageStorage,
  });

  final ProjectSummary project;
  final ProjectStorage projectStorage;

  /// Abre outro projeto no lugar deste (usado ao converter para Python).
  final ValueChanged<ArcaProject>? onOpenProject;
  final LibraryCatalogRepository? catalogRepository;
  final PackageInstallationStorage? packageStorage;

  @override
  State<BlocksPage> createState() => _BlocksPageState();
}

enum _BlockAction {
  copy,
  duplicate,
  duplicateChain,
  delete,
  deleteChain,
  toggleDisabled,
}

class _BlocksPageState extends State<BlocksPage> {
  final MicroPythonREPLService _service = MicroPythonREPLService();
  late final BlockProjectStorage _storage =
      ProjectBlockStorage(widget.projectStorage, widget.project.id);
  late final _deployer = ProjectDeployer(_service);
  late final LibraryCatalogRepository _catalogRepository =
      widget.catalogRepository ?? LibraryCatalogClient();
  late final PackageInstallationStorage _packageStorage =
      widget.packageStorage ?? LocalPackageInstallationStorage();
  WebViewController? _controller;
  Timer? _saveTimer;
  Completer<void>? _stateRefresh;
  String? _stateRefreshId;
  int _stateRefreshSerial = 0;
  String? _savedWorkspace;
  late ProjectSummary _project = widget.project;
  String _python = '';
  List<String> _requirements = const [];
  List<BlockVariable> _variables = const [];
  List<LibraryBlockManifest> _libraryManifests = const [];
  String? _notice;
  String? _libraryWarning;
  bool _initializing = false;
  bool _blockActionsOpen = false;
  bool _variableShortcutsOpen = false;

  // Bloco copiado. Estático para poder colar em outro projeto enquanto o app
  // está aberto; some quando o usuário toca no X.
  static String? _clipboard;
  static String? _clipboardLabel;

  // Biblioteca do sexto atalho; também vale entre projetos.
  static String? _lastLibraryPackage;
  final Set<String> _expandedBlockSections = {};

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_controller != null || _initializing) return;
    _initializing = true;
    try {
      try {
        _savedWorkspace = await _storage.loadWorkspace();
      } catch (_) {
        _notice = 'O projeto salvo estava inválido. Um novo blink será criado.';
      }
      try {
        _libraryManifests = await _catalogRepository.cachedBlockManifests();
      } catch (_) {
        _libraryWarning =
            'Blocos de bibliotecas indisponíveis. Abra Bibliotecas para baixar novamente.';
      }
      if (!mounted) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xfff4fafb))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final localAsset = request.url.startsWith(
                'file:///android_asset/flutter_assets/assets/blockly/',
              );
              return localAsset || request.url == 'about:blank'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
          ),
        )
        ..addJavaScriptChannel(
          'MicroArcaBlocks',
          onMessageReceived: (message) =>
              unawaited(_handleBridgeMessage(message.message)),
        );
      setState(() => _controller = controller);
      await controller.loadFlutterAsset('assets/blockly/index.html');
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Não foi possível abrir os blocos: $error');
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _handleBridgeMessage(String message) async {
    try {
      final envelope = jsonDecode(message);
      if (envelope is! Map || envelope['type'] is! String) {
        throw const FormatException('Mensagem inválida.');
      }
      switch (envelope['type']) {
        case 'ready':
          await _controller?.runJavaScript(
            'window.microArca.registerLibraryManifests('
            '${jsonEncode(_libraryManifests.map((item) => item.toBridgeJson()).toList())}'
            ');',
          );
          final encoded = _savedWorkspace;
          if (encoded == null) {
            await _controller?.runJavaScript(
              'window.microArca.createDefault();',
            );
          } else {
            await _controller?.runJavaScript(
              'window.microArca.loadWorkspace(${jsonEncode(encoded)});',
            );
          }
          return;
        case 'error':
          final detail = envelope['message'];
          if (mounted) {
            setState(() {
              _notice = detail is String
                  ? 'Erro nos blocos: $detail'
                  : 'Erro no editor de blocos.';
            });
          }
          return;
        case 'prompt':
          final id = envelope['id'];
          if (id is! String || !RegExp(r'^prompt-\d{1,9}$').hasMatch(id)) {
            throw const FormatException('Pedido inválido.');
          }
          final message = envelope['message'];
          final defaultValue = envelope['defaultValue'];
          final value = mounted
              ? await showDialog<String>(
                  context: context,
                  builder: (_) => _FieldValueDialog(
                    title: message is String && message.isNotEmpty
                        ? message
                        : 'Mudar valor',
                    initialValue: defaultValue is String ? defaultValue : '',
                    numeric: envelope['numeric'] == true,
                  ),
                )
              : null;
          await _controller?.runJavaScript(
            'window.microArca.resolvePrompt('
            '${jsonEncode(id)}, ${jsonEncode(value)});',
          );
          return;
        case 'blockActions':
          final blockId = _bridgeBlockId(envelope);
          if (_blockActionsOpen || !mounted) return;
          final rawLength = envelope['chainLength'];
          final chainLength = rawLength is int && rawLength > 0 ? rawLength : 1;
          final disabled = envelope['disabled'] == true;
          final below = chainLength - 1;
          final danger = Theme.of(context).colorScheme.error;
          _blockActionsOpen = true;
          final action = await showModalBottomSheet<_BlockAction>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) {
              ListTile option(
                _BlockAction value,
                IconData icon,
                String title,
                String subtitle, {
                Color? color,
              }) =>
                  ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(title, style: TextStyle(color: color)),
                    subtitle: Text(subtitle),
                    onTap: () => Navigator.pop(sheetContext, value),
                  );
              return SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      option(
                        _BlockAction.copy,
                        Icons.copy,
                        'Copiar',
                        'Guarda o bloco para colar quantas vezes quiser.',
                      ),
                      option(
                        _BlockAction.duplicate,
                        Icons.control_point_duplicate,
                        'Duplicar bloco',
                        'Cria uma cópia só deste bloco.',
                      ),
                      option(
                        _BlockAction.duplicateChain,
                        Icons.library_add_outlined,
                        'Duplicar cadeia',
                        switch (below) {
                          0 => 'Não há blocos encaixados abaixo deste.',
                          1 => 'Copia este bloco e o encaixado abaixo dele.',
                          _ => 'Copia este bloco e os $below encaixados '
                              'abaixo dele.',
                        },
                      ),
                      option(
                        _BlockAction.delete,
                        Icons.delete_outline,
                        'Deletar bloco',
                        below == 0
                            ? 'Apaga só este bloco.'
                            : 'Apaga só este bloco; os de baixo sobem.',
                        color: danger,
                      ),
                      option(
                        _BlockAction.deleteChain,
                        Icons.delete_sweep_outlined,
                        'Deletar cadeia',
                        switch (below) {
                          0 => 'Não há blocos abaixo; apaga só este.',
                          1 => 'Apaga este bloco e o encaixado abaixo dele.',
                          _ => 'Apaga este bloco e os $below encaixados '
                              'abaixo dele.',
                        },
                        color: danger,
                      ),
                      option(
                        _BlockAction.toggleDisabled,
                        disabled
                            ? Icons.play_circle_outline
                            : Icons.block_outlined,
                        disabled ? 'Ativar bloco' : 'Desativar bloco',
                        disabled
                            ? 'Volta a executar este bloco.'
                            : 'Pula este bloco sem apagá-lo. Os blocos de '
                                'baixo continuam executando.',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
          _blockActionsOpen = false;
          final id = jsonEncode(blockId);
          final script = switch (action) {
            null => null,
            _BlockAction.copy => 'window.microArca.copyBlock($id);',
            _BlockAction.duplicate =>
              'window.microArca.duplicateBlock($id, false);',
            _BlockAction.duplicateChain =>
              'window.microArca.duplicateBlock($id, true);',
            _BlockAction.delete => 'window.microArca.deleteBlock($id, false);',
            _BlockAction.deleteChain =>
              'window.microArca.deleteBlock($id, true);',
            _BlockAction.toggleDisabled => 'window.microArca.setBlockDisabled('
                '$id, ${jsonEncode(!disabled)});',
          };
          if (script != null) await _controller?.runJavaScript(script);
          return;
        case 'copied':
          final state = envelope['state'];
          final label = envelope['label'];
          if (state is! String ||
              utf8.encode(state).length > maxBlockWorkspaceBytes ||
              jsonDecode(state) is! Map) {
            throw const FormatException('Cópia inválida.');
          }
          if (mounted) {
            setState(() {
              _clipboard = state;
              _clipboardLabel = label is String ? label : null;
            });
          }
          return;
        case 'state':
          final snapshot = BlockProgramSnapshot.fromBridgeMessage(message);
          _savedWorkspace = snapshot.workspace;
          if (mounted) {
            setState(() {
              _python = snapshot.python;
              _requirements = snapshot.requirements;
              _variables = snapshot.variables;
              _notice = null;
            });
          }
          _scheduleSave(snapshot.workspace);
          if (envelope['requestId'] == _stateRefreshId) {
            final refresh = _stateRefresh;
            _stateRefresh = null;
            _stateRefreshId = null;
            if (refresh != null && !refresh.isCompleted) refresh.complete();
          }
          return;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'O editor enviou um projeto inválido.');
      }
    }
  }

  String _bridgeBlockId(Map<dynamic, dynamic> envelope) {
    final blockId = envelope['blockId'];
    if (blockId is! String ||
        blockId.isEmpty ||
        blockId.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(blockId)) {
      throw const FormatException('Bloco inválido.');
    }
    return blockId;
  }

  Future<void> _paste() async {
    final clipboard = _clipboard;
    if (clipboard == null) return;
    await _controller?.runJavaScript(
      'window.microArca.pasteBlock(${jsonEncode(clipboard)});',
    );
  }

  String? _variableNameError(String value) {
    if (value.isEmpty) return 'Informe um nome para a variável.';
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$').hasMatch(value)) {
      return 'Use até 32 letras, números ou _. O nome não pode começar com número.';
    }
    if (_pythonKeywords.contains(value)) {
      return 'Esse nome é reservado pelo Python.';
    }
    return null;
  }

  Future<BlockVariable?> _chooseVariable({required bool numberOnly}) async {
    return showDialog<BlockVariable>(
      context: context,
      builder: (_) => _VariableDialog(
        variables: _variables,
        validator: _variableNameError,
        numberOnly: numberOnly,
      ),
    );
  }

  Future<void> _showVariableQuickPicker() async {
    await _refreshProgramState();
    if (!mounted) return;
    final variable = await showDialog<BlockVariable>(
      context: context,
      builder: (_) => _VariableQuickPickerDialog(variables: _variables),
    );
    if (variable == null || !mounted) return;
    setState(() => _variableShortcutsOpen = false);
    await _controller?.runJavaScript(
      'window.microArca.addVariableBlock('
      '${jsonEncode('variables_get_dynamic')}, '
      '${jsonEncode(variable.name)}, ${jsonEncode(variable.type.bridgeName)});',
    );
  }

  Future<void> _showVariableAssignmentPicker() async {
    final variable = await _chooseVariable(numberOnly: false);
    if (variable == null || !mounted) return;
    setState(() => _variableShortcutsOpen = false);
    await _controller?.runJavaScript(
      'window.microArca.addVariableBlock('
      '${jsonEncode('variables_set_dynamic')}, '
      '${jsonEncode(variable.name)}, ${jsonEncode(variable.type.bridgeName)});',
    );
  }

  void _openShortcutSection(String id) {
    if (id == 'variables') {
      setState(() => _variableShortcutsOpen = !_variableShortcutsOpen);
      return;
    }
    if (_variableShortcutsOpen) {
      setState(() => _variableShortcutsOpen = false);
    }
    unawaited(_showBlockMenu(focusSection: id));
  }

  void _openVariableDrawer() {
    setState(() => _variableShortcutsOpen = false);
    unawaited(_showBlockMenu(focusSection: 'variables'));
  }

  void _scheduleSave(String workspace) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _storage.saveWorkspace(workspace);
        // A revisão mudou: o indicador "gravado no kit" precisa saber.
        final project = await widget.projectStorage.load(widget.project.id);
        if (project != null && mounted) setState(() => _project = project);
      } catch (_) {
        if (mounted) {
          setState(() => _notice = 'Não foi possível salvar os blocos.');
        }
      }
    });
  }

  Future<void> _newBlink() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Criar novo blink?'),
            content: const Text(
              'Os blocos atuais serão substituídos pelo exemplo de GPIO.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Criar blink'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _controller?.runJavaScript('window.microArca.createDefault();');
    await _refreshProgramState();
  }

  Future<bool> _refreshProgramState() async {
    final controller = _controller;
    if (controller == null) return false;

    final previous = _stateRefresh;
    if (previous != null && !previous.isCompleted) {
      previous.complete();
    }
    final refresh = Completer<void>();
    final requestId = 'flutter-${++_stateRefreshSerial}';
    _stateRefresh = refresh;
    _stateRefreshId = requestId;
    try {
      await controller.runJavaScript(
        'window.microArca.emitState(${jsonEncode(requestId)});',
      );
      await refresh.future.timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      if (identical(_stateRefresh, refresh)) {
        _stateRefresh = null;
        _stateRefreshId = null;
      }
      if (mounted) {
        setState(() => _notice = 'Não foi possível sincronizar os blocos.');
      }
      return false;
    }
  }

  // The drawer is rebuilt every time it opens, so the sections the user left
  // open live here to survive between openings.
  void _rememberBlockSection(String id, bool expanded) {
    if (expanded) {
      _expandedBlockSections.add(id);
    } else {
      _expandedBlockSections.remove(id);
    }
  }

  void _rememberLibrary(String packageId) {
    if (_lastLibraryPackage == packageId) return;
    setState(() => _lastLibraryPackage = packageId);
  }

  LibraryBlockManifest? get _lastLibrary {
    final id = _lastLibraryPackage;
    if (id == null) return null;
    for (final manifest in _libraryManifests) {
      if (manifest.packageId == id) return manifest;
    }
    return null;
  }

  /// [focusSection] abre a gaveta só com essa seção aberta e rola até ela;
  /// [focusLibrary] faz o mesmo com um pacote dentro de Bibliotecas.
  Future<void> _showBlockMenu({
    String? focusSection,
    String? focusLibrary,
  }) async {
    if (focusSection != null || focusLibrary != null) {
      _expandedBlockSections
        ..clear()
        ..add(focusLibrary != null ? _librarySectionId : focusSection!);
    }
    final focusKey = GlobalKey();
    var scrolled = false;
    final type = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        if (!scrolled && (focusSection != null || focusLibrary != null)) {
          scrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = focusKey.currentContext;
            if (target != null) {
              Scrollable.ensureVisible(
                target,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          });
        }
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Text('Adicionar bloco',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final section in _blockSections)
                  _BlockSectionTile(
                    key: section.id == focusSection ? focusKey : null,
                    section: section,
                    initiallyExpanded: _expandedBlockSections.contains(
                      section.id,
                    ),
                    onExpansionChanged: (expanded) =>
                        _rememberBlockSection(section.id, expanded),
                    onBlockSelected: (type) =>
                        Navigator.pop(sheetContext, type),
                  ),
                _LibraryBlocksDrawer(
                  manifests: _libraryManifests,
                  initiallyExpanded: _expandedBlockSections.contains(
                    _librarySectionId,
                  ),
                  onExpansionChanged: (expanded) =>
                      _rememberBlockSection(_librarySectionId, expanded),
                  expandedPackage: focusLibrary,
                  focusKey: focusLibrary != null ? focusKey : null,
                  onPackageOpened: _rememberLibrary,
                  onBlockSelected: (type) => Navigator.pop(sheetContext, type),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (type == null || !mounted) return;
    if (type == 'variables_get_dynamic') {
      await _showVariableQuickPicker();
      return;
    }
    if (_variableBlockTypes.contains(type)) {
      final variable = await _chooseVariable(
        numberOnly: type == 'microarca_variable_change',
      );
      if (variable == null || !mounted) return;
      await _controller?.runJavaScript(
        'window.microArca.addVariableBlock('
        '${jsonEncode(type)}, ${jsonEncode(variable.name)}, '
        '${jsonEncode(variable.type.bridgeName)});',
      );
      return;
    }
    await _controller?.runJavaScript(
      'window.microArca.addBlock(${jsonEncode(type)});',
    );
  }

  Future<void> _workspaceAction(String action) async {
    switch (action) {
      case 'undo':
        await _controller?.runJavaScript('window.microArca.undo();');
      case 'redo':
        await _controller?.runJavaScript('window.microArca.redo();');
      case 'delete':
        await _controller?.runJavaScript(
          'window.microArca.deleteSelected();',
        );
      case 'code':
        await _showCode();
      case 'install':
        await _install();
      case 'convert':
        await _convertToPython();
      case 'console':
        await openConsole(context);
      case 'new':
        await _newBlink();
    }
  }

  String _statusLine() {
    if (!_service.isConnected) return 'ESP32 desconectado';
    return switch (kitProjectRelation(_service, _project)) {
      KitProjectRelation.current => '⚡ Gravado no kit',
      KitProjectRelation.currentOutdated =>
        '⚡ Gravado no kit • alterações não gravadas',
      _ => _service.status,
    };
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showCode() async {
    if (!await _refreshProgramState() || !mounted) return;
    if (_python.trim().isEmpty) {
      _showMessage('Monte um programa para gerar o MicroPython.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'MicroPython gerado',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xfff4fafb),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _python,
                        style: const TextStyle(
                          fontFamily: 'FiraCode',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sincroniza os blocos e grava o projeto no celular antes de enviá-lo.
  /// Retorna o projeto atualizado, ou null se não há o que enviar.
  Future<ArcaProject?> _prepareDeploy() async {
    final reason = _deployer.unavailableReason;
    if (reason != null) {
      _showMessage(reason);
      return null;
    }
    if (!await _refreshProgramState() || !mounted) return null;
    if (_python.trim().isEmpty) {
      _showMessage('Monte um programa antes de enviar ao kit.');
      return null;
    }
    if (!await _requirementsAreInstalled()) return null;
    await _flushSave();
    return widget.projectStorage.load(widget.project.id);
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    final workspace = _savedWorkspace;
    if (workspace == null) return;
    try {
      await _storage.saveWorkspace(workspace);
      final project = await widget.projectStorage.load(widget.project.id);
      if (project != null && mounted) setState(() => _project = project);
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Não foi possível salvar os blocos.');
      }
    }
  }

  Future<void> _run() async {
    final project = await _prepareDeploy();
    if (project == null || !mounted) return;
    if (!await _deployer.run(project, {'main.py': _python}) && mounted) {
      _showMessage(_service.status);
    }
  }

  Future<void> _install() async {
    if (!_service.autorunAvailable) {
      _showMessage(
        _deployer.unavailableReason ??
            'Atualize main.py e arca_files.py na placa, pelo cabo, para gravar.',
      );
      return;
    }
    if (!await confirmInstallOnKit(context, widget.project.name) || !mounted) {
      return;
    }
    final project = await _prepareDeploy();
    if (project == null || !mounted) return;
    await _deployer.install(project, {'main.py': _python});
    _showMessage(_service.status);
  }

  Future<void> _convertToPython() async {
    if (!await _refreshProgramState() || !mounted) return;
    if (_python.trim().isEmpty) {
      _showMessage('Monte um programa antes de converter.');
      return;
    }
    const suffix = ' (Python)';
    final base = widget.project.name;
    final name = base.length + suffix.length > maxProjectNameLength
        ? '${base.substring(0, maxProjectNameLength - suffix.length)}$suffix'
        : '$base$suffix';
    final project = ArcaProject.create(name, ProjectKind.python)
        .copyWith(files: {'main.py': _python});
    try {
      await widget.projectStorage.save(project);
    } catch (_) {
      _showMessage('Não foi possível criar o projeto Python.');
      return;
    }
    if (!mounted) return;
    final open = widget.onOpenProject;
    if (open != null) {
      open(project);
    } else {
      _showMessage('Projeto "$name" criado.');
    }
  }

  Future<bool> _requirementsAreInstalled() async {
    if (_requirements.isEmpty) return true;
    final device = _service.device;
    if (device == null) return false;
    try {
      final registry = await _packageStorage.load(device.id);
      final missing = <String>[];
      for (final requirement in _requirements) {
        final separator = requirement.lastIndexOf('@');
        final id = requirement.substring(0, separator);
        final version = requirement.substring(separator + 1);
        if (registry.packages[id]?.version != version) {
          missing.add(requirement);
        }
      }
      if (missing.isNotEmpty) {
        _showMessage(
          'Instale no ESP32 antes de executar: ${missing.join(', ')}.',
        );
        return false;
      }
      return true;
    } catch (error) {
      _showMessage('Não foi possível conferir as bibliotecas do kit: $error');
      return false;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    final refresh = _stateRefresh;
    if (refresh != null && !refresh.isCompleted) refresh.complete();
    final workspace = _savedWorkspace;
    if (workspace != null) unawaited(_storage.saveWorkspace(workspace));
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
          backgroundColor: const Color(0xfff4fafb),
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller == null)
                  const Center(child: CircularProgressIndicator())
                else
                  WebViewWidget(
                    controller: _controller!,
                    // Blockly owns every gesture on the canvas. Without this,
                    // the app-wide tap detector wins the arena and cancels a
                    // held touch after ~150 ms, so long presses never land.
                    gestureRecognizers: const {
                      Factory<OneSequenceGestureRecognizer>(
                        EagerGestureRecognizer.new,
                      ),
                    },
                  ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _FloatingControl(
                    tooltip: 'Voltar para os projetos',
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                Positioned(
                  left: 66,
                  right: 66,
                  top: 14,
                  child: Center(
                    child: Material(
                      color: const Color(0xf2ffffff),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              _statusLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Material(
                    color: const Color(0xf2ffffff),
                    elevation: 3,
                    shape: const CircleBorder(),
                    child: PopupMenuButton<String>(
                      tooltip: 'Mais ações',
                      onSelected: (action) =>
                          unawaited(_workspaceAction(action)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'undo',
                          child: ListTile(
                            leading: Icon(Icons.undo),
                            title: Text('Desfazer'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'redo',
                          child: ListTile(
                            leading: Icon(Icons.redo),
                            title: Text('Refazer'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Excluir bloco selecionado'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'install',
                          child: ListTile(
                            leading: Icon(Icons.power_settings_new),
                            title: Text('Gravar no kit'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'console',
                          child: ListTile(
                            leading: Icon(Icons.terminal),
                            title: Text('Console'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'code',
                          child: ListTile(
                            leading: Icon(Icons.code),
                            title: Text('Ver código'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'convert',
                          child: ListTile(
                            leading: Icon(Icons.transform),
                            title: Text('Converter em projeto Python'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'new',
                          child: ListTile(
                            leading: Icon(Icons.refresh),
                            title: Text('Recomeçar com blink'),
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ),
                if (_controller != null)
                  Positioned(
                    left: 17,
                    top: 76,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final id in _shortcutSections)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FloatingControl(
                                  compact: true,
                                  tooltip: id == 'variables'
                                      ? 'Ações de variáveis'
                                      : _sectionById(id).title,
                                  icon: _sectionById(id).icon,
                                  color: _sectionById(id).color,
                                  onPressed: () => _openShortcutSection(id),
                                ),
                                if (id == 'variables' &&
                                    _variableShortcutsOpen) ...[
                                  const SizedBox(width: 7),
                                  _FloatingControl(
                                    compact: true,
                                    tooltip: 'Usar variável',
                                    icon: Icons.attach_money,
                                    color: _sectionById(id).color,
                                    onPressed: () => unawaited(
                                      _showVariableQuickPicker(),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  _FloatingControl(
                                    compact: true,
                                    tooltip: 'Declarar ou atribuir variável',
                                    icon: Icons.arrow_back,
                                    color: _sectionById(id).color,
                                    onPressed: () => unawaited(
                                      _showVariableAssignmentPicker(),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  _FloatingControl(
                                    compact: true,
                                    tooltip: 'Abrir gaveta de variáveis',
                                    icon: Icons.more_horiz,
                                    color: _sectionById(id).color,
                                    onPressed: _openVariableDrawer,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (_lastLibrary case final library?)
                          _FloatingControl(
                            compact: true,
                            tooltip: library.categoryName,
                            icon: Icons.widgets_outlined,
                            color: _manifestColor(library.color),
                            onPressed: () => _showBlockMenu(
                              focusLibrary: library.packageId,
                            ),
                          ),
                      ],
                    ),
                  ),
                // Mesmo indicador do projeto Python: aparece enquanto o
                // projeto é enviado ao kit.
                if (busy)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 66,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _service.progress,
                        minHeight: 5,
                      ),
                    ),
                  ),
                if (_notice != null || _libraryWarning != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 78,
                    child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          _notice ?? _libraryWarning!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                if (_clipboard != null && _controller != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 84,
                    child: Center(
                      child: Material(
                        color: const Color(0xf2ffffff),
                        elevation: 4,
                        borderRadius: BorderRadius.circular(28),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: _clipboardLabel ?? 'Bloco copiado',
                                child: FilledButton.icon(
                                  onPressed: _paste,
                                  icon: const Icon(Icons.content_paste),
                                  label: const Text('Colar'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Parar de colar',
                                onPressed: () => setState(() {
                                  _clipboard = null;
                                  _clipboardLabel = null;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: FloatingActionButton.extended(
                    heroTag: 'add-block',
                    onPressed: _controller == null ? null : _showBlockMenu,
                    icon: const Icon(Icons.extension_outlined),
                    label: const Text('Blocos'),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: running
                      ? FloatingActionButton.extended(
                          heroTag: 'stop-blocks',
                          onPressed: _service.state == KitState.stopping
                              ? null
                              : _service.stop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Parar'),
                        )
                      : FloatingActionButton.extended(
                          heroTag: 'run-blocks',
                          onPressed: _python.trim().isEmpty ? null : _run,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Executar'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _manifestColor(String value) =>
    Color(0xff000000 | int.parse(value.substring(1), radix: 16));

class _FloatingControl extends StatelessWidget {
  const _FloatingControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  /// 70% do tamanho normal, para a coluna de atalhos.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xf2ffffff),
      elevation: 3,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        // No Material 3 o tamanho vem do style; constraints é ignorado.
        style: compact
            ? IconButton.styleFrom(
                fixedSize: const Size(34, 34),
                minimumSize: const Size(34, 34),
                padding: EdgeInsets.zero,
                iconSize: 22,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            : null,
      ),
    );
  }
}

class _BlockOption extends StatelessWidget {
  const _BlockOption({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          foregroundColor: Colors.white,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.add),
        onTap: onTap,
      ),
    );
  }
}

class _BlockEntry {
  const _BlockEntry(this.type, this.icon, this.title, this.subtitle,
      {this.color});

  final String type;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Overrides the section color when the block itself is drawn in another
  /// color, so the icon matches what lands on the canvas.
  final Color? color;
}

class _BlockSection {
  const _BlockSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.color,
    required this.blocks,
  });

  final String id;
  final String title;

  /// Shown while the section is collapsed so users can tell what is inside
  /// without opening it.
  final String summary;
  final IconData icon;
  final Color color;
  final List<_BlockEntry> blocks;
}

const _librarySectionId = 'libraries';

/// Seções com atalho fixo no canvas, na ordem da coluna.
const _shortcutSections = ['pins', 'variables', 'control', 'logic', 'math'];

_BlockSection _sectionById(String id) =>
    _blockSections.firstWhere((section) => section.id == id);

const _blockSections = [
  _BlockSection(
    id: 'control',
    title: 'Controle',
    summary: 'Repetir para sempre, se, se/senão, esperar',
    icon: Icons.call_split,
    color: Color(0xff1565c0),
    blocks: [
      _BlockEntry('microarca_forever', Icons.all_inclusive,
          'Repetir para sempre', 'Executa continuamente os blocos encaixados.'),
      _BlockEntry('controls_if', Icons.call_split, 'Se',
          'Executa blocos somente quando a condição for verdadeira.'),
      _BlockEntry('controls_ifelse', Icons.alt_route, 'Se / senão',
          'Escolhe entre dois caminhos usando uma condição.'),
      _BlockEntry('microarca_wait', Icons.timer_outlined, 'Esperar',
          'Pausa o programa pelo número de segundos.',
          color: Color(0xff7b61c9)),
    ],
  ),
  _BlockSection(
    id: 'pins',
    title: 'Pinos',
    summary: 'Leitura digital e analógica, escrita e PWM',
    icon: Icons.electrical_services_outlined,
    color: Color(0xff00a9bd),
    blocks: [
      _BlockEntry('microarca_pin_mode', Icons.settings_input_component,
          'Configurar pino', 'Define o GPIO como entrada, saída ou pull-up.'),
      _BlockEntry('microarca_pin_read', Icons.input, 'Ler pino digital',
          'Retorna ALTO ou BAIXO; preserva o pull-up configurado.'),
      _BlockEntry('microarca_analog_read', Icons.tune, 'Ler pino analógico',
          'Lê um pino ADC na escala de 0 a 65535.'),
      _BlockEntry('microarca_pwm_config', Icons.settings_input_component,
          'Configurar PWM', 'Define a frequência em Hz e inicia em 0%.'),
      _BlockEntry('microarca_pwm_write', Icons.tune, 'Definir PWM',
          'Ajusta o ciclo ativo de 0 a 100%.'),
      _BlockEntry('microarca_pwm_stop', Icons.stop_circle_outlined,
          'Desligar PWM', 'Encerra o PWM e deixa a saída em BAIXO.'),
      _BlockEntry('microarca_pin_write', Icons.electrical_services_outlined,
          'Escrever no pino', 'Define o nível lógico como ALTO ou BAIXO.'),
      _BlockEntry('microarca_logic_level', Icons.toggle_on_outlined,
          'ALTO / BAIXO', 'Valor lógico para usar no pino ou em condições.',
          color: Color(0xff4c97ff)),
    ],
  ),
  _BlockSection(
    id: 'logic',
    title: 'Lógica e comparações',
    summary: 'Comparar, E/OU, não, ALTO/BAIXO',
    icon: Icons.compare_arrows,
    color: Color(0xff4c97ff),
    blocks: [
      _BlockEntry('logic_compare', Icons.compare_arrows, 'Comparação',
          'Compara valores com =, ≠, <, ≤, > ou ≥.'),
      _BlockEntry('logic_operation', Icons.join_inner, 'E / OU',
          'Combina duas condições lógicas.'),
      _BlockEntry('logic_negate', Icons.not_interested, 'Não',
          'Inverte um valor lógico.'),
      _BlockEntry('microarca_logic_level', Icons.toggle_on_outlined,
          'ALTO / BAIXO', 'Cria um valor lógico verdadeiro ou falso.'),
    ],
  ),
  _BlockSection(
    id: 'math',
    title: 'Matemática',
    summary: 'Número, operação matemática',
    icon: Icons.calculate_outlined,
    color: Color(0xff5b67a5),
    blocks: [
      _BlockEntry(
          'math_number', Icons.numbers, 'Número', 'Cria um valor numérico.'),
      _BlockEntry(
          'math_arithmetic',
          Icons.calculate_outlined,
          'Operação matemática',
          'Soma, subtrai, multiplica ou divide valores.'),
    ],
  ),
  _BlockSection(
    id: 'text',
    title: 'Texto e console',
    summary: 'Texto, mostrar no console',
    icon: Icons.text_fields,
    color: Color(0xff5ba58c),
    blocks: [
      _BlockEntry(
          'text', Icons.text_fields, 'Texto', 'Cria um valor de texto.'),
      _BlockEntry('microarca_text_join', Icons.add_link, 'Juntar valores',
          'Combina texto, número ou valor lógico em um único texto.'),
      _BlockEntry('text_print', Icons.terminal, 'Mostrar no console',
          'Exibe texto, número ou valor lógico no console do MicroARCA.'),
    ],
  ),
  _BlockSection(
    id: 'variables',
    title: 'Variáveis',
    summary: 'Declarar/atribuir, usar e somar',
    icon: Icons.data_object,
    color: Color(0xffa55b80),
    blocks: [
      _BlockEntry(
          'variables_set_dynamic',
          Icons.arrow_back,
          'Declarar/atribuir  (x ← valor)',
          'Guarda um valor na variável. Se ela não existe, é criada.'),
      _BlockEntry('variables_get_dynamic', Icons.data_object, 'Usar variável',
          'Fornece o valor atual de uma variável.'),
      _BlockEntry('microarca_variable_change', Icons.exposure_plus_1,
          'Somar à variável', 'Soma um número ao valor atual da variável.'),
    ],
  ),
  _BlockSection(
    id: 'functions',
    title: 'Funções',
    summary: 'Definir e chamar funções',
    icon: Icons.account_tree_outlined,
    color: Color(0xffd06b22),
    blocks: [
      _BlockEntry('microarca_function_def', Icons.account_tree_outlined,
          'Definir função', 'Cria uma função com o nome escolhido.'),
      _BlockEntry('microarca_function_call', Icons.playlist_play,
          'Chamar função', 'Executa uma função criada no programa.'),
    ],
  ),
];

class _BlockSectionTile extends StatelessWidget {
  const _BlockSectionTile({
    super.key,
    required this.section,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.onBlockSelected,
  });

  final _BlockSection section;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final ValueChanged<String> onBlockSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: section.color,
          foregroundColor: Colors.white,
          child: Icon(section.icon),
        ),
        title: Text(section.title),
        subtitle: Text(section.summary),
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          for (final block in section.blocks)
            _BlockOption(
              color: block.color ?? section.color,
              icon: block.icon,
              title: block.title,
              subtitle: block.subtitle,
              onTap: () => onBlockSelected(block.type),
            ),
        ],
      ),
    );
  }
}

class _LibraryBlocksDrawer extends StatelessWidget {
  const _LibraryBlocksDrawer({
    required this.manifests,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.onPackageOpened,
    required this.onBlockSelected,
    this.expandedPackage,
    this.focusKey,
  });

  final List<LibraryBlockManifest> manifests;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final ValueChanged<String> onPackageOpened;
  final ValueChanged<String> onBlockSelected;
  final String? expandedPackage;
  final Key? focusKey;

  @override
  Widget build(BuildContext context) {
    final libraryCount = manifests.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        leading: const CircleAvatar(
          child: Icon(Icons.local_library_outlined),
        ),
        title: const Text('Bibliotecas'),
        subtitle: Text(
          libraryCount == 0
              ? 'Nenhuma biblioteca com blocos instalada'
              : libraryCount == 1
                  ? '1 biblioteca com blocos'
                  : '$libraryCount bibliotecas com blocos',
        ),
        children: libraryCount == 0
            ? const [
                ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Instale uma biblioteca compatível'),
                  subtitle: Text(
                    'Abra a área Bibliotecas para baixar blocos adicionais.',
                  ),
                ),
              ]
            : [
                for (final manifest in manifests)
                  _LibraryBlockPackage(
                    key:
                        manifest.packageId == expandedPackage ? focusKey : null,
                    manifest: manifest,
                    initiallyExpanded: manifest.packageId == expandedPackage,
                    onOpened: () => onPackageOpened(manifest.packageId),
                    onBlockSelected: (type) {
                      onPackageOpened(manifest.packageId);
                      onBlockSelected(type);
                    },
                  ),
              ],
      ),
    );
  }
}

class _LibraryBlockPackage extends StatelessWidget {
  const _LibraryBlockPackage({
    super.key,
    required this.manifest,
    required this.initiallyExpanded,
    required this.onOpened,
    required this.onBlockSelected,
  });

  final LibraryBlockManifest manifest;
  final bool initiallyExpanded;
  final VoidCallback onOpened;
  final ValueChanged<String> onBlockSelected;

  @override
  Widget build(BuildContext context) {
    final color = _manifestColor(manifest.color);
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: (expanded) {
        if (expanded) onOpened();
      },
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: const Icon(Icons.widgets_outlined),
      ),
      title: Text(manifest.categoryName),
      subtitle: Text('${manifest.packageId} • ${manifest.packageVersion}'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        for (final block in manifest.blocks)
          _BlockOption(
            color: color,
            icon: Icons.widgets_outlined,
            title: block.name,
            subtitle: block.description,
            onTap: () => onBlockSelected(block.type),
          ),
      ],
    );
  }
}

String _variableTypeLabel(BlockVariableType type) => switch (type) {
      BlockVariableType.number => 'Número',
      BlockVariableType.text => 'Texto',
      BlockVariableType.boolean => 'Lógico',
    };

IconData _variableTypeIcon(BlockVariableType type) => switch (type) {
      BlockVariableType.number => Icons.numbers,
      BlockVariableType.text => Icons.text_fields,
      BlockVariableType.boolean => Icons.toggle_on_outlined,
    };

class _VariableQuickPickerDialog extends StatefulWidget {
  const _VariableQuickPickerDialog({required this.variables});

  final List<BlockVariable> variables;

  @override
  State<_VariableQuickPickerDialog> createState() =>
      _VariableQuickPickerDialogState();
}

class _VariableQuickPickerDialogState
    extends State<_VariableQuickPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BlockVariable> get _filteredVariables {
    final query = _query.trim().toLowerCase();
    final variables = [...widget.variables]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (query.isEmpty) return variables;
    return variables
        .where((variable) => variable.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final variables = _filteredVariables;
    return AlertDialog(
      title: const Text('Usar variável'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Pesquisar variável',
                hintText: 'Digite o nome',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: variables.isEmpty
                  ? Center(
                      child: Text(
                        widget.variables.isEmpty
                            ? 'Ainda não há variáveis no programa.\n'
                                'Use o botão … para criar uma.'
                            : 'Nenhuma variável encontrada.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: variables.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final variable = variables[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _sectionById('variables').color,
                            foregroundColor: Colors.white,
                            child: Icon(_variableTypeIcon(variable.type)),
                          ),
                          title: Text(variable.name),
                          subtitle: Text(_variableTypeLabel(variable.type)),
                          trailing: const Icon(Icons.add),
                          onTap: () => Navigator.pop(context, variable),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _VariableDialog extends StatefulWidget {
  const _VariableDialog({
    required this.variables,
    required this.validator,
    required this.numberOnly,
  });

  final List<BlockVariable> variables;
  final String? Function(String) validator;
  final bool numberOnly;

  @override
  State<_VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<_VariableDialog> {
  late final List<BlockVariable> _availableVariables = widget.numberOnly
      ? widget.variables
          .where((variable) => variable.type == BlockVariableType.number)
          .toList()
      : widget.variables;
  late final TextEditingController _controller = TextEditingController(
    text: _availableVariables.isEmpty
        ? 'variavel'
        : _availableVariables.first.name,
  );
  late BlockVariableType _selectedType = widget.numberOnly
      ? BlockVariableType.number
      : (_availableVariables.isEmpty
          ? BlockVariableType.number
          : _availableVariables.first.type);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    var error = widget.validator(name);
    final existing =
        widget.variables.where((variable) => variable.name == name).firstOrNull;
    if (widget.numberOnly &&
        existing != null &&
        existing.type != BlockVariableType.number) {
      error = 'Escolha uma variável numérica para esta operação.';
    }
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.pop(
      context,
      existing ?? BlockVariable(name: name, type: _selectedType),
    );
  }

  void _selectVariable(BlockVariable variable) {
    _controller
      ..text = variable.name
      ..selection = TextSelection.collapsed(offset: variable.name.length);
    setState(() {
      _selectedType = variable.type;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Escolher variável'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nome',
                hintText: 'contador',
                errorText: _errorText,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                final existing = widget.variables
                    .where(
                        (variable) => variable.name == _controller.text.trim())
                    .firstOrNull;
                setState(() {
                  if (existing != null) _selectedType = existing.type;
                  _errorText = null;
                });
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            if (widget.numberOnly)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.numbers),
                title: Text('Tipo: Número'),
                dense: true,
              )
            else
              DropdownButtonFormField<BlockVariableType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final type in BlockVariableType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_variableTypeLabel(type)),
                    ),
                ],
                onChanged: (type) {
                  if (type != null) setState(() => _selectedType = type);
                },
              ),
            if (_availableVariables.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Variáveis existentes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final variable in _availableVariables)
                    ActionChip(
                      label: Text(
                        '${variable.name} · ${_variableTypeLabel(variable.type)}',
                      ),
                      onPressed: () => _selectVariable(variable),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _FieldValueDialog extends StatefulWidget {
  const _FieldValueDialog({
    required this.title,
    required this.initialValue,
    required this.numeric,
  });

  final String title;
  final String initialValue;
  final bool numeric;

  @override
  State<_FieldValueDialog> createState() => _FieldValueDialogState();
}

class _FieldValueDialogState extends State<_FieldValueDialog> {
  // Starts fully selected so typing replaces the old value, like Blockly's
  // inline editor on desktop.
  late final _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Brazilian keyboards offer a decimal comma; Blockly only parses the point.
  void _submit() => Navigator.pop(
        context,
        widget.numeric
            ? _controller.text.replaceAll(',', '.')
            : _controller.text,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.numeric
            ? const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              )
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: widget.numeric ? 'Número' : 'Texto',
          border: const OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
