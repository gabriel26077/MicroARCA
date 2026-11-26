# Declarações de dados e configuração da Play — 09/11/2026

## Base técnica

App local 1.2.2+7, incluindo documentos offline, posterior à 1.2.1+6 do
teste interno. Não confundir o preenchimento da Console com aprovação da
publicação em produção. O autor informou que testou o fluxo da 1.2.1 no
Moto G34 com ESP32 e que funcionou; este é um relato do autor, não um novo
ensaio físico observado pela IA.

Inspeção do cliente HTTP: consultas/downloads do catálogo por HTTPS,
User-Agent MicroARCA/0.1.0 e ETag. Não inclui projetos, endereço BLE do kit
ou cadastro nesses pedidos. Não há anúncios, conta de usuário, envio de
falhas por um SDK do app, nem coleta de coordenadas GPS. As transferências
BLE são entre o celular e a placa escolhida pelo usuário.

Consulta somente de leitura à VPS confirmou o servidor atual `edge-caddy`,
com rota de arquivos para o catálogo e sem logging de acessos HTTP habilitado
na configuração ativa. Nada da infraestrutura do TraceEdu foi modificado.
Isso não implica ausência de registros técnicos dos provedores.

Cloudflare oferece métricas de tráfego, erros, visitantes e país de origem,
inclusive no plano Free. Essa observação da documentação exige considerar
região inferida a partir do IP na declaração; não é uso do GPS pelo app.

## Segurança dos dados

Tipos declarados como coletados por causa da infraestrutura do catálogo:

| Tipo da Console | Dado considerado | Finalidades |
| --- | --- | --- |
| Local aproximado | País/região inferidos do IP | Análise; segurança, conformidade e prevenção de fraudes |
| Interações no app | Requisições/acessos ao catálogo e aos pacotes | Funcionalidade; análise; segurança, conformidade e prevenção de fraudes |
| Diagnóstico | Metadados técnicos de requisição, resposta, erros e desempenho do serviço | Funcionalidade; análise; segurança, conformidade e prevenção de fraudes |
| Identificadores do dispositivo e outros IDs | IP da conexão, nos registros de infraestrutura | Funcionalidade; análise; segurança, conformidade e prevenção de fraudes |

Não foram declarados Android ID, IMEI, publicidade ou MAC do celular como
coletados: o tipo amplo de identificadores na Console cobre o IP nesse caso.
O identificador da placa é usado localmente para o gerenciamento de kits e
bibliotecas, sem inclusão nos pedidos HTTP.

Todos esses tipos foram declarados não efêmeros devido aos registros e
métricas de infraestrutura. Coleta obrigatória: o app não oferece uma opção
interna para desativar esses metadados mantendo o acesso ao catálogo. Não
foram declarados publicidade, personalização ou gerenciamento de contas.

Marcada a conexão criptografada para os dados coletados pelo serviço HTTPS.
Isso não certifica criptografia própria do armazenamento nem autenticação
do protocolo BLE. O app não cria contas e não oferece login externo.

Os provedores que processam dados para prestar o serviço foram tratados
conforme a exceção de prestador de serviços da definição de compartilhamento
da Play. A indicação de nenhum compartilhamento na ficha da Play não
significa ausência de provedores; eles são identificados na política.

Página de solicitação de exclusão:
https://gabriel26077.github.io/microarca-site/exclusao/index.html

O atendimento recebe pedidos por e-mail; não existe apagamento remoto de
celular/placa. Não foi marcada exclusão automática universal em 90 dias.
O prazo de suporte não foi estendido aos registros dos fornecedores.

## Confirmações do autor

- Público a partir de 9 anos, com acompanhamento adulto para crianças e
  adolescentes; também inclui adultos.
- Rotina de revisão mensal da caixa de suporte e exclusão dos atendimentos
  encerrados há mais de 90 dias, incluindo anexos e lixeira, salvo necessidade
  legal: confirmada pelo autor nesta conversa.
- Aceite dos Termos de Uso da IARC e envio do e-mail de suporte para contato
  da classificação: explicitamente autorizados pelo autor.
- Declaração do desenvolvedor sobre cumprimento de regras de proteção
  infantil: explicitamente autorizada pelo autor. Não é uma certificação
  jurídica ou auditoria independente emitida pela IA.

## Classificação e público

Questionário: Todos os Outros Tipos de Aplicativo; sem material sensível
embutido; sem troca de conteúdo entre usuários; conteúdo online devido ao
catálogo; sem violência, sexualidade, linguagem ofensiva ou drogas no
catálogo; sem produtos restritos, compras digitais, recompensas, browser
ou compartilhamento de localização com outros usuários. Produto educativo.

Resultado apresentado e salvo na Console: Classificação Livre no Brasil;
ESRB Livre; PEGI 3; USK todas as idades; IARC genérico 3 anos. Sujeito à
revisão pelas autoridades/Google. Público declarado: 9–12, 13–15, 16–17 e
18+. Não inscrito no programa opcional Aprovado por Professores.

## Página da loja e imagens

Cadastro inicial concluído na Console: nome MicroARCA, descrições em pt-BR,
categoria Educação, e-mail de suporte, site e três capturas reais do emulador
(blocos, Python e bibliotecas). Ícone e recurso gráfico foram rotulados como
criados/editados com IA; o autor confirmou explicitamente a origem do ícone.
As capturas são registros do app, sem geração de telas fictícias.

Após salvar, a Console confirmou a mudança e o painel passou à etapa de
teste fechado. Ainda exige publicação nessa faixa, ao menos 12 participantes
que aceitem o teste e permanência por 14 dias consecutivos. O painel mostrava
zero participantes; instalações no teste interno não cumprem esse requisito.

Posteriormente, com autorização do autor, a faixa Alpha foi configurada para
Brasil, com a lista existente `testadores` (26 contas) e o AAB 1.2.2+7.
O impedimento adicional de ID de publicidade foi resolvido declarando que
o app não o utiliza, após conferir dependências, código e manifesto release.
Console confirmou “14 mudanças enviadas para revisão” e passou a exibir
“Alterações em análise”, com verificações rápidas ainda em execução.
Isso não significa aprovação do Google nem início dos 14 dias de adesão.

## Referências conferidas

- [Segurança dos dados — definições e exceções](https://support.google.com/googleplay/android-developer/answer/10787469?hl=pt-BR).
- [Dados do usuário e Política de Privacidade](https://support.google.com/googleplay/android-developer/answer/10144311?hl=pt-BR).
- [Cloudflare Zone Analytics — requisições por país e métricas](https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/).
- [Privacidade da Cloudflare](https://www.cloudflare.com/privacypolicy/).
- [Termos da IARC, consultados antes do aceite autorizado](https://web.iarcservices.com/terms).
- [Declaração de recursos de IA](https://support.google.com/googleplay/android-developer/answer/17262077?hl=pt-BR).

Os textos publicados estão no repositório separado `microarca-site`.
Artefatos e registros operacionais de envio ficam em `../../output/playstore/`.
