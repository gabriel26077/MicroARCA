# boot

import network
import time
import webrepl
import socket
import json
import os
from machine import reset
import gc

# Configurações
AP_SSID = 'MicroArca-Config'
AP_PASSWORD = 'config123' 
CONFIG_FILE = 'wifi_config.json'
BUFFER_FILE = 'buffer_conf.json'

# ========== GERENCIAMENTO DE RESETS ==========
def gerenciar_reset_counter():
    """Gerencia o contador de resets rápidos"""
    try:
        # Carrega ou cria o buffer
        if BUFFER_FILE in os.listdir():
            with open(BUFFER_FILE, 'r') as f:
                buffer = json.load(f)
        else:
            buffer = {'reset_acc': 0}
        
        # Incrementa o contador
        buffer['reset_acc'] += 1
        reset_count = buffer['reset_acc']
        
        # Salva imediatamente
        with open(BUFFER_FILE, 'w') as f:
            json.dump(buffer, f)
        
        print(f"🔄 Reset counter: {reset_count}")
        
        # Aguarda 5 segundos para possíveis resets rápidos
        print("⏳ Aguardando 5 segundos...")
        time.sleep(5)
        
        # Verifica se deve entrar em modo configuração
        if reset_count >= 3:
            print("🎛️  Modo Configuração (3+ resets detectados)")
            # Zera o contador
            buffer['reset_acc'] = 0
            with open(BUFFER_FILE, 'w') as f:
                json.dump(buffer, f)
            return True
        else:
            print("⚡ Modo Normal")
            # Zera o contador
            buffer['reset_acc'] = 0
            with open(BUFFER_FILE, 'w') as f:
                json.dump(buffer, f)
            return False
            
    except Exception as e:
        print(f"❌ Erro no gerenciamento de reset: {e}")
        return False

# ========== CONEXÃO WiFi ==========
def conectar_wifi_simples(ssid, password, ip_fixo=None):
    """Conecta ao WiFi"""
    print(f"📡 Conectando a: {ssid}")
    
    sta = network.WLAN(network.STA_IF)
    sta.active(True)
    sta.disconnect()
    time.sleep(2)
    
    if ip_fixo:
        sta.ifconfig(ip_fixo)
        print(f"🎯 IP Fixo: {ip_fixo[0]}")
    else:
        print("🌐 Usando DHCP")
    
    sta.connect(ssid, password)
    
    max_wait = 20
    while max_wait > 0:
        if sta.isconnected():
            break
        print("⏳ Aguardando conexão...")
        time.sleep(1)
        max_wait -= 1
    
    if sta.isconnected():
        ip = sta.ifconfig()[0]
        print(f"✅ Conectado! IP: {ip}")
        return True, ip
    else:
        print("❌ Timeout na conexão WiFi")
        return False, None

def obter_configuracao_ip_fixo(ip_dhcp):
    """Converte IP DHCP para configuração IP fixo"""
    # Analisa o IP obtido via DHCP para criar IP fixo na mesma rede
    partes = ip_dhcp.split('.')
    if len(partes) == 4:
        # Mantém a mesma rede, usa .80 no último octeto
        ip_fixo = f"{partes[0]}.{partes[1]}.{partes[2]}.80"
        mascara = "255.255.255.0"
        gateway = f"{partes[0]}.{partes[1]}.{partes[2]}.1"
        dns = "8.8.8.8"
        
        return (ip_fixo, mascara, gateway, dns)
    else:
        # Fallback se não conseguir parsear o IP
        return ('192.168.1.80', '255.255.255.0', '192.168.1.1', '8.8.8.8')

def salvar_configuracao(ssid, password, ip_dhcp):
    """Salva configuração WiFi COM IP FIXO baseado no DHCP"""
    # Converte o IP DHCP para configuração IP fixo
    ip_fixo_config = obter_configuracao_ip_fixo(ip_dhcp)
    
    config = {
        'ssid': ssid,
        'password': password,
        'ip_fixo': ip_fixo_config,  # ⚠️ AGORA salva IP fixo
        'timestamp': time.time()
    }
    
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f)
        print(f"💾 Config salva: {ssid}")
        print(f"📍 IP Fixo: {ip_fixo_config[0]}")
        return True
    except Exception as e:
        print(f"❌ Erro ao salvar: {e}")
        return False

def carregar_configuracao():
    """Carrega configuração do arquivo"""
    try:
        if CONFIG_FILE in os.listdir():
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"❌ Erro ao carregar config: {e}")
    return None

