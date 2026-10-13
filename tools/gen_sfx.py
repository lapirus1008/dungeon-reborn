#!/usr/bin/env python3
"""중세 분위기 효과음 합성기 -> godot/assets/sfx/<이름>[_<번호>].wav (22050Hz, 16bit, 모노)

전자음(사각파/톱니파 비프) 대신 재질을 흉내 낸 소리를 만든다:
  금속 = 비정수배 배음(모달 합성), 나무 = 낮고 빨리 사라지는 공명, 천/가죽 = 걸러진 잡음,
  돌바닥 발소리 = 낮은 쿵 + 짧은 자갈 소리, 활/하프 = 카플러스-스트롱 현 뜯기, 종 = 교회 종 배음.
같은 동작이라도 매번 조금씩 다르게 들리도록 여러 개(변형)를 만든다.
실행: pip install numpy scipy && python3 tools/gen_sfx.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "sfx")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env(dur, attack=0.005, decay=0.3, curve=1.0):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4)) ** curve
    return a * d


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def nsamp(dur):
    return int(dur * SR)


def bandpass(x, lo, hi, order=2):
    lo = max(lo, 20)
    hi = min(hi, SR / 2 - 100)
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    sos = signal.butter(order, min(f, SR / 2 - 100), btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, f, order=2):
    sos = signal.butter(order, f, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def resonator(x, f, q):
    """좁은 공명 필터 (나무·금속 몸통 울림)"""
    b, a = signal.iirpeak(min(f, SR / 2 - 200), q, fs=SR)
    return signal.lfilter(b, a, x)


def sweep_band(x, f0, f1, width=0.6, steps=24):
    """중심 주파수가 f0 -> f1 로 움직이는 대역 통과 (휘두르는 바람 소리)"""
    out = np.zeros_like(x)
    n = len(x)
    seg = max(1, n // steps)
    for i in range(steps):
        s, e = i * seg, n if i == steps - 1 else (i + 1) * seg
        k = i / max(1, steps - 1)
        fc = f0 * (f1 / f0) ** k
        y = bandpass(x, fc * (1 - width / 2), fc * (1 + width / 2))
        out[s:e] = y[s:e]
    return out


def modal(freqs, decays, amps, dur, jitter=0.0):
    """비정수배 배음 합 (금속·종·나무). decays: 각 배음 감쇠 시간(초)"""
    t = t_axis(dur)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        f = f * (1 + rng.uniform(-jitter, jitter))
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return y


def pluck(f, dur, damp=0.996, bright=0.5):
    """카플러스-스트롱 현 (활시위, 하프)"""
    n = int(dur * SR)
    p = int(SR / f)
    buf = lowpass(rng.uniform(-1, 1, p), 1000 + 7000 * bright)
    out = np.zeros(n)
    for i in range(n):
        v = buf[i % p]
        out[i] = v
        buf[i % p] = damp * 0.5 * (v + buf[(i + 1) % p])
    return out


def thump(f0, f1, dur, decay):
    """낮은 쿵 (음높이가 떨어지는 사인)"""
    t = t_axis(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / decay)


def crackle(dur, rate, lo=1500, hi=6000):
    """타닥거리는 작은 터짐들 (불, 자갈)"""
    n = int(dur * SR)
    y = np.zeros(n)
    count = int(rate * dur)
    for _ in range(count):
        s = rng.integers(0, max(1, n - 400))
        ln = rng.integers(40, 300)
        y[s:s + ln] += rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 4)) * rng.uniform(0.3, 1)
    return bandpass(y, lo, hi)


def room(x, size=0.25, mix=0.18):
    """돌방 잔향 (짧은 지수 감쇠 잡음과 합성곱)"""
    ir_t = t_axis(size)
    ir = rng.standard_normal(len(ir_t)) * np.exp(-ir_t / (size / 5))
    ir = lowpass(ir, 3500)
    ir /= np.abs(ir).sum() / 6 + 1e-9
    wet = signal.fftconvolve(x, ir)[: len(x) + len(ir_t)]
    out = np.zeros(len(wet))
    out[: len(x)] += x
    return out * (1 - mix) + wet * mix


def pad(x, dur):
    n = int(dur * SR)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[: max(n, len(x))]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(int(delay * SR)), x])


def fit(x, n):
    """길이를 n에 맞춤 (자르거나 0으로 채움)"""
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]


def fade_tail(x, ms=15):
    k = int(ms / 1000 * SR)
    if len(x) > k:
        x[-k:] *= np.linspace(1, 0, k)
    return x


def voice(f0, f1, dur, formants, breath=0.15):
    """낮은 신음/으르렁 (성대 펄스 + 모음 공명)"""
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    f = f * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t) + 0.02 * rng.standard_normal(len(t)).cumsum() / np.sqrt(len(t)))
    ph = np.cumsum(f) / SR
    pulses = (np.mod(ph, 1.0) < 0.12).astype(float) - 0.12
    src = pulses + breath * noise(dur)
    y = sum(resonator(src, fm, q) * g for fm, q, g in formants)
    return y


# ---------------------------------------------------------------- 소리 정의
SOUNDS = {}


def sound(name, variants=1, peak=0.8):
    def deco(fn):
        SOUNDS[name] = (fn, variants, peak)
        return fn
    return deco


@sound("step", 4, 0.45)
def s_step(i):
    d = 0.16
    heel = thump(140 + 20 * i, 60, d, 0.035) * 0.9
    grit = bandpass(noise(d), 1200, 5000) * env(d, 0.002, 0.018) * 0.5
    scuff = bandpass(noise(d), 300, 1400) * env(d, 0.01, 0.04) * 0.35
    return room(mix(heel, at(grit, 0.004), at(scuff, 0.012)), 0.18, 0.12)


@sound("swing", 3, 0.6)
def s_swing(i):
    d = 0.32
    n = noise(d)
    y = sweep_band(n, 500 + 80 * i, 2200 + 200 * i, 0.7)
    e = np.sin(np.pi * np.clip(t_axis(d) / d, 0, 1)) ** 1.6
    return fade_tail(y * e)


@sound("hit", 3, 0.85)
def s_hit(i):
    d = 0.35
    body = thump(180, 70, d, 0.06) * 1.2
    crack = bandpass(noise(d), 900, 4500) * env(d, 0.001, 0.02) * 0.9
    ring = modal([620 + 40 * i, 1530, 2480], [0.08, 0.05, 0.03], [0.25, 0.15, 0.1], d, 0.05)
    flesh = lowpass(noise(d), 700) * env(d, 0.002, 0.05) * 0.6
    return room(mix(body, crack, ring, flesh), 0.2, 0.15)


@sound("block", 2, 0.85)
def s_block(i):
    d = 1.3
    base = 480 + 60 * i
    ring = modal([base, base * 2.76, base * 4.11, base * 5.4, base * 6.9],
                 [0.45, 0.3, 0.2, 0.12, 0.08], [1, 0.7, 0.5, 0.35, 0.2], d, 0.02)
    click = highpass(noise(d), 2500) * env(d, 0.0005, 0.008) * 1.5
    return room(mix(ring * 0.6, click), 0.3, 0.2)


@sound("shield_hit", 2, 0.8)
def s_shield_hit(i):
    d = 0.45
    wood = mix(resonator(noise(d) * env(d, 0.001, 0.01), 190 + 20 * i, 8) * 3,
               resonator(noise(d) * env(d, 0.001, 0.01), 430, 10) * 2)
    rim = modal([1180, 2900], [0.18, 0.1], [0.2, 0.12], d)
    return room(mix(wood * 0.8, rim, thump(120, 60, d, 0.05) * 0.6), 0.25, 0.15)


@sound("bow", 2, 0.7)
def s_bow(i):
    d = 0.5
    string = pluck(98 + 12 * i, d, 0.985, 0.35) * 0.9
    air = sweep_band(noise(d), 1800, 700, 0.8) * env(d, 0.005, 0.12) * 0.35
    return mix(string, air)


@sound("draw_blade", 1, 0.6)
def s_draw_blade(i):
    d = 0.55
    scrape = sweep_band(noise(d), 2200, 5200, 0.25) * (np.sin(np.pi * t_axis(d) / d) ** 0.8)
    ring = modal([2650, 4100, 5900], [0.25, 0.18, 0.12], [0.3, 0.2, 0.12], d)
    return room(mix(scrape * 0.7, at(ring, 0.38)[: int(d * SR)]), 0.25, 0.12)


@sound("draw_wood", 1, 0.55)
def s_draw_wood(i):
    d = 0.3
    knock = resonator(noise(d) * env(d, 0.001, 0.006), 320, 9) * 4
    knock2 = resonator(noise(d) * env(d, 0.001, 0.006), 780, 12) * 2
    rustle = bandpass(noise(d), 600, 2500) * env(d, 0.02, 0.06) * 0.3
    return mix(knock, knock2, rustle)


@sound("draw_soft", 2, 0.4)
def s_draw_soft(i):
    d = 0.3
    y = bandpass(noise(d), 700, 3200)
    am = 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * (14 + 4 * i) * t_axis(d)))
    return y * am * env(d, 0.03, 0.08)


@sound("pickup", 2, 0.5)
def s_pickup(i):
    d = 0.25
    leather = bandpass(noise(d), 500, 2500) * env(d, 0.005, 0.04) * 0.6
    clink = modal([2100 + 300 * i, 5200], [0.06, 0.04], [0.25, 0.12], d)
    return mix(leather, at(clink, 0.03)[: int(d * SR)])


@sound("drop", 2, 0.55)
def s_drop(i):
    d = 0.35
    return room(mix(thump(160, 70, d, 0.04), crackle(0.15, 60, 800, 4000) * 0.4,
                    bandpass(noise(d), 300, 1500) * env(d, 0.002, 0.03) * 0.5), 0.2, 0.15)


@sound("coin", 2, 0.5)
def s_coin(i):
    d = 0.5
    y = np.zeros(int(d * SR))
    for k in range(5 + i):
        f = rng.uniform(3200, 5200)
        c = modal([f, f * 1.47, f * 2.13], [0.09, 0.06, 0.04], [0.4, 0.25, 0.15], d)
        y += fit(at(c, rng.uniform(0, 0.18)), len(y))
    return y


@sound("chest", 1, 0.75)
def s_chest(i):
    d = 1.0
    # 경첩 삐걱임: 마찰로 생기는 불규칙 펄스열을 나무 공명에 통과
    n = int(0.6 * SR)
    pulses = np.zeros(n)
    pos = 0
    while pos < n:
        pulses[pos] = rng.uniform(0.5, 1)
        pos += max(20, int(SR / (rng.uniform(45, 110) * (1 + 0.5 * pos / n))))
    creak = sum(resonator(pulses, f, q) * g for f, q, g in [(520, 18, 1.0), (1150, 22, 0.6), (2300, 25, 0.3)])
    creak *= np.sin(np.pi * np.linspace(0, 1, n)) ** 0.7
    latch = modal([1900, 3300], [0.05, 0.03], [0.4, 0.2], 0.2)
    lid = thump(130, 60, 0.4, 0.07)
    return room(mix(at(latch, 0.0), at(creak * 0.6, 0.05), at(lid * 0.7, 0.62)), 0.35, 0.22)


@sound("door", 1, 0.7)
def s_door(i):
    d = 1.1
    n = int(0.9 * SR)
    pulses = np.zeros(n)
    pos = 0
    while pos < n:
        pulses[pos] = rng.uniform(0.4, 1)
        # 마찰 삐걱임: 빠르기가 계속 출렁이고 펄스 세기도 들쭉날쭉
        rate = 35 + 55 * np.sin(np.pi * pos / n) + 18 * np.sin(2 * np.pi * 3.1 * pos / SR) + rng.uniform(-15, 15)
        pos += max(20, int(SR / rate))
    creak = sum(resonator(pulses, f, q) * g for f, q, g in [(380, 15, 1.0), (840, 20, 0.6), (1700, 22, 0.25)])
    creak *= np.sin(np.pi * np.linspace(0, 1, n)) ** 0.5
    return room(pad(creak, d), 0.5, 0.3)


@sound("door_shut", 1, 0.85)
def s_door_shut(i):
    d = 0.9
    slam = thump(110, 45, d, 0.12) * 1.3
    wood = resonator(noise(d) * env(d, 0.001, 0.01), 240, 7) * 3
    iron = modal([880, 2150, 3400], [0.25, 0.15, 0.1], [0.2, 0.12, 0.08], d)
    return room(mix(slam, wood, at(iron, 0.01)[: int(d * SR)]), 0.6, 0.35)


@sound("fire", 1, 0.55)
def s_fire(i):
    d = 0.9
    roar = lowpass(noise(d), 500) * env(d, 0.08, 0.35) * 1.2
    whoosh = sweep_band(noise(d), 300, 1400, 0.9) * env(d, 0.03, 0.2) * 0.5
    return mix(roar, whoosh, crackle(d, 35) * 0.6)


@sound("growl", 2, 0.75)
def s_growl(i):
    d = 0.7
    v = voice(78 + 10 * i, 58, d, [(320, 6, 1.0), (780, 7, 0.6), (2300, 9, 0.2)], 0.4)
    am = 1 + 0.5 * np.sin(2 * np.pi * 23 * t_axis(d))
    return room(v * am * env(d, 0.06, 0.3), 0.3, 0.2)


@sound("hurt", 2, 0.7)
def s_hurt(i):
    d = 0.32
    grunt = voice(150 - 15 * i, 105, d, [(380, 6, 1.0), (920, 8, 0.5), (2400, 10, 0.15)], 0.3) * env(d, 0.01, 0.09)
    return mix(grunt, thump(120, 60, d, 0.04) * 0.4)


@sound("death", 1, 0.8)
def s_death(i):
    d = 1.4
    groan = voice(120, 70, 0.9, [(360, 6, 1.0), (850, 8, 0.5)], 0.35) * env(0.9, 0.02, 0.35)
    fall = thump(90, 40, 0.8, 0.12) * 1.2
    clatter = crackle(0.4, 40, 1500, 6000) * 0.5
    ring = modal([700, 1820, 2950], [0.3, 0.2, 0.12], [0.2, 0.12, 0.08], 0.8)
    return room(mix(groan, at(fall, 0.55), at(clatter, 0.58), at(ring, 0.6)), 0.5, 0.25)


@sound("magic", 2, 0.5)
def s_magic(i):
    d = 0.7
    base = 440 * (1.122 ** i)
    t = t_axis(d)
    shimmer = sum(np.sin(2 * np.pi * base * r * t * (1 + 0.003 * np.sin(2 * np.pi * 6 * t))) * w
                  for r, w in [(1, 0.5), (1.5, 0.35), (2.01, 0.25), (3.02, 0.12)])
    air = bandpass(noise(d), 2000, 7000) * 0.15
    return room((shimmer + air) * env(d, 0.08, 0.25), 0.6, 0.35)


@sound("heal", 1, 0.55)
def s_heal(i):
    # 하프 아르페지오 (C-E-G-C)
    d = 1.4
    y = np.zeros(int(d * SR))
    for k, f in enumerate([523.3, 659.3, 784.0, 1046.5]):
        y += fit(at(pluck(f, 1.0, 0.9975, 0.6), 0.09 * k), len(y)) * 0.5
    return room(y, 0.6, 0.3)


@sound("shield", 1, 0.55)
def s_shield(i):
    d = 1.0
    t = t_axis(d)
    hum = (np.sin(2 * np.pi * 110 * t) * 0.5 + np.sin(2 * np.pi * 165 * t) * 0.3) * env(d, 0.15, 0.4)
    glass = modal([1760, 2640, 3520], [0.6, 0.4, 0.3], [0.25, 0.15, 0.1], d)
    return room(mix(hum, at(glass, 0.08)[: len(t)]), 0.7, 0.35)


@sound("shield_break", 1, 0.75)
def s_shield_break(i):
    d = 0.8
    y = np.zeros(int(d * SR))
    for k in range(14):
        f = rng.uniform(2500, 7000)
        y += fit(at(modal([f, f * 1.6], [0.05, 0.03], [0.4, 0.2], 0.2), rng.uniform(0, 0.25)), len(y))
    return room(mix(y, highpass(noise(d), 3000) * env(d, 0.001, 0.08) * 0.5), 0.4, 0.25)


@sound("portal", 1, 0.55)
def s_portal(i):
    d = 1.6
    t = t_axis(d)
    f = 120 * (4 ** (t / d))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.4 + np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * 0.2
    wind = sweep_band(noise(d), 300, 2500, 0.9) * 0.4
    return room((tone + wind) * env(d, 0.3, 0.6), 0.8, 0.4)


@sound("bell", 1, 0.7)
def s_bell(i):
    # 교회 종: hum/prime/tierce/quint/nominal 배음
    d = 4.0
    f = 196.0
    y = modal([f * 0.5, f, f * 1.2, f * 1.5, f * 2.0, f * 2.5, f * 3.0, f * 4.2],
              [3.5, 2.8, 2.2, 1.8, 1.5, 1.0, 0.8, 0.5], [0.6, 0.8, 0.5, 0.35, 0.6, 0.25, 0.2, 0.1], d)
    strike = lowpass(noise(d), 2500) * env(d, 0.001, 0.01) * 0.5
    return room(mix(y, strike), 1.2, 0.35)


@sound("ui", 1, 0.3)
def s_ui(i):
    # 양피지/나무 딸깍
    d = 0.08
    return resonator(noise(d) * env(d, 0.0005, 0.004), 1800, 10) * 3


@sound("bandage", 1, 0.45)
def s_bandage(i):
    # 천을 찢고 감는 소리 (거친 잡음이 리듬 있게)
    d = 1.2
    t = t_axis(d)
    rip = bandpass(noise(0.25), 1500, 6000) * env(0.25, 0.005, 0.08)
    wrap = bandpass(noise(d), 600, 2800) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 2.2 * t))) * env(d, 0.1, 0.6)
    return mix(rip, at(wrap * 0.6, 0.2)[: int((d + 0.2) * SR)])


@sound("potion_open", 1, 0.5)
def s_potion_open(i):
    # 코르크 뽑는 '뽁' + 꿀꺽 거품
    d = 0.7
    pop = resonator(noise(0.05) * env(0.05, 0.0005, 0.004), 900, 6) * 3
    gl = np.zeros(int(d * SR))
    for k in range(4):
        tt = t_axis(0.09)
        f = 300 + 500 * tt / 0.09 + rng.uniform(-40, 40)
        b = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(0.09, 0.005, 0.03)
        gl += fit(at(b, 0.25 + 0.1 * k), len(gl)) * 0.4
    return mix(pop, gl)


@sound("rummage", 1, 0.45)
def s_rummage(i):
    # 가방/상자 안을 뒤지는 소리
    d = 0.45
    y = bandpass(noise(d), 500, 3000) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 9 * t_axis(d)))) * env(d, 0.02, 0.15)
    return mix(y, at(modal([2400], [0.05], [0.2], 0.1), 0.2)[: int(d * SR)])


def write(name, y, peak):
    y = np.asarray(y, dtype=float)
    y -= np.mean(y)
    m = np.max(np.abs(y)) or 1.0
    y = y / m * peak
    # 끝이 뚝 끊기지 않게: 마지막 부분을 부드럽게 줄임 (남은 울림이 있을 때 특히)
    k = min(int(len(y) * 0.3), int(0.35 * SR))
    if k > 8:
        y[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    pcm = np.clip(y * 32767, -32768, 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    total = 0
    for name, (fn, variants, peak) in SOUNDS.items():
        for v in range(variants):
            y = fn(v)
            if y is None:
                continue
            fname = name if variants == 1 else "%s_%d" % (name, v + 1)
            write(fname, y, peak)
            total += 1
    print("wrote", total, "files to", os.path.abspath(OUT))
