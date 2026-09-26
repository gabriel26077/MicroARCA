"""Roda o programa de inicialização, se houver, e devolve o controle ao REPL.

boot.py já ligou o BLE antes deste arquivo, então o app consegue interromper o
programa com Ctrl-C a qualquer momento. Nada aqui pode impedir o REPL de subir.
"""
import sys

try:
    import arca_files

    arca_files.autorun_boot()
except KeyboardInterrupt:
    print("Programa de inicialização interrompido.")
except Exception as error:
    print("Erro no programa de inicialização:")
    sys.print_exception(error)

print("ARCA pronto. Selecione o kit no aplicativo Android.")
