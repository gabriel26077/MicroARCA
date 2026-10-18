/* GPIO/ADC/PWM blocks and their self-contained MicroPython runtime. */
"use strict";

const MicroArcaIO = {
  types: [
    "microarca_pin_read", "microarca_analog_read", "microarca_pwm_config",
    "microarca_pwm_write", "microarca_pwm_stop",
  ],
  defaults: {
    microarca_pin_read: { PIN: 4 },
    microarca_analog_read: { PIN: 34 },
    microarca_pwm_config: { PIN: 2, FREQUENCY: 1000 },
    microarca_pwm_write: { PIN: 2, DUTY: 50 },
    microarca_pwm_stop: { PIN: 2 },
  },
  install(Blockly, python) {
    const generator = python.pythonGenerator;
    const number = (name) => ({ type: "input_value", name, check: "Number" });
    const block = (type, message0, args0, tooltip, output) => ({
      type, message0, args0, tooltip, inputsInline: true,
      style: "microarca_io_blocks", helpUrl: "",
      ...(output ? { output } : { previousStatement: null, nextStatement: null }),
    });
    Blockly.defineBlocksWithJsonArray([
      block("microarca_pin_read", "ler pino digital %1", [number("PIN")],
        "Retorna ALTO ou BAIXO. Usa entrada por padrão e preserva o pull-up configurado.", "Boolean"),
      block("microarca_analog_read", "ler pino analógico %1 (0–65535)", [number("PIN")],
        "Lê um pino ADC com atenuação de 11 dB. A escala 0–65535 não representa precisão de 16 bits.", "Number"),
      block("microarca_pwm_config", "configurar PWM no pino %1 frequência %2 Hz",
        [number("PIN"), number("FREQUENCY")], "Configura PWM inicialmente em 0%. Frequência de 1 a 40000 Hz."),
      block("microarca_pwm_write", "definir PWM no pino %1 em %2 %",
        [number("PIN"), number("DUTY")], "Define o ciclo ativo de 0 a 100%. Configure o PWM antes."),
      block("microarca_pwm_stop", "desligar PWM no pino %1", [number("PIN")],
        "Libera o PWM e deixa o pino em nível BAIXO."),
    ]);

    function runtime(g) {
      g.definitions_.microarca_import_pin = "from machine import Pin, ADC, PWM";
      g.definitions_.microarca_pin_registry =
        "_microarca_pinos = {}\n_microarca_modos = {}\n_microarca_adcs = {}\n_microarca_pwms = {}";
      g.definitions_["%microarca_io"] = `def _microarca_numero_pino(numero, saida=False):
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
`;
    }
    const value = (b, name, g, fallback) =>
      g.valueToCode(b, name, python.Order.NONE) || String(fallback);
    generator.forBlock.microarca_pin_mode = (b, g) => {
      runtime(g);
      const mode = b.getFieldValue("MODE");
      return `_microarca_configurar_pino(${value(b, "PIN", g, 2)}, Pin.${mode === "OUT" ? "OUT" : "IN"}${mode === "PULL_UP" ? ", Pin.PULL_UP" : ""})\n`;
    };
    generator.forBlock.microarca_pin_write = (b, g) => {
      runtime(g);
      return `_microarca_obter_pino(${value(b, "PIN", g, 2)}, Pin.OUT).value(1 if ${value(b, "LEVEL", g, "False")} else 0)\n`;
    };
    generator.forBlock.microarca_pin_read = (b, g) => {
      runtime(g);
      return [`bool(_microarca_obter_pino(${value(b, "PIN", g, 4)}, Pin.IN).value())`, python.Order.FUNCTION_CALL];
    };
    generator.forBlock.microarca_analog_read = (b, g) => {
      runtime(g);
      return [`_microarca_ler_analogico(${value(b, "PIN", g, 34)})`, python.Order.FUNCTION_CALL];
    };
    generator.forBlock.microarca_pwm_config = (b, g) => {
      runtime(g);
      return `_microarca_configurar_pwm(${value(b, "PIN", g, 2)}, ${value(b, "FREQUENCY", g, 1000)})\n`;
    };
    generator.forBlock.microarca_pwm_write = (b, g) => {
      runtime(g);
      return `_microarca_escrever_pwm(${value(b, "PIN", g, 2)}, ${value(b, "DUTY", g, 50)})\n`;
    };
    generator.forBlock.microarca_pwm_stop = (b, g) => {
      runtime(g);
      return `_microarca_parar_pwm(${value(b, "PIN", g, 2)})\n`;
    };
    // Keep imports, variables and function definitions at module scope. Only
    // the executable body is wrapped, so functions still see project globals.
    const finish = generator.finish;
    generator.finish = function (code) {
      const cleanup = [];
      if (this.definitions_.microarca_pin_registry) cleanup.push("_microarca_finalizar_pwm()");
      if (Object.values(this.definitions_).some((line) => line.includes("from lib_buzzer_passivo import"))) {
        this.definitions_.microarca_buzzer_cleanup = "from lib_buzzer_passivo import parar_todos as _microarca_parar_buzzers";
        cleanup.push("_microarca_parar_buzzers()");
      }
      if (cleanup.length && code.trim()) {
        code = "try:\n" + this.prefixLines(code, this.INDENT) +
          "\nfinally:\n" + this.prefixLines(cleanup.join("\n") + "\n", this.INDENT);
      }
      return finish.call(this, code);
    };
  },
};
