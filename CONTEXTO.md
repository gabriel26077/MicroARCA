# Retomada da sessão — Projeto ARCA

> **Gestos do editor de blocos — 26/09/2026:** arrastar o fundo move o canvas
> (o Blockly 13 exige `scrollbars: true` para isso; as barras ficam ocultas por
> CSS). A lixeira de arrastar foi removida. Segurar um bloco por 0,75 s abre:
> Copiar, Duplicar bloco, Duplicar cadeia, Deletar bloco (os de baixo sobem),
> Deletar cadeia e Desativar/Ativar. Copiar mostra uma barra **Colar | X** que
> fica até o X; cada colagem sai um pouco deslocada, e a cópia vale entre
> projetos enquanto o app está aberto. Cada ação é um único passo de desfazer.
> A pinça de zoom do Blockly foi substituída por uma própria (`pinch: false`):
> com o arraste do canvas ligado, o primeiro dedo já iniciava um arraste e o
> Blockly ignorava o segundo. Agora o segundo dedo cancela o gesto do Blockly, a
> distância entre os dedos define o zoom e o ponto médio desloca o canvas.
> Validado no Moto G34 com toques simulados pelo DevTools.
> Atalhos à esquerda do canvas (ideia do usuário): Pinos, Variáveis, Controle
> (ícone de setas se dividindo, também na gaveta), Lógica, Matemática e a última
> biblioteca aberta ou usada. Cada um abre a gaveta só com aquela seção aberta,
> já rolada até ela. A última biblioteca vale entre projetos enquanto o app
> está aberto.
> Variáveis: o bloco de atribuição (`variables_set_dynamic`, redefinido no
> `index.html`) virou só `x ← valor`, chamado "Declarar/atribuir" na gaveta e na
> dica; um bloco só, porque em Python criar e atribuir são o mesmo `x = valor`.
> O posicionamento padrão do Zelos preserva o encaixe superior sem recortar o
> seletor da variável. "alterar x por 1" virou "somar 1 a x". Ao tocar no
> atalho de Variáveis aparecem `$` (usar), `←` (declarar/atribuir) e `…`
> (gaveta completa). O seletor rápido lista e pesquisa variáveis sem abrir o
> teclado automaticamente. O menu nativo de renomear/excluir recebeu fonte e
> áreas de toque maiores para celular.
> Texto e console: `Exibir no console` aceita texto, número e lógico; o bloco
> `Juntar valores` converte cada parte com `str`. Manifestos de bibliotecas
> também aceitam o campo declarativo `value` para esses três tipos básicos.

> **Projetos unificados — 26/09/2026:** as abas agora são Projetos | Console |
> Kits. Todo programa é um **projeto** no celular, de **Blocos** ou **Python**
> (vários arquivos, `main.py` como entrada), guardado em `LocalProjectStorage`
> (`project_storage.dart`). O kit deixou de ser lugar de edição: cada projeto tem
> **Executar** (envia e roda) e **Gravar no kit** (envia e deixa rodando ao
> ligar), via `ProjectDeployer`, que deixa `/app` com exatamente os arquivos do
> projeto. O firmware (`arca_files.py` v5) registra o projeto em
> `.arca-project.json` e o copia para o estado da execução ao ligar; o app mostra
> "⚡ gravado no kit" ou "alterações não gravadas" comparando a revisão
> (`updatedAt`; renomear não muda a revisão). Blocos têm "Converter em projeto
> Python" (só de ida). Removidos o antigo Editor, o `ProgramStorage` e o projeto
> de blocos único, sem migração, por decisão do usuário. "Trazer do kit" ficou
> para depois. Testes: 57 no app, 46 no firmware (Linux).

> **Executar ao ligar — 25/09/2026:** `arca_files.py` versão 4 grava uma cópia
> congelada de `/app` em `/autorun` (cópia conferida por SHA-256, troca segura
> contra reset) e `main.py` a executa ao ligar. Saídas: conectar o app (Ctrl+C,
> como antes), segurar BOOT ~1,5 s logo depois de ligar, e um contador em
> `.arca-autorun.json` que desliga a opção após 3 boots seguidos sem zerar (zera
> ao terminar, após 10 s rodando ou quando o app conecta). A aba Kits ganhou o
> cartão **Executar ao ligar** (gravar, gravar de novo, desligar, aviso de
> desligamento automático). Decisões: conectar continua interrompendo o
> programa; o programa é uma cópia congelada; não há bloco "ao iniciar". Testes
> do firmware: 44 no Linux (WSL); no Windows um teste antigo falha por CRLF.
> **Pendente:** copiar `arca_files.py` e `main.py` para cada placa pelo cabo e
> validar em hardware real (Ctrl+C por BLE durante o programa, botão BOOT,
> contador).

