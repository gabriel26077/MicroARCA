import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/app_theme.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

// Definindo a cor principal (necessário para a AppBar e tema)
const Color primaryColor = Color(0xFF00BCD4);

// A função precisa ser async, pois fizemos configurações de SO que não são instantâneas
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await AppTheme.instance.load();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppTheme.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: AppTheme.instance.mode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const MainScreen(),
        // Configuração global para scroll suave (opcional)
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          physics: const BouncingScrollPhysics(),
        ),
        // Builder para adicionar comportamento global de dismiss do teclado
        builder: (context, child) {
          return GestureDetector(
            onTap: () {
              // Fecha o teclado quando tocar fora de campos de texto
              FocusScopeNode currentFocus = FocusScope.of(context);
              if (!currentFocus.hasPrimaryFocus &&
                  currentFocus.focusedChild != null) {
                currentFocus.focusedChild?.unfocus();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: child,
          );
        },
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    if (brightness == Brightness.light) {
      return ThemeData(
        scaffoldBackgroundColor: const Color.fromARGB(249, 227, 251, 255),
        useMaterial3: true,
        platform: TargetPlatform.android,
        primaryColor: primaryColor,
        appBarTheme: const AppBarTheme(backgroundColor: primaryColor),
      );
    }
    final scheme =
        ColorScheme.fromSeed(seedColor: primaryColor, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.android,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    );
  }
}
