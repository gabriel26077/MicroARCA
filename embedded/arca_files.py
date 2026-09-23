"""Arquivos seguros do MicroARCA: pacotes oficiais em /lib e projeto em /app.

A API nunca recebe caminhos arbitrários: aceita apenas nomes simples de módulos
Python e mantém os arquivos de infraestrutura da raiz fora do alcance do app.
"""

import binascii
import hashlib
import os
import sys


VERSION = 3
LIB_DIR = "lib"
APP_DIR = "app"
MAX_FILE_SIZE = 65536
_RESERVED = (
    "boot.py",
    "main.py",
    "user.py",
    "arca_ble.py",
    "arca_runtime.py",
    "arca_files.py",
)

_file = None
_name = None
_size = 0
_written = 0
_digest = None
_expected_hash = None
_transaction = False
_staged = []

_workspace_file = None
_workspace_name = None
_workspace_size = 0
_workspace_written = 0
_workspace_digest = None
_workspace_expected_hash = None


def _valid_name(name):
    if not isinstance(name, str) or not name.endswith(".py"):
        return False
    module = name[:-3]
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if not module or module[0] not in letters + "_":
        return False
    return (
        name.lower() not in _RESERVED
        and all(char in letters + "0123456789_" for char in module)
    )


def _checked_name(name):
    if not _valid_name(name):
        raise ValueError("Nome de biblioteca inválido")
    return name


def _ensure_lib_dir():
    try:
        os.mkdir(LIB_DIR)
    except OSError:
        if not (os.stat(LIB_DIR)[0] & 0x4000):
            raise


def _ensure_directory(path):
    try:
        os.mkdir(path)
    except OSError:
        if not (os.stat(path)[0] & 0x4000):
            raise


def _copy_file(source, target):
    with open(source, "rb") as original:
        with open(target, "wb") as copy:
            while True:
                chunk = original.read(256)
                if not chunk:
                    break
                copy.write(chunk)


def _ensure_workspace():
    _ensure_directory(APP_DIR)
    entrypoint = APP_DIR + "/main.py"
    if _exists(entrypoint):
        return
    # Migra o último programa do fluxo antigo sem remover o user.py original.
    if _exists("user.py") and os.stat("user.py")[6] <= MAX_FILE_SIZE:
        _copy_file("user.py", entrypoint)
    else:
        with open(entrypoint, "w") as entry:
            entry.write('# Arquivo principal do projeto MicroARCA\n')
    os.sync()


def _directory_has_name(directory, name):
    try:
        expected = name.lower()
        return any(item.lower() == expected for item in os.listdir(directory))
    except OSError:
        return False


def _path(name):
    return LIB_DIR + "/" + _checked_name(name)


def _part_path(name):
    return LIB_DIR + "/." + _checked_name(name) + ".part"


def _backup_path(name):
    return LIB_DIR + "/." + _checked_name(name) + ".arca-bak"


def _delete_path(name):
    return LIB_DIR + "/." + _checked_name(name) + ".arca-delete"


def _exists(path):
    try:
        os.stat(path)
        return True
    except OSError:
        return False


def _forget_import(name):
    module = name[:-3]
    try:
        del sys.modules[module]
    except KeyError:
        pass


def abort():
    global _file, _name, _transaction, _staged
    if _file is not None:
        _file.close()
        _file = None
    if _name is not None:
        try:
            os.remove(_part_path(_name))
        except OSError:
            pass
    _name = None
    for name in _staged:
        try:
            os.remove(_part_path(name))
        except OSError:
            pass
    _staged = []
    _transaction = False


def _recover_hidden():
    """Conclui a recuperação segura de resets entre renames."""
    try:
        names = os.listdir(LIB_DIR)
    except OSError:
        return
    for hidden in names:
        if hidden.startswith(".") and hidden.endswith(".arca-bak"):
            name = hidden[1:-9]
            if not _valid_name(name):
                continue
            backup = _backup_path(name)
            if _exists(_path(name)):
                try:
                    os.remove(backup)
                except OSError:
                    pass
            else:
                try:
                    os.rename(backup, _path(name))
                except OSError:
                    pass
        elif hidden.startswith(".") and hidden.endswith(".arca-delete"):
            name = hidden[1:-12]
            if _valid_name(name):
                try:
                    os.remove(_delete_path(name))
                except OSError:
                    pass