def tentar_conexao_salva():
    """Tenta conectar usando configuração salva - COM IP FIXO"""
    config = carregar_configuracao()
    
    if config and config.get('ssid'):
        ssid = config['ssid']
        password = config['password']
        ip_fixo = config.get('ip_fixo')
        
        print(f"🔄 Tentando conexão salva: {ssid}")
        if ip_fixo:
            print(f"📍 Com IP fixo: {ip_fixo[0]}")
        
        success, ip = conectar_wifi_simples(ssid, password, ip_fixo)
        
        if success:
            return True, ip
    
    return False, None

# ========== WEBREPL NORMAL ==========
def iniciar_webrepl(ip):
    """Inicia WebREPL normalmente"""
    print("🚀 Iniciando WebREPL...")
    
    # Limpeza
    gc.collect()
    ap = network.WLAN(network.AP_IF)
    ap.active(False)
    
    print(f"🌐 WebREPL: http://{ip}:8266")
    print("🔑 Senha: admin")
    
    webrepl.start(password="admin")
    
    # Mantém o programa rodando sem travar
    print("💤 Sistema ativo - WebREPL rodando...")

# ========== SERVIDOR DE CONFIGURAÇÃO ==========
def scan_wifi():
    """Escaneia redes WiFi"""
    print("🔍 Escaneando redes...")
    try:
        sta = network.WLAN(network.STA_IF)
        sta.active(True)
        networks = sta.scan()
        result = []
        for net in networks:
            try:
                ssid = net[0].decode('utf-8')
                if ssid and ssid not in result:
                    result.append(ssid)
            except:
                pass
        print(f"✅ {len(result)} redes encontradas")
        return sorted(result)
    except Exception as e:
        print(f"❌ Erro scan: {e}")
        return []

def get_html(networks=None, status=""):
    """Gera página HTML"""
    networks_html = ""
    if networks:
        for net in networks:
            networks_html += f'<option value="{net}">{net}</option>'
    else:
        networks_html = '<option value="">-- Nenhuma rede --</option>'
    
    return f"""HTTP/1.1 200 OK
Content-Type: text/html

<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
function connectWifi() {{
    var ssid = document.getElementById('ssid').value;
    var password = document.getElementById('password').value;
    var button = document.getElementById('connectBtn');
    
    if (!ssid) {{
        alert('Selecione uma rede WiFi');
        return;
    }}
    
    button.innerHTML = '⏳ Conectando...';
    button.disabled = true;
    
    fetch('/connect', {{
        method: 'POST',
        headers: {{'Content-Type': 'application/json'}},
        body: JSON.stringify({{ssid: ssid, password: password}})
    }})
    .then(r => r.json())
    .then(data => {{
        if (data.success) {{
            document.body.innerHTML = [
                '<div style="font-family: Arial; padding: 20px; text-align: center; background: #4CAF50; color: white; min-height: 100vh;">',
                '<h1>✅ Conectado!</h1>',
                '<p><b>IP:</b> ' + data.ip + '</p>',
                '<p><b>IP Fixo Salvo:</b> ' + data.ip_fixo + '</p>',
                '<p><b>WebREPL:</b> http://' + data.ip_fixo + ':8266</p>',
                '<p>Desligando AP em 5 segundos...</p>',
                '</div>'
            ].join('');
        }} else {{
            alert('Erro: ' + data.error);
            button.innerHTML = '📡 Conectar';
            button.disabled = false;
        }}
    }})
    .catch(error => {{
        alert('Erro de rede: ' + error);
        button.innerHTML = '📡 Conectar';
        button.disabled = false;
    }});
}}

function scanNetworks() {{
    var button = document.getElementById('scanBtn');
    button.innerHTML = '🔍 Escaneando...';
    button.disabled = true;
    
    fetch('/scan')
    .then(r => r.text())
    .then(html => {{
        document.documentElement.innerHTML = html;
    }})
    .catch(error => {{
        alert('Erro ao escanear: ' + error);
        button.innerHTML = '🔍 Escanear Redes';
        button.disabled = false;
    }});
}}
</script>
</head>
<body style="font-family: Arial; margin: 20px;">
<h1>🤖 MicroArca - Config WiFi</h1>
<p><b>Status:</b> {status}</p>

<div>
    <label>Rede WiFi:</label><br>
    <select id="ssid" style="width: 100%; padding: 8px; margin: 5px 0;">
    {networks_html}
    </select><br><br>

    <label>Senha:</label><br>
    <input type="password" id="password" style="width: 100%; padding: 8px; margin: 5px 0;" placeholder="Digite a senha WiFi"><br><br>

    <button id="connectBtn" onclick="connectWifi()" style="background: #4CAF50; color: white; padding: 10px; border: none; width: 100%;">
        📡 Conectar
    </button>
</div>

<br>
<button id="scanBtn" onclick="scanNetworks()" style="background: #2196F3; color: white; padding: 10px; border: none; width: 100%;">
    🔍 Escanear Redes
</button>

<p style="color: #666; font-size: 12px; margin-top: 20px;">
💡 Para sair do modo configuração: Reinicie 3x rapidamente
</p>
</body>
</html>"""

