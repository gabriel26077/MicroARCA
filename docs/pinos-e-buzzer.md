# Pinos, PWM e buzzer passivo

A categoria **Pinos** oferece leitura digital (valor lógico ALTO/BAIXO),
leitura analógica (número de 0 a 65535), configuração de PWM em Hz,
ajuste do ciclo ativo em porcentagem e desligamento do PWM.

## Leitura

**Ler pino digital** configura entrada quando necessário e preserva o pull-up
já configurado. Pode ser encaixado diretamente em uma condição **Se**.
**Ler pino analógico** configura o ADC com atenuação de 11 dB e reutiliza o
conversor entre leituras. A escala 0–65535 não significa resolução física de
16 bits nem uma conversão exata para volts. O padrão é GPIO 34 (ADC1).

O runtime gerado valida os pinos para o ESP32 clássico: GPIOs de memória são
rejeitados, 34–39 não aceitam saída nem pull-up interno, e somente pinos ADC
aceitam leitura analógica. Nem todos os GPIOs do chip estão expostos em cada
placa; consulte sua pinagem. Não exceda os limites elétricos do kit.

## PWM

1. Configure PWM no pino e escolha uma frequência inteira de 1 a 40000 Hz.
2. Defina o ciclo ativo entre 0 e 100%.
3. Mantenha o programa em execução durante o efeito desejado.
4. Use **Desligar PWM** para liberar o canal e deixar a saída em BAIXO.

PWM alterna níveis digitais; não é uma tensão analógica contínua. Reconfigurar
PWM inicia em 0%. Trocar para leitura/escrita digital ou ADC libera o PWM
anterior. O programa gerado também libera seus canais em `finally`, ao terminar,
falhar ou receber uma interrupção Python. A precisão do ciclo ativo depende
da frequência e do hardware.

## Biblioteca Buzzer passivo

O pacote `buzzer-passivo@1.0.0` está preparado no repositório do catálogo:
`/home/gsnn/Projects/SistemaMicroARCA/packages/buzzer-passivo/1.0.0/`.
Ele ainda precisa ser publicado no espelho para aparecer no catálogo online.

Blocos disponíveis:

- Criar buzzer em um pino de saída.
- Tocar nota (seletor Dó–Si, incluindo sustenidos), oitava e duração em ms.
- Tocar frequência inteira em Hz por uma duração em ms.
- Iniciar som contínuo, continuando imediatamente os próximos blocos.
- Parar som.

Os blocos com duração aguardam o som terminar. A biblioteca aceita oitavas
0–8, frequências de 1 a 20000 Hz e durações de 0 a 60000 ms. A faixa audível
depende do buzzer. Não há controle de volume.

```python
from lib_buzzer_passivo import criar_buzzer

with criar_buzzer(25) as buzzer:
    buzzer.tocar_nota("Dó", 4, 300)
    buzzer.tocar_nota("Mi", 4, 300)
    buzzer.tocar(440, 500)
```

Use pinos distintos para o buzzer e para outros blocos que controlam saídas.
O circuito de acionamento deve ser adequado à corrente e tensão do componente.
PWM pode compartilhar recursos de frequência entre canais; valide combinações
de dispositivos na placa.

## Atualização e limpeza de recursos

O app atualizado aceita seletores declarativos (`dropdown`) nos manifestos de
bibliotecas. Apps anteriores não interpretam os blocos deste pacote.

O comando de execução do app chama o hook opcional `__arca_cleanup__` dos
módulos carregados em um `finally`. A biblioteca usa esse hook para desligar
todos os buzzers, inclusive som contínuo. O código gerado pelos blocos também
inclui sua própria limpeza, para funcionar ao gravar e executar ao ligar.

Para a mesma limpeza automática em **projetos Python gravados**, atualize
`embedded/arca_files.py` na placa. Fora desses executores, use `with` (como no
exemplo) ou `try/finally`. Desconectar o Bluetooth não equivale a interromper
o programa; a limpeza ocorre quando sua execução termina ou é interrompida.

## Verificação

- `flutter analyze --no-pub` e `flutter test --no-pub` na pasta do app.
- `node test/blockly_io_test.mjs` testa Blockly, tipagem, geração e reabertura.
- `python3 -B -m unittest discover -s embedded/tests` na raiz (WSL).
- No catálogo: testes, validação e `build_catalog.py --check`.

Os testes usam hardware simulado. Antes do uso em aula, validar na placa:
entrada digital com pull-up, potenciômetro no ADC, PWM em 0/50/100%, notas,
frequências, som contínuo, botão Parar e execução ao ligar.
