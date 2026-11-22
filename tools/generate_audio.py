#!/usr/bin/env python3
"""Generate every WAV asset used by the game using only the standard library.

Ten short synth sound effects are rendered at 22.05 kHz and an eight second
seamless music loop is rendered at 11.025 kHz. All files are 16-bit mono PCM
and are written to assets/audio/ next to the project root.
"""

import math
import os
import random
import struct
import wave

SR_SFX = 22050
SR_MUSIC = 11025
TWO_PI = 2.0 * math.pi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")

# Harmonic recipes: (harmonic number, relative amplitude). Keeping the upper
# partials soft avoids the harsh, buzzy sound of a raw square/saw oscillator.
SOFT_SQUARE = ((1.0, 1.0), (3.0, 0.25), (5.0, 0.10))
BELL = ((1.0, 1.0), (2.0, 0.32), (3.01, 0.12))
WARM = ((1.0, 1.0), (2.0, 0.22), (3.0, 0.08))


# ---------------------------------------------------------------------------
# Small synthesis toolkit
# ---------------------------------------------------------------------------

def env_ad(n, sr, attack=0.005, power=2.0, release=0.0):
    """Raised-cosine attack + exponential-ish decay down to silence."""
    a = max(1, min(n, int(sr * attack)))
    r = max(0, min(n - a, int(sr * release)))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            e = 0.5 - 0.5 * math.cos(math.pi * i / a)
        else:
            t = (i - a) / max(1, n - a - 1)
            e = (1.0 - t) ** power
            if r and i >= n - r:
                e *= 0.5 + 0.5 * math.cos(math.pi * (i - (n - r)) / r)
        out[i] = e
    return out


