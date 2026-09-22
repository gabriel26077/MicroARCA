"""Upload transacional de user.py. Chamado pelo app através do raw REPL."""
import binascii
import hashlib
import os

MAX_FILE_SIZE = 65536
_file = None
_size = 0
_written = 0
_digest = None
_expected_hash = None


def abort():
    global _file
    if _file is not None:
        _file.close()
        _file = None
    try:
        os.remove("user.py.part")
    except OSError:
        pass


def begin(size, sha256):
    global _file, _size, _written, _digest, _expected_hash
    if not isinstance(size, int) or not 0 <= size <= MAX_FILE_SIZE:
        raise ValueError("Programa deve ter no máximo 64 KiB")
    if len(sha256) != 64 or any(c not in "0123456789abcdef" for c in sha256):
        raise ValueError("SHA-256 inválido")
    abort()
    _size = size
    _written = 0
    _expected_hash = sha256
    _digest = hashlib.sha256()
    _file = open("user.py.part", "wb")


def append(hex_data):
    global _written
    if _file is None:
        raise RuntimeError("Upload não iniciado")
    data = binascii.unhexlify(hex_data)
    if _written + len(data) > _size:
        abort()
        raise ValueError("Upload maior que o tamanho declarado")
    count = _file.write(data)
    if count != len(data):
        abort()
        raise OSError("Gravação incompleta")
    _digest.update(data)
    _written += count


def finish():
    global _file
    if _file is None:
        raise RuntimeError("Upload não iniciado")
    if _written != _size or binascii.hexlify(_digest.digest()).decode() != _expected_hash:
        abort()
        raise ValueError("Tamanho ou SHA-256 do upload incorreto")
    _file.close()
    _file = None
    os.sync()
    # Confere também o conteúdo relido do filesystem antes de substituir user.py.
    disk_hash = hashlib.sha256()
    with open("user.py.part", "rb") as saved:
        while True:
            chunk = saved.read(256)
            if not chunk:
                break
            disk_hash.update(chunk)
    if binascii.hexlify(disk_hash.digest()).decode() != _expected_hash:
        abort()
        raise ValueError("SHA-256 do arquivo gravado incorreto")
    # LittleFS do firmware ESP32 substitui o destino com rename atômico.
    # Nunca remova user.py antes: uma falha deve preservar o programa anterior.
    os.rename("user.py.part", "user.py")
    os.sync()
