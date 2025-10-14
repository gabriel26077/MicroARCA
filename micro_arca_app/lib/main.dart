import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 1. Importe o pacote de serviços
import 'package:micro_arca_app/screens/main_screen.dart';

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
      theme: ThemeData(
        scaffoldBackgroundColor: const Color.fromARGB(249, 227, 251, 255),
      ),
      home: const MainScreen(),
    );
  }
}

