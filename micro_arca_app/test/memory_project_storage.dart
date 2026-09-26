import 'package:micro_arca_app/services/project_storage.dart';

class MemoryProjectStorage implements ProjectStorage {
  final Map<String, ArcaProject> projects = {};

  @override
  Future<List<ProjectSummary>> list() async => projects.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<ArcaProject?> load(String id) async => projects[id];

  @override
  Future<void> save(ArcaProject project) async =>
      projects[project.id] = project;

  @override
  Future<void> delete(String id) async => projects.remove(id);
}
