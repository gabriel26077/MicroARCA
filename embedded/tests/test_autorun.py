import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / 'arca_files.py'


class AutorunTests(unittest.TestCase):
    def setUp(self):
        self.previous = os.getcwd()
        self.directory = tempfile.TemporaryDirectory()
        os.chdir(self.directory.name)
        spec = importlib.util.spec_from_file_location('arca_files_autorun', SOURCE)
        self.files = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.files)
        self.patches = [
            patch.object(self.files.os, 'sync', lambda: None, create=True),
            patch.object(
                self.files.os,
                'statvfs',
                lambda _: (4096, 4096, 100, 50, 50, 0, 0, 0, 0, 255),
                create=True,
            ),
            patch.object(self.files.os, 'rename', os.replace),
            patch.object(self.files, '_skip_requested', lambda: False),
            patch.object(self.files, '_mark_healthy_later', lambda: None),
            patch.object(self.files, '_ROOT', os.getcwd() + os.sep),
        ]
        for active in self.patches:
            active.start()
        Path('app').mkdir()

    def tearDown(self):
        for active in reversed(self.patches):
            active.stop()
        os.chdir(self.previous)
        self.directory.cleanup()

    def write_app(self, name, content):
        Path('app', name).write_text(content, encoding='utf-8')

    def state(self):
        return json.loads(Path('.arca-autorun.json').read_text())

    def test_enable_freezes_a_copy_of_the_project(self):
        self.write_app('main.py', 'import ajuda\n')
        self.write_app('ajuda.py', 'VALOR = 1\n')
        status = self.files.autorun_enable()
        self.assertTrue(status['enabled'])
        self.assertTrue(status['installed'])
        self.assertEqual(sorted(status['files']), ['ajuda.py', 'main.py'])
        self.write_app('ajuda.py', 'VALOR = 2\n')
        self.assertEqual(
            Path('autorun/ajuda.py').read_text(encoding='utf-8'), 'VALOR = 1\n'
        )

    def test_boot_runs_frozen_program_and_resets_counter(self):
        self.write_app('ajuda.py', 'VALOR = 7\n')
        self.write_app(
            'main.py',
            'import json, ajuda\n'
            'boots = json.load(open(".arca-autorun.json"))["boots"]\n'
            'open("saida.txt", "w").write(str(ajuda.VALOR) + ":" + str(boots))\n',
        )
        self.files.autorun_enable()
        self.files.autorun_boot()
        # O contador sobe antes do programa e volta a zero quando ele termina.
        self.assertEqual(Path('saida.txt').read_text(), '7:1')
        self.assertEqual(self.state()['boots'], 0)
        self.assertNotIn(os.getcwd() + os.sep + 'autorun', self.files.sys.path)

    def test_program_error_propagates_and_is_not_counted_as_reset(self):
        self.write_app('main.py', 'raise ValueError("falhou")\n')
        self.files.autorun_enable()
        with self.assertRaises(ValueError):
            self.files.autorun_boot()
        self.assertEqual(self.state()['boots'], 0)
        self.assertTrue(self.state()['enabled'])

    def test_repeated_resets_disable_autorun_without_running(self):
        self.write_app('main.py', 'open("rodou.txt", "w").write("sim")\n')
        self.files.autorun_enable()
        state = self.state()
        state['boots'] = self.files.AUTORUN_MAX_FAILED_BOOTS
        Path('.arca-autorun.json').write_text(json.dumps(state))
        self.files.autorun_boot()
        self.assertFalse(Path('rodou.txt').exists())
        status = self.files.autorun_status()
        self.assertFalse(status['enabled'])
        self.assertTrue(status['tripped'])

    def test_boot_button_skips_program_without_counting(self):
        self.write_app('main.py', 'open("rodou.txt", "w").write("sim")\n')
        self.files.autorun_enable()
        with patch.object(self.files, '_skip_requested', lambda: True):
            self.files.autorun_boot()
        self.assertFalse(Path('rodou.txt').exists())
        self.assertEqual(self.state()['boots'], 0)
        self.assertTrue(self.state()['enabled'])

    def test_disabled_or_missing_state_runs_nothing(self):
        self.write_app('main.py', 'open("rodou.txt", "w").write("sim")\n')
        self.files.autorun_boot()
        self.files.autorun_enable()
        self.files.autorun_disable()
        self.files.autorun_boot()
        self.assertFalse(Path('rodou.txt').exists())
        self.assertFalse(Path('autorun').exists())
        self.assertFalse(self.files.autorun_status()['installed'])

    def test_mark_healthy_resets_counter(self):
        self.write_app('main.py', 'pass\n')
        self.files.autorun_enable()
        state = self.state()
        state['boots'] = 2
        Path('.arca-autorun.json').write_text(json.dumps(state))
        self.files.autorun_mark_healthy()
        self.assertEqual(self.state()['boots'], 0)

    def test_failed_copy_keeps_previous_snapshot(self):
        self.write_app('main.py', 'VERSAO = 1\n')
        self.files.autorun_enable()
        self.write_app('main.py', 'VERSAO = 2\n')
        self.write_app('extra.py', 'pass\n')
        original = self.files._copy_file
        calls = []

        def failing_copy(source, target):
            calls.append(source)
            if len(calls) == 2:
                raise OSError('flash cheia')
            original(source, target)

        with patch.object(self.files, '_copy_file', failing_copy):
            with self.assertRaises(OSError):
                self.files.autorun_enable()
        self.assertEqual(
            Path('autorun/main.py').read_text(encoding='utf-8'), 'VERSAO = 1\n'
        )
        self.assertFalse(Path('autorun.part').exists())

    def test_interrupted_swap_is_recovered_on_boot(self):
        self.write_app('main.py', 'open("rodou.txt", "w").write("sim")\n')
        self.files.autorun_enable()
        os.replace('autorun', 'autorun.old')
        self.files.autorun_boot()
        self.assertTrue(Path('autorun/main.py').exists())
        self.assertTrue(Path('rodou.txt').exists())

    def test_rejects_snapshot_without_space(self):
        self.write_app('main.py', 'pass\n')
        with patch.object(
            self.files.os,
            'statvfs',
            lambda _: (4096, 4096, 100, 0, 0, 0, 0, 0, 0, 255),
            create=True,
        ):
            with self.assertRaises(OSError):
                self.files.autorun_enable()
        self.assertFalse(Path('autorun').exists())


    def project(self, **changes):
        info = {'id': 'p1', 'name': 'Semáforo', 'kind': 'blocks', 'revision': 5}
        info.update(changes)
        return info

    def test_project_info_is_recorded_with_the_snapshot(self):
        self.write_app('main.py', 'pass\n')
        self.assertIsNone(self.files.project_info())
        self.files.project_set(self.project())
        self.assertEqual(self.files.project_info(), self.project())
        status = self.files.autorun_enable()
        self.assertEqual(status['project'], self.project())
        # Enviar outro projeto depois não muda o que está gravado para o boot.
        self.files.project_set(self.project(id='p2', kind='python'))
        self.assertEqual(self.files.autorun_status()['project'], self.project())
        self.assertIsNone(self.files.autorun_disable()['project'])

    def test_rejects_invalid_project_info(self):
        invalid = [
            'texto',
            self.project(kind='java'),
            self.project(revision='5'),
            self.project(name=''),
            self.project(id='x' * 65),
            dict(self.project(), extra=1),
        ]
        for info in invalid:
            with self.subTest(info=info):
                with self.assertRaises(ValueError):
                    self.files.project_set(info)
        self.assertIsNone(self.files.project_info())

if __name__ == '__main__':
    unittest.main()
