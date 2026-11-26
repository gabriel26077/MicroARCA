import 'package:flutter/material.dart';
import '../services/library_catalog_client.dart';

import 'package:micro_arca_app/pages/console_page.dart';
import 'package:micro_arca_app/pages/projects_page.dart';
import 'package:micro_arca_app/pages/libraries_page.dart';
import 'package:micro_arca_app/services/console_log.dart';
import 'package:micro_arca_app/services/project_storage.dart';
import 'package:micro_arca_app/widgets/app_bar.dart';
import 'package:micro_arca_app/widgets/top_nav_bar.dart';

/// Abas Projetos, Console e Bibliotecas. Os editores abrem por cima, a partir de
/// Projetos, e podem abrir o console por cima de si mesmos.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.projectStorage, this.catalogRepository});

  final ProjectStorage? projectStorage;
  final LibraryCatalogRepository? catalogRepository;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedPage = 0;

  @override
  void initState() {
    super.initState();
    // Começa a guardar a saída do kit antes de qualquer console abrir.
    ConsoleLog();
  }

  void _onTabTapped(int index) => setState(() => _selectedPage = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            TopNavBar(selectedIndex: _selectedPage, onTap: _onTabTapped),
            Expanded(
              child: IndexedStack(
                index: _selectedPage,
                children: [
                  ProjectsPage(storage: widget.projectStorage),
                  const ConsolePage(),
                  LibrariesPage(
                      embedded: true,
                      catalogRepository: widget.catalogRepository),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
