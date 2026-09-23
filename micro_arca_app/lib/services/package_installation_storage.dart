import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'library_catalog.dart';

class InstalledPackageRecord {
  const InstalledPackageRecord({
    required this.id,
    required this.name,
    required this.version,
    required this.dependencies,
    required this.files,
    required this.installedAt,
  });

  final String id;
  final String name;
  final String version;
  final List<CatalogDependency> dependencies;
  final List<String> files;
  final DateTime installedAt;

  factory InstalledPackageRecord.fromPackage(CatalogPackage package) =>
      InstalledPackageRecord(
        id: package.id,
        name: package.name,
        version: package.version,
        dependencies: package.dependencies,
        files: package.files.map((file) => file.name).toList(growable: false),
        installedAt: DateTime.now().toUtc(),
      );

  factory InstalledPackageRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final version = json['version'];
    final dependencies = json['dependencies'];
    final files = json['files'];
    final installedAt = json['installedAt'];
    if (id is! String ||
        name is! String ||
        version is! String ||
        dependencies is! List ||
        files is! List ||
        files.any((file) => file is! String) ||
        installedAt is! String) {
      throw const FormatException('Registro de pacote instalado inválido.');
    }
    return InstalledPackageRecord(
      id: id,
      name: name,
      version: version,
      dependencies: dependencies.map((value) {
        if (value is! Map) {
          throw const FormatException('Dependência instalada inválida.');
        }
        return CatalogDependency.fromJson(value.cast<String, Object?>());
      }).toList(growable: false),
      files: files.cast<String>(),
      installedAt: DateTime.parse(installedAt),
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'dependencies': dependencies.map((value) => value.toJson()).toList(),
        'files': files,
        'installedAt': installedAt.toUtc().toIso8601String(),
      };
}

class DevicePackageRegistry {
  DevicePackageRegistry({
    required this.deviceId,
    required Map<String, String> roots,
    required Map<String, InstalledPackageRecord> packages,
  })  : roots = Map.unmodifiable(roots),
        packages = Map.unmodifiable(packages);

  factory DevicePackageRegistry.empty(String deviceId) => DevicePackageRegistry(
      deviceId: deviceId, roots: const {}, packages: const {});

  final String deviceId;
  final Map<String, String> roots;
  final Map<String, InstalledPackageRecord> packages;

  factory DevicePackageRegistry.fromJson(Map<String, Object?> json) {
    final deviceId = json['deviceId'];
    final roots = json['roots'];
    final packages = json['packages'];
    if (deviceId is! String || roots is! Map || packages is! Map) {
      throw const FormatException('Registro do dispositivo inválido.');
    }
    return DevicePackageRegistry(
      deviceId: deviceId,
      roots: roots.map((key, value) {
        if (key is! String || value is! String) {
          throw const FormatException('Pacote principal inválido.');
        }
        return MapEntry(key, value);
      }),
      packages: packages.map((key, value) {
        if (key is! String || value is! Map) {
          throw const FormatException('Pacote instalado inválido.');
        }
        return MapEntry(
          key,
          InstalledPackageRecord.fromJson(value.cast<String, Object?>()),
        );
      }),
    );
  }

  Map<String, Object> toJson() => {
        'deviceId': deviceId,
        'roots': roots,
        'packages': packages.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
}

abstract interface class PackageInstallationStorage {
  Future<DevicePackageRegistry> load(String deviceId);
  Future<void> save(DevicePackageRegistry registry);
}

class LocalPackageInstallationStorage implements PackageInstallationStorage {
  LocalPackageInstallationStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _storageKey = 'arca.installed_packages.v1';
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<DevicePackageRegistry> load(String deviceId) async {
    final encoded = await _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return DevicePackageRegistry.empty(deviceId);
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Histórico de instalações inválido.');
    }
    final value = decoded[deviceId];
    if (value == null) return DevicePackageRegistry.empty(deviceId);
    if (value is! Map) {
      throw const FormatException('Histórico do kit inválido.');
    }
    return DevicePackageRegistry.fromJson(value.cast<String, Object?>());
  }

  @override
  Future<void> save(DevicePackageRegistry registry) async {
    final encoded = await _prefs.getString(_storageKey);
    final Map<String, Object?> all;
    if (encoded == null || encoded.isEmpty) {
      all = {};
    } else {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('Histórico de instalações inválido.');
      }
      all = decoded.cast<String, Object?>();
    }
    all[registry.deviceId] = registry.toJson();
    await _prefs.setString(_storageKey, jsonEncode(all));
  }
}

