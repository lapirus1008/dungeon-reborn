// 진입점: 렌더러, 입력, 로비 <-> 레이드 전환
import * as THREE from 'three';
import { Game } from './game.js';
import { UI } from './ui.js';
import { loadSave, writeSave, STASH_SIZE } from './save.js';
import { initAudio } from './audio.js';

const params = new URLSearchParams(location.search);
const NO_LOCK = params.has('nolock'); // 테스트용: 포인터 잠금 없이 조작

const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.15;
const canvas = renderer.domElement;
document.getElementById('canvas-wrap').appendChild(canvas);

const input = { keys: new Set(), pressed: new Set(), mouse: { l: false, r: false, rPressed: false }, dx: 0, dy: 0, locked: NO_LOCK };
const ui = new UI();
const game = new Game(renderer, ui, input);
let save = loadSave();
let mode = 'lobby';

const sens = Number(localStorage.getItem('dr_sens') || 1);
game.sensitivity = 0.0022 * sens;
const sensInput = document.getElementById('sens');
sensInput.value = sens;
sensInput.addEventListener('input', () => {
  game.sensitivity = 0.0022 * Number(sensInput.value);
  try {
    localStorage.setItem('dr_sens', sensInput.value);
  } catch (e) {
    /* 무시 */
  }
});

function lock() {
  if (NO_LOCK) return;
  try {
    const r = canvas.requestPointerLock();
    if (r && r.catch) r.catch(() => {});
  } catch (e) {
    /* 무시 */
  }
}

document.addEventListener('pointerlockchange', () => {
  input.locked = NO_LOCK || document.pointerLockElement === canvas;
  if (!input.locked) {
    input.mouse.l = input.mouse.r = false;
  }
});

document.addEventListener('mousemove', (e) => {
  if (input.locked) {
    input.dx += e.movementX || 0;
    input.dy += e.movementY || 0;
  }
});

canvas.addEventListener('mousedown', (e) => {
  initAudio();
  if (mode !== 'raid') return;
  if (!input.locked) {
    if (!ui.isPanelOpen()) lock();
    return;
  }
  if (ui.isPanelOpen()) return;
  if (e.button === 0) input.mouse.l = true;
  if (e.button === 2) {
    input.mouse.r = true;
    input.mouse.rPressed = true;
  }
});
document.addEventListener('mouseup', (e) => {
  if (e.button === 0) input.mouse.l = false;
  if (e.button === 2) input.mouse.r = false;
});

document.addEventListener('keydown', (e) => {
  if (mode !== 'raid') return;
  if (['Tab', 'Space', 'KeyQ', 'KeyE', 'KeyF', 'KeyM'].includes(e.code)) e.preventDefault();
  input.keys.add(e.code);
  if (!e.repeat) input.pressed.add(e.code);
  if (e.repeat || game.result) return;
  if (e.code === 'Tab' || e.code === 'KeyI') {
    if (ui.container) ui.closeContainer();
    else ui.toggleInventory();
    if (ui.isPanelOpen()) document.exitPointerLock?.();
    else lock();
  } else if (e.code === 'KeyF' && ui.container) {
    ui.closeContainer();
    input.pressed.delete('KeyF');
    lock();
  } else if (e.code === 'Escape' && ui.isPanelOpen()) {
    ui.closePanels();
  } else if (e.code === 'KeyM') {
    ui.toggleMap();
  }
});
document.addEventListener('keyup', (e) => input.keys.delete(e.code));
window.addEventListener('blur', () => {
  input.keys.clear();
  input.mouse.l = input.mouse.r = false;
});

document.getElementById('pause').addEventListener('mousedown', (e) => {
  if (e.target.closest('button') || e.target.closest('input')) return;
  lock();
});
document.getElementById('resume-btn').onclick = () => lock();

for (const b of document.querySelectorAll('.tab-btn')) {
  b.onclick = () => {
    ui.lobbyTab = b.dataset.tab;
    ui.renderLobby();
  };
}

window.addEventListener('resize', () => {
  renderer.setSize(innerWidth, innerHeight);
  game.camera.aspect = innerWidth / innerHeight;
  game.camera.updateProjectionMatrix();
});

// ------------------------------------------------------------- 상태 전환
function startRaid() {
  initAudio();
  save = ui.save;
  const loadout = { cls: save.cls, equipment: { ...save.equipment }, bag: [...save.bag] };
  // 입장 시 소지품은 위험에 노출됨 (탈출해야 돌아옴)
  save.equipment = { weapon: null, head: null, chest: null, trinket: null };
  save.bag = [];
  save.stats.raids++;
  writeSave(save);
  mode = 'raid';
  game.start(loadout);
  ui.startHud(game);
  lock();
}

ui.onResultContinue = () => {
  const r = game.result;
  if (r) {
    save.stats.kills += r.kills;
    save.stats.pvpKills += r.pvpKills;
    if (r.success) {
      save.stats.extracts++;
      save.stats.bestHaul = Math.max(save.stats.bestHaul, r.value);
      save.equipment = { ...r.equipment };
      let sold = 0;
      for (const it of r.bag) {
        if (save.stash.length < STASH_SIZE) save.stash.push(it);
        else {
          save.gold += it.value;
          sold += it.value;
        }
      }
      if (sold) setTimeout(() => ui.toast(`보관함이 가득 차 남은 물건을 ${sold}g에 판매했습니다`), 300);
    } else save.stats.deaths++;
    writeSave(save);
  }
  mode = 'lobby';
  ui.openLobby(save, startRaid);
};

function abandon() {
  if (mode !== 'raid' || game.result) return;
  game.player.hp = 0;
  game.player.alive = false;
  game.endRaid(false, '포기');
  game.endTimer = 0;
}

ui.openLobby(save, startRaid);

// ------------------------------------------------------------- 루프
let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (mode === 'raid') {
    const paused = !input.locked && !ui.isPanelOpen() && !game.result && game.running;
    ui.showPause(paused, abandon);
    if (!paused) {
      game.update(dt);
      if (game.running || game.result) ui.updateHud(dt);
    }
    game.render();
  }
  input.dx = input.dy = 0;
  input.pressed.clear();
  input.mouse.rPressed = false;
}
requestAnimationFrame(frame);

// 디버그 접근
window.__game = game;
window.__ui = ui;
window.__input = input;
