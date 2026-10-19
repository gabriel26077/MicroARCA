# Publicação de teste do MicroARCA

O app Android usa o identificador definitivo `com.microarca.app`. Depois do
primeiro envio à Play Console, esse identificador não pode ser alterado para o
mesmo aplicativo.

## Gerar o pacote

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
