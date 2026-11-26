import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'arca_ble.py'


class FakeBLE:
    def __init__(self):
        self.values = {}
        self.sent = []
        self.disconnected = []
        self.advertisements = []
        self.fail_indication = False
    def active(self, value): pass
    def config(self, **kwargs): pass
    def gatts_register_services(self, services): return ((10, 11, 12),)
    def gatts_set_buffer(self, *args): pass
    def irq(self, callback): self.callback = callback
    def gap_advertise(self, *args, **kwargs): self.advertisements.append((args, kwargs))
    def gap_disconnect(self, conn): self.disconnected.append(conn)
    def gatts_read(self, handle): return self.values.pop(handle, b'')
    def gatts_indicate(self, conn, handle, data):
        if self.fail_indication:
            raise OSError('CCCD not ready')
        self.sent.append(bytes(data))


class BleTests(unittest.TestCase):
    def setUp(self):
        self.callbacks = []
        self.ble = FakeBLE()
        modules = {
            'bluetooth': types.SimpleNamespace(BLE=lambda: self.ble,
                UUID=lambda value: bytes.fromhex(value.replace('-', '')),
                FLAG_WRITE=8, FLAG_INDICATE=32),
            'machine': types.SimpleNamespace(unique_id=lambda: b'\x01\x02\x03\x04\x05\x06'),
            'micropython': types.SimpleNamespace(const=lambda v: v,
                schedule=lambda fn, arg: self.callbacks.append((fn, arg))),
        }
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location('arca_ble_test', SOURCE)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            self.module = module
            self.stream = module.ArcaBLE()
        self.notify = patch.object(module.os, 'dupterm_notify', create=True)
        self.notified = self.notify.start()
        self.stream._irq(1, (7, 0, b''))
        self.write_control(b'R')
        self.drain()
        self.stream._irq(20, (7, 11, 0))
        self.write_control(b'A')
        self.ble.sent.clear()

    def tearDown(self): self.notify.stop()

    def drain(self):
        while self.callbacks:
            fn, arg = self.callbacks.pop(0)
            fn(arg)

    def write_control(self, data):
        self.ble.values[12] = data
        self.stream._irq(3, (7, 12))

    def test_tx_waits_for_ack_and_preserves_bytes(self):
        data = ('ação\n' * 10).encode()
        self.stream.write(data)
        self.drain()
        self.assertEqual(len(self.ble.sent), 1)
        self.assertEqual(self.ble.sent[0], data[:20])
        while self.stream._tx:
            self.stream._irq(20, (7, 11, 0))
            self.drain()
        self.assertEqual(b''.join(self.ble.sent), data)

    def test_rx_notifies_repl_about_ctrl_c(self):
        self.ble.values[10] = b'\x03'
        self.stream._irq(3, (7, 10))
        self.notified.assert_called_once_with(None)
        buf = bytearray(1)
        self.assertEqual(self.stream.readinto(buf), 1)
        self.assertEqual(buf, b'\x03')
        self.assertIsNone(self.stream.readinto(buf))

    def test_overflow_closes_link_instead_of_silent_truncation(self):
        self.stream.write(b'x' * 16385)
        self.assertEqual(self.ble.disconnected, [7])
        self.assertIn('buffer', self.stream.last_error)
        self.assertFalse(self.stream._ready)

    def test_reconnect_has_no_stale_rx_or_tx(self):
        self.stream.write(b'old')
        self.stream._irq(2, (7, 0, b''))
        self.drain()
        self.assertEqual(self.ble.sent, [])
        self.assertFalse(self.stream._rx)
        self.assertFalse(self.stream._tx)
        self.assertFalse(self.stream._ready)
        self.assertEqual(self.ble.advertisements[-1][0], (100000,))

    def test_second_client_is_rejected(self):
        self.stream._irq(1, (8, 0, b''))
        self.assertEqual(self.ble.disconnected, [8])
        self.assertEqual(self.stream._conn, 7)

    def test_hello_restarts_session_on_existing_connection(self):
        # O Android pode abrir outra sessão GATT sem um novo evento CONNECT.
        self.assertFalse(self.stream._handshake)
        self.write_control(b'R')
        self.drain()
        self.assertEqual(self.ble.sent, [b'ARCA-BLE/1\n'])
        self.assertTrue(self.stream._handshake)
        self.stream._irq(20, (7, 11, 0))
        self.write_control(b'A')
        self.assertFalse(self.stream._handshake)
        self.ble.values[10] = b'\x03'
        self.stream._irq(3, (7, 10))
        self.notified.assert_called_once_with(None)

    def test_hello_restart_waits_for_pending_output_confirmation(self):
        self.stream.write(b'contador\n')
        self.drain()
        self.write_control(b'R')
        self.assertEqual(self.ble.sent, [b'contador\n'])
        self.assertEqual(self.stream._inflight, len(b'contador\n'))
        self.stream._irq(20, (7, 11, 0))
        self.write_control(b'R')
        self.drain()
        self.assertEqual(self.ble.sent, [b'contador\n', b'ARCA-BLE/1\n'])
        self.assertTrue(self.stream._handshake)

    def test_failed_indication_invalidates_session(self):
        self.stream.write(b'hello')
        self.drain()
        self.stream._irq(20, (7, 11, 1))
        self.assertEqual(self.ble.disconnected, [7])

    def test_mtu_increases_packets_and_resets_for_next_client(self):
        self.stream._irq(21, (7, 247))
        self.stream.write(b'a' * 300)
        self.drain()
        self.assertEqual(len(self.ble.sent[0]), 244)
        self.stream._irq(2, (7, 0, b''))
        self.stream._irq(1, (8, 0, b''))
        self.assertEqual(self.stream._packet, 20)

    def test_hello_can_retry_until_android_subscribes(self):
        self.stream._irq(2, (7, 0, b''))
        self.stream._irq(1, (7, 0, b''))
        self.ble.fail_indication = True
        self.write_control(b'R')
        self.drain()
        self.assertFalse(self.ble.disconnected)
        self.ble.fail_indication = False
        self.write_control(b'R')
        self.drain()
        self.assertEqual(self.ble.sent[-1], b'ARCA-BLE/1\n')


if __name__ == '__main__':
    unittest.main()
