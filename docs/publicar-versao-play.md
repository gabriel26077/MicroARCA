# Preparar e enviar uma versão do MicroARCA

## 1. Preparar no computador

Abra o PowerShell na pasta `ProjetoARCA` e execute:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar-versao.ps1
```

O `Bypass` vale apenas para esse processo; não altera a política do Windows.
O computador precisa de Flutter, Node, Python e Android Studio/JDK, além da
chave de envio já configurada em `%USERPROFILE%\.microarca\`. Não copie a chave
para o projeto nem a envie ao GitHub.

O script usa a versão de `micro_arca_app/pubspec.yaml`, roda análise e testes,
gera o AAB release e verifica sua assinatura. Ele não altera a versão nem
publica na Play. Falhas interrompem a preparação.

Desde 1.2.4+9, a preparação inclui testes nativos do filtro CDM com Robolectric
(Android 8.1, 10 e 11). Na primeira execução, o Gradle baixa as dependências e
os frameworks necessários; pode demorar mais e exige internet. Esses testes
não substituem a confirmação da busca/seleção no telefone real.

Para a versão atual, os arquivos ficam em:

```text
micro_arca_app/build/publicacao/1.2.4+9/
  MicroARCA-1.2.4+9.aab
  notas-para-play-console.txt
  notas-pt-BR.txt
  SHA256.txt
  versao.json
  preparacao.log
```

Use os arquivos somente depois de o script terminar com sucesso. O AAB completo
preserva os metadados e símbolos gerados pelo Flutter; não é necessário separar
ou refazer a assinatura para fazer upload manual no seu navegador. Os ZIPs
separados das sessões anteriores foram necessários pelo limite da ferramenta
de automação, não pelo envio manual da Console.

## 2. Conferir no app

Antes de enviar, use uma instalação de teste para abrir um projeto de blocos,
ir a **Controle → Repetir enquanto**, encaixar uma comparação e comandos,
conferir o Python e salvar/reabrir. Um exemplo é iniciar `contador` em 0,
repetir enquanto `contador < 3`, aumentar em 1 e, após o laço, mostrar o contador.
O resultado esperado é 3. Condição inicialmente falsa não executa o corpo.
O bloco novo começa com BAIXO/falso; substitua pela condição desejada.

Os testes locais executam o Python gerado, mas não substituem o teste com kit
real. A mudança usa `while` padrão: não exige atualização do firmware.

## 3. Enviar à Play Console

1. Abra o [teste fechado Alpha](https://play.google.com/console/u/0/developers/8417117222726546255/app/4973139400701389186/tracks/4699186484896569354).
2. Confira a situação da revisão anterior. Se a Console bloquear a criação
   durante uma análise em andamento, aguarde; não remova o envio anterior só
   para atualizar o app.
3. Clique em **Criar nova versão**. Se aparecer um rascunho existente, abra-o
   e confira seu conteúdo antes de continuar.
4. Envie `MicroARCA-1.2.4+9.aab`. Aguarde o processamento e confirme
   **9 (1.2.4)**. Não use o APK debug “MicroARCA Teste”.
5. Em nome da versão, escreva **MicroARCA 1.2.4 - teste fechado**.
6. Cole todo o conteúdo de `notas-para-play-console.txt` em notas da versão.
7. Clique em **Avançar**. Confira erros, avisos, código 8 e as notas.
8. Clique em **Salvar**. Aguarde a confirmação da Console.
9. Abra **Visão geral da publicação**, confira as mudanças e clique em
   **Enviar mudanças para revisão**, confirmando o diálogo.
10. Confirme que aparece **Alterações em análise**. Isso confirma o envio,
    mas ainda não a aprovação ou disponibilidade aos testadores.

Os nomes dos botões podem variar. Se aparecer uma declaração nova, responda
conforme o comportamento real do app. Não altere a lista de testadores ou os
países para uma atualização comum. Evite editar versões simultaneamente em
várias abas.

## 4. Depois da aprovação

Confira na faixa fechada se a versão está disponível aos testadores e peça
que atualizem pela Play Store. Uma atualização na mesma faixa não exige
sair e entrar novamente no programa. O guia de troca do teste interno para
o fechado é destinado à primeira migração:
https://gabriel26077.github.io/microarca-site/teste/index.html

## Próximas versões

Depois de implementar e conferir a mudança, aumente a versão e o código em
`pubspec.yaml` (ex.: `1.2.5+10`) e crie `release_notes/1.2.5-pt-BR.txt`, com até
500 caracteres. Execute o mesmo script. Cada novo pacote enviado precisa de
um código de versão ainda não utilizado. Não edite notas antigas para uma
versão diferente.