class CatalogInstallPlan {
  const CatalogInstallPlan({
    required this.root,
    required this.resolved,
    required this.toInstall,
    required this.filesToRemove,
    required this.unmanagedConflicts,
    required this.nextRegistry,
  });

  final CatalogPackage root;
  final List<CatalogPackage> resolved;
  final List<CatalogPackage> toInstall;
  final List<String> filesToRemove;
  final List<String> unmanagedConflicts;
  final DevicePackageRegistry nextRegistry;
}

class CatalogRemovalPlan {
  const CatalogRemovalPlan({
    required this.packagesToRemove,
    required this.filesToRemove,
    required this.nextRegistry,
  });

  final List<InstalledPackageRecord> packagesToRemove;
  final List<String> filesToRemove;
  final DevicePackageRegistry nextRegistry;
}

class PackageInstallationPlanner {
  const PackageInstallationPlanner();

  CatalogInstallPlan install({
    required LibraryCatalog catalog,
    required DevicePackageRegistry current,
    required CatalogPackage root,
    required Set<String> filesOnDevice,
  }) {
    final roots = Map<String, String>.of(current.roots);
    roots[root.id] = root.version;
    final resolved = catalog.resolve(
      roots.entries
          .map(
              (entry) => CatalogDependency(id: entry.key, version: entry.value))
          .toList(growable: false),
    );
    final desired = <String, InstalledPackageRecord>{};
    final toInstall = <CatalogPackage>[];
    for (final package in resolved) {
      final record = InstalledPackageRecord.fromPackage(package);
      desired[package.id] = record;
      final installed = current.packages[package.id];
      final filesPresent = record.files.every(filesOnDevice.contains);
      if (installed == null ||
          installed.version != package.version ||
          !_sameFiles(installed.files, record.files) ||
          !filesPresent) {
        toInstall.add(package);
      }
    }

    final currentOwners = <String, String>{};
    for (final package in current.packages.values) {
      for (final file in package.files) {
        currentOwners[file] = package.id;
      }
    }
    final desiredFiles =
        desired.values.expand((package) => package.files).toSet();
    final conflicts = <String>{};
    for (final package in toInstall) {
      for (final file in package.files) {
        final owner = currentOwners[file.name];
        if (filesOnDevice.contains(file.name) && owner != package.id) {
          conflicts.add(file.name);
        }
      }
    }
    final obsolete = current.packages.values
        .expand((package) => package.files)
        .where((file) => !desiredFiles.contains(file))
        .toSet()
        .toList()
      ..sort();

    return CatalogInstallPlan(
      root: root,
      resolved: resolved,
      toInstall: List.unmodifiable(toInstall),
      filesToRemove: List.unmodifiable(obsolete),
      unmanagedConflicts: List.unmodifiable(conflicts.toList()..sort()),
      nextRegistry: DevicePackageRegistry(
        deviceId: current.deviceId,
        roots: roots,
        packages: desired,
      ),
    );
  }

  CatalogRemovalPlan remove({
    required DevicePackageRegistry current,
    required String rootId,
  }) {
    if (!current.roots.containsKey(rootId)) {
      throw PackageResolutionException(
        '$rootId é uma dependência de outro pacote e não pode ser removida diretamente.',
      );
    }
    final roots = Map<String, String>.of(current.roots)..remove(rootId);
    final retainedIds = <String>{};

    void retain(String id) {
      if (!retainedIds.add(id)) return;
      final package = current.packages[id];
      if (package == null) {
        throw PackageResolutionException('Registro instalado incompleto: $id.');
      }
      for (final dependency in package.dependencies) {
        final installed = current.packages[dependency.id];
        if (installed == null || installed.version != dependency.version) {
          throw PackageResolutionException(
            'Dependência instalada inconsistente: ${dependency.key}.',
          );
        }
        retain(dependency.id);
      }
    }

    for (final id in roots.keys) {
      retain(id);
    }
    final retained = <String, InstalledPackageRecord>{
      for (final id in retainedIds) id: current.packages[id]!,
    };
    final retainedFiles = retained.values.expand((item) => item.files).toSet();
    final removed = current.packages.values
        .where((item) => !retainedIds.contains(item.id))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final files = removed
        .expand((item) => item.files)
        .where((file) => !retainedFiles.contains(file))
        .toSet()
        .toList()
      ..sort();
    return CatalogRemovalPlan(
      packagesToRemove: List.unmodifiable(removed),
      filesToRemove: List.unmodifiable(files),
      nextRegistry: DevicePackageRegistry(
        deviceId: current.deviceId,
        roots: roots,
        packages: retained,
      ),
    );
  }

  bool _sameFiles(List<String> left, List<String> right) =>
      left.length == right.length && left.toSet().containsAll(right);
}
