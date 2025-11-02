import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

// Definindo a cor principal (necessário para a AppBar e tema)
const Color primaryColor = Color(0xFF00BCD4); 

// A função precisa ser async, pois fizemos configurações de SO que não são instantâneas
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Passando a cor principal para o tema e o Scaffold
      theme: ThemeData(
        scaffoldBackgroundColor: const Color.fromARGB(249, 227, 251, 255),
        // Adicione estas configurações para melhor comportamento do teclado
        useMaterial3: true,
        platform: TargetPlatform.android,
        // Configura a cor principal para ser acessível em todo o app (como a AppBar)
        primaryColor: primaryColor,
        appBarTheme: const AppBarTheme(backgroundColor: primaryColor), 
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
