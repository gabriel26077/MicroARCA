// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../services/micropython_repl_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final MicroPythonREPLService _replService = MicroPythonREPLService();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  String _status = 'Não conectado';
  bool _isConnected = false;
  bool _isConnecting = false;


  @override
  void initState() {
    super.initState();
    
    // ✅ PRÉ-PREENCHER OS CAMPOS COM VALORES PADRÃO
    _ipController.text = '192.168.1.80';
    _passwordController.text = 'admin';
    
    // Ouvir atualizações de status do serviço
    _replService.onStatusUpdate.listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
    
    _replService.onConnectionChanged.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _isConnecting = false;
        });
      }
    });
  }
  
  Future<void> _connectToDevice() async {
    final ip = _ipController.text.trim();
    final password = _passwordController.text.trim();
    
    if (ip.isEmpty) {
      _showSnackBar('Por favor, insira o IP do dispositivo');
      return;
    }
    
    setState(() => _isConnecting = true);
    
    final success = await _replService.connect(ip, password);
    
    if (success && _replService.isConnected) {
      _showSnackBar('Conectado com sucesso!');
      // Opcional: Navegar para a próxima página automaticamente
      // Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage()));
    } else {
      _showSnackBar('Falha na conexão');
    }
  }
  
  void _disconnectFromDevice() {
    _replService.disconnect();
    setState(() {
      _isConnected = false;
      _isConnecting = false;
    });
    _showSnackBar('Desconectado');
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 2),
      ),
    );
  }

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

              // Status da conexão
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isConnected 
                    ? const Color(0xFFE8F5E8) 
                    : _isConnecting 
                      ? const Color(0xFFFFF8E1)
                      : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isConnected 
                      ? const Color(0xFF4CAF50) 
                      : _isConnecting 
                        ? const Color(0xFFFFC107)
                        : const Color(0xFFF44336),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected 
                        ? Icons.check_circle 
                        : _isConnecting 
                          ? Icons.sync
                          : Icons.error_outline,
                      color: _isConnected 
                        ? const Color(0xFF4CAF50) 
                        : _isConnecting 
                          ? const Color(0xFFFFC107)
                          : const Color(0xFFF44336),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _isConnected 
                          ? const Color(0xFF2E7D32) 
                          : _isConnecting 
                            ? const Color(0xFFF57C00)
                            : const Color(0xFFC62828),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Responsive container
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
                              controller: _ipController,
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
                              controller: _passwordController,
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

                            if (!_isConnected && !_isConnecting)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _connectToDevice,
                                  icon: const Icon(Icons.link, color: Colors.black87, size: 20),
                                  label: const Text(
                                    "Conectar ao Dispositivo",
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

                            if (_isConnecting)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: null,
                                  icon: const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                                    strokeWidth: 2,
                                  ),
                                  label: const Text(
                                    "Conectando...",
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFF59D),
                                    minimumSize: const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),

                            if (_isConnected)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _disconnectFromDevice,
                                  icon: const Icon(Icons.link_off, color: Colors.white, size: 20),
                                  label: const Text(
                                    "Desconectar",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF44336),
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
                        "Dica: Certifique-se de que seu ESP32 está na mesma rede e o WebREPL está habilitado!",
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

  @override
  void dispose() {
    
    _ipController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}