def env_sustain(n, sr, attack=0.10, release=0.20):
    """Smooth gate that starts and ends at exactly zero (good for pad notes)."""
    a = max(1, min(n // 2, int(sr * attack)))
    r = max(1, min(n // 2, int(sr * release)))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            e = 0.5 - 0.5 * math.cos(math.pi * i / a)
        elif i >= n - r:
            e = 0.5 + 0.5 * math.cos(math.pi * (i - (n - r)) / r)
        else:
            e = 1.0
        out[i] = e
    return out


def tone(dur, freq, sr=SR_SFX, harmonics=WARM, glide=1.0, phase=0.0):
    """Band-limited oscillator with optional exponential pitch glide."""
    n = max(1, int(dur * sr))
    out = [0.0] * n
    ph = phase
    for i in range(n):
        p = i / max(1, n - 1)
        f = freq * (1.0 + (glide - 1.0) * p)
        ph += TWO_PI * f / sr
        s = 0.0
        for h, amp in harmonics:
            s += amp * math.sin(ph * h)
        out[i] = s
    return out


def noise(dur, sr=SR_SFX, cutoff=0.3, seed=0):
    """One-pole low-passed white noise: softer than raw random samples."""
    rng = random.Random(seed)
    n = max(1, int(dur * sr))
    out = [0.0] * n
    y = 0.0
    for i in range(n):
        y += cutoff * (rng.uniform(-1.0, 1.0) - y)
        out[i] = y
    return out


def apply_env(sig, env):
    return [s * e for s, e in zip(sig, env)]


def add(dst, src, offset=0, gain=1.0):
    """Mix src into dst at a sample offset, ignoring out-of-range samples."""
    for i, value in enumerate(src):
        j = offset + i
        if 0 <= j < len(dst):
            dst[j] += value * gain


def write_wav(path, samples, sr):
    """Normalize to a safe peak, then write a 16-bit mono PCM WAV file."""
    peak = max((abs(s) for s in samples), default=0.0)
    scale = 0.85 / peak if peak > 1e-9 else 0.0
    frames = bytearray()
    for i in range(0, len(samples), 4096):
        chunk = samples[i:i + 4096]
        frames.extend(struct.pack("<%dh" % len(chunk),
                                  *[int(max(-1.0, min(1.0, s * scale)) * 32767)
                                    for s in chunk]))
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sr)
        wav.writeframes(bytes(frames))


# ---------------------------------------------------------------------------
# Sound effects (all below 1.2 s except the game-over sting)
# ---------------------------------------------------------------------------

def sfx_switch():
    out = [0.0] * int(0.22 * SR_SFX)
    add(out, apply_env(tone(0.09, 620.0, harmonics=SOFT_SQUARE),
                       env_ad(int(0.09 * SR_SFX), SR_SFX, 0.003, 3.0)), 0, 0.50)
    add(out, apply_env(tone(0.09, 930.0, harmonics=SOFT_SQUARE),
                       env_ad(int(0.09 * SR_SFX), SR_SFX, 0.003, 3.0)),
        int(0.09 * SR_SFX), 0.45)
    return out


def sfx_collect():
    out = [0.0] * int(0.34 * SR_SFX)
    for k, freq in enumerate((523.25, 659.25, 783.99, 1046.50)):
        n = int(0.12 * SR_SFX)
        add(out, apply_env(tone(0.12, freq, harmonics=BELL),
                           env_ad(n, SR_SFX, 0.003, 2.6)),
            int(0.055 * k * SR_SFX), 0.30)
    return out


def sfx_perfect():
    out = [0.0] * int(0.78 * SR_SFX)
    for k, freq in enumerate((523.25, 659.25, 783.99, 1046.50)):
        n = int(0.70 * SR_SFX)
        add(out, apply_env(tone(0.70, freq, harmonics=BELL),
                           env_ad(n, SR_SFX, 0.008, 1.5)),
            int(0.035 * k * SR_SFX), 0.22)
    for k, freq in enumerate((1046.50, 1318.51, 1567.98, 2093.00)):
        n = int(0.09 * SR_SFX)
        add(out, apply_env(tone(0.09, freq, harmonics=((1.0, 1.0),)),
                           env_ad(n, SR_SFX, 0.002, 3.0)),
            int((0.30 + 0.06 * k) * SR_SFX), 0.12)
    return out


def sfx_hit():
    out = [0.0] * int(0.28 * SR_SFX)
    n = int(0.24 * SR_SFX)
    add(out, apply_env(tone(0.24, 150.0, harmonics=WARM, glide=0.42),
                       env_ad(n, SR_SFX, 0.002, 2.2)), 0, 0.75)
    n = int(0.12 * SR_SFX)
    add(out, apply_env(noise(0.12, cutoff=0.22, seed=7),
                       env_ad(n, SR_SFX, 0.001, 4.0)), 0, 0.35)
    return out


def sfx_fever():
    out = [0.0] * int(0.85 * SR_SFX)
    for k, (start, multiplier) in enumerate(((440.0, 2.0), (660.0, 2.0))):
        n = int(0.38 * SR_SFX)
        sig = tone(0.38, start, harmonics=((1.0, 1.0), (2.0, 0.30), (3.0, 0.12)),
                   glide=multiplier)
        add(out, apply_env(sig, env_ad(n, SR_SFX, 0.005, 1.4)),
            int(k * 0.36 * SR_SFX), 0.32)
    n = int(0.70 * SR_SFX)
    add(out, apply_env(noise(0.70, cutoff=0.5, seed=11),
                       env_ad(n, SR_SFX, 0.05, 1.6)), 0, 0.10)
    return out


def sfx_start():
    out = [0.0] * int(0.50 * SR_SFX)
    n = int(0.24 * SR_SFX)
    for k, freq in enumerate((523.25, 659.25, 783.99)):
        add(out, apply_env(tone(0.24, freq, harmonics=BELL),
                           env_ad(n, SR_SFX, 0.004, 2.0)),
            int(0.11 * k * SR_SFX), 0.32)
    return out


def sfx_gameover():
    """Slightly longer descending minor progression with a low tail."""
    out = [0.0] * int(1.95 * SR_SFX)
    chords = ((392.00, 466.16, 587.33),
              (349.23, 440.00, 523.25),
              (261.63, 329.63, 392.00))
    for k, chord in enumerate(chords):
        start = int(0.58 * k * SR_SFX)
        n = int(0.80 * SR_SFX)
        for freq in chord:
            sig = tone(0.80, freq, harmonics=((1.0, 1.0), (2.0, 0.18)))
            add(out, apply_env(sig, env_ad(n, SR_SFX, 0.02, 1.5, release=0.14)),
                start, 0.16)
    n = int(1.70 * SR_SFX)
    tail = tone(1.70, 98.0, harmonics=((1.0, 1.0), (2.0, 0.25)))
    add(out, apply_env(tail, env_ad(n, SR_SFX, 0.08, 1.2, release=0.35)), 0, 0.24)
    return out


def sfx_tongue():
    out = [0.0] * int(0.18 * SR_SFX)
    n = int(0.15 * SR_SFX)
    add(out, apply_env(tone(0.15, 620.0, harmonics=WARM, glide=0.30),
                       env_ad(n, SR_SFX, 0.002, 2.6)), 0, 0.50)
    n = int(0.12 * SR_SFX)
    add(out, apply_env(noise(0.12, cutoff=0.45, seed=3),
                       env_ad(n, SR_SFX, 0.002, 3.0)), 0, 0.22)
    return out


def sfx_click():
    out = [0.0] * int(0.07 * SR_SFX)
    n = int(0.06 * SR_SFX)
    add(out, apply_env(tone(0.06, 1180.0, harmonics=((1.0, 1.0), (2.0, 0.20))),
                       env_ad(n, SR_SFX, 0.001, 5.0)), 0, 0.50)
    n = int(0.035 * SR_SFX)
    add(out, apply_env(noise(0.035, cutoff=0.6, seed=5),
                       env_ad(n, SR_SFX, 0.001, 6.0)), 0, 0.25)
    return out


def sfx_jump():
    out = [0.0] * int(0.26 * SR_SFX)
    n = int(0.24 * SR_SFX)
    sig = tone(0.24, 320.0, harmonics=((1.0, 1.0), (2.0, 0.22), (3.0, 0.08)),
               glide=2.2)
    add(out, apply_env(sig, env_ad(n, SR_SFX, 0.006, 1.6)), 0, 0.55)
    return out


# ---------------------------------------------------------------------------
# Seamless eight-second music loop
# ---------------------------------------------------------------------------

def music_loop():
    """Pad + bass + arpeggio built from events that repeat every eight seconds.

    Every note uses a gate that reaches zero at its start and end, so the
    waveform value at t=0 and at t=8 s is identical (silence). That makes the
    loop click-free even though the WAV itself has no loop metadata.
    """
    sr = SR_MUSIC
    step = 0.25                      # 32 arpeggio steps per 8-second loop
    out = [0.0] * (8 * sr)
    chords = (
        (220.00, 261.63, 329.63),    # A minor
        (174.61, 220.00, 261.63),    # F major
        (196.00, 246.94, 293.66),    # G major
        (164.81, 207.65, 246.94),    # E minor
    )

    # Slow chord pad and sub-bass, one event per two-second chord.
    for ci, chord in enumerate(chords):
        start = int(ci * 2.0 * sr)
        n = int(1.98 * sr)
        gate = env_sustain(n, sr, 0.14, 0.22)
        for freq in chord:
            pad = tone(1.98, freq, sr=sr, harmonics=((1.0, 1.0), (2.0, 0.16)))
            add(out, apply_env(pad, gate), start, 0.13)
        bass = tone(1.98, chord[0] / 2.0, sr=sr,
                    harmonics=((1.0, 1.0), (2.0, 0.12)))
        add(out, apply_env(bass, env_sustain(n, sr, 0.08, 0.16)), start, 0.16)

    # Plucked arpeggio: the same 8-step motif repeats over each chord.
    motif = (0, 1, 2, 1, 0, 2, 1, 2)
    for s in range(32):
        chord = chords[s // 8]
        freq = chord[motif[s % 8]] * 2.0
        start = int(s * step * sr)
        n = int(0.23 * sr)
        pluck = tone(0.23, freq, sr=sr, harmonics=((1.0, 1.0), (2.0, 0.28)))
        add(out, apply_env(pluck, env_ad(n, sr, 0.004, 2.8)), start, 0.13)

    return out[:8 * sr]


def main():
    os.makedirs(AUDIO_DIR, exist_ok=True)
    effects = {
        "sfx_switch": sfx_switch,
        "sfx_collect": sfx_collect,
        "sfx_perfect": sfx_perfect,
        "sfx_hit": sfx_hit,
        "sfx_fever": sfx_fever,
        "sfx_start": sfx_start,
        "sfx_gameover": sfx_gameover,
        "sfx_tongue": sfx_tongue,
        "sfx_click": sfx_click,
        "sfx_jump": sfx_jump,
    }
    for name, factory in effects.items():
        path = os.path.join(AUDIO_DIR, name + ".wav")
        write_wav(path, factory(), SR_SFX)
        print("wrote", os.path.relpath(path, ROOT))

    music_path = os.path.join(AUDIO_DIR, "music_loop.wav")
    write_wav(music_path, music_loop(), SR_MUSIC)
    print("wrote", os.path.relpath(music_path, ROOT))


if __name__ == "__main__":
    main()
