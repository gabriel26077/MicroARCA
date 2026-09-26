import 'package:flutter/material.dart';

import '../services/library_catalog.dart';
import '../services/library_catalog_client.dart';
import '../services/micropython_repl_service.dart';
import '../services/package_installation_storage.dart';

enum _LibrarySection { online, phone, device }

class LibrariesPage extends StatefulWidget {
  const LibrariesPage({
    super.key,
    this.catalogRepository,
    this.packageStorage,
  });

  final LibraryCatalogRepository? catalogRepository;
  final PackageInstallationStorage? packageStorage;

  @override
  State<LibrariesPage> createState() => _LibrariesPageState();
}

class _LibrariesPageState extends State<LibrariesPage> {
  final _service = MicroPythonREPLService();
  late final LibraryCatalogRepository _catalogRepository =
      widget.catalogRepository ?? LibraryCatalogClient();
  late final PackageInstallationStorage _packageStorage =
      widget.packageStorage ?? LocalPackageInstallationStorage();
  static const _planner = PackageInstallationPlanner();
  List<InstalledLibrary> _installed = const [];
  List<CatalogPackage> _downloaded = const [];
  LibraryCatalog? _catalog;
  DevicePackageRegistry? _registry;
  final Map<String, String> _selectedVersions = {};
  bool _loadingKit = false;
  bool _loadingCatalog = true;
  bool _catalogBusy = false;
  String? _catalogError;
  String? _catalogWarning;
  String? _catalogActivity;
  double? _catalogProgress;
  String? _notice;
  _LibrarySection _section = _LibrarySection.online;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshKit());
  }

  Future<void> _loadCatalog() async {
    if (mounted) {
      setState(() {
        _loadingCatalog = true;
        _catalogError = null;
      });
    }
    try {
      final snapshot = await _catalogRepository.fetchCatalog();
      if (!mounted) return;
      final selections = <String, String>{};
      for (final package in snapshot.catalog.packages) {
        selections.putIfAbsent(
          package.id,
          () => snapshot.catalog.versionsOf(package.id).first.version,
        );
      }
      setState(() {
        _catalog = snapshot.catalog;
        _selectedVersions
          ..clear()
          ..addAll(selections);
        _catalogWarning = snapshot.warning;
        _loadingCatalog = false;
      });
      await _loadDownloaded();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogError = '$error';
        _loadingCatalog = false;
      });
    }
  }

  Future<void> _loadDownloaded() async {
    final catalog = _catalog;
    if (catalog == null) return;
    try {
      final packages = await _catalogRepository.downloadedPackages(catalog);
      if (mounted) setState(() => _downloaded = packages);
    } catch (error) {
      _message('Não foi possível consultar os downloads: $error');
    }
  }

  Future<void> _refreshKit() async {
    if (!_service.isReady || !_service.libraryManagerAvailable) return;
    setState(() => _loadingKit = true);
    final libraries = await _service.listLibraries();
    DevicePackageRegistry? registry;
    final deviceId = _service.device?.id;
    if (deviceId != null) {
      try {
        registry = await _packageStorage.load(deviceId);
      } catch (error) {
        if (mounted) _message('Histórico de pacotes inválido: $error');
      }
    }
    if (mounted) {
      setState(() {
        _installed = libraries;
        _registry = registry;
        _loadingKit = false;
      });
    }
  }

  Future<void> _deleteFromKit(InstalledLibrary library) async {
    final managedBy = _registry?.packages.values
        .where((package) => package.files.contains(library.name))
        .firstOrNull;
    if (managedBy != null) {
      _message(
        '${library.name} é usada pelo pacote ${managedBy.name}. '
        'Remova o pacote pela seção do catálogo.',
      );
      return;
    }
    if (!await _confirm(
      'Remover do kit?',
      '${library.name} será apagada somente de /lib.',
      'Remover',
    )) {
      return;
    }
    final success = await _service.deleteLibrary(library.name);
    if (!mounted) return;
    _message(_service.status);
    if (success) await _refreshKit();
  }

  CatalogPackage _selectedPackage(String id) {
    final catalog = _catalog!;
    final version = _selectedVersions[id]!;
    return catalog.find(id, version)!;
  }

  Future<void> _downloadOffline(CatalogPackage root) async {
    final catalog = _catalog!;
    try {
      setState(() {
        _catalogBusy = true;
        _catalogActivity = 'Baixando ${root.name}…';
        _catalogProgress = 0;
      });
      final resolved = catalog.resolve([
        CatalogDependency(id: root.id, version: root.version),
      ]);
      await _catalogRepository.download(
        resolved,
        onProgress: (received, total) {
          if (mounted) {
            setState(
                () => _catalogProgress = total == 0 ? 1 : received / total);
          }
        },
      );
      await _loadDownloaded();
      _message('${root.name} e suas dependências estão disponíveis offline.');
    } catch (error) {
      _message('Não foi possível baixar ${root.name}: $error');
    } finally {
      if (mounted) {
        setState(() {
          _catalogBusy = false;
          _catalogActivity = null;
          _catalogProgress = null;
        });
      }
    }
  }

  Future<void> _deleteDownload(CatalogPackage package) async {
    final catalog = _catalog;
    if (catalog == null ||
        !await _confirm(
          'Apagar do celular?',
          '${package.name} ${package.version} será removida dos downloads. '
              'A instalação no dispositivo não será alterada.',
          'Apagar',
        )) {
      return;
    }
    try {
      setState(() => _catalogBusy = true);
      await _catalogRepository.removeDownloadedPackage(catalog, package);
      await _loadDownloaded();
      _message('${package.name} removida do celular.');
    } catch (error) {
      _message('Não foi possível apagar ${package.name}: $error');
    } finally {
      if (mounted) setState(() => _catalogBusy = false);
    }
  }

  Future<void> _installCatalogPackage(CatalogPackage root) async {
    final catalog = _catalog!;
    final device = _service.device;
    if (device == null) return;
    try {
      final current = _registry ?? await _packageStorage.load(device.id);
      final previous = current.roots[root.id];
      if (previous != null &&
          !await _confirm(
            previous == root.version
                ? 'Reinstalar pacote?'
                : 'Atualizar pacote?',
            previous == root.version
                ? '${root.name} $previous já está registrada neste kit.'
                : '${root.name} será atualizada de $previous para ${root.version}.',
            previous == root.version ? 'Reinstalar' : 'Atualizar',
          )) {
        return;
      }
      final plan = _planner.install(
        catalog: catalog,
        current: current,
        root: root,
        filesOnDevice: _installed.map((file) => file.name).toSet(),
      );
      if (plan.unmanagedConflicts.isNotEmpty &&
          !await _confirm(
            'Substituir arquivos existentes?',
            '${plan.unmanagedConflicts.join(', ')} já existe no kit e não foi '
                'instalado pelo catálogo. A versão atual será substituída.',
            'Substituir',
          )) {
        return;
      }
      setState(() {
        _catalogBusy = true;
        _catalogActivity = 'Validando todos os downloads…';
        _catalogProgress = 0;
      });
      final verified = await _catalogRepository.download(
        plan.resolved,
        onProgress: (received, total) {
          if (mounted) {
            setState(
                () => _catalogProgress = total == 0 ? 1 : received / total);
          }
        },
      );
      final installKeys = plan.toInstall.map((package) => package.key).toSet();
      final uploads = [
        for (final package in verified)
          if (installKeys.contains(package.package.key))
            for (final file in package.files)
              LibraryUpload(name: file.metadata.name, bytes: file.bytes),
      ];
      if (uploads.isNotEmpty &&
          !await _service.installLibrariesAtomically(uploads)) {
        if (mounted) _message(_service.status);
        return;
      }
      final obsoleteOnDevice = plan.filesToRemove
          .where((name) => _installed.any((file) => file.name == name))
          .toList();
      if (obsoleteOnDevice.isNotEmpty &&
          !await _service.deleteLibrariesAtomically(obsoleteOnDevice)) {
        _message(
          'O pacote foi atualizado, mas arquivos antigos não puderam ser removidos.',
        );
      }
      await _packageStorage.save(plan.nextRegistry);
      if (!mounted) return;
      setState(() => _registry = plan.nextRegistry);
      _message('${root.name} ${root.version} instalada com sucesso.');
      await _refreshKit();
    } on PackageResolutionException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Não foi possível instalar ${root.name}: $error');
    } finally {
      if (mounted) {
        setState(() {
          _catalogBusy = false;
          _catalogActivity = null;
          _catalogProgress = null;
        });
      }
    }
  }

  Future<void> _removeCatalogPackage(InstalledPackageRecord package) async {
    final current = _registry;
    if (current == null) return;
    try {
      final plan = _planner.remove(current: current, rootId: package.id);
      final packageNames = plan.packagesToRemove
          .map((item) => '${item.name} ${item.version}')
          .join(', ');
      if (!await _confirm(
        'Remover pacote?',
        'Serão removidos $packageNames. Arquivos usados por outros pacotes '
            'serão preservados.',
        'Remover',
      )) {
        return;
      }
      final present = plan.filesToRemove
          .where((name) => _installed.any((file) => file.name == name))
          .toList();
      if (present.isNotEmpty &&
          !await _service.deleteLibrariesAtomically(present)) {
        _message(_service.status);
        return;
      }
      await _packageStorage.save(plan.nextRegistry);
      if (!mounted) return;
      setState(() => _registry = plan.nextRegistry);
      _message('${package.name} removida do kit.');
      await _refreshKit();
    } on PackageResolutionException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Não foi possível remover ${package.name}: $error');
    }
  }

  Future<bool> _confirm(
    String title,
    String message,
    String action,
  ) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }

  Widget _catalogPackageCard(String id, bool canInstall) {
    final catalog = _catalog!;
    final versions = catalog.versionsOf(id);
    final package = _selectedPackage(id);
    final installed = _registry?.packages[id];
    final downloaded = _downloaded.any((item) => item.key == package.key);
    final dependencies = package.dependencies.isEmpty
        ? 'Nenhuma'
        : package.dependencies.map((item) => item.key).join(', ');
    return Card(
      child: ExpansionTile(
        leading: Icon(
          downloaded ? Icons.download_done_outlined : Icons.cloud_outlined,
        ),
        title: Text(package.name),
        subtitle: Text(
          '${package.id}@${package.version}'
          '${downloaded ? ' • No celular' : ''}'
          '${installed == null ? '' : ' • no dispositivo: ${installed.version}'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(package.description),
          const SizedBox(height: 8),
          if (versions.length > 1)
            DropdownButtonFormField<String>(
              initialValue: package.version,
              decoration: const InputDecoration(labelText: 'Versão'),
              items: [
                for (final version in versions)
                  DropdownMenuItem(
                    value: version.version,
                    child: Text(version.version),
                  ),
              ],
              onChanged: _catalogBusy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedVersions[id] = value);
                      }
                    },
            )
          else
            Text('Versão: ${package.version}'),
          const SizedBox(height: 6),
          Text('Autor: ${package.author}'),
          Text('Licença: ${package.license}'),
          Text('MicroPython: ${package.compatibility.micropython}'),
          Text('Placas: ${package.compatibility.boards.join(', ')}'),
          Text('Dependências: $dependencies'),
          Text(
              'Arquivos: ${package.files.map((file) => file.name).join(', ')}'),
          const SizedBox(height: 4),
          SelectableText(
            'Licença: ${package.licenseUri}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (package.provenanceUri != null)
            SelectableText(
              'Origem: ${package.provenanceUri}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _catalogBusy || downloaded
                    ? null
                    : () => _downloadOffline(package),
                icon: Icon(downloaded
                    ? Icons.check_circle_outline
                    : Icons.offline_pin_outlined),
                label: Text(downloaded ? 'No celular' : 'Baixar'),
              ),
              FilledButton.icon(
                onPressed:
                    canInstall ? () => _installCatalogPackage(package) : null,
                icon: const Icon(Icons.install_mobile_outlined),
                label: Text(installed == null ? 'Instalar' : 'Atualizar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliotecas')),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final busy =
              _service.state == KitState.managingLibraries || _catalogBusy;
          final canManage = _service.isReady &&
              _service.libraryManagerAvailable &&
              !_loadingKit;
          final canInstallCatalog =
              canManage && _service.libraryManagerVersion >= 2 && !_catalogBusy;
          final catalogIds = _catalog?.packages
              .map((item) => item.id)
              .toSet()
              .toList()
            ?..sort();
          final installedRoots = _registry?.roots.keys
                  .map((id) => _registry!.packages[id])
                  .whereType<InstalledPackageRecord>()
                  .toList() ??
              const <InstalledPackageRecord>[];
          final managedFiles = _registry?.packages.values
                  .expand((package) => package.files)
                  .toSet() ??
              const <String>{};
          final unmanagedInstalled = _installed
              .where((library) => !managedFiles.contains(library.name))
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_LibrarySection>(
                segments: const [
                  ButtonSegment(
                    value: _LibrarySection.online,
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('Online'),
                  ),
                  ButtonSegment(
                    value: _LibrarySection.phone,
                    icon: Icon(Icons.phone_android_outlined),
                    label: Text('Celular'),
                  ),
                  ButtonSegment(
                    value: _LibrarySection.device,
                    icon: Icon(Icons.memory_outlined),
                    label: Text('Dispositivo'),
                  ),
                ],
                selected: {_section},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.first);
                },
              ),
              if (_notice != null) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(_notice!),
                    trailing: IconButton(
                      tooltip: 'Fechar aviso',
                      onPressed: () => setState(() => _notice = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_section == _LibrarySection.online) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Catálogo oficial',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar catálogo',
                      onPressed: busy ? null : _loadCatalog,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const Text(
                  'Bibliotecas verificadas antes de qualquer alteração no ESP32.',
                ),
                const SizedBox(height: 8),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.security_outlined),
                    title: Text('Bibliotecas executam código no ESP32'),
                    subtitle: Text(
                      'HTTPS, tamanho e SHA-256 protegem a integridade. '
                      'O catálogo ainda não possui assinatura digital.',
                    ),
                  ),
                ),
                if (_catalogActivity != null) ...[
                  Text(_catalogActivity!),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: _catalogProgress),
                ],
                if (_catalogWarning != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.offline_bolt_outlined),
                      title: Text(_catalogWarning!),
                    ),
                  ),
                if (_loadingCatalog)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_catalogError != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('Catálogo indisponível'),
                      subtitle: Text(_catalogError!),
                      trailing: IconButton(
                        tooltip: 'Tentar novamente',
                        onPressed: _loadCatalog,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  )
                else
                  for (final id in catalogIds ?? const <String>[])
                    _catalogPackageCard(id, canInstallCatalog),
                if (_service.isConnected &&
                    _service.libraryManagerAvailable &&
                    _service.libraryManagerVersion < 2)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.system_update_alt),
                      title: Text('Atualização necessária para pacotes online'),
                      subtitle: Text(
                        'Atualize arca_files.py no ESP32. As bibliotecas locais '
                        'de um único arquivo continuam disponíveis.',
                      ),
                    ),
                  ),
              ],
              if (_section == _LibrarySection.phone) ...[
                const SizedBox(height: 12),
                Text(
                  'Pacotes oficiais no celular',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Downloads verificados do catálogo, disponíveis para instalar '
                  'mesmo sem internet. Seus próprios arquivos ficam no explorador '
                  'do Editor.',
                ),
                const SizedBox(height: 8),
                for (final package in _downloaded)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.download_done_outlined),
                      title: Text(package.name),
                      subtitle: Text('${package.id}@${package.version}'),
                      trailing: IconButton(
                        tooltip: 'Apagar do celular',
                        onPressed: busy ? null : () => _deleteDownload(package),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                if (_downloaded.isEmpty && !_loadingCatalog)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.cloud_download_outlined),
                      title: Text('Nenhum pacote baixado do catálogo'),
                    ),
                  ),
              ],
              if (_section == _LibrarySection.device) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Instaladas no kit',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar lista',
                      onPressed: canManage ? _refreshKit : null,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(_service.status),
                if (busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _service.progress > 0 ? _service.progress : null,
                  ),
                ],
                if (installedRoots.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Pacotes oficiais',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final package in installedRoots)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(package.name),
                        subtitle: Text(
                          '${package.id}@${package.version} • '
                          '${package.files.join(', ')}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remover do dispositivo',
                          onPressed: canInstallCatalog
                              ? () => _removeCatalogPackage(package)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                if (!_service.isConnected)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.bluetooth_disabled),
                      title: Text('Conecte um kit para instalar bibliotecas'),
                    ),
                  )
                else if (!_service.libraryManagerAvailable)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.system_update_alt),
                      title: Text('Atualização necessária no kit'),
                      subtitle: Text(
                        'Copie arca_files.py para a raiz do ESP32 e reconecte.',
                      ),
                    ),
                  )
                else if (_loadingKit)
                  const Center(child: CircularProgressIndicator())
                else if (installedRoots.isEmpty && unmanagedInstalled.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined),
                      title: Text('Nenhuma biblioteca instalada'),
                      subtitle: Text('Somente o conteúdo de /lib é exibido.'),
                    ),
                  )
                else ...[
                  if (unmanagedInstalled.isNotEmpty)
                    Text(
                      'Arquivos avulsos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  for (final library in unmanagedInstalled)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.memory),
                        title: Text(library.name),
                        subtitle: Text(
                            '/lib/${library.name} • ${_size(library.size)}'),
                        trailing: IconButton(
                          tooltip: 'Remover do kit',
                          onPressed:
                              canManage ? () => _deleteFromKit(library) : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Arquivos como boot.py, main.py e os módulos ARCA não são '
                  'listados nem acessíveis por esta tela.',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
