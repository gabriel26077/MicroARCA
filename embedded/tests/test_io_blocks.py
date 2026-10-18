"""Execute the actual Python runtime embedded in the Blockly generator."""
from pathlib import Path
import re
import sys
import types
import unittest
from unittest.mock import patch


class Pin:
    IN, OUT, PULL_UP = 0, 1, 2

    def __init__(self, number, mode, pull=None, value=0):
        self.number, self.mode, self.pull, self.level = number, mode, pull, value

    def value(self, value=None):
        if value is not None:
            self.level = value
        return self.level


class PWM:
    def __init__(self, pin, freq, duty_u16):
        self.pin, self.frequency, self.duty, self.closed = pin, freq, duty_u16, False

    def duty_u16(self, duty):
        self.duty = duty

    def deinit(self):
        self.closed = True


class ADC:
    ATTN_11DB = 3

    def __init__(self, pin):
        self.pin = pin

    def atten(self, value):
        self.attenuation = value

    def read_u16(self):
        return 32768


class IOBlocksTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[2] / 'micro_arca_app/assets/blockly/io_blocks.js'
        runtime = re.search(r'g.definitions_\["%microarca_io"\] = `([\s\S]*?)`;', path.read_text(encoding='utf-8')).group(1)
        self.scope = dict(Pin=Pin, ADC=ADC, PWM=PWM)
        for name in ('pinos', 'modos', 'adcs', 'pwms'):
            self.scope['_microarca_' + name] = {}
        exec(runtime, self.scope)

    def call(self, name, *args):
        return self.scope['_microarca_' + name](*args)

    def test_digital_read_defaults_to_input_and_preserves_pullup(self):
        pin = self.call('obter_pino', 4, Pin.IN)
        self.assertEqual(pin.mode, Pin.IN)
        pin = self.call('configurar_pino', 4, Pin.IN, Pin.PULL_UP)
        self.assertIs(self.call('obter_pino', 4, Pin.IN), pin)
        self.assertEqual(pin.pull, Pin.PULL_UP)

    def test_analog_read_caches_adc_and_switches_back_to_digital(self):
        self.assertEqual(self.call('ler_analogico', 34), 32768)
        adc = self.scope['_microarca_adcs'][34]
        self.call('ler_analogico', 34)
        self.assertIs(adc, self.scope['_microarca_adcs'][34])
        self.assertEqual(adc.attenuation, ADC.ATTN_11DB)
        self.call('obter_pino', 34, Pin.IN)
        self.assertNotIn(34, self.scope['_microarca_adcs'])

    def test_pwm_limits_and_transitions(self):
        self.call('configurar_pwm', 25, 1000)
        pwm = self.scope['_microarca_pwms'][25]
        for percent, expected in ((0, 0), (50, 32768), (100, 65535)):
            self.call('escrever_pwm', 25, percent)
            self.assertEqual(pwm.duty, expected)
        pin = self.call('obter_pino', 25, Pin.OUT)
        self.assertTrue(pwm.closed)
        self.assertEqual(pin.level, 0)
        self.assertNotIn(25, self.scope['_microarca_pwms'])
        self.call('configurar_pwm', 25, 440)
        pwm = self.scope['_microarca_pwms'][25]
        self.call('ler_analogico', 25)
        self.assertTrue(pwm.closed)

    def test_invalid_pins_and_parameters_are_rejected(self):
        for name, args in (
            ('configurar_pwm', (34, 1000)), ('configurar_pwm', (6, 1000)),
            ('configurar_pwm', (25, 0)), ('configurar_pwm', (25, 440.5)),
            ('ler_analogico', (18,)), ('obter_pino', (2.5, Pin.OUT)),
            ('configurar_pino', (34, Pin.IN, Pin.PULL_UP)),
            ('escrever_pwm', (25, 50)),
        ):
            with self.subTest(name=name, args=args), self.assertRaises(ValueError):
                self.call(name, *args)
        self.call('configurar_pwm', 25, 1000)
        for value in (-1, 101, float('nan')):
            with self.assertRaises(ValueError):
                self.call('escrever_pwm', 25, value)

    def test_cleanup_releases_all_channels(self):
        for pin in (25, 26):
            self.call('configurar_pwm', pin, 1000)
        pwms = list(self.scope['_microarca_pwms'].values())
        self.call('finalizar_pwm')
        self.call('finalizar_pwm')
        self.assertTrue(all(pwm.closed and pwm.duty == 0 for pwm in pwms))
        self.assertFalse(self.scope['_microarca_pwms'])


class WorkspaceCleanupTests(unittest.TestCase):
    def test_app_command_cleans_up_on_success_error_and_interrupt(self):
        path = Path(__file__).resolve().parents[2] / 'micro_arca_app/lib/services/workspace_run_command.dart'
        source = path.read_text(encoding='utf-8').split("r'''", 1)[1].split("'''", 1)[0]
        self.assertLessEqual(len(source.encode()), 1024)
        for program, exception in (('pass', None), ('raise ValueError()', ValueError), ('raise KeyboardInterrupt()', KeyboardInterrupt)):
            calls = []
            library = types.SimpleNamespace(__arca_cleanup__=lambda: calls.append('stopped'))
            files = types.SimpleNamespace(workspace_prepare_run=lambda: 'main.py')
            from io import StringIO
            with patch.dict(sys.modules, {'fake_buzzer': library}), patch('builtins.open', return_value=StringIO(program)):
                scope = {'_arca_files': files, '_arca_input': input}
                if exception:
                    with self.assertRaises(exception):
                        exec(source, scope)
                else:
                    exec(source, scope)
            self.assertEqual(calls, ['stopped'])
