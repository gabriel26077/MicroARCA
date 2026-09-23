import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / 'arca_files.py'


class LibraryFileTests(unittest.TestCase):
    def setUp(self):
        self.previous = os.getcwd()
        self.directory = tempfile.TemporaryDirectory()
        os.chdir(self.directory.name)
        spec = importlib.util.spec_from_file_location('arca_files_test', SOURCE)
        self.files = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.files)
        self.sync = patch.object(
            self.files.os, 'sync', lambda: None, create=True
        )
        self.sync.start()
        self.statvfs = patch.object(
            self.files.os,
            'statvfs',
            lambda _: (4096, 4096, 100, 50, 50, 0, 0, 0, 0, 255),
            create=True,
        )
        self.statvfs.start()
        self.rename = patch.object(self.files.os, 'rename', os.replace)
        self.rename.start()

    def tearDown(self):
        self.files.abort()
        self.files.workspace_abort()
        self.rename.stop()
        self.statvfs.stop()
        self.sync.stop()
        os.chdir(self.previous)
        self.directory.cleanup()

    def upload(self, name, content):
        digest = hashlib.sha256(content).hexdigest()
        self.files.begin(name, len(content), digest)
        for offset in range(0, len(content), 3):
            self.files.append(content[offset:offset + 3].hex())
        self.files.finish()

    def test_upload_lists_and_deletes_library(self):
        content = b'class PintorOLED:\n    pass\n'
        self.upload('lib_oled_pintor.py', content)
        self.assertEqual(
            self.files.list_files(),
            [{'name': 'lib_oled_pintor.py', 'size': len(content)}],
        )
        self.files.delete('lib_oled_pintor.py')
        self.assertEqual(self.files.list_files(), [])

    def test_rejects_paths_and_non_python_names(self):
        invalid = [
            '../boot.py', '/boot.py', 'boot.py/../main.py', '.hidden.py',
            'two words.py', '1module.py', 'module.mpy', 'package/module.py',
            'módulo.py', 'boot.py', 'main.py', 'user.py', 'arca_files.py',
        ]
        for name in invalid:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    self.files.begin(name, 0, hashlib.sha256(b'').hexdigest())
        self.assertFalse(Path('boot.py').exists())

    def test_interrupted_update_preserves_previous_library(self):
        self.upload('sensor.py', b'VALUE = 1\n')
        content = b'VALUE = 2\n'
        self.files.begin('sensor.py', len(content), hashlib.sha256(content).hexdigest())
        self.files.append(b'VALUE'.hex())
        self.files.abort()
        self.assertEqual(Path('lib/sensor.py').read_bytes(), b'VALUE = 1\n')

    def test_hash_mismatch_preserves_previous_library(self):
        self.upload('sensor.py', b'VALUE = 1\n')
        self.files.begin('sensor.py', 3, hashlib.sha256(b'new').hexdigest())
        self.files.append(b'bad'.hex())
        with self.assertRaises(ValueError):
            self.files.finish()
        self.assertEqual(Path('lib/sensor.py').read_bytes(), b'VALUE = 1\n')

    def test_hidden_and_invalid_files_are_not_listed(self):
        Path('lib').mkdir()
        Path('lib/ok.py').write_text('')
        Path('lib/.arca-lock.json').write_text('{}')
        Path('lib/readme.txt').write_text('')
        Path('lib/package').mkdir()
        self.assertEqual(self.files.list_files(), [{'name': 'ok.py', 'size': 0}])

    def test_size_limit_is_checked_before_creating_lib_directory(self):
        with self.assertRaises(ValueError):
            self.files.begin('large.py', 65537, '0' * 64)
        self.assertFalse(Path('lib').exists())

    def test_filesystem_info_reports_positive_capacity(self):
        info = self.files.filesystem_info()
        self.assertGreater(info['total'], 0)
        self.assertGreater(info['free'], 0)
        self.assertLessEqual(info['free'], info['total'])

    def test_rename_failure_keeps_previous_library(self):
        self.upload('sensor.py', b'old')
        content = b'new'
        self.files.begin('sensor.py', len(content), hashlib.sha256(content).hexdigest())
        self.files.append(content.hex())
        with patch.object(self.files.os, 'rename', side_effect=OSError('disk')):
            with self.assertRaises(OSError):
                self.files.finish()
        self.assertEqual(Path('lib/sensor.py').read_bytes(), b'old')

    def test_transaction_commits_all_files_together(self):
        self.files.transaction_begin()
        for name, content in [('ssd1306.py', b'DRIVER = 1\n'),
                              ('pintor.py', b'import ssd1306\n')]:
            digest = hashlib.sha256(content).hexdigest()
            self.files.transaction_stage(name, len(content), digest)
            self.files.append(content.hex())
            self.files.transaction_finish_file()
        self.assertEqual(self.files.list_files(), [])
        self.files.transaction_commit()
        self.assertEqual(
            [item['name'] for item in self.files.list_files()],
            ['pintor.py', 'ssd1306.py'],
        )

    def test_transaction_abort_preserves_previous_files(self):
        self.upload('sensor.py', b'old')
        content = b'new'
        self.files.transaction_begin()
        self.files.transaction_stage(
            'sensor.py', len(content), hashlib.sha256(content).hexdigest()
        )
        self.files.append(content.hex())
        self.files.transaction_finish_file()
        self.files.abort()
        self.assertEqual(Path('lib/sensor.py').read_bytes(), b'old')

    def test_transaction_commit_failure_rolls_back_every_file(self):
        self.upload('a.py', b'old-a')
        self.upload('b.py', b'old-b')
        self.files.transaction_begin()
        for name, content in [('a.py', b'new-a'), ('b.py', b'new-b')]:
            self.files.transaction_stage(
                name, len(content), hashlib.sha256(content).hexdigest()
            )
            self.files.append(content.hex())
            self.files.transaction_finish_file()
        original_rename = os.replace

        def fail_on_second_install(source, target):
            if source.endswith('.b.py.part'):
                raise OSError('disk')
            return original_rename(source, target)

        with patch.object(self.files.os, 'rename', side_effect=fail_on_second_install):
            with self.assertRaises(OSError):
                self.files.transaction_commit()
        self.assertEqual(Path('lib/a.py').read_bytes(), b'old-a')
        self.assertEqual(Path('lib/b.py').read_bytes(), b'old-b')

    def test_delete_many_rolls_back_if_one_file_is_missing(self):
        self.upload('a.py', b'a')
        with self.assertRaises(OSError):
            self.files.delete_many(['a.py', 'missing.py'])
        self.assertEqual(Path('lib/a.py').read_bytes(), b'a')

    def workspace_upload(self, name, content):
        digest = hashlib.sha256(content).hexdigest()
        self.files.workspace_begin(name, len(content), digest)
        for offset in range(0, len(content), 3):
            self.files.workspace_append(content[offset:offset + 3].hex())
        self.files.workspace_finish()

    def test_workspace_creates_editable_main_and_lists_user_files(self):
        self.assertEqual(
            self.files.workspace_list(),
            [{'name': 'main.py', 'size': 41}],
        )
        self.workspace_upload('sensor.py', b'VALUE = 1\n')
        self.assertEqual(
            [item['name'] for item in self.files.workspace_list()],
            ['main.py', 'sensor.py'],
        )
        self.assertEqual(
            self.files.workspace_read_chunk('sensor.py', 0, 4),
            b'VALU'.hex(),
        )

    def test_workspace_migrates_legacy_user_file_to_main(self):
        Path('user.py').write_bytes(b'print("legado")\n')
        self.files.workspace_list()
        self.assertEqual(Path('app/main.py').read_bytes(), b'print("legado")\n')
        self.assertTrue(Path('user.py').exists())

    def test_workspace_update_is_atomic_and_main_cannot_be_deleted(self):
        self.workspace_upload('main.py', b'print(1)\n')
        content = b'print(2)\n'
        self.files.workspace_begin(
            'main.py', len(content), hashlib.sha256(content).hexdigest()
        )
        self.files.workspace_append(b'bad'.hex())
        with self.assertRaises(ValueError):
            self.files.workspace_finish()
        self.assertEqual(Path('app/main.py').read_bytes(), b'print(1)\n')
        with self.assertRaises(ValueError):
            self.files.workspace_delete('main.py')

    def test_workspace_delete_and_name_protection(self):
        self.workspace_upload('helper.py', b'pass\n')
        self.files.workspace_delete('helper.py')
        self.assertFalse(Path('app/helper.py').exists())
        for name in ('boot.py', 'arca_ble.py', '../main.py', 'dois nomes.py'):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    self.files.workspace_begin(
                        name, 0, hashlib.sha256(b'').hexdigest()
                    )

    def test_workspace_renames_user_file_but_protects_main(self):
        self.workspace_upload('helper.py', b'VALUE = 1\n')
        self.files.workspace_rename('helper.py', 'sensor.py')
        self.assertFalse(Path('app/helper.py').exists())
        self.assertEqual(Path('app/sensor.py').read_bytes(), b'VALUE = 1\n')
        with self.assertRaises(ValueError):
            self.files.workspace_rename('main.py', 'inicio.py')
        self.workspace_upload('outro.py', b'pass\n')
        with self.assertRaises(ValueError):
            self.files.workspace_rename('sensor.py', 'outro.py')

    def test_workspace_and_official_library_names_cannot_collide(self):
        self.upload('display.py', b'OFFICIAL = 1\n')
        with self.assertRaises(ValueError):
            self.workspace_upload('display.py', b'USER = 1\n')

        self.workspace_upload('sensor.py', b'USER = 1\n')
        with self.assertRaises(ValueError):
            self.upload('sensor.py', b'OFFICIAL = 1\n')


if __name__ == '__main__':
    unittest.main()
