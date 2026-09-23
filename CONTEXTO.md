# Retomada da sessão — Projeto ARCA

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
- Configuração Android atual: Gradle wrapper **8.12**, Android Gradle Plugin
  **8.9.1**, Kotlin **2.1.0**.
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
