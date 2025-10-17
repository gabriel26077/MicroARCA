import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_arca_app/screens/main_screen.dart';

// Definindo a cor principal (necessário para a AppBar e tema)
const Color primaryColor = Color(0xFF00BCD4); 

// A função precisa ser async, pois fizemos configurações de SO que não são instantâneas
Future<void> main() async {
  // 3. Garante que o Flutter está inicializado antes de rodar comandos
  WidgetsFlutterBinding.ensureInitialized();

  // 4. Define as orientações permitidas (apenas retrato)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 5. Roda o seu aplicativo normalmente
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
        // Configura a cor principal para ser acessível em todo o app (como a AppBar)
        primaryColor: primaryColor,
        appBarTheme: const AppBarTheme(backgroundColor: primaryColor), 
      ),
      home: const MainScreen(),
    );
  }
}