> **Layout dos blocos de biblioteca — 25/09/2026:** blocos de manifesto agora
> usam `inputsInline: true` e quebram a linha antes de cada coordenada (campo
> `X`, `X1`, `X2`…), levando junto as duas palavras anteriores ("de x", "até x",
> "em x"). Ex.: `na tela [tela] retângulo` / `de x 0 y 0` / `até x 40 y 20`. Os
> argumentos passam a ser ligados pelo nome do campo, não pela ordem. Nada muda
> no catálogo nem em projetos salvos. **Achado pendente:** no Blockly 13,
> `move.drag` é forçado a `false` quando `scrollbars` é `false` (ver
> `parseMoveOptions`), então arrastar o canvas não funciona no app.

> **Gaveta de blocos em seções expansíveis — 25/09/2026:** a gaveta "Adicionar
> bloco" agora lista seções fechadas (Controle, Pinos, Lógica e comparações,
> Matemática, Texto e console, Variáveis, Funções, Bibliotecas), cada uma com
> ícone na cor dos seus blocos e um resumo do conteúdo. As seções abertas são
> lembradas entre aberturas da gaveta. As seções são dados (`_blockSections`
> em `blocks_page.dart`); ALTO/BAIXO aparece em Pinos e em Lógica de propósito.
> Um painel lateral só com ícones foi descartado porque, no celular, o usuário
> não associa ícone e conteúdo de imediato.

> **Edição de campos do Blockly em diálogo Flutter — 25/09/2026:** no celular o
> Blockly edita campos de texto e número via `window.prompt`, que o WebView
> mostrava como uma caixa crua do sistema. O `Blockly.dialog.setPrompt` agora
> manda o pedido ao Flutter, que mostra um `AlertDialog` Material com o valor já
> selecionado. Campos `FieldNumber` abrem o teclado numérico, e a vírgula
> decimal vira ponto. Validado no emulador Android API 37 (texto, número,
> cancelar e desfazer).

> **Duplicar por toque longo no Blockly — 25/09/2026:** segurar um bloco parado
> por 2 s abre uma folha com **Duplicar bloco** (o bloco com o que está encaixado
> dentro dele, sem os de baixo) e **Duplicar cadeia** (o bloco e todos os
> encaixados abaixo). Para bloco solto, as duas opções dão o mesmo resultado. A
> cópia aparece deslocada 32 unidades e o desfazer trata a duplicação como uma
> ação só. A mesma folha tem **Desativar bloco** / **Ativar bloco**, que usa o
> motivo `MANUALLY_DISABLED` do próprio Blockly: o bloco fica hachurado, ele e
> o que está dentro dele não geram código, e os blocos de baixo continuam
> executando. Os menus nativos do Blockly (bloco e canvas, 750 ms) foram
> desativados; o do canvas oferecia "Deletar N blocos". O `WebViewWidget`
> passou a usar `EagerGestureRecognizer`: sem ele, o `GestureDetector` global de
> `main.dart` ganhava a disputa de gestos e o WebView recebia `pointerup` depois
> de cerca de 150 ms. Validado no emulador Android API 37 com cadeia, bloco do
> meio, bloco solto e arraste comum.

> **Lixeira por arraste no Blockly — 25/09/2026:** ao começar a arrastar um
> bloco, uma lixeira flutuante aparece no topo do canvas. Ela aumenta e fica
> vermelha quando o bloco intersecta sua área. Ao soltar nessa posição, a IDE
> abre o diálogo **“Deseja apagar esse bloco?”**. Confirmar remove o bloco;
> cancelar desfaz o arraste e restaura sua posição e conexões anteriores. Se o
> bloco arrastado é o topo de uma pilha, a pilha inteira vai junto no arraste e
> é apagada inteira (sem “curar” a pilha); o diálogo informa quantos blocos
> encaixados serão removidos, sem contar blocos-sombra. O gesto
> completo, a confirmação, o cancelamento e a exclusão foram validados no
> emulador Android API 37. A análise Dart e os 46 testes Flutter passaram, e o
> APK foi recompilado e instalado no emulador.

