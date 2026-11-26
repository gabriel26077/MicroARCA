from machine import Pin, ADC, PWM
import time

pin_led_verde = None
pin_led_vermelho = None
pin_botao = None

_microarca_pinos = {}
_microarca_modos = {}
_microarca_adcs = {}
_microarca_pwms = {}

def _microarca_numero_pino(numero, saida=False):
    if isinstance(numero, bool) or int(numero) != numero:
        raise ValueError('O pino deve ser um numero inteiro')
    numero = int(numero)
    if numero not in (0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 37, 38, 39):
        raise ValueError('Pino indisponivel no ESP32 classico')
    if saida and numero >= 34:
        raise ValueError('Este pino aceita somente entrada')
    return numero

def _microarca_parar_pwm(numero):
    numero = _microarca_numero_pino(numero, True)
    pwm = _microarca_pwms.get(numero)
    if pwm is not None:
        try:
            pwm.duty_u16(0)
        finally:
            pwm.deinit()
            del _microarca_pwms[numero]
    _microarca_adcs.pop(numero, None)
    _microarca_pinos[numero] = Pin(numero, Pin.OUT, value=0)
    _microarca_modos[numero] = Pin.OUT

def _microarca_configurar_pino(numero, modo, pull=None):
    numero = _microarca_numero_pino(numero, modo == Pin.OUT)
    if pull is not None and numero >= 34:
        raise ValueError('Este pino nao possui pull-up interno')
    if numero in _microarca_pwms:
        _microarca_parar_pwm(numero)
    _microarca_adcs.pop(numero, None)
    pino = Pin(numero, modo, pull)
    _microarca_pinos[numero] = pino
    _microarca_modos[numero] = modo
    return pino

def _microarca_obter_pino(numero, modo):
    numero = _microarca_numero_pino(numero, modo == Pin.OUT)
    if numero in _microarca_pwms or numero in _microarca_adcs or _microarca_modos.get(numero) != modo:
        return _microarca_configurar_pino(numero, modo)
    return _microarca_pinos[numero]

def _microarca_ler_analogico(numero):
    numero = _microarca_numero_pino(numero)
    if numero not in (0, 2, 4, 12, 13, 14, 15, 25, 26, 27, 32, 33, 34, 35, 36, 37, 38, 39):
        raise ValueError('Este pino nao possui ADC')
    if numero not in _microarca_adcs:
        pino = _microarca_configurar_pino(numero, Pin.IN)
        adc = ADC(pino)
        adc.atten(ADC.ATTN_11DB)
        _microarca_adcs[numero] = adc
    return _microarca_adcs[numero].read_u16()

def _microarca_configurar_pwm(numero, frequencia):
    numero = _microarca_numero_pino(numero, True)
    if isinstance(frequencia, bool) or int(frequencia) != frequencia or not 1 <= frequencia <= 40000:
        raise ValueError('Frequencia PWM deve ser inteira, entre 1 e 40000 Hz')
    pino = _microarca_configurar_pino(numero, Pin.OUT)
    _microarca_pwms[numero] = PWM(pino, freq=int(frequencia), duty_u16=0)

def _microarca_escrever_pwm(numero, percentual):
    numero = _microarca_numero_pino(numero, True)
    if isinstance(percentual, bool) or not 0 <= percentual <= 100:
        raise ValueError('PWM deve estar entre 0 e 100%')
    if numero not in _microarca_pwms:
        raise ValueError('Configure o PWM deste pino antes de escrever')
    _microarca_pwms[numero].duty_u16(int(percentual * 65535 / 100 + 0.5))

def _microarca_finalizar_pwm():
    for numero in list(_microarca_pwms):
        try:
            _microarca_parar_pwm(numero)
        except Exception as erro:
            print('Falha ao desligar PWM:', erro)

def sinal_verde():
  _microarca_obter_pino(pin_led_verde, Pin.OUT).value(1 if True else 0)
  _microarca_obter_pino(pin_led_vermelho, Pin.OUT).value(1 if False else 0)

def sinal_vermelho():
  _microarca_obter_pino(pin_led_verde, Pin.OUT).value(1 if False else 0)
  _microarca_obter_pino(pin_led_vermelho, Pin.OUT).value(1 if True else 0)


try:
  pin_led_verde = 22
  pin_led_vermelho = 23
  pin_botao = 21
  _microarca_configurar_pino(pin_led_verde, Pin.OUT)
  _microarca_configurar_pino(pin_led_vermelho, Pin.OUT)
  _microarca_configurar_pino(pin_botao, Pin.IN, Pin.PULL_UP)
  while True:
    sinal_verde()
    if not bool(_microarca_obter_pino(pin_botao, Pin.IN).value()):
      time.sleep(max(0, min(3600, float(3))))
      sinal_vermelho()
      time.sleep(max(0, min(3600, float(8))))
    time.sleep(max(0, min(3600, float(0.1))))

finally:
  _microarca_finalizar_pwm()