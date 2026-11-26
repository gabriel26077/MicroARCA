# Seleção de kits pelo Android — 1.2.1+6

**Atualização local 14/11/2026 (1.2.4+9):** relatório do Samsung SM-J260M /
Android 8.1 mostrou crash do CDM no filtro UUID (`Arrays.asList` com cache
nulo). Em API 26–29, o app agora filtra pelo nome completo ARCA-XXXXXX,
mantendo o CDM. Em API 30+, preserva o UUID. Detalhes, testes e limites em
`cdm-android-antigo.md`. APK de teste preparado; o funcionamento no Samsung
foi confirmado pelo usuário em 14/11/2026, conforme o registro de desenvolvimento.
As descrições abaixo registram a implementação anterior.

Implementação de 09/11/2026, posterior à versão 1.2.0+5. Versão 1.2.1+6
publicada no teste interno da Play às 20:22 desse dia; não é produção.
Registro em `../../output/playstore/publicacao-1.2.1.md`.

## Comportamento

- Se o Bluetooth estiver desligado, procurar ou reconectar solicita sua
  ativação pela janela oficial do Android (`ACTION_REQUEST_ENABLE`). Ao
  aceitar, o app confere o adaptador e continua; recusar encerra a operação.
  Cancelar a operação invalida respostas tardias dessa janela também.
- Android 8 ou mais recente (API 26+): **Procurar kits** abre o seletor do
  Companion Device Manager (CDM). O filtro procura o UUID do serviço ARCA
  `6e400001-b5a3-f393-e0a9-e50e24dcca9e`, já anunciado pelo firmware.
- Após a autorização, o app verifica a associação registrada no Android e
  abre a conexão GATT pelo transporte existente. CDM não substitui BLE,
  raw REPL ou o protocolo de arquivos e não exige mudança no firmware.
- **Kits associados** consulta o Android, permite reconectar e esquecer uma
  associação. Esquecer o kit conectado primeiro desconecta o app. Não apaga
  programas da placa nem promete interromper um programa em execução.
- Android 7/7.1 (API 24/25): mantém a busca BLE anterior, porque não possui
  CDM. A localização fina fica limitada a essas versões no manifesto.
- Em API 26+, ausência/falha do CDM não aciona busca BLE própria como
  alternativa. O app informa a indisponibilidade.
- Android 12+: pede `BLUETOOTH_CONNECT`; `BLUETOOTH_SCAN` foi retirado do
  manifesto mesclado. Android 8+ não pede permissão de localização. O
  serviço de localização do sistema pode precisar estar ligado para o CDM.

Os fluxos API 26–32 usam o callback e resultado anteriores; API 33+ usa
`AssociationInfo`. Respostas atrasadas não iniciam conexão após cancelar.
Solicitações têm códigos distintos para que o resultado de uma janela
anterior não cancele uma nova. Associações novas notificadas após cancelar
são desfeitas; associações já existentes são preservadas. A associação do
Android não acrescenta autenticação ao protocolo da placa.

## Verificação

- Testes Dart verificam cancelamento, resposta tardia, duplo toque, falha
  ao fechar a janela, Bluetooth desligado, CDM indisponível, associação
  ausente/revogada e contratos de listagem e esquecimento.
- Emulador `Medium_Phone`, Android 37.2: instalação do APK de teste;
  permissão de dispositivos próximos; abertura efetiva de
  `com.android.companiondevicemanager/.CompanionAssociationActivity`;
  cancelamento pelo botão do sistema e consulta da lista vazia.
- Manifesto debug mesclado: versão 1.2.1, código 6; sem `BLUETOOTH_SCAN`,
  sem localização ampla e com `ACCESS_FINE_LOCATION` limitada à API 25.

O registro final de comandos, resultados e artefatos fica em
`../../output/app-revisao/validacao-cdm.md`. Nenhum celular foi detectado
pelo ADB e nenhum kit físico foi utilizado neste ensaio. Seleção de placa real, conexão,
transferência, reconexão e remoção de associação real permanecem para
ensaio no Moto G34 com ESP32. Não houve execução em API 24–32 nesta sessão.
Os testes com canais simulados não substituem essas verificações.

## Referências consultadas

- [Pareamento com dispositivos complementares](https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing).
- [Callbacks do CDM](https://developer.android.com/reference/android/companion/CompanionDeviceManager.Callback).
- [Preparação e ativação do Bluetooth](https://developer.android.com/develop/connectivity/bluetooth/setup).
- [CompanionDeviceManager](https://developer.android.com/reference/android/companion/CompanionDeviceManager).
- [Política de famílias da Play](https://support.google.com/googleplay/android-developer/answer/9893335?hl=pt-BR).

A integração atende ao mecanismo técnico escolhido; não comprova por si
só conformidade integral com a política de famílias nem aprovação da Play.