> **Variáveis tipadas, lógica e fluxo no Blockly — 25/09/2026:** as variáveis
> agora têm um dos tipos básicos `Number`, `String` ou `Boolean`. O diálogo mostra
> o tipo em português e os encaixes do Blockly impedem combinações inválidas;
> alterar variável aceita somente números. Pino, espera e os parâmetros numéricos
> ou textuais dos blocos de bibliotecas foram convertidos em entradas tipadas com
> blocos-sombra, preservando a edição simples e permitindo usar variáveis. Foram
> adicionados `se`, `se/senão`, comparações `=`, `≠`, `<`, `≤`, `>` e `≥`, além
> de `não`, `e`, `ou` e do valor lógico `ALTO/BAIXO`. Projetos legados são migrados
> ao abrir. O gerador usa um registro de pinos para que o número do GPIO também
> possa vir de uma expressão. A validação real no WebView confirmou que texto não
> encaixa em número e que lógico encaixa no nível, mas não no número do pino. A
> análise Dart passou, os 46 testes Flutter passaram e o APK foi recompilado,
> instalado e aberto no emulador Android API 37. A toolchain Android está em
> Gradle 8.14, Android Gradle Plugin 8.11.1 e Kotlin 2.2.20.

> **Blocos associados a bibliotecas — 24/09/2026:** o catálogo passou a aceitar
> um `blocks.json` declarativo, versionado e protegido por tamanho/SHA-256, sem
> JavaScript remoto. A nova `oled-pintor@1.1.0` oferece oito blocos para criar,
> limpar e atualizar a tela, escrever texto e desenhar linha, retângulo, círculo
> e coração. A IDE baixa e valida o manifesto junto do pacote, guarda-o somente
> no celular e monta dinamicamente as categorias do editor Blockly usando o
> cache offline. O workspace registra `id@versão` das bibliotecas utilizadas e,
> antes de executar, confere se essas versões estão instaladas no ESP32 conectado.

> **Protótipo Blockly — 23/09/2026:** a IDE ganhou um modo visual em tela cheia,
> aberto pela opção **Blocos** e executado inteiramente offline com Blockly 13.3.0
> empacotado no APK. O canvas começa com um blink infinito editável; o menu
> sobreposto permite inserir blocos de GPIO em baixo nível (configurar pino e
> escrever nível lógico), controle, espera, definição e chamada de funções. Ele
> fecha após a escolha e posiciona o novo bloco no workspace. O exemplo de blink
> configura explicitamente o `Pin(2)` como saída, sem associar o GPIO a um LED.
> O menu secundário oferece
> desfazer, refazer, excluir o bloco selecionado, visualizar o MicroPython e
> restaurar o exemplo. **Executar** gera o código, salva em `/app/main.py` pelo
> transporte BLE existente e inicia o entrypoint; **Parar** envia a interrupção.
> O workspace JSON é salvo automaticamente no celular. O app passou a exigir
> Android 7.0/API 24 por causa da WebView. A prévia real gerou corretamente o
> blink para `Pin(2)` e a interface foi validada no Moto g34. Passaram 42 testes
> Flutter, a análise Dart e o build Android; o APK foi instalado e aberto. Ainda
> falta confirmar o blink no ESP32 físico conectado.

> **Workspace editável no ESP32 — 23/09/2026:** o Editor passou a tratar códigos
> do usuário como arquivos de projeto, não como bibliotecas oficiais. O explorador
> reúne cópias do celular e arquivos seguros de `/app`; permite abrir, editar,
> salvar, salvar como, renomear e excluir módulos, mantendo `/app/main.py` como entrypoint editável e
> não removível. **Executar** sincroniza o arquivo atual e inicia esse `main.py`.
> O `/main.py` real e os módulos ARCA continuam protegidos na raiz. Imports de
> módulos do projeto usam `/app`, são recarregados a cada execução e não podem
> colidir com pacotes oficiais de `/lib`. O antigo `user.py` é copiado para o novo
> entrypoint na primeira inicialização, sem ser apagado, e as antigas bibliotecas
> locais do celular são migradas para os arquivos do Editor. `arca_files.py` agora
> usa a API versão 3. A barra do Editor separa as ações do celular e do ESP32,
> cada lado com abrir, salvar e salvar como, além da ação central de novo arquivo.
> Passaram 40 testes Flutter, 34 testes Python, a análise Dart
> completa e `git diff --check`. O APK debug foi compilado, instalado e aberto
> no Moto g34 5G conectado.

