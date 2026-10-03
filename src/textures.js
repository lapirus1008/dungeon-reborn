// 캔버스로 생성하는 절차적 텍스처
import * as THREE from 'three';

function canvas(size) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  return [c, c.getContext('2d')];
}

function speckle(g, size, count, alpha, light = false) {
  for (let i = 0; i < count; i++) {
    const v = light ? 255 : 0;
    g.fillStyle = `rgba(${v},${v},${v},${Math.random() * alpha})`;
    g.fillRect(Math.random() * size, Math.random() * size, 1 + Math.random() * 2, 1 + Math.random() * 2);
  }
}

function toTex(c, repeat = 1) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

export function stoneWallTexture(tint = [92, 86, 80]) {
  const S = 256;
  const [c, g] = canvas(S);
  g.fillStyle = '#2a2622';
  g.fillRect(0, 0, S, S);
  const rows = 6;
  const bh = S / rows;
  for (let r = 0; r < rows; r++) {
    const off = r % 2 ? 0 : S / 6;
    for (let x = -S / 3; x < S; x += S / 3) {
      const k = 0.75 + Math.random() * 0.35;
      g.fillStyle = `rgb(${tint[0] * k | 0},${tint[1] * k | 0},${tint[2] * k | 0})`;
      g.fillRect(x + off + 3, r * bh + 3, S / 3 - 6, bh - 6);
    }
  }
  speckle(g, S, 4000, 0.25);
  speckle(g, S, 1500, 0.12, true);
  // 이끼/얼룩
  for (let i = 0; i < 12; i++) {
    const gr = g.createRadialGradient(Math.random() * S, Math.random() * S, 0, 0, 0, 0);
    g.fillStyle = `rgba(40,55,30,${Math.random() * 0.15})`;
    g.beginPath();
    g.arc(Math.random() * S, Math.random() * S, 6 + Math.random() * 20, 0, Math.PI * 2);
    g.fill();
    void gr;
  }
  return toTex(c);
}

export function floorTexture(tint = [70, 66, 60]) {
  const S = 256;
  const [c, g] = canvas(S);
  g.fillStyle = '#1b1916';
  g.fillRect(0, 0, S, S);
  const n = 4;
  const s = S / n;
  for (let i = 0; i < n; i++)
    for (let j = 0; j < n; j++) {
      const k = 0.7 + Math.random() * 0.4;
      g.fillStyle = `rgb(${tint[0] * k | 0},${tint[1] * k | 0},${tint[2] * k | 0})`;
      g.fillRect(i * s + 2, j * s + 2, s - 4, s - 4);
    }
  speckle(g, S, 5000, 0.3);
  speckle(g, S, 1200, 0.1, true);
  // 균열
  g.strokeStyle = 'rgba(0,0,0,0.5)';
  for (let i = 0; i < 6; i++) {
    g.beginPath();
    let x = Math.random() * S;
    let y = Math.random() * S;
    g.moveTo(x, y);
    for (let k = 0; k < 5; k++) {
      x += (Math.random() - 0.5) * 30;
      y += (Math.random() - 0.5) * 30;
      g.lineTo(x, y);
    }
    g.stroke();
  }
  return toTex(c);
}

export function woodTexture() {
  const S = 128;
  const [c, g] = canvas(S);
  g.fillStyle = '#5a3a1e';
  g.fillRect(0, 0, S, S);
  for (let i = 0; i < 4; i++) {
    g.fillStyle = i % 2 ? '#64421f' : '#553519';
    g.fillRect(0, i * 32 + 1, S, 30);
  }
  for (let i = 0; i < 300; i++) {
    g.strokeStyle = `rgba(30,15,5,${Math.random() * 0.4})`;
    g.beginPath();
    const y = Math.random() * S;
    g.moveTo(0, y);
    g.bezierCurveTo(S / 3, y + Math.random() * 4 - 2, (2 * S) / 3, y + Math.random() * 4 - 2, S, y);
    g.stroke();
  }
  return toTex(c);
}