def _start(name, size, sha256):
    global _file, _name, _size, _written, _digest, _expected_hash
    _checked_name(name)
    if not isinstance(size, int) or not 0 <= size <= MAX_FILE_SIZE:
        raise ValueError("Biblioteca deve ter no máximo 64 KiB")
    if (
        not isinstance(sha256, str)
        or len(sha256) != 64
        or any(char not in "0123456789abcdef" for char in sha256)
    ):
        raise ValueError("SHA-256 inválido")
    _ensure_lib_dir()
    if _directory_has_name(APP_DIR, name):
        raise ValueError("Já existe um arquivo do projeto com esse nome")
    _name = name
    _size = size
    _written = 0
    _expected_hash = sha256
    _digest = hashlib.sha256()
    _file = open(_part_path(name), "wb")


def begin(name, size, sha256):
    abort()
    _start(name, size, sha256)


def transaction_begin():
    global _transaction, _staged
    abort()
    _ensure_lib_dir()
    _recover_hidden()
    _transaction = True
    _staged = []


def transaction_stage(name, size, sha256):
    if not _transaction:
        raise RuntimeError("Transação não iniciada")
    if _file is not None:
        raise RuntimeError("Upload anterior ainda aberto")
    if name in _staged:
        raise ValueError("Biblioteca duplicada na transação")
    _start(name, size, sha256)


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


def _verify_staged_file():
    global _file, _name
    if _file is None or _name is None:
        raise RuntimeError("Upload não iniciado")
    name = _name
    if (
        _written != _size
        or binascii.hexlify(_digest.digest()).decode() != _expected_hash
    ):
        abort()
        raise ValueError("Tamanho ou SHA-256 do upload incorreto")
    _file.close()
    _file = None
    os.sync()

    disk_hash = hashlib.sha256()
    with open(_part_path(name), "rb") as saved:
        while True:
            chunk = saved.read(256)
            if not chunk:
                break
            disk_hash.update(chunk)
    if binascii.hexlify(disk_hash.digest()).decode() != _expected_hash:
        abort()
        raise ValueError("SHA-256 do arquivo gravado incorreto")

    return name


def finish():
    global _name
    if _transaction:
        raise RuntimeError("Use transaction_finish_file")
    name = _verify_staged_file()
    os.rename(_part_path(name), _path(name))
    os.sync()
    _name = None
    _forget_import(name)


def transaction_finish_file():
    global _name, _staged
    if not _transaction:
        raise RuntimeError("Transação não iniciada")
    name = _verify_staged_file()
    _staged.append(name)
    _name = None


def transaction_commit():
    global _transaction, _staged
    if not _transaction or _file is not None:
        raise RuntimeError("Transação incompleta")
    if not _staged:
        raise RuntimeError("Nenhuma biblioteca preparada")
    backups = []
    installed = []
    try:
        for name in _staged:
            target = _path(name)
            backup = _backup_path(name)
            if _exists(backup):
                os.remove(backup)
            if _exists(target):
                os.rename(target, backup)
                backups.append(name)
        for name in _staged:
            os.rename(_part_path(name), _path(name))
            installed.append(name)
        os.sync()
    except Exception:
        for name in installed:
            try:
                os.remove(_path(name))
            except OSError:
                pass
        for name in reversed(backups):
            try:
                os.rename(_backup_path(name), _path(name))
            except OSError:
                pass
        abort()
        os.sync()
        raise
    for name in backups:
        try:
            os.remove(_backup_path(name))
        except OSError:
            pass
    committed = _staged
    _staged = []
    _transaction = False
    os.sync()
    for name in committed:
        _forget_import(name)


def list_files():
    try:
        names = os.listdir(LIB_DIR)
    except OSError:
        return []
    result = []
    for name in names:
        if _valid_name(name):
            path = _path(name)
            try:
                stat = os.stat(path)
                if not (stat[0] & 0x4000):
                    result.append({"name": name, "size": stat[6]})
            except OSError:
                pass
    result.sort(key=lambda item: item["name"].lower())
    return result