> **Catálogo oficial de bibliotecas — 23/09/2026:** a IDE passou a consumir
> `https://libs-microarca.traceedu.com.br/v1/catalog.json` com o User-Agent da
> aplicação, HTTPS sem redirecionamentos, limites de tamanho, ETag e cache do
> último catálogo validado. URLs ficam restritas à mesma origem e ao caminho
> exato do pacote. O cliente resolve versões exatas, dependências, ciclos e
> conflitos; baixa e confere tamanho/SHA-256 de todos os bytes antes de usar BLE.
> Instalações ficam registradas por dispositivo, distinguindo pacotes principais
> de dependências para preservar módulos ainda utilizados. `arca_files.py` agora
> possui API versão 2 para preparar vários módulos e fazer commit/rollback em
> lote; kits com a versão anterior continuam aceitando a instalação manual de
> um arquivo, mas pedem atualização para pacotes online. O catálogo ainda não é
> assinado digitalmente e a interface informa que as bibliotecas executam código
> no ESP32.
> Validação final: 35 testes Flutter e 28 testes Python passaram;
> `flutter analyze --no-pub` não encontrou problemas e `git diff --check` passou.
> O APK debug foi compilado, instalado e aberto no Moto g34. No aparelho real, o
> catálogo público foi carregado pela rede e o download de `oled-pintor@1.0.0`
> armazenou no cache validado tanto `lib_oled_pintor.py` quanto a dependência
> `ssd1306.py`, além do ETag. Para instalar pacotes online no ESP32 físico ainda é
> preciso substituir uma vez o `arca_files.py` da placa pela API versão 2 desta
> branch e reiniciar/reconectar o kit.

> **Entrada interativa no Console — 22/09/2026:** o aplicativo passou a suportar
> `input()` durante a execução por BLE. Ao conectar, ele instala no contexto do
> raw REPL um wrapper temporário que preserva o prompt e emite um marcador de
> controle; esse marcador é removido da saída visível e muda o estado para
> **Aguardando resposta**. O campo do Console então envia uma única linha ao
> `stdin` via `dupterm`, inclusive vazia, sem finalizar a operação raw REPL.
> Fragmentação do marcador entre pacotes BLE, várias perguntas consecutivas e
> interrupção com Ctrl+C são tratadas. Não foi necessário alterar o firmware.
> Os 27 testes Flutter passaram, `flutter analyze --no-pub` ficou sem problemas
> e o APK debug foi compilado, instalado e aberto no Moto g34. A interação real
> com `input()` no ESP32 ainda precisa do teste de bancada do usuário. Os testes
> Python não foram repetidos porque não há Python no PATH deste Windows; nenhum
> arquivo de firmware foi alterado nesta etapa.

> **Gerenciador local de bibliotecas — 22/09/2026:** foi criada a branch local
> `feature/library-manager` a partir do commit estável `9b86d17`. O firmware agora
> possui `arca_files.py`, API transacional limitada a módulos `.py` em `/lib`, com
> validação de nome, limite de 64 KiB, SHA-256, releitura, arquivo parcial e exclusão
> restrita. O app ganhou a tela **Kits → Bibliotecas**, armazenamento local, seletor
> nativo de documentos Android, instalação, atualização, listagem e remoção por BLE.
> O editor também ganhou **Salvar código como biblioteca**: o conteúdo atual entra
> diretamente no acervo interno e, com o kit conectado, oferece **Instalar** no aviso
> de sucesso, sem depender do explorador de arquivos do Android.
> Arquivos da raiz não são listados nem aceitos pela API. Passaram 23 testes Python,
> 20 testes Flutter, `flutter analyze` e a compilação Kotlin/Android; o APK foi gerado,
> instalado e aberto no Moto g34. Para habilitar a função na placa atual ainda é
> necessário copiar `embedded/arca_files.py` uma vez para a raiz do ESP32 e reconectar.
> O catálogo web, pacotes com vários arquivos e dependências continuam para fases
> posteriores. As alterações desta branch ainda não foram commitadas nem enviadas.

> **Atualização em 22/09/2026:** o ambiente Windows foi configurado com Flutter
> 3.47.5, JDK 21, Android SDK e NDK 28.2.13676358. O APK Android foi compilado,
> instalado e executado em um Moto g34 5G. A conexão BLE com o ESP32 físico e
> MicroPython 1.29.0 funcionou. `arca_ble.py` foi ajustado para não usar exclusão
> de itens de `bytearray`, operação indisponível no MicroPython; os oito testes
> específicos do transporte BLE passaram depois da correção. O app também passou
> a salvar, listar, carregar, substituir e excluir programas Python no armazenamento
> local do Android. `flutter analyze --no-pub` passou, os 17 testes Flutter passaram
> e o APK atualizado foi instalado no celular. O próximo recurso em planejamento é
> um gerenciador de bibliotecas/arquivos do usuário no ESP32, com infraestrutura
> protegida e, futuramente, catálogo de bibliotecas obtidas pela internet.

