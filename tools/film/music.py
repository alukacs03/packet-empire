#!/usr/bin/env python3
"""Compose the demo film's background track: a lo-fi loop in A minor at 92 bpm
(detuned saw pad, plucked arpeggio, sine bass, kick, snare, hats), written as
a stereo 48 kHz WAV. Needs numpy. usage: music.py <out.wav> [seconds]"""
import sys, wave
import numpy as np

sr = 48000
bpm = 92
beat = 60 / bpm
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 78.0
bars = int(seconds / (4 * beat)) + 1
total = bars * 4 * beat
t = np.arange(int(total * sr)) / sr
midi = lambda n: 440 * 2 ** ((n - 69) / 12)
prog = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]  # Am F C G


def env(n, a, d, s, r):
    x = np.zeros(n); sa, sd, sr_ = int(a * sr), int(d * sr), int(r * sr)
    x[:sa] = np.linspace(0, 1, sa); x[sa:sa + sd] = np.linspace(1, s, sd); x[sa + sd:] = s
    tail = min(sr_, n); x[-tail:] *= np.linspace(1, 0, tail)
    return x


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / sr); y = np.zeros_like(x); p = 0.0
    for i in range(len(x)):
        p = a * p + (1 - a) * x[i]; y[i] = p
    return y


out = np.zeros(len(t))
for bar in range(bars):
    ch = prog[(bar // 2) % 4]
    n0, n1 = int(bar * 4 * beat * sr), int((bar + 1) * 4 * beat * sr); n = n1 - n0
    tt = np.arange(n) / sr
    pad = np.zeros(n)
    for m in ch:
        for det in (-0.4, 0.4):
            f = midi(m - 12) * 2 ** (det / 1200)
            pad += 2 * ((f * tt) % 1) - 1
    out[n0:n1] += lowpass(pad, 900) * env(n, 0.4, 0.5, 0.8, 0.6) * 0.08
    arp = [m + 12 for m in ch] + [ch[0] + 24]
    for k in range(8):
        f = midi(arp[k % 4]); s0 = n0 + int(k * beat / 2 * sr); ln = int(beat * 0.45 * sr)
        tt2 = np.arange(ln) / sr
        out[s0:s0 + ln] += (2 * np.abs(2 * ((f * tt2) % 1) - 1) - 1) * np.exp(-tt2 * 6) * 0.09
    for k in (0, 2):
        f = midi(ch[0] - 24); s0 = n0 + int(k * beat * sr); ln = int(beat * 0.9 * sr); tt2 = np.arange(ln) / sr
        out[s0:s0 + ln] += np.sin(2 * np.pi * f * tt2) * np.exp(-tt2 * 2.5) * 0.18
    rng = np.random.default_rng(bar)
    for k in range(4):
        s0 = n0 + int(k * beat * sr)
        if k in (0, 2):
            ln = int(0.25 * sr); tt2 = np.arange(ln) / sr
            out[s0:s0 + ln] += np.sin(2 * np.pi * (55 + 90 * np.exp(-tt2 * 30)) * tt2) * np.exp(-tt2 * 12) * 0.35
        else:
            ln = int(0.18 * sr); tt2 = np.arange(ln) / sr
            out[s0:s0 + ln] += lowpass(rng.standard_normal(ln), 3500) * np.exp(-tt2 * 18) * 0.28
    for k in range(8):
        s0 = n0 + int(k * beat / 2 * sr); ln = int(0.05 * sr); tt2 = np.arange(ln) / sr
        out[s0:s0 + ln] += (rng.standard_normal(ln) - lowpass(rng.standard_normal(ln), 4000)) * np.exp(-tt2 * 60) * 0.05
fade = int(1.5 * sr); out[:fade] *= np.linspace(0, 1, fade); out[-int(4 * sr):] *= np.linspace(1, 0, int(4 * sr))
out = out / np.max(np.abs(out)) * 0.7
right = np.concatenate([np.zeros(240), out[:-240]])
stereo = np.stack([out, right], axis=1)
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
w.writeframes((stereo * 32767).astype(np.int16).tobytes()); w.close()
