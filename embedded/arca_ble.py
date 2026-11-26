"""REPL por BLE: uma conexão, RX com resposta e TX com indications.

Não usa asyncio nem reserva timers do aluno. Não bloqueia dentro de dupterm.
Se o consumidor não acompanhar a saída, encerra a conexão em vez de corromper
silenciosamente o protocolo. A serial USB/UART continua disponível.
"""
import bluetooth
import io
import machine
import micropython
import os
from binascii import hexlify
from micropython import const

_CONNECT = const(1)
_DISCONNECT = const(2)
_WRITE = const(3)
_INDICATE_DONE = const(20)
_MTU_EXCHANGED = const(21)
_POLL = const(3)
_POLL_RD = const(1)
_RX_LIMIT = const(2048)
_TX_LIMIT = const(16384)
_PACKET = const(20)  # Também funciona com MTU padrão 23.

SERVICE_UUID = bluetooth.UUID("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
RX_UUID = bluetooth.UUID("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
TX_UUID = bluetooth.UUID("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
CONTROL_UUID = bluetooth.UUID("6e400004-b5a3-f393-e0a9-e50e24dcca9e")


class ArcaBLE(io.IOBase):
    def __init__(self):
        self.name = "ARCA-" + hexlify(machine.unique_id()[-3:]).decode().upper()
        self._ble = bluetooth.BLE()
        self._ble.active(True)
        self._ble.config(gap_name=self.name)
        self._ble.config(mtu=247)
        self._conn = None
        self._ready = False
        self._handshake = True
        self._packet = _PACKET
        self._rx = bytearray()
        self._tx = bytearray()
        self._inflight = 0
        self._scheduled = False
        self._flush_ref = self._flush
        self.last_error = None
        ((self._rx_handle, self._tx_handle, self._control_handle),) = (
            self._ble.gatts_register_services(((SERVICE_UUID, (
                (RX_UUID, bluetooth.FLAG_WRITE),
                (TX_UUID, bluetooth.FLAG_INDICATE),
                (CONTROL_UUID, bluetooth.FLAG_WRITE),
            )),))
        )
        self._ble.gatts_set_buffer(self._rx_handle, 256, True)
        self._ble.irq(self._irq)
        self._advertisement = b"\x02\x01\x06\x11\x07" + bytes(SERVICE_UUID)
        name = self.name.encode()
        self._scan_response = bytes((len(name) + 1, 0x09)) + name
        self._advertise()

    def _advertise(self):
        self._ble.gap_advertise(100000, adv_data=self._advertisement,
                                resp_data=self._scan_response)

    def _fail(self, reason):
        # Sem print: este método também é chamado pelo próprio console.
        self.last_error = reason
        self._ready = False
        self._rx = bytearray()
        self._tx = bytearray()
        self._inflight = 0
        if self._conn is not None:
            try:
                self._ble.gap_disconnect(self._conn)
            except OSError:
                pass

    def _schedule(self):
        if self._scheduled or self._inflight or not self._ready or not self._tx:
            return
        self._scheduled = True
        try:
            micropython.schedule(self._flush_ref, None)
        except RuntimeError:
            self._scheduled = False
            self._fail("Fila de callbacks cheia")

    def _flush(self, _):
        self._scheduled = False
        if not self._ready or self._conn is None or self._inflight or not self._tx:
            return
        self._inflight = min(self._packet, len(self._tx))
        try:
            self._ble.gatts_indicate(self._conn, self._tx_handle,
                                     self._tx[:self._inflight])
        except OSError:
            if self._handshake:
                # O Android pode ainda estar habilitando o CCCD. O app repete
                # o hello até receber a indication, sem depender de um sleep.
                self._inflight = 0
                self._tx = bytearray()
                self._ready = False
            else:
                self._fail("Falha no envio BLE")

    def _irq(self, event, data):
        if event == _CONNECT:
            conn = data[0]
            if self._conn is not None:
                self._ble.gap_disconnect(conn)
                return
            self._conn = conn
            self._ready = False
            self._handshake = True
            self._packet = _PACKET
            self._ble.gap_advertise(None)
        elif event == _DISCONNECT and data[0] == self._conn:
            self._conn = None
            self._ready = False
            self._rx = bytearray()
            self._tx = bytearray()
            self._inflight = 0
            self._advertise()
        elif event == _WRITE and data[0] == self._conn:
            handle = data[1]
            if handle == self._control_handle:
                value = self._ble.gatts_read(handle)
                if value == b"R" and not self._inflight:
                    # Uma nova sessão do app pode reutilizar a conexão BLE.
                    # Não dependa de outro CONNECT para identificar o canal.
                    # Uma indication em voo termina antes de aceitar a repetição.
                    self._handshake = True
                    self._ready = True
                    self._tx = bytearray()
                    self.write(b"ARCA-BLE/1\n")
                elif value == b"A" and self._ready:
                    self._handshake = False
            elif handle == self._rx_handle:
                incoming = self._ble.gatts_read(handle)
                if not self._ready:
                    return
                if len(self._rx) + len(incoming) > _RX_LIMIT:
                    self._fail("Entrada BLE excedeu o buffer")
                    return
                self._rx.extend(incoming)
                os.dupterm_notify(None)
        elif event == _MTU_EXCHANGED and data[0] == self._conn:
            self._packet = max(_PACKET, min(244, data[1] - 3))
        elif event == _INDICATE_DONE and data[0] == self._conn:
            if data[1] != self._tx_handle or not self._inflight:
                return
            if data[2] != 0:
                if self._handshake:
                    self._inflight = 0
                    self._tx = bytearray()
                    self._ready = False
                else:
                    self._fail("Saída BLE não confirmada")
                return
            self._tx = self._tx[self._inflight:]
            self._inflight = 0
            self._schedule()

    def readinto(self, buf):
        if not self._rx:
            return None
        count = min(len(buf), len(self._rx))
        buf[:count] = self._rx[:count]
        self._rx = self._rx[count:]
        return count

    def write(self, buf):
        if not self._ready:
            return len(buf)
        if len(self._tx) + len(buf) > _TX_LIMIT:
            self._fail("Console excedeu o buffer; reduza a frequência de print")
            return len(buf)
        self._tx.extend(buf)
        self._schedule()
        return len(buf)

    def ioctl(self, op, arg):
        if op == _POLL:
            return _POLL_RD if self._rx else 0
        return 0