> **Recuperação após exclusão acidental — 21/09/2026:** a pasta original foi
> apagada pelo Explorador via `\\wsl.localhost\Ubuntu`. O projeto foi reconstruído
> a partir do repositório GitHub no mesmo commit `2e4253d4e262b52fde8fee685531e58340e39f50`
> e das alterações registradas nesta sessão. Foram recuperados os 169 arquivos de
> trabalho do inventário, incluindo este documento, e recriada a branch
> `feature/bluetooth-ble`. Os 16 testes Python e os 16 testes Flutter passaram
> novamente; `flutter analyze --no-pub` e `git diff --check` passaram. As alterações
> continuam sem commit. A reconstrução não é uma recuperação forense byte a byte:
> formatação Dart e metadados locais de `.git` podem diferir. Nenhuma validação
> física ou compilação APK foi acrescentada. A cópia para retomar no Windows fica
> em `C:\Users\GSNN\Documents\ARCA-recuperado-2026-09-21\ProjetoARCA`, com ZIP de
> segurança ao lado. O restante deste documento registra o estado anterior ao
> acidente; os caches foram excluídos da cópia entregue novamente.

Atualizado em 21/09/2026, ao preparar a mudança do WSL2 para o Windows.
Este documento registra o estado da sessão; confira os arquivos e o `git status`
antes de continuar, pois o projeto pode ter recebido alterações depois desta data.

## Objetivo e decisões do usuário

- Aplicativo Flutter em `micro_arca_app/`, firmware MicroPython em `embedded/`.
- Hardware confirmado: **ESP32 clássico / ESP32 Dev Module**.
- Plataforma do aplicativo: **somente Android**, mesmo que o desenvolvimento
  passe a acontecer no Windows. As pastas desktop/iOS são scaffolds do Flutter;
  não significam que a integração BLE foi implementada para essas plataformas.
- O usuário sofreu com Wi-Fi/WebREPL e decidiu migrar a comunicação para Bluetooth.
- Foi implementada uma primeira versão **BLE GATT + raw REPL nativo do MicroPython**.
  Não é Bluetooth clássico SPP. O rádio e a pilha Bluetooth são nativos do ESP32
  e do Android; o software faz a ponte entre as características GATT e o REPL.
- Prioridade: conexão confiável, transferência de código verificável, console
  legível e interface que represente o estado real da execução.
- Agora o usuário vai **copiar este repositório do WSL para o Windows** para
  compilar e instalar o app no celular. Não continuar instalando SDKs no WSL.
- O usuário autorizou criar este documento e remover do repositório caches,
  dependências baixadas e arquivos locais regeneráveis para facilitar a cópia.

## Git: preservar o trabalho ainda não commitado

- Branch na saída do WSL: `feature/bluetooth-ble`.
- HEAD: `2e4253d` — `docs: define ARCA acronym in README`.
- **A implementação BLE, seus testes, documentos e `mise.toml` ainda não foram
  commitados nem enviados a um remoto.** Há arquivos modificados e arquivos novos.
- Copiar a pasta inteira, **inclusive `.git` e todos os arquivos não rastreados**.
  Clonar apenas o remoto ou copiar apenas arquivos já commitados perderia o trabalho.
- Não executar `git reset --hard`, `git clean` ou restaurar os arquivos modificados.
- Nenhuma mudança foi feita na placa ou instalada no celular durante esta sessão.

## Diagnóstico anterior do Wi-Fi (contexto da migração)

A revisão estática encontrou IP fixado com final `.80`, máscara `/24` e gateway
terminado em `.1`, além de endereço padrão no app. Isso não acomodava corretamente
redes diferentes. O boot antigo podia ficar preso tentando conectar, sem chegar ao
REPL normal e sem fallback confiável para o modo de configuração.

O cliente WebREPL tinha problemas no tratamento de cabeçalhos e de mensagens
WebSocket fragmentadas ou agrupadas, filtragem de bytes que corrompia UTF-8 e
confirmações de upload incorretas. A interface também indicava sucesso/fim de
execução por temporização, sem confirmação efetiva. O código antigo pode ser
consultado no histórico Git; não deve ser reintroduzido na migração BLE.

## O que já foi implementado

### Firmware em `embedded/`

- `boot.py`: desliga STA/AP Wi-Fi, instancia `ArcaBLE` e o registra em
  `os.dupterm()`. O boot termina normalmente e mantém a serial USB disponível.
