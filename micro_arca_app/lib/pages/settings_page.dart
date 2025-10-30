import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Página para as configurações do aplicativo.
///
/// Segue a convenção de nomenclatura de classes PascalCase.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: const Alignment(0, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '🛠️ Conexão MicroArca 🛠️',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20.00,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 0, 188, 212),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Configure as conexões do seu ESP32 aqui!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.00,
                  fontWeight: FontWeight.normal,
                  color: Color.fromARGB(255, 96, 172, 184),
                ),
              ),

              const SizedBox(height: 20),

              // Responsive container: largura = min(95% do pai, 600px)
              LayoutBuilder(
                builder: (context, constraints) {
                  final double max = constraints.maxWidth;
                  final double desired = max * 0.95;
                  final double width = math.min(desired, 600);

                  return Center(
                    child: SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromARGB(55, 0, 0, 0),
                              blurRadius: 5,
                              offset: Offset(0, 5),
                            ),
                          ],
                          border: Border.all(
                            color: const Color(0xFF00BCD4),
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.wifi, color: Color(0xFF00BCD4)),
                                SizedBox(width: 8),
                                Text(
                                  "ESP32 IP Address",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF007A8C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            TextField(
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              ],
                              decoration: InputDecoration(
                                hintText: "192.168.1.100",
                                filled: true,
                                fillColor: const Color(0xFFF9FBFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFB0E0E6),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00BCD4),
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),
                            const Text(
                              "Enter the IP address of your ESP32 device",
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7A8A99),
                              ),
                            ),

                            const SizedBox(height: 24),

                            const Row(
                              children: [
                                Icon(Icons.lock, color: Color(0xFF00BCD4)),
                                SizedBox(width: 8),
                                Text(
                                  "WebREPL Password",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF007A8C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            TextField(
                              obscureText: true,
                              decoration: InputDecoration(
                                hintText: "•••••••••",
                                filled: true,
                                fillColor: const Color(0xFFF9FBFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFB0E0E6),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00BCD4),
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "The password for WebREPL access",
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7A8A99),
                              ),
                            ),

                            const SizedBox(height: 28),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.save, color: Colors.black87, size: 20),
                                label: const Text(
                                  "Save Settings",
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFEB3B),
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  elevation: 2,
                                ),
                              ),
                            ),

                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFB2EBF2),
                    width: 1.0,
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, color: Color(0xFFFFC107)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Tip: Make sure your ESP32 is connected to the same network and WebREPL is enabled!",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF007A8C),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}