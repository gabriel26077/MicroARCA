# Demonstrações

Os vídeos são registros técnicos produzidos pelo autor. Permanecem no YouTube; este índice mantém os endereços associados aos exemplos e às imagens do projeto.

| Demonstração | Conteúdo | Material complementar |
| --- | --- | --- |
| [Semáforo simples](https://youtube.com/shorts/4j4VN3_md6g) | Acionamento alternado dos LEDs verde e vermelho por um programa em blocos. | [Montagem e ligações](montagens.md#semáforo-simples) |
| [Leitura digital de botão](https://youtu.be/rywTD_ZDoG4) | Botão no GPIO 21, entrada com pull-up interno e apresentação do estado no console. | [Blocos](../imagens/botao/blocos.jpeg) · [Console](../imagens/botao/console.jpeg) |
| [Semáforo com botão](https://youtube.com/shorts/Z60QdG66KMw) | Uso de funções, variáveis e condição: o botão solicita a passagem do sinal verde para vermelho. | [Blocos](../imagens/semaforo-botao/blocos.jpeg) · [Montagem](montagens.md#semáforo-com-botão) |
| [Conversão de blocos para Python](https://youtube.com/shorts/yihG3YCMe60) | Conversão do semáforo com botão e execução do programa Python resultante na placa. | [Código completo gerado](../exemplos/semaforo-com-botao/main.py) |
| [Projeto Python, erro e entrada pelo console](https://youtube.com/shorts/oPV4c6HjdaU) | Dois arquivos Python, identificação de erro de digitação, correção e resposta a input(). | [Código e capturas](../exemplos/projeto-python/README.md) |
| [Biblioteca e tela OLED](https://youtube.com/shorts/W23DYBzJblE) | Instalação e uso de biblioteca do catálogo para escrever e desenhar na tela. | [Exemplo fotográfico adicional](../exemplos/tela-oled/README.md) |
| [Persistência, execução ao ligar e console](https://www.youtube.com/shorts/qJykF9K4wJY) | Reabertura de projeto, gravação para executar ao ligar a placa e saída textual no console. | [Tela OLED e ligações](montagens.md#tela-oled) |

## Condições dos registros

Os ensaios utilizam um ESP32 genérico clássico e um Moto g34 5G com Android 15. As demonstrações recentes de botão, conversão e projeto Python utilizam a versão 1.2.3 do aplicativo. O semáforo simples e o ensaio OLED são registros anteriores, associados à versão 1.0.0. A versão do aplicativo não aparece no vídeo de persistência e execução ao ligar.

Os tempos e desenhos dos exemplos não são idênticos em todos os registros. No semáforo simples, o vídeo mostra tempos de dois segundos para o verde e três para o vermelho. O código OLED disponível neste repositório corresponde à montagem fotografada com texto e várias figuras; o vídeo OLED mostra outro desenho. Os materiais foram mantidos com essas diferenças, sem alterar retrospectivamente os programas.

[Voltar à apresentação](../README.md)
