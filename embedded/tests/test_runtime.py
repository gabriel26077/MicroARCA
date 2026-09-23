import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'arca_runtime.py'


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.previous = os.getcwd()
        self.directory = tempfile.TemporaryDirectory()
        os.chdir(self.directory.name)
        spec = importlib.util.spec_from_file_location('arca_runtime_test', SOURCE)
        self.runtime = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runtime)
        self.sync = patch.object(
            self.runtime.os, 'sync', lambda: None, create=True
        )
        self.sync.start()
        # LittleFS substitui o destino com rename; no Windows, os.replace
        # reproduz essa semântica para o teste executado no computador.
        self.rename = patch.object(self.runtime.os, 'rename', os.replace)
        self.rename.start()
        Path('user.py').write_bytes(b'previous program')

    def tearDown(self):
        self.runtime.abort()
        self.rename.stop()
        self.sync.stop()
        os.chdir(self.previous)
        self.directory.cleanup()

    def begin(self, content):
        self.runtime.begin(len(content), hashlib.sha256(content).hexdigest())

    def test_success_replaces_previous_file_only_after_verified_finish(self):
        content = 'print("ação 🚀")\n'.encode()
        self.begin(content)
        for byte in content:
            self.runtime.append(bytes([byte]).hex())
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')
        self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), content)
        self.assertFalse(Path('user.py.part').exists())

    def test_missing_chunk_preserves_previous_program(self):
        self.begin(b'1234')
        self.runtime.append(b'12'.hex())
        with self.assertRaises(ValueError):
            self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')

    def test_wrong_hash_preserves_previous_program(self):
        self.begin(b'1234')
        self.runtime.append(b'4321'.hex())
        with self.assertRaises(ValueError):
            self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')

    def test_extra_chunk_aborts(self):
        self.begin(b'1')
        with self.assertRaises(ValueError):
            self.runtime.append(b'12'.hex())
        self.assertFalse(Path('user.py.part').exists())

    def test_new_upload_discards_interrupted_upload(self):
        self.begin(b'old partial')
        self.runtime.append(b'old'.hex())
        self.begin(b'new')
        self.runtime.append(b'new'.hex())
        self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), b'new')

    def test_size_limit_rejected_before_file_changes(self):
        with self.assertRaises(ValueError):
            self.runtime.begin(65537, '0' * 64)
        self.assertFalse(Path('user.py.part').exists())
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')

    def test_rename_failure_preserves_previous_program(self):
        self.begin(b'new')
        self.runtime.append(b'new'.hex())
        with patch.object(self.runtime.os, 'rename', side_effect=OSError('disk')):
            with self.assertRaises(OSError):
                self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')

    def test_reads_back_file_before_commit(self):
        self.begin(b'new')
        self.runtime.append(b'new'.hex())
        self.runtime._file.flush()
        Path('user.py.part').write_bytes(b'bad')
        with self.assertRaises(ValueError):
            self.runtime.finish()
        self.assertEqual(Path('user.py').read_bytes(), b'previous program')


if __name__ == '__main__':
    unittest.main()
