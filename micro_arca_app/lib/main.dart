import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color.fromARGB(249, 227, 251, 255),
        // Adicione estas configurações para melhor comportamento do teclado
        useMaterial3: true,
        platform: TargetPlatform.android,
      ),
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
    );
  }
}