- `main.py`: apenas anuncia disponibilidade; **não executa `user.py` no boot**.
- `arca_ble.py`: stream `io.IOBase`, BLE nativo, filas limitadas e envio agendado
  por `micropython.schedule`. Não depende de um loop asyncio concorrente com o
  programa do aluno. Recepção chama `os.dupterm_notify(None)` para processar Ctrl+C.
- `arca_runtime.py`: upload de `user.py` por trechos, limite de 64 KiB, conferência
  de tamanho/SHA-256, releitura do arquivo gravado, sincronização e substituição
  por `rename` a partir de `user.py.part`. LittleFS padrão é o alvo. Upload
  incompleto não deve destruir o `user.py` anterior.
- `tests/test_ble.py` e `tests/test_runtime.py`: simulação da API BLE e testes
  do upload com filesystem temporário.
- `README.md`: instruções de instalação, protocolo, limites e teste de bancada.
- `wifi_config.json` e `buffer_config.json` foram preservados como arquivos
  antigos, mas **não são usados nem devem ser copiados para o firmware novo**.

### Protocolo BLE

- Nome anunciado: `ARCA-XXXXXX`, derivado dos últimos três bytes do ID da placa.
- Serviço: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`.
- RX: `6e400002-b5a3-f393-e0a9-e50e24dcca9e`, write com resposta.
- TX: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`, **indications**, uma pendente por vez.
- Controle: `6e400004-b5a3-f393-e0a9-e50e24dcca9e`.
- Handshake: cliente escreve `R`, espera `ARCA-BLE/1\n`, envia `A`.
  O cliente repete `R` enquanto a assinatura de TX está sendo habilitada.
- Depois disso usa o raw REPL nativo: Ctrl+A, código + Ctrl+D, `OK`, stdout,
  `0x04`, stderr, `0x04`, prompt `>`. Ctrl+C interrompe Python.
- MTU solicitado 247; fallback para 23. Escritas do app têm no máximo 128 bytes
  e respeitam MTU-3. Indications têm no máximo 244 bytes.
- Firmware: RX 2 KiB e TX 16 KiB. Overflow/falha de transporte encerra a conexão
  explicitamente. Diagnóstico pela serial: `arca_ble.last_error`.
- Um celular por conexão. Reconexão limpa buffers e sincroniza novamente o REPL.

### Flutter e Android

- `lib/services/ble_transport.dart`: integração com `flutter_reactive_ble`,
  assinatura TX, MTU, escrita com resposta em trechos e fila de escritas.
- `lib/services/raw_repl.dart`: parser de bytes independente do BLE; trata
  mensagens fragmentadas/agrupadas, decodifica UTF-8 incrementalmente e separa
  stdout/stderr. Serializa operações e invalida o canal após timeout/falha para
  não reutilizar uma sessão dessincronizada. Helpers têm timeout; programas do
  usuário podem executar indefinidamente até interrupção/desconexão. Durante uma
  execução ativa, também permite enviar uma linha validada diretamente ao stdin.
- `lib/services/input_protocol.dart`: reconhece e remove da saída o marcador de
  `input()`, mesmo dividido entre pacotes, avisando o serviço para liberar o campo
  de resposta apenas quando o programa estiver realmente aguardando uma linha.
- `lib/services/micropython_repl_service.dart`: estados disconnected/scanning/
  connecting/ready/uploading/managingLibraries/running/waitingForInput/stopping,
  permissões, busca, handshake, transferência, execução e interrupção. IDs de
  sessão impedem callbacks antigos
  de alterar uma conexão nova. Criação do BLE é tardia, após permissão. Cancelar
  enquanto a permissão está aberta não deve iniciar uma busca posteriormente.
- `pages/settings_page.dart`: lista de kits, procurar/conectar/cancelar/desconectar.
- `pages/editor_page.dart`: enviar, executar e parar com estados reais; executar
  depende de o texto atual ter sido enviado na sessão atual. Progresso de upload.
- `widgets/python_indent_modifier.dart`: indentação Python no editor.
- `pages/console_page.dart`: fluxo contínuo UTF-8, sem bolhas por pacote ou
  timestamps por fragmento, atualização em lotes de 100 ms, limite de 64 mil
  caracteres e rolagem que respeita a leitura do usuário. O campo alterna entre
  comandos e respostas de `input()` de acordo com o estado confirmado pelo kit.
- Ajustes de SafeArea, navegação, teclado e disposição de botões em telas pequenas.
- `android/.../MainActivity.kt`: MethodChannel `arca/bluetooth_permissions`.
  Android 12+ usa scan/connect; anteriores usam localização para descoberta BLE.
