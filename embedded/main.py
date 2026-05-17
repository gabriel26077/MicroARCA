
# main

import machine

def execute_main():
    try:
        print(">>> Executando user.py")
        exec(open("user.py").read(), globals())
        print(">>> user.py terminou")
    except Exception as e:
        print("Erro ao executar user.py:", e)

def reset():
    print("Reiniciando ESP32...")
    machine.reset()

print("Gerenciador pronto!")
print("Use WebREPL para enviar um arquivo 'user.py'")
print("Depois digite: execute_main() para rodar")
