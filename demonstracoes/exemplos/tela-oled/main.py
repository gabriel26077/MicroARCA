from lib_oled_pintor import criar_tela


tela = criar_tela(scl=max(0, min(39, int(22))), sda=max(0, min(39, int(23))))
tela.limpa()
tela.escreve('Ola!!! ', max(0, min(127, int(40))), max(0, min(63, int(0))))
tela.coracao(max(0, min(127, int(15))), max(0, min(63, int(32))), max(1, min(32, int(12))))
tela.circulo(max(0, min(127, int(64))), max(0, min(63, int(32))), max(1, min(63, int(10))))
tela.retangulo(max(0, min(127, int(90))), max(0, min(63, int(20))), max(0, min(127, int(120))), max(0, min(63, int(44))))
tela.atualiza()