def config_server():
    """Servidor web de configuração"""
    print("🌐 Servidor de configuração: http://192.168.4.1")
    
    # Configura AP
    ap = network.WLAN(network.AP_IF)
    ap.active(True)
    ap.config(essid=AP_SSID, password=AP_PASSWORD)
    time.sleep(2)
    
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', 80))
    s.listen(5)
    
    networks = []
    status = "Conecte-se a uma rede WiFi"
    
    while True:
        try:
            client, addr = s.accept()
            request = client.recv(1024).decode('utf-8', 'ignore')
            
            if 'GET / ' in request:
                client.send(get_html(networks, status).encode())
                
            elif 'GET /scan' in request:
                networks = scan_wifi()
                status = f"{len(networks)} redes encontradas"
                client.send(get_html(networks, status).encode())
                
            elif 'POST /connect' in request:
                if '\r\n\r\n' in request:
                    body = request.split('\r\n\r\n')[1]
                    try:
                        data = json.loads(body)
                        
                        ssid = data.get('ssid', '')
                        password = data.get('password', '')
                        
                        if ssid:
                            print(f"🔗 Tentando conectar: {ssid}")
                            
                            # ⚠️ MODO CONFIGURAÇÃO: Usa DHCP para descobrir a rede
                            success, ip_dhcp = conectar_wifi_simples(ssid, password, None)
                            
                            if success:
                                # ⚠️ CORREÇÃO: Salva com IP FIXO baseado no IP DHCP
                                ip_fixo_config = obter_configuracao_ip_fixo(ip_dhcp)
                                salvar_configuracao(ssid, password, ip_dhcp)
                                
                                response = json.dumps({
                                    'success': True,
                                    'ip': ip_dhcp,
                                    'ip_fixo': ip_fixo_config[0],
                                    'message': 'Conectado com sucesso!'
                                })
                                client.send(('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n' + response).encode())
                                client.close()
                                
                                # Aguarda 5 segundos antes de desligar o AP
                                print(f"✅ Conexão bem-sucedida! IP DHCP: {ip_dhcp}")
                                print(f"📍 IP Fixo salvo: {ip_fixo_config[0]}")
                                print("⏳ Aguardando 5 segundos antes de desligar AP...")
                                time.sleep(5)
                                
                                # Fecha tudo e reinicia
                                s.close()
                                ap.active(False)
                                time.sleep(2)
                                
                                print("🔄 Reiniciando para modo normal...")
                                reset()
                                return
                            else:
                                status = f"Falha na conexão com {ssid}"
                                response = json.dumps({
                                    'success': False,
                                    'error': 'Falha na conexão WiFi'
                                })
                                client.send(('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n' + response).encode())
                        else:
                            status = "Selecione uma rede"
                            client.send(get_html(networks, status).encode())
                    except Exception as e:
                        print(f"❌ Erro JSON: {e}")
                        status = "Erro nos dados"
                        client.send(get_html(networks, status).encode())
                
            else:
                client.send(get_html(networks, status).encode())
                
            client.close()
            
        except Exception as e:
            print(f"❌ Erro servidor: {e}")
            try:
                client.close()
            except:
                pass

# ========== MAIN ==========
def main():
    print("=" * 50)
    print("🤖 MicroArca - Sistema WiFi Inteligente")
    print("=" * 50)
    
    # Verifica modo via contador de resets
    modo_config = gerenciar_reset_counter()
    
    if modo_config:
        print("🎛️  Iniciando modo configuração...")
        print("📡 Modo: DHCP (para descobrir rede)")
        config_server()
    else:
        print("⚡ Iniciando modo normal...")
        print("📍 Modo: IP FIXO (usando configuração salva)")
        success, ip = tentar_conexao_salva()
        
        if success:
            print(f"✅ Conectado! IP: {ip}")
            iniciar_webrepl(ip)
            
            # Mantém o programa rodando
            while True:
                time.sleep(10)
                gc.collect()
        else:
            print("❌ Falha na conexão - Entre em modo configuração (3 resets rápidos)")
            # Mantém o programa rodando mesmo sem WiFi
            while True:
                time.sleep(10)
                gc.collect()

# Executa
if __name__ == "__main__":
    main()