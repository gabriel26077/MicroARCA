"""Inicialização curta: BLE REPL, sem rede Wi-Fi ou execução automática."""
import network
import os
from arca_ble import ArcaBLE

# Desativa interfaces que podem ter permanecido ativas após um soft reset.
network.WLAN(network.STA_IF).active(False)
network.WLAN(network.AP_IF).active(False)

# Mantém o transporte vivo depois que boot.py termina.
arca_ble = ArcaBLE()
os.dupterm(arca_ble)