- `android/app/src/main/AndroidManifest.xml`: estrutura corrigida e permissões BLE.
- `pubspec.yaml`/`pubspec.lock`: remove WebSocket, adiciona `flutter_reactive_ble`
  e `crypto`. **Preservar o lockfile** durante a mudança de computador.

## Validação já feita e limites de confiança

Resultados da sessão **antes da limpeza dos caches**:

- 16 testes Python passaram.
- 16 testes Flutter passaram (protocolo, ciclo de conexão, editor e layouts).
- `flutter analyze --no-pub`: sem problemas.
- Parsing dos quatro arquivos do firmware e do manifest Android passou.
- `git diff --check`: passou.
- `flutter build apk --debug --no-pub`: **não compilou porque não havia SDK Android
  no WSL**. Nenhum APK foi gerado. Kotlin/Gradle ainda precisam da primeira
  compilação Android completa; não confundir testes Dart com validação nativa.
- Sem teste físico de BLE, flash do ESP32 ou instalação no celular.

Os testes do firmware simulam Bluetooth; não provam estabilidade do rádio,
temporização real, comportamento de `dupterm`, memória ou alimentação elétrica.

Limitações conhecidas que continuam abertas:

- Sem PIN, bonding ou autenticação por aluno. Nome/hello não autenticam o usuário.
- Conectar/reconectar interrompe o programa anterior para sincronizar o REPL.
- Desconectar não para automaticamente o programa nem desliga atuadores.
- Ctrl+C não restaura GPIO/motores. Programas devem fazer limpeza em `finally`.
- Bloqueios em código nativo, IRQs desabilitadas ou alterações em BLE/dupterm pelo
  programa podem impedir interrupção. App aguarda confirmação e, após cinco
  segundos sem resposta, desconecta e orienta RESET.
- Saída é texto UTF-8, não um canal binário arbitrário com delimitadores raw REPL.
- Prints sem pausa podem exceder os buffers e causar desconexão explícita.
- Não há retomada automática de upload/execução depois de queda.

## Ambiente de origem e preparação do Windows

Origem: `/home/gsnn/Projects/ProjetoARCA`, WSL2, usuário `gsnn` no computador
`gabdesk`. Esses caminhos Linux não devem ser reaproveitados na configuração Windows.

- Flutter usado nos testes: **3.47.5**, Dart **3.13.4**, em
  `/tmp/arca-flutter-sdk`. Essa instalação é temporária, externa ao repositório e
  **não acompanhará a cópia**.
- Configuração Android atual: Gradle wrapper **8.14**, Android Gradle Plugin
  **8.11.1**, Kotlin **2.2.20**.
- Com o Flutter testado: compile/target SDK **36**, min SDK **24** (Android 7),
  NDK **28.2.13676358**, derivados dos defaults do Flutter.
- O Linux tinha Java 25. Instalamos via mise o Temurin
  `21.0.12+101.0.LTS` (runtime informa 21.0.12.1) e criamos `mise.toml` na raiz.
  Java 21 é compatível com o Gradle 8.12. A ativação por `mise trust` foi recusada;
  **o arquivo existe, mas não afirmar que já está confiado/ativado**.
- As solicitações para instalar SDK Linux e tornar Flutter permanente foram
  recusadas. Depois o usuário decidiu migrar para Windows. Não insistir nisso.
- Java/mise instalados no Linux não migram junto. Usar JDK Windows compatível;
  Java 21 é a referência. Se usar mise no Windows, verificar suporte e instalação
  antes de assumir os caminhos. Flutter também pode usar o JDK do Android Studio;
  conferir a versão real com `flutter doctor -v`.
- Encontramos Android Studio em `C:\Program Files\Android\Android Studio` e SDK
  em `C:\Users\GSNN\AppData\Local\Android\Sdk`.
- No SDK Windows vimos `platform-tools/adb.exe`, Build Tools **36.0.0** e plataforma
  **android-37.0**. **Não havia `cmdline-tools` nem `android-36` nessa inspeção**.
  Conferir e instalar o que falta no SDK Manager. SDK 37 não substitui a plataforma
  36 exigida pela configuração atual. NDK necessário ainda precisa ser conferido.
- Flutter Windows e reconhecimento do celular pelo ADB **ainda não foram verificados**.

## Próximos passos ao abrir no Windows

1. Abrir a pasta copiada em disco local do Windows, usando terminal PowerShell e
   ferramentas Windows. Ler este arquivo e `embedded/README.md`; conferir branch
   e alterações com `git status --short` e `git branch --show-current`.
