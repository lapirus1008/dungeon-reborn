// WebAudio 합성 효과음 (외부 에셋 없음)
let ctx = null;
let master = null;
let noiseBuf = null;

export function initAudio() {
  if (ctx) {
    if (ctx.state === 'suspended') ctx.resume();
    return;
  }
  try {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain();
    master.gain.value = 0.35;
    master.connect(ctx.destination);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  } catch (e) {
    ctx = null;
  }
}

function noise(dur, freq, q, vol, type = 'bandpass', sweepTo = null) {
  if (!ctx) return;
  const t = ctx.currentTime;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuf;
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.frequency.setValueAtTime(freq, t);
  if (sweepTo) f.frequency.exponentialRampToValueAtTime(sweepTo, t + dur);
  f.Q.value = q;
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  src.connect(f).connect(g).connect(master);
  src.start(t, Math.random() * 0.5);
  src.stop(t + dur + 0.05);
}

function tone(dur, f0, f1, vol, type = 'sine') {
  if (!ctx) return;
  const t = ctx.currentTime;
  const o = ctx.createOscillator();
  o.type = type;
  o.frequency.setValueAtTime(f0, t);
  o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  const g = ctx.createGain();
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  o.connect(g).connect(master);
  o.start(t);
  o.stop(t + dur + 0.05);
}

// 거리 기반 볼륨
function vol(base, dist) {
  if (dist === undefined) return base;
  return base * Math.max(0, 1 - dist / 35);
}

export const sfx = {
  swing: (d) => noise(0.18, 900, 1.2, vol(0.5, d), 'bandpass', 3000),
  hit: (d) => {
    noise(0.12, 400, 1, vol(0.7, d), 'lowpass');
    tone(0.12, 160, 60, vol(0.4, d), 'triangle');
  },
  block: (d) => tone(0.15, 1200, 900, vol(0.3, d), 'square'),
  bow: (d) => {
    tone(0.12, 300, 120, vol(0.35, d), 'triangle');
    noise(0.1, 2000, 2, vol(0.2, d));
  },
  magic: (d) => tone(0.25, 900, 300, vol(0.25, d), 'sawtooth'),
  fire: (d) => noise(0.6, 300, 0.7, vol(0.8, d), 'lowpass', 80),
  heal: () => {
    tone(0.4, 500, 900, 0.2);
    tone(0.5, 750, 1300, 0.12);
  },
  chest: () => {
    tone(0.25, 180, 120, 0.3, 'square');
    noise(0.3, 600, 1, 0.3);
  },
  pickup: () => tone(0.1, 900, 1400, 0.2, 'triangle'),
  coin: () => {
    tone(0.08, 1800, 1800, 0.15, 'square');
    setTimeout(() => tone(0.12, 2400, 2400, 0.12, 'square'), 70);
  },
  portal: () => tone(1.2, 200, 800, 0.25, 'sine'),
  hurt: () => {
    tone(0.2, 220, 90, 0.4, 'sawtooth');
    noise(0.15, 300, 1, 0.4, 'lowpass');
  },
  growl: (d) => tone(0.5, 110, 60, vol(0.35, d), 'sawtooth'),
  death: (d) => {
    tone(0.7, 200, 40, vol(0.5, d), 'sawtooth');
    noise(0.5, 200, 0.6, vol(0.4, d), 'lowpass');
  },
  bell: () => {
    tone(2.5, 220, 218, 0.3, 'sine');
    tone(2.5, 440, 438, 0.15, 'sine');
  },
  step: () => noise(0.06, 250, 1, 0.08, 'lowpass'),
  ui: () => tone(0.05, 700, 700, 0.12, 'triangle'),
};
