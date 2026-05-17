from machine import ADC, Pin
import time

sensor = ADC(Pin(34))

while True:
    valor = sensor.read()
    print(f"ADC D23: {valor}")
    time.sleep(0.2)