def delete(name):
    if _file is not None:
        raise RuntimeError("Upload em andamento")
    os.remove(_path(name))
    os.sync()
    _forget_import(name)


def delete_many(names):
    if _file is not None or _transaction:
        raise RuntimeError("Upload em andamento")
    if not isinstance(names, (list, tuple)) or not names:
        raise ValueError("Lista de bibliotecas inválida")
    checked = []
    for name in names:
        _checked_name(name)
        if name in checked:
            raise ValueError("Biblioteca duplicada")
        checked.append(name)
    _recover_hidden()
    moved = []
    try:
        for name in checked:
            tomb = _delete_path(name)
            if _exists(tomb):
                os.remove(tomb)
            os.rename(_path(name), tomb)
            moved.append(name)
        os.sync()
    except Exception:
        for name in reversed(moved):
            try:
                os.rename(_delete_path(name), _path(name))
            except OSError:
                pass
        os.sync()
        raise
    for name in moved:
        try:
            os.remove(_delete_path(name))
        except OSError:
            pass
        _forget_import(name)
    os.sync()


def filesystem_info():
    values = os.statvfs("/")
    block_size = values[1]
    return {
        "free": block_size * values[4],
        "total": block_size * values[2],
    }


def _workspace_checked_name(name):
    if not isinstance(name, str) or not name.endswith(".py"):
        raise ValueError("Nome de arquivo inválido")
    module = name[:-3]
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if (
        not module
        or module[0] not in letters + "_"
        or any(char not in letters + "0123456789_" for char in module)
        or (name.lower() in _RESERVED and name.lower() != "main.py")
    ):
        raise ValueError("Nome de arquivo inválido")
    return name


def _workspace_path(name):
    return APP_DIR + "/" + _workspace_checked_name(name)


def _workspace_part_path(name):
    return APP_DIR + "/." + _workspace_checked_name(name) + ".arca-part"


def _workspace_backup_path(name):
    return APP_DIR + "/." + _workspace_checked_name(name) + ".arca-bak"


def workspace_abort():
    global _workspace_file, _workspace_name
    if _workspace_file is not None:
        _workspace_file.close()
        _workspace_file = None
    if _workspace_name is not None:
        try:
            os.remove(_workspace_part_path(_workspace_name))
        except OSError:
            pass
    _workspace_name = None


def _workspace_recover(name):
    target = _workspace_path(name)
    backup = _workspace_backup_path(name)
    if _exists(backup):
        if _exists(target):
            os.remove(backup)
        else:
            os.rename(backup, target)


def workspace_begin(name, size, sha256):
    global _workspace_file, _workspace_name, _workspace_size
    global _workspace_written, _workspace_digest, _workspace_expected_hash
    workspace_abort()
    name = _workspace_checked_name(name)
    if not isinstance(size, int) or not 0 <= size <= MAX_FILE_SIZE:
        raise ValueError("Arquivo deve ter no máximo 64 KiB")
    if (
        not isinstance(sha256, str)
        or len(sha256) != 64
        or any(char not in "0123456789abcdef" for char in sha256)
    ):
        raise ValueError("SHA-256 inválido")
    _ensure_workspace()
    if _directory_has_name(LIB_DIR, name):
        raise ValueError("Já existe uma biblioteca oficial com esse nome")
    _workspace_recover(name)
    _workspace_name = name
    _workspace_size = size
    _workspace_written = 0
    _workspace_digest = hashlib.sha256()
    _workspace_expected_hash = sha256
    _workspace_file = open(_workspace_part_path(name), "wb")


def workspace_append(hex_data):
    global _workspace_written
    if _workspace_file is None:
        raise RuntimeError("Upload de arquivo não iniciado")
    data = binascii.unhexlify(hex_data)
    if _workspace_written + len(data) > _workspace_size:
        workspace_abort()
        raise ValueError("Upload maior que o tamanho declarado")
    count = _workspace_file.write(data)
    if count != len(data):
        workspace_abort()
        raise OSError("Gravação incompleta")
    _workspace_digest.update(data)
    _workspace_written += count


