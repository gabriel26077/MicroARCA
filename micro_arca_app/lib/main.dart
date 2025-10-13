import 'package:flutter/material.dart';
import 'package:micro_arca_app/widgets/app_bar.dart';


void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        appBar: MyAppBar(),
        body: Center(
          child: Text('Hello World!'),
        ),
      ),
    );
  }
}
