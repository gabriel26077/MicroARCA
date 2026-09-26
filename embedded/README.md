# ARCA por Bluetooth BLE — ESP32 clássico + Android

Esta versão substitui Wi-Fi/WebREPL por BLE. O interpretador continua sendo o
MicroPython. O Bluetooth é o nativo do ESP32 e do Android; `arca_ble.py` conecta
um serviço GATT ao REPL através de `os.dupterm()`.

## Preparar a placa

Use uma versão estável do [MicroPython ESP32_GENERIC](https://micropython.org/download/ESP32_GENERIC/)
compatível com sua placa e flash. A referência das APIs usadas é o MicroPython
1.26.0; é necessário ter `bluetooth`, `hashlib.sha256`, `os.dupterm`,
`os.dupterm_notify` e `os.sync`. O filesystem padrão LittleFS é o alvo do upload
com substituição atômica. Esta implementação ainda precisa ser validada no kit
físico e nos Androids que serão usados em aula.

Copie estes cinco arquivos para a **raiz** da placa:

1. `arca_ble.py`
2. `arca_runtime.py`
3. `arca_files.py`
4. `main.py`
5. `boot.py` — copie por último, depois das dependências.

Não copie a pasta `tests`. `wifi_config.json`, `buffer_config.json` e o antigo
`buffer_conf.json` não são mais usados. A versão anterior do firmware permanece
no histórico Git. Faça uma cópia de seus arquivos da placa antes de substituir
`boot.py` e `main.py`.

Exemplo a partir da raiz do repositório, com
[mpremote](https://docs.micropython.org/en/latest/reference/mpremote.html) instalado
(troque `/dev/ttyUSB0` pela porta da placa; no Windows, por exemplo `COM3`):

```sh
mpremote connect /dev/ttyUSB0 fs cp embedded/arca_ble.py :arca_ble.py
mpremote connect /dev/ttyUSB0 fs cp embedded/arca_runtime.py :arca_runtime.py
mpremote connect /dev/ttyUSB0 fs cp embedded/arca_files.py :arca_files.py
mpremote connect /dev/ttyUSB0 fs cp embedded/main.py :main.py
mpremote connect /dev/ttyUSB0 fs cp embedded/boot.py :boot.py
mpremote connect /dev/ttyUSB0 reset
```

A placa anuncia `ARCA-XXXXXX`, usando os últimos três bytes de `machine.unique_id()`.
Para conferir pela serial:

```python
print(arca_ble.name)
print(arca_ble.last_error)
```

O boot termina normalmente e não abre Wi-Fi. `main.py` só executa um programa se
a opção **Executar ao ligar** tiver sido gravada pelo app (veja abaixo).
A conexão serial do cabo continua disponível para diagnóstico e recuperação.

## Usar no Android

Com Flutter e Android SDK instalados:

As verificações automatizadas foram feitas com Flutter 3.47.5 / Dart 3.13.4.
O projeto mantém o `minSdk` padrão do Flutter (API 24 / Android 7 nessa versão).

```sh
cd micro_arca_app
flutter pub get
flutter run
```

1. Abra **Kits → Procurar kits** e conceda a permissão solicitada.
2. Android 12+ pede dispositivos próximos; Android 7–11 precisa da permissão de
   localização para descobrir BLE e pode exigir que a localização esteja ligada.
3. Selecione o nome da placa. Não é necessário parear primeiro nas configurações
   do Android. Um kit aceita apenas um celular por vez.
4. Em **Projetos**, crie um projeto de **Blocos** ou de **Python**. Projetos
   ficam no celular. Um projeto Python pode ter vários arquivos; `main.py` é a
   entrada e pode importar os outros.
5. **Executar** envia o projeto ao kit e roda agora. `/app` passa a conter
   exatamente os arquivos do projeto (o Python gerado, no caso de blocos).
   **Gravar no kit** faz o mesmo e deixa o projeto rodando ao ligar.
6. Veja a saída em **Console**. **Parar** fica no editor do projeto.
7. Em **Kits → Bibliotecas**, consulte o catálogo oficial em
   `https://libs-microarca.traceedu.com.br/v1/catalog.json`. Pacotes e todas as
   dependências ficam em `/lib` e são baixados e verificados antes de o ESP32
   ser modificado. Eles não aparecem entre os arquivos editáveis do projeto.

O workspace editável exige `arca_files.py` versão 3. Ao ser aberto pela primeira
vez, `/app/main.py` recebe uma cópia do antigo `user.py`, se ele existir; o
original é preservado. O `main.py` da raiz continua protegido porque é executado
automaticamente pelo MicroPython durante o boot. Arquivos de `/app` não podem
usar o mesmo nome de uma biblioteca oficial em `/lib`.

Pacotes do catálogo com vários arquivos usam a API transacional introduzida na
versão 2. Ela prepara todos os módulos em arquivos ocultos e só os substitui depois que
o lote inteiro foi recebido e teve tamanho e SHA-256 conferidos. Uma falha antes
do commit preserva as versões anteriores. A instalação manual de um único módulo
continua compatível com a API anterior.

Quando o programa chama `input()`, o Console muda para **Aguardando resposta**.
Digite a resposta no campo inferior e toque em enviar. Linhas vazias também são
aceitas. O campo volta a ficar bloqueado enquanto o programa estiver executando,
até que outro `input()` seja alcançado. Por exemplo:

```python
v = int(input("Digite um número: "))
print(2 * v)
```

Conectar ou reconectar interrompe a execução anterior para sincronizar o REPL.
O app não reenvia nem executa um programa automaticamente depois de uma queda.
Desconectar não interrompe o programa e não desliga os pinos/motores. Ctrl+C
interrompe o Python, mas também não restaura automaticamente os pinos: programas
com atuadores devem desligá-los em um `finally` apropriado.

## Executar ao ligar

Requer `arca_files.py` versão 5 e o `main.py` atual na placa. **Gravar no kit**,
no editor do projeto, envia o projeto para `/app`, registra qual projeto é em
`.arca-project.json` e copia `/app` para `/autorun`, conferindo cada cópia por
SHA-256 antes de substituir a anterior. Editar o projeto depois não muda o que
roda ao ligar; é preciso gravar de novo, e o app avisa quando há alterações não
gravadas. A aba **Kits** mostra qual projeto roda ao ligar e permite desligar.
Bibliotecas continuam vindo de `/lib`.

`boot.py` liga o BLE antes de `main.py`, então o programa roda com o REPL já
disponível. Há três formas de retomar o controle:

1. **Conectar o app**: a conexão envia Ctrl+C e interrompe o programa.
2. **Botão BOOT**: segurá-lo durante ~1,5 s logo **depois** de ligar pula o
   programa. Segurá-lo *durante* o reset entra no modo de gravação do ESP32.
3. **Proteção contra reinícios**: cada boot que executa o programa soma 1 em
   `.arca-autorun.json`. O contador zera quando o programa termina, após 10 s
   rodando ou quando o app conecta. Com 3 boots seguidos sem zerar, a opção é
   desligada e o app avisa.

Programas podem anular a primeira saída se capturarem `KeyboardInterrupt`
(`except:` sem tipo), desligarem o Ctrl+C (`micropython.kbd_intr(-1)`) ou
mexerem no Bluetooth. Nesses casos use o botão BOOT ou o cabo USB (`mpremote`),
que continua sendo o último recurso de recuperação.

## Teste de bancada necessário

Comece sem motores, com alimentação USB estável:

```python
import time
contador = 0
while True:
    print("ação 🚀", contador)
    contador += 1
    time.sleep(0.2)
```

Verifique caracteres e linhas, deixe executar alguns minutos e toque **Parar**.
Depois execute `while True: pass` e confira a interrupção. Se não houver confirmação
em cinco segundos, o app encerra a sessão e orienta usar RESET; ele não informa
falsamente que conseguiu parar. Código nativo bloqueado, interrupções desabilitadas,
reconfiguração do Bluetooth ou `dupterm` pelo aluno podem impedir o controle remoto.

Valide também:

- Desligar Bluetooth ou resetar a placa durante o envio; reconectar e reenviar.
- Interromper um upload e verificar pela serial que o `user.py` anterior foi preservado.
- Enviar um arquivo maior, inclusive com acentos, e executar após a confirmação.
- Testar segundo celular tentando conectar ao mesmo kit.
- Repetir com motores e alimentação real para verificar resets elétricos.
- Abrir teclado, alternar abas e voltar ao app após bloquear a tela.
- Executar o exemplo com `input()`, responder `7`, conferir `14` e repetir com
  duas perguntas consecutivas e com uma resposta vazia.

## Protocolo e limites

- Serviço: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`.
- RX: `...0002...`, GATT write **com resposta**.
- TX: `...0003...`, GATT **indications** (confirmação pelo cliente), uma pendente
  por vez. Não depende de timers reservados nem de um servidor asyncio ao lado
  do código do aluno.
- Controle: `...0004...`. `R` pede `ARCA-BLE/1\n`; `A` confirma o canal. O cliente
  repete o hello enquanto a assinatura de TX está sendo habilitada pelo Android.
- Depois do hello, o app usa o **raw REPL nativo**: Ctrl+A, código, Ctrl+D,
  `OK`, stdout + `0x04`, stderr + `0x04`, `>`. Ctrl+C interrompe uma execução.
  Para `input()`, o app instala ao conectar um wrapper temporário no contexto do
  raw REPL. Um marcador reservado informa que o programa está esperando e a
  resposta é enviada diretamente ao `stdin` pelo mesmo canal `dupterm`.
  A saída esperada é texto UTF-8; bytes de controle do raw REPL não podem ser
  usados como saída binária arbitrária. Soft/hard reset encerra BLE e exige reconexão.
- MTU solicitado: 247, com fallback 23. RX envia no máximo 128 bytes por escrita;
  TX respeita o MTU negociado, até 244 bytes por indication.
- Arquivo: até 64 KiB. Cada trecho é confirmado pelo raw REPL. O firmware grava
  `user.py.part`, verifica tamanho e SHA-256, relê e verifica o arquivo e só então
  faz `rename` para `user.py`. Esse limite de transferência não garante que um
  programa de 64 KiB caiba na memória disponível durante a execução.
- Catálogo: no máximo 1 MiB, HTTPS sem redirecionamentos e cache validado por
  ETag. Cada módulo remoto mantém o limite de 64 KiB e é conferido byte a byte
  pelo tamanho e SHA-256 publicados antes da transferência BLE.
- RX: 2 KiB de buffer; TX: 16 KiB. Excesso de saída encerra a conexão explicitamente,
  em vez de perder bytes do protocolo silenciosamente. Evite `print()` sem pausa.
  Consulte `arca_ble.last_error` pela serial para diagnosticar.
- Console no app: últimos 64 mil caracteres, atualizado em lotes de 100 ms.

O nome do kit e o hello identificam o dispositivo/protocolo; **não autenticam o
usuário**. Esta primeira versão não implementa PIN, bonding ou autorização por
aluno. Um celular próximo com o protocolo pode controlar um kit desocupado.

## Verificação automatizada

```sh
python3 -B -m unittest discover -s embedded/tests -v
cd micro_arca_app
flutter analyze
flutter test
```

Os testes Python simulam a API BLE e testam transferência, integridade, buffers e
reconexão. Os testes Dart cobrem respostas agrupadas/fragmentadas, UTF-8,
interrupção, timeout e desconexão. Esses testes não substituem a bancada BLE real.