2. Conferir/instalar Flutter Windows, preferencialmente a versão testada, e JDK
   compatível. Conferir `flutter doctor -v` antes de mudar dependências do projeto.
3. No Android Studio → SDK Manager, completar as ferramentas exigidas, incluindo
   Command-line Tools, Platform Tools, SDK Platform 36, Build Tools e NDK conforme
   o projeto solicitar. Se o Flutter não localizar o SDK, configurar o caminho
   Windows com `flutter config --android-sdk`.
4. Executar `flutter doctor --android-licenses` para o usuário revisar eventuais
   licenças pendentes. Não presumir que as licenças do WSL estão configuradas.
5. Na pasta `micro_arca_app`, executar `flutter pub get`, `flutter analyze`,
   `flutter test` e `flutter build apk --debug`. Corrigir eventuais erros nativos
   encontrados na primeira compilação. Não executar `flutter create .` para
   resolver caminhos: isso pode alterar customizações Android existentes.
6. No celular, ativar opções de desenvolvedor/depuração USB, conectar um cabo de
   dados e autorizar o computador. Conferir `flutter devices`; usar
   `flutter run -d ID_DO_CELULAR`. Não selecionar o alvo desktop Windows.
7. Alternativamente instalar o APK com ADB Windows, depois de compilado. Caminho
   esperado do APK: `micro_arca_app/build/app/outputs/flutter-apk/app-debug.apk`.
8. Preparar ESP32 com MicroPython ESP32_GENERIC compatível. Referência das APIs:
   MicroPython 1.26.0; confirmar na placa `bluetooth`, `os.dupterm`,
   `os.dupterm_notify`, `hashlib.sha256` e `os.sync`.
9. Fazer backup da placa e copiar `arca_ble.py`, `arca_runtime.py`, `main.py` e
   **`boot.py` por último**, para a raiz do filesystem. Usar porta COM no Windows.
   Instruções completas e comandos mpremote estão em `embedded/README.md`.
10. Testar em bancada: descoberta, envio/execução, acentos/emoji, Ctrl+C, reset,
    queda durante upload, reconexão, segundo celular, teclado e retorno ao app.
    Primeiro sem motores; depois com alimentação/atuadores reais.

## Limpeza para a cópia

Foram removidos somente caches e arquivos locais gerados:

- `micro_arca_app/build/`
- `micro_arca_app/.dart_tool/`
- `micro_arca_app/.flutter-plugins-dependencies`
- `micro_arca_app/android/local.properties` (apontava para Flutter em `/tmp`)
- `micro_arca_app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
- `micro_arca_app/ios/Flutter/Generated.xcconfig`
- `micro_arca_app/ios/Flutter/flutter_export_environment.sh`
- `micro_arca_app/ios/Flutter/ephemeral/`
- `micro_arca_app/ios/Runner/GeneratedPluginRegistrant.h`
- `micro_arca_app/ios/Runner/GeneratedPluginRegistrant.m`
- `micro_arca_app/macos/Flutter/ephemeral/`

Não havia `node_modules`, virtualenv Python, `.pub-cache`, Pods ou cache Gradle
local adicional para remover nesta inspeção. Caches globais/SDKs fora do
repositório não foram apagados, pois não acompanham a cópia.

Preservados: `.git`, fontes, testes, assets, documentos, `pubspec.yaml`,
`pubspec.lock`, `mise.toml`, `.metadata`, arquivos de configuração Gradle e os
scaffolds de plataforma rastreados pelo Git, inclusive registrants desktop
versionados. Estes são textos portáveis, não bibliotecas Linux baixadas.

`flutter pub get` e a compilação regeneram os arquivos necessários no Windows.
Limpeza concluída: **49,1 MiB removidos**, repositório com aproximadamente
**5,1 MiB incluindo `.git`**. A comparação de SHA-256 confirmou que os 169
arquivos de trabalho preservados não mudaram durante a remoção. Não restaram
arquivos ignorados no inventário Git e `git diff --check` passou.
Os scripts/binários ignorados do wrapper Gradle não estavam presentes; o Flutter
normalmente os prepara ao compilar. Nenhum teste Flutter deve ser rodado após a
limpeza nesta sessão, para não recriar os caches antes da cópia.

## Mensagem sugerida para a nova conversa

> Leia CONTEXTO.md e embedded/README.md para retomar a sessão. Já estamos no
> Windows. Preserve as alterações não commitadas da branch feature/bluetooth-ble.
> Nosso próximo objetivo é configurar o Flutter/SDK Windows, compilar o APK,
> instalar no Android e validar a conexão BLE com o ESP32 clássico físico.
