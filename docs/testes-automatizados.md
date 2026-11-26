# Testes automatizados do MicroARCA

As suítes existentes verificam partes do software sem exigir emulador Android
ou ESP32 físico. Não demonstram qualidade do enlace de rádio, alimentação,
compatibilidade elétrica ou funcionamento integrado na montagem real.

## Executar

Na raiz de ProjetoARCA:

```sh
python -B -m unittest discover -s embedded/tests -v
```

Em `micro_arca_app`:

```sh
flutter test --reporter expanded
flutter analyze
node test/blockly_io_test.mjs
node test/blockly_while_test.mjs
```

Usar `flutter pub get` se as dependências ainda não estiverem disponíveis.
`flutter analyze` é análise estática, não uma suíte de testes.
O teste de `while` inclui a suíte de IO e usa Python local para verificar
reavaliação da condição, término do laço, continuidade do programa, condição
inicial falsa e bloco vazio. Também confere salvar/reabrir e tipagem booleana.

No repositório separado SistemaMicroARCA, usar Linux/WSL:

```sh
python3 -B -m unittest discover -s tests -v
python3 scripts/validate_catalog.py
python3 scripts/build_catalog.py --check
```

Não atualizar o lock nem alterar pacotes publicados para fazer verificações
passarem. O catálogo depende de recursos Linux; a conversão automática de
finais de linha no checkout também pode invalidar os hashes dos metadados.

## Cobertura e limites

- Flutter: armazenamento e operações de projetos, interface, catálogo local,
  console, entrada, ciclo de conexão e protocolo raw REPL com transporte simulado.
- Blockly/Node: geração de Python e preservação de programas ao serializar e
  restaurar blocos, sem navegador ou placa.
- Python embarcado: arquivos, autorun, transporte BLE e recursos auxiliares de
  pinos com substitutos das interfaces de hardware, executados em CPython.
- Catálogo: validação e construção da distribuição, além dos testes específicos
  presentes no repositório. Sua execução completa precisa do ambiente Linux.

## Suíte acrescentada em 09/11/2026

`test/project_deployer_test.dart` exercita o ProjectDeployer real com serviço
de comunicação simulado, sem mudar código de produção. Verifica:

1. Módulo auxiliar enviado antes de main.py, preservando conteúdo e identidade.
2. Remoção de módulo antigo sem remover entrada e módulo reutilizado.
3. Falha de remoção impede envio e execução.
4. Falha no módulo impede envio da entrada, metadados e execução.
5. Falha na entrada impede habilitar autorun.
6. Falha nos metadados impede execução.
7. Executar inicia somente após o envio.
8. Gravar no kit habilita autorun após envio, sem chamar a execução corrente.
9. Ausência de suporte a autorun permite envio, mas impede instalação.
10. Projeto sem entrada ou kit indisponível não inicia mutações.

Esses testes não executam a importação Python na placa e não substituem o
ensaio físico R10. Também não estabelecem atomicidade do projeto inteiro.

## Registro para o TCC

Cada execução deve preservar data, sistema, versões das ferramentas, comando,
log completo, commit e alterações locais. Resultados de uma árvore modificada
não devem ser atribuídos apenas ao commit base. A execução de 09/11/2026 está
em `demonstracoes/testes-automatizados/2026-11-09/`, na pasta raiz de trabalho.
O relatório dessa execução distingue aprovação, falhas e etapas não executadas.
