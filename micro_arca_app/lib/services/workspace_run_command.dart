/// Run cleanup hooks even on KeyboardInterrupt, including on older kit firmware.
/// Libraries opt in with __arca_cleanup__; unrelated modules are left alone.
const workspaceRunCommand = r'''
import sys
_arca_path = _arca_files.workspace_prepare_run()
try:
 exec(compile(open(_arca_path).read(), _arca_path, 'exec'), {'__name__': '__main__', '__file__': _arca_path, 'input': _arca_input})
finally:
 for _arca_module in list(sys.modules.values()):
  _arca_cleanup = getattr(_arca_module, '__arca_cleanup__', None)
  if callable(_arca_cleanup):
   try:
    _arca_cleanup()
   except Exception as _arca_error:
    print('Falha ao liberar biblioteca:', _arca_error)
''';
