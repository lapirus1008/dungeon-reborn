// DOM UI: 로비(보관함/상인/장비), 인게임 HUD, 인벤토리, 전리품 창, 결과 화면
import * as THREE from 'three';
import { CLASSES, RARITIES, ITEM_BASES, STAT_LABELS, makeItem, itemBase, STARTER_WEAPON } from './data.js';
import { STASH_SIZE, BAG_SIZE, writeSave, resetSave } from './save.js';
import { computeStats } from './actors.js';
import { sfx } from './audio.js';

const $ = (s) => document.querySelector(s);
const el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html !== undefined) e.innerHTML = html;
  return e;
};

const SLOT_NAMES = { weapon: '무기', head: '머리', chest: '몸통', trinket: '장신구' };
const SHOP = [
  ['health_potion', 30],
  ['bandage', 12],
  ['rusty_sword', 40],
  ['short_bow', 40],
  ['oak_staff', 40],
  ['leather_cap', 30],
  ['padded_tunic', 40],
];

export function canEquip(item, cls) {
  const b = itemBase(item);
  if (!['weapon', 'head', 'chest', 'trinket'].includes(b.slot)) return false;
  if (b.slot === 'weapon' && b.cls !== cls) return false;
  return true;
}

export class UI {
  constructor() {
    this.container = null;
    this.invOpen = false;
    this.mapOpen = false;
    this.game = null;
    this.tooltip = $('#tooltip');
    this.dmgLayer = $('#dmg-layer');
    this.dmgNums = [];
    this.minimap = $('#minimap');
    this.mm = this.minimap.getContext('2d');
    this.bigmap = $('#bigmap');
    this.bm = this.bigmap.getContext('2d');
    this.mmTimer = 0;
    this.tipVisible = false;
    this.tipH = 0;
    document.addEventListener('mousemove', (e) => {
      // 포인터 잠금 중에는 초당 수백 번 발생하므로 툴팁이 보일 때만 처리 (레이아웃 강제 계산 방지)
      if (!this.tipVisible || document.pointerLockElement) return;
      this.tooltip.style.transform = `translate(${Math.min(innerWidth - 270, e.clientX + 16)}px, ${Math.max(0, Math.min(innerHeight - this.tipH - 8, e.clientY + 12))}px)`;
    });
    this.cache = new Map();
    document.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  // ======================================================== 공통 아이템 슬롯
  slot(item, onClick, onRight, opts = {}) {
    const s = el('div', 'slot');
    if (opts.label) s.appendChild(el('span', 'slot-label', opts.label));
    if (item) {
      const r = RARITIES[item.rarity];
      s.style.borderColor = r.color;
      s.style.boxShadow = `inset 0 0 14px ${r.color}44`;
      s.appendChild(el('span', 'slot-icon', ITEM_BASES[item.base].icon));
      if (opts.price !== undefined) s.appendChild(el('span', 'slot-price', opts.price + 'g'));
      s.addEventListener('mouseenter', () => this.showTip(item, opts.tipExtra));
      s.addEventListener('mouseleave', () => this.hideTip());
      if (opts.dim) s.classList.add('dim');
    } else s.classList.add('empty');
    s.addEventListener('mousedown', (e) => {
      if (e.button === 0 && onClick) {
        onClick(e);
        this.hideTip();
        sfx.ui();
      }
      if (e.button === 2 && onRight) {
        onRight(e);
        this.hideTip();
        sfx.ui();
      }
    });
    return s;
  }

  showTip(item, extra = '') {
    const b = ITEM_BASES[item.base];
    const r = RARITIES[item.rarity];
    let h = `<div class="tip-name" style="color:${r.color}">${b.icon} ${b.name}</div>`;
    const kind = b.slot === 'weapon' ? `무기 · ${CLASSES[b.cls].name} 전용` : b.slot === 'consumable' ? '소모품' : b.slot === 'treasure' ? '보물' : SLOT_NAMES[b.slot];
    h += `<div class="tip-sub">${r.name} ${kind}</div>`;
    for (const [k, v] of Object.entries(item.stats || {})) if (STAT_LABELS[k]) h += `<div class="tip-stat">${STAT_LABELS[k](v)}</div>`;
    if (b.heal) h += `<div class="tip-stat">체력 ${b.heal} 회복</div>`;
    h += `<div class="tip-val">💰 ${item.value} 골드</div>`;
    if (extra) h += `<div class="tip-hint">${extra}</div>`;
    this.tooltip.innerHTML = h;
    this.tooltip.style.display = 'block';
    this.tipVisible = true;
    this.tipH = this.tooltip.offsetHeight;
  }
  hideTip() {
    if (!this.tipVisible) return;
    this.tipVisible = false;
    this.tooltip.style.display = 'none';
  }

  // 값이 바뀔 때만 DOM에 기록 (매 프레임 스타일 변경으로 인한 끊김 방지)
  setStyle(sel, prop, val) {
    const key = sel + '|' + prop;
    if (this.cache.get(key) === val) return;
    this.cache.set(key, val);
    this.q(sel).style[prop] = val;
  }
  setText(sel, val) {
    const key = sel + '|text';
    if (this.cache.get(key) === val) return;
    this.cache.set(key, val);
    this.q(sel).textContent = val;
  }
  setClass(sel, cls, on) {
    const key = sel + '|c|' + cls;
    if (this.cache.get(key) === on) return;
    this.cache.set(key, on);
    this.q(sel).classList.toggle(cls, on);
  }
  q(sel) {
    this.els = this.els || new Map();
    let e = this.els.get(sel);
    if (!e || !e.isConnected) {
      e = document.querySelector(sel);
      this.els.set(sel, e);
    }
    return e;
  }

  toast(text) {
    const t = el('div', 'toast', text);
    $('#toasts').appendChild(t);
    setTimeout(() => t.classList.add('out'), 1800);
    setTimeout(() => t.remove(), 2400);
  }

  show(id) {
    for (const s of ['#lobby', '#hud', '#results', '#pause']) $(s).classList.add('hidden');
    if (id) $(id).classList.remove('hidden');
  }

  // ======================================================== 로비
  openLobby(save, onStart) {
    this.save = save;
    this.onStart = onStart;
    this.lobbyTab = this.lobbyTab || 'stash';
    this.show('#lobby');
    this.renderLobby();
  }

  persist() {
    writeSave(this.save);
  }

  renderLobby() {
    const s = this.save;
    // 직업 선택
    const classes = $('#class-list');
    classes.innerHTML = '';
    for (const c of Object.values(CLASSES)) {
      const card = el('div', 'class-card' + (s.cls === c.id ? ' selected' : ''));
      const icon = c.id === 'fighter' ? '🛡️' : c.id === 'ranger' ? '🏹' : '🔮';
      card.innerHTML = `<div class="cc-icon">${icon}</div><div><div class="cc-name">${c.name}</div><div class="cc-desc">${c.desc}</div><div class="cc-skills">${Object.entries(c.skills)
        .map(([k, v]) => `<span><b>${k.toUpperCase()}</b> ${v.name}</span>`)
        .join('')}</div></div>`;
      card.onclick = () => {
        if (s.cls === c.id) return;
        s.cls = c.id;
        // 다른 직업 무기는 보관함으로
        const w = s.equipment.weapon;
        if (w && !canEquip(w, s.cls)) {
          s.stash.push(w);
          s.equipment.weapon = null;
          this.toast('무기가 보관함으로 이동했습니다');
        }
        sfx.ui();
        this.persist();
        this.renderLobby();
      };
      classes.appendChild(card);
    }

    // 장비
    const eq = $('#equip-slots');
    eq.innerHTML = '';
    for (const slot of ['weapon', 'head', 'chest', 'trinket']) {
      const it = s.equipment[slot];
      const wrap = el('div', 'equip-wrap');
      wrap.appendChild(
        this.slot(
          it,
          () => {
            if (!it) return;
            if (s.stash.length >= STASH_SIZE) return this.toast('보관함이 가득 찼습니다');
            s.stash.push(it);
            s.equipment[slot] = null;
            this.persist();
            this.renderLobby();
          },
          null,
          { label: SLOT_NAMES[slot], tipExtra: '클릭: 장착 해제' },
        ),
      );
      eq.appendChild(wrap);
    }
    const st = computeStats(s.cls, s.equipment);
    const noWeapon = !s.equipment.weapon;
    $('#char-stats').innerHTML = `
      <div>❤️ 체력 <b>${st.maxHp}</b></div>
      <div>🛡️ 방어도 <b>${st.armor}</b> <small>(피해 -${Math.round((1 - 100 / (100 + st.armor)) * 100)}%)</small></div>
      <div>⚔️ 공격력 <b>x${st.dmgMul.toFixed(2)}</b></div>
      <div>👟 이동속도 <b>${Math.round(st.speedMul * 100)}%</b></div>
      ${st.maxMana ? `<div>🔷 마나 <b>${st.maxMana}</b></div>` : ''}
      ${noWeapon ? `<div class="warn">⚠️ 무기 없음 - 기본 무기(공격력 x0.85)로 싸웁니다</div>` : ''}
      <div class="gear-value">위험 부담 장비 가치: 💰 ${[...Object.values(s.equipment).filter(Boolean), ...s.bag].reduce((a, i) => a + i.value, 0)}</div>`;

    // 가방
    const bag = $('#bag-slots');
    bag.innerHTML = '';
    for (let i = 0; i < BAG_SIZE; i++) {
      const it = s.bag[i];
      bag.appendChild(
        this.slot(
          it,
          () => {
            if (!it) return;
            if (s.stash.length >= STASH_SIZE) return this.toast('보관함이 가득 찼습니다');
            s.bag.splice(i, 1);
            s.stash.push(it);
            this.persist();
            this.renderLobby();
          },
          null,
          { tipExtra: '클릭: 보관함으로' },
        ),
      );
    }

    // 오른쪽 탭
    for (const b of document.querySelectorAll('.tab-btn')) b.classList.toggle('active', b.dataset.tab === this.lobbyTab);
    const right = $('#lobby-right-content');
    right.innerHTML = '';
    if (this.lobbyTab === 'stash') {
      const grid = el('div', 'grid stash-grid');
      for (let i = 0; i < STASH_SIZE; i++) {
        const it = s.stash[i];
        const equipable = it && canEquip(it, s.cls);
        const b = it && itemBase(it);
        const hint = !it ? '' : equipable ? '클릭: 장착 · 우클릭: 판매' : b.slot === 'consumable' ? '클릭: 가방에 넣기 · 우클릭: 판매' : b.slot === 'weapon' ? '다른 직업 무기 · 우클릭: 판매' : '클릭: 가방에 넣기 · 우클릭: 판매';
        grid.appendChild(
          this.slot(
            it,
            () => {
              if (!it) return;
              if (equipable) {
                const slot = b.slot;
                const prev = s.equipment[slot];
                s.equipment[slot] = it;
                s.stash.splice(i, 1);
                if (prev) s.stash.push(prev);
              } else if (b.slot === 'weapon') {
                return this.toast(`${CLASSES[b.cls].name} 전용 무기입니다`);
              } else {
                if (s.bag.length >= BAG_SIZE) return this.toast('가방이 가득 찼습니다');
                s.stash.splice(i, 1);
                s.bag.push(it);
              }
              this.persist();
              this.renderLobby();
            },
            () => {
              if (!it) return;
              s.stash.splice(i, 1);
              s.gold += it.value;
              sfx.coin();
              this.toast(`${b.name} 판매: +${it.value}g`);
              this.persist();
              this.renderLobby();
            },
            { tipExtra: hint, dim: it && b.slot === 'weapon' && !equipable },
          ),
        );
      }
      right.appendChild(grid);
      const btns = el('div', 'row-btns');
      const sellT = el('button', 'btn small', '보물 모두 판매');
      sellT.onclick = () => {
        let sum = 0;
        s.stash = s.stash.filter((it) => {
          if (itemBase(it).slot === 'treasure') {
            sum += it.value;
            return false;
          }
          return true;
        });
        if (!sum) return this.toast('판매할 보물이 없습니다');
        s.gold += sum;
        sfx.coin();
        this.toast(`보물 판매: +${sum}g`);
        this.persist();
        this.renderLobby();
      };
      const sort = el('button', 'btn small', '정렬');
      sort.onclick = () => {
        const order = { weapon: 0, head: 1, chest: 2, trinket: 3, consumable: 4, treasure: 5 };
        s.stash.sort((a, b) => order[itemBase(a).slot] - order[itemBase(b).slot] || b.rarity - a.rarity || b.value - a.value);
        this.persist();
        this.renderLobby();
      };
      btns.append(sort, sellT);
      right.appendChild(btns);
    } else if (this.lobbyTab === 'shop') {
      const list = el('div', 'shop-list');
      for (const [base, price] of SHOP) {
        const b = ITEM_BASES[base];
        const row = el('div', 'shop-row');
        const preview = makeItem(base, 0);
        row.appendChild(this.slot(preview, null, null, {}));
        row.appendChild(el('div', 'shop-name', `${b.name}<small>${b.cls ? CLASSES[b.cls].name + ' 무기' : b.slot === 'consumable' ? '소모품' : SLOT_NAMES[b.slot]}</small>`));
        const buy = el('button', 'btn small', `${price}g 구매`);
        buy.disabled = s.gold < price;
        buy.onclick = () => {
          if (s.gold < price) return;
          if (s.stash.length >= STASH_SIZE) return this.toast('보관함이 가득 찼습니다');
          s.gold -= price;
          s.stash.push(makeItem(base, 0));
          sfx.coin();
          this.toast(`${b.name} 구매`);
          this.persist();
          this.renderLobby();
        };
        row.appendChild(buy);
        list.appendChild(row);
      }
      right.appendChild(list);
      right.appendChild(el('p', 'hint', '보관함의 아이템은 우클릭으로 판매할 수 있습니다.'));
    } else {
      const st2 = s.stats;
      right.appendChild(
        el(
          'div',
          'records',
          `<div>입장 횟수 <b>${st2.raids}</b></div><div>탈출 성공 <b>${st2.extracts}</b></div><div>사망 <b>${st2.deaths}</b></div>
          <div>탈출률 <b>${st2.raids ? Math.round((st2.extracts / st2.raids) * 100) : 0}%</b></div>
          <div>몬스터 처치 <b>${st2.kills}</b></div><div>모험가 처치 <b>${st2.pvpKills}</b></div><div>최고 수익 <b>💰 ${st2.bestHaul}</b></div>`,
        ),
      );
      const reset = el('button', 'btn small danger', '저장 데이터 초기화');
      reset.onclick = () => {
        if (!confirm('모든 진행 상황을 삭제할까요?')) return;
        this.save = resetSave();
        this.renderLobby();
      };
      right.appendChild(reset);
    }

    $('#gold').textContent = s.gold;
    // 빈털터리 구제
    const broke = !s.equipment.weapon && !s.stash.some((i) => canEquip(i, s.cls) && itemBase(i).slot === 'weapon') && s.gold < 40;
    $('#relief').classList.toggle('hidden', !broke);
    $('#relief').onclick = () => {
      s.stash.push(makeItem(STARTER_WEAPON[s.cls]), makeItem('health_potion'));
      this.toast('구호 물자를 받았습니다');
      this.persist();
      this.renderLobby();
    };
    $('#enter-btn').onclick = () => {
      this.hideTip();
      this.onStart();
    };
  }

  // ======================================================== 인게임 HUD
  startHud(game) {
    this.game = game;
    this.container = null;
    this.invOpen = false;
    this.mapOpen = false;
    this.show('#hud');
    $('#inventory').classList.add('hidden');
    $('#container').classList.add('hidden');
    $('#bigmap-wrap').classList.add('hidden');
    $('#killfeed').innerHTML = '';
    this.dmgLayer.innerHTML = '';
    this.dmgNums = [];
    this._pv = new THREE.Vector3();
    this.cache.clear();
    const cls = CLASSES[game.player.cls];
    const sk = $('#skills');
    sk.innerHTML = '';
    this.skillEls = {};
    for (const k of ['rmb', 'q', 'e']) {
      const d = cls.skills[k];
      const box = el('div', 'skill', `<div class="sk-key">${k === 'rmb' ? '우클릭' : k.toUpperCase()}</div><div class="sk-name">${d.name}</div><div class="sk-cd"></div>`);
      box.title = d.desc;
      box.id = 'sk-' + k;
      sk.appendChild(box);
      this.skillEls[k] = box;
    }
    for (const k of ['1', '2']) {
      const box = el('div', 'skill potion', `<div class="sk-key">${k}</div><div class="sk-name">${k === '1' ? '🧪' : '🩹'} <span></span></div><div class="sk-cd"></div>`);
      box.id = 'sk-p' + k;
      sk.appendChild(box);
      this.skillEls['p' + k] = box;
    }
    $('#mana-bar').parentElement.classList.toggle('hidden', !game.player.stats.maxMana);
  }

  isPanelOpen() {
    return this.invOpen || !!this.container;
  }

  updateHud(dt) {
    const g = this.game;
    const p = g.player;
    const pct = (v) => Math.max(0, Math.min(100, v * 100)).toFixed(1) + '%';
    this.setStyle('#hp-bar', 'width', pct(p.hp / p.maxHp));
    this.setText('#hp-text', `${Math.ceil(p.hp)} / ${p.maxHp}` + (p.shield > 0 ? ` (+${Math.ceil(p.shield)})` : ''));
    this.setStyle('#hp-heal', 'width', pct(Math.min(p.maxHp, p.hp + p.heal) / p.maxHp));
    this.setStyle('#st-bar', 'width', pct(p.stamina / 100));
    if (p.stats.maxMana) this.setStyle('#mana-bar', 'width', pct(p.mana / p.stats.maxMana));
    const tl = Math.max(0, g.timeLeft);
    const mm = Math.floor(tl / 60);
    const ss = Math.floor(tl % 60);
    this.setText('#timer', `${mm}:${ss.toString().padStart(2, '0')}`);
    this.setClass('#timer', 'danger', tl < 120);
    this.setText('#depth', g.depth > 1 ? `심연 ${g.depth}층` : '고대 지하묘지 1층');
    const ex = g.exitPortals().length;
    this.setText('#portal-info', ex ? `🌀 탈출 포탈 ${ex}개 열림` : `🌀 포탈 대기 중`);
    // 스킬 쿨다운
    const cdOf = { rmb: p.cd.rmb, q: p.cd.q, e: p.cd.e };
    const clsSk = CLASSES[p.cls].skills;
    for (const k of ['rmb', 'q', 'e']) {
      const max = clsSk[k].cd;
      const c = cdOf[k];
      const cooling = !!(max && c > 0);
      this.setStyle(`#sk-${k} .sk-cd`, 'height', cooling ? pct(c / max) : '0%');
      this.setClass(`#sk-${k}`, 'cooling', cooling);
      if (k === 'rmb') this.setClass('#sk-rmb', 'active', (p.cls === 'fighter' && p.blocking) || (p.cls === 'ranger' && !!g.zoom) || (p.cls === 'mage' && p.shield > 0));
      if (k === 'e' && p.cls === 'fighter') this.setClass('#sk-e', 'active', p.rage > 0);
    }
    let pots = 0;
    let bands = 0;
    for (const i of p.bag) {
      if (i.base === 'health_potion') pots++;
      else if (i.base === 'bandage') bands++;
    }
    this.setText('#sk-p1 span', String(pots));
    this.setText('#sk-p2 span', String(bands));

    // 조준 대상
    const t = g.aimedActor();
    if (t) {
      this.setClass('#target', 'hidden', false);
      this.setText('#target .t-name', t.displayName);
      this.setStyle('#target .t-name', 'color', t.kind === 'bot' ? '#ff7a5a' : t.def && t.def.boss ? '#ff4040' : '#ddd');
      this.setStyle('#target .t-hp', 'width', pct(t.hp / t.maxHp));
    } else this.setClass('#target', 'hidden', true);

    // 차징 바
    if (this.channelT > 0) this.channelT -= dt;
    this.setClass('#channel', 'hidden', !(this.channelT > 0));
    const drawK = p.cls === 'ranger' && p.draw >= 0 ? Math.min(1, p.draw / 0.9) : -1;
    this.setStyle('#crosshair', 'transform', drawK >= 0 ? `translate(-50%,-50%) scale(${(1.6 - drawK * 0.8).toFixed(2)})` : 'translate(-50%,-50%)');

    // 피격 비네트
    const lowHp = p.hp / p.maxHp < 0.3 ? 0.35 + Math.sin(g.time * 6) * 0.1 : 0;
    this.hurtV = Math.max(0, (this.hurtV || 0) - dt * 1.5);
    this.setStyle('#vignette', 'opacity', Math.min(1, this.hurtV + lowHp).toFixed(2));

    // 데미지 숫자 (transform만 사용해 레이아웃 계산 없이 이동)
    const cam = g.camera;
    for (let i = this.dmgNums.length - 1; i >= 0; i--) {
      const n = this.dmgNums[i];
      n.t += dt;
      n.pos.y += dt * 1.2;
      const v = this._pv.copy(n.pos).project(cam);
      if (n.t > 0.9 || v.z > 1) {
        n.el.remove();
        this.dmgNums.splice(i, 1);
        continue;
      }
      const x = ((v.x + 1) / 2) * innerWidth;
      const y = ((1 - v.y) / 2) * innerHeight;
      n.el.style.transform = `translate(${x.toFixed(0)}px, ${y.toFixed(0)}px) translate(-50%, -50%)`;
      n.el.style.opacity = (1 - n.t / 0.9).toFixed(2);
    }

    this.fpsFrames = (this.fpsFrames || 0) + 1;
    this.fpsT = (this.fpsT || 0) + dt;
    this.mmTimer -= dt;
    if (this.mmTimer <= 0) {
      this.mmTimer = 0.1;
      this.drawMinimap();
      if (this.mapOpen) this.drawBigMap();
    }
  }

  prompt(text) {
    if (!text) this.setClass('#prompt', 'hidden', true);
    else {
      this.setClass('#prompt', 'hidden', false);
      this.setText('#prompt', text);
    }
  }

  channel(text, k) {
    this.channelT = 0.1;
    this.setText('#channel .ch-text', text);
    this.setStyle('#channel .ch-fill', 'width', (Math.min(1, k) * 100).toFixed(1) + '%');
  }

  announce(title, sub) {
    const a = $('#announce');
    a.innerHTML = `<div class="an-title">${title}</div><div class="an-sub">${sub || ''}</div>`;
    a.classList.remove('show');
    void a.offsetWidth;
    a.classList.add('show');
  }

  killfeed(text, mine, info) {
    const k = el('div', 'kf' + (mine ? ' mine' : '') + (info ? ' info' : ''), text);
    const f = $('#killfeed');
    f.prepend(k);
    while (f.children.length > 6) f.lastChild.remove();
    setTimeout(() => k.remove(), 9000);
  }

  damageNumber(pos, amount, color) {
    const e = el('div', 'dmg', Math.round(amount));
    e.style.color = color;
    this.dmgLayer.appendChild(e);
    pos.x += (Math.random() - 0.5) * 0.6;
    this.dmgNums.push({ el: e, pos, t: 0 });
  }

  hitMarker(kill) {
    const h = $('#hitmarker');
    h.classList.remove('show', 'kill');
    void h.offsetWidth;
    h.classList.add('show');
    if (kill) h.classList.add('kill');
  }

  hurt(frac) {
    this.hurtV = Math.min(1, (this.hurtV || 0) + 0.3 + frac * 2);
  }

  // ======================================================== 미니맵
  drawMap(ctx, w, h, scale, centerOnPlayer) {
    const g = this.game;
    const dg = g.dungeon;
    const p = g.player;
    ctx.fillStyle = '#0b0a09';
    ctx.fillRect(0, 0, w, h);
    const ptx = p.pos.x / 4;
    const ptz = p.pos.z / 4;
    const ox = centerOnPlayer ? w / 2 - ptx * scale : (w - dg.W * scale) / 2;
    const oz = centerOnPlayer ? h / 2 - ptz * scale : (h - dg.H * scale) / 2;
    ctx.save();
    if (centerOnPlayer) {
      ctx.translate(w / 2, h / 2);
      ctx.rotate(p.yaw);
      ctx.translate(-w / 2, -h / 2);
    }
    for (let z = 0; z < dg.H; z++)
      for (let x = 0; x < dg.W; x++) {
        const i = dg.idx(x, z);
        if (!g.explored[i]) continue;
        const v = dg.grid[i];
        if (v === 0) continue;
        ctx.fillStyle = v === 3 ? '#3a342c' : dg.roomId[i] >= 0 ? '#6d6253' : '#4d463c';
        ctx.fillRect(ox + x * scale, oz + z * scale, scale + 0.5, scale + 0.5);
      }
    const dot = (wx, wz, color, r) => {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(ox + (wx / 4) * scale, oz + (wz / 4) * scale, r, 0, Math.PI * 2);
      ctx.fill();
    };
    for (const c of g.chests) if (g.explored[dg.idx(dg.toTile(c.pos.x), dg.toTile(c.pos.z))]) dot(c.pos.x, c.pos.z, c.opened ? '#5a4a2a' : '#ffcc44', Math.max(2, scale * 0.35));
    for (const b of g.lootBags) if (g.explored[dg.idx(dg.toTile(b.pos.x), dg.toTile(b.pos.z))]) dot(b.pos.x, b.pos.z, '#ffe08a', Math.max(1.5, scale * 0.25));
    // 시야 내 적
    for (const a of g.actors) {
      if (a === p || !a.alive || a.extracted) continue;
      if (a.pos.distanceTo(p.pos) > 30 || !dg.los(p.pos.x, p.pos.z, a.pos.x, a.pos.z)) continue;
      dot(a.pos.x, a.pos.z, a.kind === 'bot' ? '#ff5a3a' : '#c33', Math.max(2, scale * 0.35));
    }
    for (const po of g.portals) {
      const t = g.time * 4;
      dot(po.pos.x, po.pos.z, po.kind === 'exit' ? '#4ab8ff' : '#ff3a2a', Math.max(4, scale * 0.8) + Math.sin(t));
    }
    ctx.restore();
    // 플레이어 화살표
    const px = centerOnPlayer ? w / 2 : ox + ptx * scale;
    const pz = centerOnPlayer ? h / 2 : oz + ptz * scale;
    ctx.save();
    ctx.translate(px, pz);
    if (!centerOnPlayer) ctx.rotate(-p.yaw);
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.moveTo(0, -7);
    ctx.lineTo(5, 5);
    ctx.lineTo(0, 2);
    ctx.lineTo(-5, 5);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  drawMinimap() {
    const c = this.minimap;
    this.drawMap(this.mm, c.width, c.height, 5, true);
  }

  drawBigMap() {
    const c = this.bigmap;
    const dg = this.game.dungeon;
    const scale = Math.floor(Math.min(c.width / dg.W, c.height / dg.H));
    this.drawMap(this.bm, c.width, c.height, scale, false);
  }

  toggleMap() {
    this.mapOpen = !this.mapOpen;
    $('#bigmap-wrap').classList.toggle('hidden', !this.mapOpen);
    if (this.mapOpen) this.drawBigMap();
  }

  // ======================================================== 인벤토리 / 컨테이너
  toggleInventory() {
    this.invOpen = !this.invOpen;
    $('#inventory').classList.toggle('hidden', !this.invOpen);
    if (this.invOpen) this.renderInventory();
    else this.hideTip();
  }

  openContainer(c) {
    this.container = c;
    $('#container').classList.remove('hidden');
    this.invOpen = true;
    $('#inventory').classList.remove('hidden');
    this.refreshPanels();
    sfx.chest();
    document.exitPointerLock?.();
  }

  closeContainer() {
    if (!this.container) return;
    this.container = null;
    $('#container').classList.add('hidden');
    this.invOpen = false;
    $('#inventory').classList.add('hidden');
    this.hideTip();
  }

  closePanels() {
    this.closeContainer();
    this.invOpen = false;
    $('#inventory').classList.add('hidden');
    this.hideTip();
  }

  refreshPanels() {
    if (this.invOpen) this.renderInventory();
    if (this.container) this.renderContainer();
  }

  renderInventory() {
    const g = this.game;
    const p = g.player;
    const eq = $('#inv-equip');
    eq.innerHTML = '';
    for (const slot of ['weapon', 'head', 'chest', 'trinket']) {
      const it = p.equipment[slot];
      eq.appendChild(
        this.slot(
          it,
          () => {
            if (!it) return;
            if (p.bag.length >= BAG_SIZE) return this.toast('가방이 가득 찼습니다');
            p.equipment[slot] = null;
            p.bag.push(it);
            p.recalc();
            this.refreshPanels();
          },
          null,
          { label: SLOT_NAMES[slot], tipExtra: '클릭: 해제' },
        ),
      );
    }
    const bag = $('#inv-bag');
    bag.innerHTML = '';
    for (let i = 0; i < BAG_SIZE; i++) {
      const it = p.bag[i];
      const b = it && itemBase(it);
      const hint = !it ? '' : this.container ? '클릭: 사용/장착 · 우클릭: 상자에 넣기' : '클릭: 사용/장착 · 우클릭: 버리기';
      bag.appendChild(
        this.slot(
          it,
          () => {
            if (!it) return;
            if (b.slot === 'consumable') {
              if (p.hp >= p.maxHp) return this.toast('체력이 가득 찼습니다');
              g.usePlayerConsumable(i);
              return;
            }
            if (canEquip(it, p.cls)) {
              const prev = p.equipment[b.slot];
              p.equipment[b.slot] = it;
              p.bag.splice(i, 1);
              if (prev) p.bag.push(prev);
              p.recalc();
              this.refreshPanels();
            } else if (b.slot === 'weapon') this.toast(`${CLASSES[b.cls].name} 전용 무기입니다`);
          },
          () => {
            if (!it) return;
            p.bag.splice(i, 1);
            if (this.container) this.container.items.push(it);
            else g.dropBag(p.pos.clone().add(new THREE.Vector3(Math.sin(-p.yaw) * 1.2, 0, -Math.cos(p.yaw) * 1.2)), [it], '버려진 물건');
            this.refreshPanels();
          },
          { tipExtra: hint },
        ),
      );
    }
    const val = [...Object.values(p.equipment).filter(Boolean), ...p.bag].reduce((s, i) => s + i.value, 0);
    $('#inv-value').textContent = `소지품 가치 💰 ${val}`;
    const st = p.stats;
    $('#inv-stats').innerHTML = `❤️ ${p.maxHp} · 🛡️ ${st.armor} · ⚔️ x${st.dmgMul.toFixed(2)} · 👟 ${Math.round(st.speedMul * 100)}%`;
  }

  renderContainer() {
    const c = this.container;
    const g = this.game;
    const p = g.player;
    $('#cont-title').textContent = c.name;
    const grid = $('#cont-items');
    grid.innerHTML = '';
    const take = (it) => {
      if (p.bag.length >= BAG_SIZE) {
        this.toast('가방이 가득 찼습니다');
        return false;
      }
      c.items.splice(c.items.indexOf(it), 1);
      p.bag.push(it);
      if (ITEM_BASES[it.base].slot === 'treasure') sfx.coin();
      else sfx.pickup();
      return true;
    };
    const n = Math.max(8, c.items.length);
    for (let i = 0; i < n; i++) {
      const it = c.items[i];
      grid.appendChild(
        this.slot(
          it,
          () => {
            if (!it) return;
            take(it);
            this.afterContainerChange();
          },
          null,
          { tipExtra: '클릭: 가져가기' },
        ),
      );
    }
    $('#take-all').onclick = () => {
      const items = [...c.items].sort((a, b) => b.value - a.value);
      for (const it of items) if (!take(it)) break;
      this.afterContainerChange();
    };
  }

  afterContainerChange() {
    const c = this.container;
    this.refreshPanels();
    if (c && c.items !== undefined && this.game.lootBags.includes(c)) this.game.refreshBag(c);
  }

  // ======================================================== 일시정지 / 결과
  showPause(show, onAbandon) {
    $('#pause').classList.toggle('hidden', !show);
    $('#abandon-btn').onclick = onAbandon;
  }

  raidEnded(result) {
    document.exitPointerLock?.();
    this.closePanels();
    this.show('#results');
    const r = $('#results');
    const mins = Math.floor(result.time / 60);
    const secs = Math.floor(result.time % 60);
    r.querySelector('.res-title').textContent = result.success ? '탈출 성공!' : '사망';
    r.querySelector('.res-title').className = 'res-title ' + (result.success ? 'ok' : 'fail');
    r.querySelector('.res-sub').textContent = result.success ? `모든 전리품을 보관함으로 옮겼습니다 (심연 ${result.depth}층)` : `${result.killer}에게 쓰러졌습니다. 소지품을 모두 잃었습니다.`;
    r.querySelector('.res-stats').innerHTML = `<div>⏱️ 생존 시간 <b>${mins}분 ${secs}초</b></div><div>💀 몬스터 처치 <b>${result.kills}</b></div><div>⚔️ 모험가 처치 <b>${result.pvpKills}</b></div><div>💰 ${result.success ? '획득' : '손실'} 가치 <b>${result.value}</b></div>`;
    const grid = r.querySelector('.res-items');
    grid.innerHTML = '';
    for (const it of result.items) {
      const s = this.slot(it, null, null, {});
      if (!result.success) s.classList.add('lost');
      grid.appendChild(s);
    }
    if (this.onResultContinue) $('#res-continue').onclick = this.onResultContinue;
  }
}