def workspace_finish():
    global _workspace_file, _workspace_name
    if _workspace_file is None or _workspace_name is None:
        raise RuntimeError("Upload de arquivo não iniciado")
    name = _workspace_name
    if (
        _workspace_written != _workspace_size
        or binascii.hexlify(_workspace_digest.digest()).decode()
        != _workspace_expected_hash
    ):
        workspace_abort()
        raise ValueError("Tamanho ou SHA-256 do arquivo incorreto")
    _workspace_file.close()
    _workspace_file = None
    os.sync()
    disk_hash = hashlib.sha256()
    with open(_workspace_part_path(name), "rb") as saved:
        while True:
            chunk = saved.read(256)
            if not chunk:
                break
            disk_hash.update(chunk)
    if binascii.hexlify(disk_hash.digest()).decode() != _workspace_expected_hash:
        workspace_abort()
        raise ValueError("SHA-256 do arquivo gravado incorreto")

    target = _workspace_path(name)
    backup = _workspace_backup_path(name)
    had_target = _exists(target)
    try:
        if _exists(backup):
            os.remove(backup)
        if had_target:
            os.rename(target, backup)
        os.rename(_workspace_part_path(name), target)
        os.sync()
    except Exception:
        try:
            if _exists(target):
                os.remove(target)
            if had_target and _exists(backup):
                os.rename(backup, target)
        finally:
            workspace_abort()
            os.sync()
        raise
    if _exists(backup):
        try:
            os.remove(backup)
        except OSError:
            pass
    _workspace_name = None
    _forget_import(name)
    os.sync()


def workspace_list():
    _ensure_workspace()
    result = []
    for name in os.listdir(APP_DIR):
        try:
            _workspace_checked_name(name)
            stat = os.stat(_workspace_path(name))
            if not (stat[0] & 0x4000):
                result.append({"name": name, "size": stat[6]})
        except (OSError, ValueError):
            pass
    result.sort(key=lambda item: (item["name"].lower() != "main.py", item["name"].lower()))
    return result


def workspace_read_chunk(name, offset, size=128):
    name = _workspace_checked_name(name)
    if not isinstance(offset, int) or offset < 0:
        raise ValueError("Posição inválida")
    if not isinstance(size, int) or not 0 < size <= 256:
        raise ValueError("Tamanho de leitura inválido")
    _ensure_workspace()
    with open(_workspace_path(name), "rb") as source:
        source.seek(offset)
        return binascii.hexlify(source.read(size)).decode()


def workspace_delete(name):
    name = _workspace_checked_name(name)
    if name.lower() == "main.py":
        raise ValueError("main.py é o entrypoint e não pode ser excluído")
    if _workspace_file is not None:
        raise RuntimeError("Upload de arquivo em andamento")
    os.remove(_workspace_path(name))
    _forget_import(name)
    os.sync()


def workspace_rename(old_name, new_name):
    old_name = _workspace_checked_name(old_name)
    new_name = _workspace_checked_name(new_name)
    if old_name.lower() == "main.py":
        raise ValueError("main.py é o entrypoint e não pode ser renomeado")
    if old_name.lower() == new_name.lower():
        raise ValueError("Escolha um nome diferente")
    if _workspace_file is not None:
        raise RuntimeError("Upload de arquivo em andamento")
    _ensure_workspace()
    if _directory_has_name(LIB_DIR, new_name):
        raise ValueError("Já existe uma biblioteca oficial com esse nome")
    if _directory_has_name(APP_DIR, new_name):
        raise ValueError("Já existe um arquivo do projeto com esse nome")
    os.rename(_workspace_path(old_name), _workspace_path(new_name))
    _forget_import(old_name)
    _forget_import(new_name)
    os.sync()


def workspace_prepare_run():
    _ensure_workspace()
    app_path = "/" + APP_DIR
    if app_path not in sys.path:
        sys.path.insert(0, app_path)
    # Um novo Run deve importar novamente todos os módulos editáveis do projeto.
    for item in workspace_list():
        module = item["name"][:-3]
        if module != "main":
            try:
                del sys.modules[module]
            except KeyError:
                pass
    return app_path + "/main.py"
