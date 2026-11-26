# Publicação de teste do MicroARCA

O app Android usa o identificador definitivo `com.microarca.app`. Depois do
primeiro envio à Play Console, esse identificador não pode ser alterado para o
mesmo aplicativo.

## Gerar o pacote

### Instalação local para teste

`flutter build apk --debug` gera o **MicroARCA Teste**, com identificador
`com.microarca.app.teste`. Essa cópia pode ser instalada junto à versão da Play
Store, que usa outra assinatura. Cada aplicativo guarda seus próprios projetos
e preferências; instalar a cópia de teste não migra os dados da versão da Play.
O APK fica em `build/app/outputs/flutter-apk/app-debug.apk`.

### Pacote de publicação

A chave de envio fica fora do repositório, em
`%USERPROFILE%\.microarca\play-upload.jks`. As senhas e o caminho da chave
ficam em `%USERPROFILE%\.microarca\play-upload.properties`. Guarde uma cópia
segura dos dois arquivos para poder publicar atualizações em outro computador.
Não envie esses arquivos ao GitHub.

Na pasta `micro_arca_app`, execute:

```sh
flutter build appbundle --release
```

O arquivo para a Play Console será
`build/app/outputs/bundle/release/app-release.aab`.

## Teste interno na Play Store

1. Crie o aplicativo **MicroARCA** na Play Console como gratuito.
2. Em **Teste e lançamento > Teste interno**, adicione os e-mails Google dos
   participantes e crie uma versão com o AAB gerado acima.
3. Compartilhe com os participantes o link de participação disponibilizado na
   própria Play Console. O app não aparece na busca pública durante esse teste.
4. Instale pelo link em um celular de teste e confirme conexão BLE, execução de
   blocos, console e download de biblioteca antes do workshop.

O teste interno permite até 100 participantes. O requisito de 12 participantes
por 14 dias de contas pessoais novas se aplica ao acesso à produção, não ao
teste interno.

Ícone provisório do beta: `assets/branding/play-store-icon.png`.

## Versão 1.2.0 (código 5)

Publicada em 09/11/2026 no teste interno existente. A Play Console confirmou
“Disponível para testadores internos”. Notas preservadas em
`release_notes/1.2.0-pt-BR.txt`.

O AAB enviado e o ZIP de símbolos nativos estão em
`../../output/playstore/`, na pasta de trabalho. Os símbolos foram anexados
separadamente pela opção “Gerenciar artefatos”, devido ao limite de
transferência de 50 MB da ferramenta de navegador. A assinatura e os hashes
dos arquivos do app foram conferidos. Essa separação não altera o aplicativo.

## Versão 1.2.1 (código 6)

Publicada em 09/11/2026, às 20:22, no teste interno existente. Play confirmou
“Disponível para testadores internos”. Inclui CDM e solicitação para ativar
Bluetooth desligado. Análise limpa, 86 testes Flutter aprovados e lint Android
sem erros. Notas em `release_notes/1.2.1-pt-BR.txt`; AAB, símbolos nativos
anexados separadamente, hashes e detalhes em
`../../output/playstore/publicacao-1.2.1.md`. Sem publicação em produção.

## Versão 1.2.2 (código 7)

Publicada em 09/11/2026, às 22:01, no teste interno existente. A Play confirmou
“Disponível para testadores internos”. Inclui Sobre e privacidade, com termos
e política disponíveis offline e links para os documentos publicados.
Análise limpa, 87 testes Flutter aprovados, release/debug e lint concluídos.
Os 446 arquivos de base foram preservados por SHA-256; assinatura conferida
e símbolos nativos anexados separadamente. Registro e hashes em
`../../output/playstore/publicacao-1.2.2.md`.

Cadastro inicial da loja concluído. Teste fechado Alpha preparado com o mesmo
AAB, Brasil e lista existente de 26 contas, conforme autorização do autor.
Console confirmou “14 mudanças enviadas para revisão” e “Alterações em análise”.
Verificações rápidas ainda em execução, sem aprovação do Google. Não é
publicação em produção; a lista de e-mails não equivale à adesão ao teste.

## Versão 1.2.3 (código 8) — preparada localmente

Novo bloco Repetir enquanto na categoria Controle. Análise limpa, 87 testes
Flutter, 8 verificações IO e 3 de while aprovados; menu, inserção, código e
persistência conferidos no emulador. Sem ensaio físico nem mudança no firmware.

Use `scripts/preparar-versao.ps1`, a partir da raiz do repositório, para
preparar as próximas versões. Guia completo: `../docs/publicar-versao-play.md`.
O script foi executado com sucesso para 1.2.3+8. AAB completo assinado, com
símbolos preservados, notas e hashes em `build/publicacao/1.2.3+8/`.
Não enviado à Play; envio manual a cargo do autor, conforme o fluxo combinado.

## Versão 1.2.4 (código 9) — correção local do CDM antigo

Preparado APK MicroARCA Teste para confirmação no Samsung SM-J260M/Android
8.1. Relatório do autor identifica crash do CDM ao filtrar UUID; ajuste usa
nome ARCA-XXXXXX em API 26–29, preservando o seletor do sistema. Sem alteração
do firmware ou das permissões por esta correção.

Seis testes nativos Robolectric, 87 testes Flutter e análise aprovados.
Detalhes e limites em `../docs/cdm-android-antigo.md`. APK em
`../../output/app-revisao/cdm-android81/MicroARCA-Teste-1.2.4+9.apk`.
Não enviado à Play, sem AAB novo nesta rodada; teste no Samsung pendente.

Após testar o primeiro APK no Samsung, o autor chegou à seleção, mas recebeu
`not_associated`. Segundo ajuste local aguarda confirmação por até 3 s,
com cancelamento e sem bloquear a tela. Total: 12 testes nativos aprovados;
novo APK e lint concluídos. Instalado no Samsung por ADB, ainda no código 9,
em `../../output/app-revisao/cdm-android81/MicroARCA-Teste-1.2.4+9-associacao.apk`.
Aguardando desbloqueio do aparelho para conferir seleção/conexão completas.

Em seguida, autor confirmou o funcionamento da associação e a correção do
diálogo Novo projeto no Samsung. AAB 1.2.4+9 preparado em 14/11/2026 pelo
script, com 88 testes Flutter, 12 nativos e verificações Blockly aprovados,
análise limpa e assinatura conferida. Arquivos em `build/publicacao/1.2.4+9/`:
`MicroARCA-1.2.4+9.aab` e `notas-para-play-console.txt`.
Símbolos nativos preservados no AAB completo. Certificado de envio igual ao
das versões anteriores. SHA-256 do AAB:
`D491E6762012B723EF5F3F3FB8FBF5F4579A43C7566DD271A833D75B854EF3CD`.
Não enviado à Play; autor solicitou arquivo e notas para realizar o envio.
