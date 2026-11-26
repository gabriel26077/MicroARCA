# Semáforo com botão: Python gerado pelos blocos

[main.py](main.py) é uma cópia integral do programa obtido pelo recurso **Converter em projeto Python**, preservado nos registros do trabalho. O programa convertido foi executado na montagem e seu funcionamento foi registrado pelo autor.

O código inclui funções auxiliares para controle e verificação de pinos, leitura analógica e PWM, mesmo quando não utilizadas pelo semáforo. Elas fazem parte da saída do gerador naquela versão e foram preservadas. Não se trata de uma versão simplificada ou reescrita para esta apresentação.

O programa usa GPIO 22 para o LED verde, GPIO 23 para o vermelho e GPIO 21 para o botão com pull-up interno. As verificações dos pinos correspondem ao ESP32 clássico; este exemplo não foi validado aqui para outras variantes.

- [Blocos originais](../../imagens/semaforo-botao/blocos.jpeg)
- [Componentes e ligações](../../docs/montagens.md#semáforo-com-botão)
- [Vídeo da conversão e execução](https://youtube.com/shorts/yihG3YCMe60)

Para reproduzir no MicroARCA, utilize um projeto Python com o conteúdo de main.py e a placa previamente preparada para o aplicativo.
