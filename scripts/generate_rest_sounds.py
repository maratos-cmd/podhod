#!/usr/bin/env python3
"""Original synthesized rest sounds. PCM16 mono WAV, normalized with headroom; no third-party recordings."""
from pathlib import Path
import math
import struct
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parent.parent / 'Podhod/Resources'

def tone(t, start, duration, frequency, rich=False):
    x = t - start
    if not 0 <= x < duration:
        return 0.0
    envelope = min(1.0, x / .008, (duration - x) / .03)
    signal = math.sin(2 * math.pi * frequency * x)
    if rich:
        signal += .3 * math.sin(2 * math.pi * frequency * 3 * x) + .12 * math.sin(2 * math.pi * frequency * 5 * x)
    return signal * envelope

def bell(t, start):
    x = t - start
    if not 0 <= x < 1.25:
        return 0.0
    return min(1, x / .005, (1.25 - x) / .03) * math.exp(-x * 2.5) * sum(
        amplitude * math.sin(2 * math.pi * frequency * x)
        for amplitude, frequency in [(1, 740), (.5, 1210), (.3, 1880), (.15, 2450)])

PRESETS = {
    'rest-short.wav': (.65, lambda t: tone(t, 0, .45, 1000, True)),
    'rest-double.wav': (1.35, lambda t: tone(t, 0, .4, 880) + tone(t, .55, .55, 1174.66)),
    'rest-triple.wav': (1.8, lambda t: sum(tone(t, i * .5, .3, 950 + i * 170, True) for i in range(3))),
    'rest-electronic.wav': (2.2, lambda t: sum(tone(t, i * .24, .17, 700 if i % 2 == 0 else 1400, True) for i in range(8))),
    'rest-bell.wav': (2.6, lambda t: bell(t, 0) + bell(t, 1.25)),
    'rest-alarm.wav': (3.0, lambda t: sum(tone(t, i * .32, .23, 850 if i % 2 == 0 else 1100, True) for i in range(8))),
}

if __name__ == '__main__':
    for name, (duration, sample) in PRESETS.items():
        values = [sample(i / RATE) for i in range(int(duration * RATE))]
        gain = .88 / max(abs(value) for value in values)
        frames = b''.join(struct.pack('<h', round(value * gain * 32767)) for value in values)
        with wave.open(str(ROOT / name), 'wb') as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(RATE); output.writeframes(frames)
        print(f'{name}: {duration:.2f} с, пик 0.88, PCM16 mono {RATE} Гц')
