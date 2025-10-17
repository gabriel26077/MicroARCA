import 'package:flutter/material.dart';

// Imports das paáginas e widgets
import 'package:micro_arca_app/pages/editor_page.dart';
import 'package:micro_arca_app/pages/console_page.dart';
import 'package:micro_arca_app/pages/settings_page.dart';
import 'package:micro_arca_app/widgets/app_bar.dart';
import 'package:micro_arca_app/widgets/top_nav_bar.dart';

// CORREÇÃO DE IMPORT: Mudamos para um caminho relativo para evitar erros de compilação
// relacionados ao nome do pacote ('micro_arca_app').

/// Esse widget lida com o estado de navegação (qual página está aberta nesse momento)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedPage = 0;

  static const List<Widget> _pages = <Widget>[
    EditorPage(),
    ConsolePage(),
    SettingsPage(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _selectedPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MyAppBar(),
      body: Column(
        children: [
          // Our new top navigation component
          TopNavBar(selectedIndex: _selectedPage, onTap: _onTabTapped),

          Expanded(
            child: IndexedStack(index: _selectedPage, children: _pages),
          ),
        ],
      ),


    );
  }
}
