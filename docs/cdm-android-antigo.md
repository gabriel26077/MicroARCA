# Crash do filtro CDM no Android antigo — 14/11/2026

## Evidência e causa

Relato do autor: Samsung SM-J260M, Android 8.1.0, mensagem
“Companion Device Manager parou”. Relatório fornecido localmente em
`C:\Users\GSNN\Downloads\bugreport-2026-11-14-16-52-41`.
O pacote MicroARCA instalado é 1.2.3+8, minSDK 24 e targetSDK 36.

Cinco ocorrências no registro do processo `com.android.companiondevicemanager`:
16:45:23, 16:45:39, 16:45:48, 16:48:28 e 16:52:53. Stack consistente:

```text
java.lang.NullPointerException
  java.util.Objects.requireNonNull
  java.util.Arrays$ArrayList.<init>
  java.util.Arrays.asList
  android.companion.BluetoothDeviceFilterUtils.matchesServiceUuid
  android.companion.BluetoothDeviceFilterUtils.matches
  android.companion.BluetoothLeDeviceFilter.matches
```

O código AOSP consultado para 8.0, 8.1, 9 e 10 passa por
`BluetoothDeviceFilterUtils.matches`, que compara o UUID do filtro com
`Arrays.asList(device.getUuids())`. O cache pode estar nulo, mesmo com o UUID
presente no anúncio BLE. A stack do Samsung corresponde a esse caminho.
O AOSP 11 usa `getScanFilter().matches(scanResult)`, considerando o anúncio.

Fontes oficiais conferidas (arquivos obtidos por `?format=TEXT`):

- https://android.googlesource.com/platform/frameworks/base/+/android-8.1.0_r1/core/java/android/companion/BluetoothDeviceFilterUtils.java
- https://android.googlesource.com/platform/frameworks/base/+/android-10.0.0_r1/core/java/android/companion/BluetoothLeDeviceFilter.java
- https://android.googlesource.com/platform/frameworks/base/+/android-11.0.0_r1/core/java/android/companion/BluetoothLeDeviceFilter.java

Stack isolada, hash/origem do relatório, cópias das fontes e logs de teste em
`../../output/app-revisao/cdm-android81/`. O relatório completo não foi copiado
para o repositório.

## Ajuste local 1.2.4+9

`CompanionKitFilter.create()` usa padrão de nome `^ARCA-[0-9A-Fa-f]{6}$` em
API 26–29. Esse é o nome produzido pelos módulos atuais do kit. Não preenche
o UUID do ScanFilter nessas versões, evitando o caminho defeituoso do sistema.
Em API 30+, mantém o filtro por UUID do serviço.

O seletor e a autorização continuam sendo do CDM. Não foi adicionada busca
BLE direta como fallback, permissão de localização ou de scan. O transporte
continua usando o serviço e as características ARCA e a preparação do protocolo
existente ao conectar. Filtragem por nome não é autenticação do kit.
Não houve alteração do firmware por esta correção.

## Verificação e limite

Teste de regressão nativo em `CompanionKitFilterTest`: cria anúncio com UUID
ARCA e cache UUID do BluetoothDevice nulo, reproduz o crash do filtro antigo
no framework 8.1 e verifica o novo filtro em 8.1 e 10. Também examina exclusão
de outros nomes e o ScanFilter de anúncio mantido no caminho Android 11.

Resultado: seis casos aprovados com Robolectric 4.16.1. Na primeira rodada,
o teste exigia a exceção também no framework 10, que já retorna falso em vez
de lançar essa exceção. O `android-all` 11 do Robolectric também conserva o
matcher CDM baseado no cache, diferentemente da fonte 11_r1 consultada.
Seu bytecode foi conferido com javap. A verificação moderna foi delimitada
ao ScanFilter construído pelo app e ao anúncio, sem alegar execução completa
do seletor Android 11. Logs das tentativas e XML final preservados.

Comando na pasta `micro_arca_app/android`:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.microarca.app.CompanionKitFilterTest --console=plain
```

Resultados efetivamente obtidos ficam no registro operacional da pasta de
evidências indicada acima. Testar frameworks no computador não comprova que
todo o seletor da Samsung passou a funcionar: ainda é necessário instalar o
APK corrigido no SM-J260M e confirmar descoberta, seleção e conexão com kit.
Não afirmar validação física nem publicação na Play antes dessa confirmação.

## Segunda falha observada: confirmação antes do registro

Após instalar o primeiro APK 1.2.4+9, o autor conseguiu procurar/selecionar o
kit no Samsung. Captura por ADB mostrou `not_associated`, emitido pelo app
antes de iniciar a conexão BLE. Ao abrir Kits associados em seguida, o mesmo
kit já estava listado. Esse comportamento indica diferença de tempo entre
o resultado da seleção e a disponibilidade da associação na consulta.

Ajuste adicional, ainda na versão local 1.2.4+9: após a seleção, consulta
imediatamente e, se necessário, a cada 150 ms por até 3 s. Usa Handler no
thread principal, sem sleep/bloqueio. Só retorna o kit ao Flutter quando a
associação é confirmada; erro, fim do prazo ou cancelamento encerram a espera.
Callbacks duplicados não iniciam duas esperas e onDestroy cancela a operação.

Seis testes adicionais de AssociationConfirmation aprovados no framework
8.1: registro imediato, registro atrasado, prazo esgotado sem autorização,
cancelamento com registro tardio, nova tentativa após cancelamento e exceção
na consulta. Junto com os seis casos do filtro, 12 testes nativos aprovados.
Comando atualizado: `gradlew.bat :app:testDebugUnitTest --tests "com.microarca.app.*Test"`.

Segundo APK instalado via ADB no Samsung, mantendo id `.teste` e código 9:
`../../output/app-revisao/cdm-android81/MicroARCA-Teste-1.2.4+9-associacao.apk`.
Captura do erro anterior: `samsung-erro-conexao.png`, na mesma pasta.
Ainda é necessário conferir o fluxo completo após esta segunda instalação.

Atualização posterior: o autor informou “deu certo” após testar a segunda
instalação. Registrado como confirmação do autor, sem alegar observação
independente de todo o fluxo. A captura seguinte foi de um problema de
frontend no diálogo Novo projeto; esse ajuste foi mantido separado dos
testes nativos do CDM.
