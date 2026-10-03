// 액터: 플레이어, 몬스터, 경쟁 모험가(봇)
import * as THREE from 'three';
import { CLASSES, MONSTERS, BOT_NAMES, STARTER_WEAPON, ITEM_BASES, makeItem, rollRarity, rollLoot } from './data.js';
import { makeHumanoid, makeHealthBar } from './models.js';
import { sfx } from './audio.js';

export function angleDiff(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}
export function yawTo(dx, dz) {
  return Math.atan2(-dx, -dz);
}
export function fwd(yaw) {
  return { x: -Math.sin(yaw), z: -Math.cos(yaw) };
}

export function computeStats(cls, equipment) {
  const c = CLASSES[cls];
  let hp = c.hp;
  let armor = 0;
  let speed = 0;
  let dmgBonus = 0;
  let mana = c.mana || 0;
  let dmg = 0.85;
  for (const slot of ['weapon', 'head', 'chest', 'trinket']) {
    const it = equipment[slot];
    if (!it) continue;
    const s = it.stats || {};
    if (slot === 'weapon') dmg = s.dmg || 1;
    hp += s.hp || 0;
    armor += s.armor || 0;
    speed += s.speed || 0;
    dmgBonus += s.dmgBonus || 0;
    if (c.mana) mana += s.mana || 0;
  }
  return { maxHp: hp, armor, speedMul: Math.max(0.6, 1 + speed), dmgMul: dmg * (1 + dmgBonus), maxMana: mana, baseSpeed: c.speed };
}

export class Actor {
  constructor(game, o) {
    this.game = game;
    this.kind = o.kind;
    this.name = o.name;
    this.faction = o.faction;
    this.pos = o.pos.clone();
    this.pos.y = 0;
    this.yaw = Math.random() * Math.PI * 2;
    this.radius = o.radius ?? 0.45;
    this.height = o.height ?? 1.9;
    this.maxHp = o.hp;
    this.hp = o.hp;
    this.armor = o.armor ?? 0;
    this.alive = true;
    this.knock = new THREE.Vector3();
    this.stun = 0;
    this.slow = 0;
    this.shield = 0;
    this.invuln = 0;
    this.blocking = false;
    this.lastAttacker = null;
    this.hitFlash = 0;
    this.heal = 0; // 남은 지속 회복량
    this.healRate = 0;
    this.deathT = 0;
    this.moveAmt = 0;
    this.walkPhase = 0;
    this.attackAnim = 0;
    this.windup = 0;
  }

  get displayName() {
    return this.name;
  }

  center(out = new THREE.Vector3()) {
    return out.set(this.pos.x, this.pos.y + this.height * 0.6, this.pos.z);
  }

  takeDamage(amount, src, info = {}) {
    if (!this.alive || this.invuln > 0) return 0;
    let dmg = amount;
    let blocked = false;
    if (this.blocking) {
      const from = info.from || (src && src.pos);
      if (from) {
        const y = yawTo(from.x - this.pos.x, from.z - this.pos.z);
        if (Math.abs(angleDiff(y, this.yaw)) < 1.25) {
          blocked = true;
          dmg *= 0.25;
          if (this.onBlock) this.onBlock(amount);
        }
      }
    }
    dmg *= 100 / (100 + this.armor);
    if (this.shield > 0) {
      const a = Math.min(this.shield, dmg);
      this.shield -= a;
      dmg -= a;
    }
    dmg = Math.max(0, dmg);
    this.hp -= dmg;
    this.hitFlash = 0.15;
    if (src && src !== this) this.lastAttacker = src;
    if (info.knock && !blocked) {
      this.knock.x += info.knock.x;
      this.knock.z += info.knock.z;
    }
    if (info.stun && !blocked) this.stun = Math.max(this.stun, info.stun);
    this.game.onDamage(this, dmg, src, blocked, info);
    if (this.onHurt) this.onHurt(src);
    if (this.hp <= 0) {
      this.hp = 0;
      this.alive = false;
      this.game.onDeath(this, src);
    }
    return dmg;
  }

  applyHeal(amount, duration) {
    this.heal += amount;
    this.healRate = Math.max(this.healRate, amount / duration);
  }

  tickCommon(dt) {
    if (this.stun > 0) this.stun -= dt;
    if (this.slow > 0) this.slow -= dt;
    if (this.invuln > 0) this.invuln -= dt;
    if (this.hitFlash > 0) this.hitFlash -= dt;
    if (this.heal > 0) {
      const h = Math.min(this.heal, this.healRate * dt);
      this.heal -= h;
      this.hp = Math.min(this.maxHp, this.hp + h);
      if (this.heal <= 0) this.healRate = 0;
    }
    // 넉백
    if (this.knock.lengthSq() > 0.001) {
      this.pos.x += this.knock.x * dt;
      this.pos.z += this.knock.z * dt;
      this.knock.multiplyScalar(Math.max(0, 1 - dt * 8));
      this.game.dungeon.resolveCircle(this.pos, this.radius);
    }
  }

  // 수평 이동 + 벽 충돌
  move(dx, dz, dt) {
    this.pos.x += dx * dt;
    this.pos.z += dz * dt;
    this.game.dungeon.resolveCircle(this.pos, this.radius);
  }
}

// ---------------------------------------------------------------------------
// AI 공용: 경로 이동
class AIActor extends Actor {
  constructor(game, o) {
    super(game, o);
    this.path = null;
    this.pathGoal = new THREE.Vector3();
    this.pathTimer = 0;
    this.directTimer = 0;
    this.direct = false;
    this.target = null;
    this.senseTimer = Math.random() * 0.3;
    this.atkCd = 0;
    this.mesh = null;
    this.hpBar = makeHealthBar();
    game.scene.add(this.hpBar);
  }

  turnTo(yaw, dt, rate = 8) {
    const d = angleDiff(yaw, this.yaw);
    this.yaw += Math.sign(d) * Math.min(Math.abs(d), rate * dt);
  }

  // 목표 지점까지 경로를 따라 이동. 도착하면 true
  navTo(goal, speed, dt, stopDist = 0.6, face = true) {
    const dg = this.game.dungeon;
    const dx0 = goal.x - this.pos.x;
    const dz0 = goal.z - this.pos.z;
    const dist = Math.hypot(dx0, dz0);
    if (dist < stopDist) {
      this.moveAmt = 0;
      return true;
    }
    this.directTimer -= dt;
    this.pathTimer -= dt;
    if (this.directTimer <= 0) {
      this.direct = dist < 40 && dg.wideLos(this.pos, goal);
      this.directTimer = 0.3 + Math.random() * 0.1;
    }
    let tx = goal.x;
    let tz = goal.z;
    if (!this.direct) {
      if (!this.path || this.pathTimer <= 0 || this.pathGoal.distanceToSquared(goal) > 9) {
        this.path = dg.path(this.pos.x, this.pos.z, goal.x, goal.z);
        this.pathGoal.copy(goal);
        this.pathTimer = 1.2;
      }
      if (this.path && this.path.length) {
        let wp = this.path[0];
        if (Math.hypot(wp.x - this.pos.x, wp.z - this.pos.z) < 0.9 && this.path.length > 1) {
          this.path.shift();
          wp = this.path[0];
        }
        tx = wp.x;
        tz = wp.z;
      }
    }
    const dx = tx - this.pos.x;
    const dz = tz - this.pos.z;
    const d = Math.hypot(dx, dz) || 1;
    const sp = speed * (this.slow > 0 ? 0.55 : 1);
    this.move((dx / d) * sp, (dz / d) * sp, dt);
    if (face) this.turnTo(yawTo(dx, dz), dt);
    this.moveAmt = 1;
    return false;
  }

  hostileTo(o) {
    return this.game.hostile(this, o);
  }

  // 시야 내 가장 가까운 적 탐색
  sense(range) {
    let best = null;
    let bd = range;
    for (const a of this.game.actors) {
      if (!a.alive || a === this || !this.hostileTo(a) || a.extracted) continue;
      const d = Math.hypot(a.pos.x - this.pos.x, a.pos.z - this.pos.z);
      if (d >= bd) continue;
      if (!this.game.dungeon.los(this.pos.x, this.pos.z, a.pos.x, a.pos.z)) continue;
      // 뒤쪽은 가까울 때만 감지
      const ang = Math.abs(angleDiff(yawTo(a.pos.x - this.pos.x, a.pos.z - this.pos.z), this.yaw));
      if (ang > 1.9 && d > 6) continue;
      best = a;
      bd = d;
    }
    return best;
  }

  animate(dt) {
    const p = this.mesh.userData.parts;
    this.mesh.position.copy(this.pos);
    this.mesh.rotation.y = this.yaw;
    if (!this.alive) {
      this.deathT += dt;
      p.rig.rotation.x = Math.max(-Math.PI / 2, -this.deathT * 5);
      p.rig.position.y = Math.min(0.25, this.deathT);
      return;
    }
    this.walkPhase += dt * 9 * this.moveAmt;
    const sw = Math.sin(this.walkPhase) * 0.7 * this.moveAmt;
    p.legL.rotation.x = sw;
    p.legR.rotation.x = -sw;
    p.armL.rotation.x = -sw * 0.6;
    p.armR.rotation.x = sw * 0.6;
    if (this.windup > 0) {
      p.armR.rotation.x = 2.6 * Math.min(1, 1 - this.windup / this.windupMax + 0.3);
      p.armR.rotation.z = 0.3;
    } else if (this.attackAnim > 0) {
      this.attackAnim -= dt;
      p.armR.rotation.x = 2.6 - (1 - this.attackAnim / 0.25) * 3.2;
      p.armR.rotation.z = 0;
    } else p.armR.rotation.z = 0;
    if (this.aimAnim) {
      p.armL.rotation.x = Math.PI / 2;
      p.armR.rotation.x = Math.PI / 2;
    }
    if (this.blocking) p.armL.rotation.x = 1.3;
    // 피격 시 붉게
    const flash = this.hitFlash > 0;
    if (flash !== this._flashing) {
      this._flashing = flash;
      this.mesh.traverse((o) => {
        if (o.isMesh && o.material.emissive) {
          if (flash) {
            o.userData.origMat = o.userData.origMat || o.material;
            o.material = this.game.flashMat;
          } else if (o.userData.origMat) o.material = o.userData.origMat;
        }
      });
    }
  }

  updateHpBar(camera) {
    const show = this.alive && this.hp < this.maxHp && this.game.player.pos.distanceTo(this.pos) < 25;
    this.hpBar.visible = show;
    if (!show) return;
    this.hpBar.position.set(this.pos.x, this.pos.y + this.height + 0.35, this.pos.z);
    this.hpBar.quaternion.copy(camera.quaternion);
    const f = this.hpBar.userData.fg;
    const r = Math.max(0, this.hp / this.maxHp);
    f.scale.x = Math.max(0.001, r);
    f.position.x = -(1 - r) / 2;
  }

  removeFromScene() {
    this.game.scene.remove(this.mesh);
    this.game.scene.remove(this.hpBar);
  }
}

// ---------------------------------------------------------------------------
export class Monster extends AIActor {
  constructor(game, type, pos, room, depthMul = 1) {
    const def = MONSTERS[type];
    super(game, {
      kind: 'monster',
      name: def.name,
      faction: 'monster',
      pos,
      hp: Math.round(def.hp * depthMul),
      radius: 0.45 * def.scale,
      height: 1.9 * def.scale,
      armor: def.boss ? 30 : 0,
    });
    this.type = type;
    this.def = def;
    this.dmgMul = depthMul;
    this.home = room;
    this.homePos = pos.clone();
    this.wanderT = Math.random() * 4;
    this.wanderGoal = null;
    this.lostT = 0;
    this.slamCd = 6;
    this.slamT = 0;
    let mesh;
    if (type === 'skeleton') mesh = makeHumanoid({ skeletal: true, head: 0xe0d8c0, body: 0xb8b09a, weapon: 'sword', eyes: 0xff4422, shield: Math.random() < 0.5 });
    else if (type === 'skeleton_archer') mesh = makeHumanoid({ skeletal: true, head: 0xe0d8c0, body: 0xa8a08a, weapon: 'bow', eyes: 0x44ff66 });
    else if (type === 'goblin') mesh = makeHumanoid({ skin: 0x5d8a3a, body: 0x5a4028, legs: 0x3a2a18, weapon: 'club', scale: 0.75, headScale: 1.35, eyes: 0xffee00 });
    else if (type === 'ghoul') mesh = makeHumanoid({ skin: 0x7a8a6a, body: 0x4a5040, legs: 0x3a4030, weapon: 'claws', scale: 1.1, eyes: 0xff0000, hunch: 0.5 });
    else mesh = makeHumanoid({ skin: 0x222233, body: 0x1d1d26, legs: 0x15151c, helmet: 0x2a2a35, weapon: 'boss_sword', scale: 1.55, eyes: 0xff2200, shield: false });
    this.mesh = mesh;
    game.scene.add(mesh);
    this.hpBar.scale.setScalar(def.boss ? 2 : 1);
  }

  onHurt(src) {
    if (src && src.alive && this.hostileTo(src)) {
      if (!this.target || Math.random() < 0.5) this.target = src;
      this.lostT = 0;
    }
  }

  update(dt) {
    this.tickCommon(dt);
    if (!this.alive) return;
    // 멀리 있으면 휴면
    if (this.game.nearestAdventurerDist(this.pos) > 50) {
      this.moveAmt = 0;
      return;
    }
    if (this.atkCd > 0) this.atkCd -= dt;
    if (this.stun > 0) {
      this.windup = 0;
      this.moveAmt = 0;
      return;
    }
    this.senseTimer -= dt;
    if (this.senseTimer <= 0) {
      this.senseTimer = 0.35;
      const t = this.sense(this.def.sight);
      if (t && (!this.target || !this.target.alive)) {
        this.target = t;
        if (Math.random() < 0.5) sfx.growl(this.game.distToPlayer(this.pos));
      }
      if (this.target && (!this.target.alive || this.target.extracted)) this.target = null;
    }
    const t = this.target;
    if (t) {
      const dx = t.pos.x - this.pos.x;
      const dz = t.pos.z - this.pos.z;
      const d = Math.hypot(dx, dz);
      const seen = this.game.dungeon.los(this.pos.x, this.pos.z, t.pos.x, t.pos.z);
      if (!seen) this.lostT += dt;
      else this.lostT = 0;
      if (this.lostT > 7 || d > 45) {
        this.target = null;
        return;
      }
      // 윈드업 진행
      if (this.windup > 0) {
        this.windup -= dt;
        this.moveAmt = 0;
        this.turnTo(yawTo(dx, dz), dt, this.def.boss ? 2.5 : 4);
        if (this.windup <= 0) this.releaseAttack();
        return;
      }
      if (this.def.boss) {
        this.slamCd -= dt;
        if (this.slamCd <= 0 && d < 7) {
          this.slamCd = 7 + Math.random() * 3;
          this.startWindup(1.1, 'slam');
          return;
        }
      }
      if (this.def.ranged) {
        this.aimAnim = d < this.def.range && seen;
        if (d < this.def.range && seen) {
          this.turnTo(yawTo(dx, dz), dt);
          if (d < 4) this.move((-dx / d) * this.def.speed * 0.7, (-dz / d) * this.def.speed * 0.7, dt);
          else this.moveAmt = 0;
          if (this.atkCd <= 0) this.startWindup(0.7, 'shoot');
        } else this.navTo(t.pos, this.def.speed, dt, 1);
      } else {
        if (d < this.def.range * 0.85 + t.radius && seen) {
          this.moveAmt = 0;
          this.turnTo(yawTo(dx, dz), dt);
          if (this.atkCd <= 0) this.startWindup(this.def.boss ? 0.7 : 0.5, 'melee');
        } else this.navTo(t.pos, this.def.speed, dt, 0.5);
      }
    } else {
      this.aimAnim = false;
      // 배회 / 귀환
      this.wanderT -= dt;
      if (!this.wanderGoal || this.wanderT <= 0) {
        this.wanderT = 3 + Math.random() * 5;
        this.wanderGoal = Math.random() < 0.4 ? null : this.game.dungeon.randomPointInRoom(this.home, 1);
        if (this.pos.distanceTo(this.homePos) > 20) this.wanderGoal = this.homePos.clone();
      }
      if (this.wanderGoal) {
        if (this.navTo(this.wanderGoal, this.def.speed * 0.4, dt, 0.8)) this.wanderGoal = null;
      } else this.moveAmt = 0;
    }
  }

  startWindup(time, kind) {
    this.windup = time;
    this.windupMax = time;
    this.windupKind = kind;
    if (kind === 'slam') this.game.spawnTelegraph(this.pos, 5.5, time);
  }

  releaseAttack() {
    const g = this.game;
    const dmg = this.def.dmg * this.dmgMul;
    this.attackAnim = 0.25;
    if (this.windupKind === 'shoot') {
      this.atkCd = this.def.cd;
      const t = this.target;
      if (t) g.shootAt(this, t, 'arrow', dmg, 30, 0.04);
    } else if (this.windupKind === 'slam') {
      this.atkCd = 1;
      g.explode(this.pos, 5.5, dmg * 1.3, this, 'slam');
    } else {
      this.atkCd = this.def.cd;
      sfx.swing(g.distToPlayer(this.pos));
      g.meleeHit(this, dmg, this.def.range + 0.3, 1.4, { knock: this.def.boss ? 9 : 3 });
    }
  }
}

// ---------------------------------------------------------------------------
const CLASS_LOOK = {
  fighter: { body: 0x7a7f88, legs: 0x3b3b40, helmet: 0x8a8f99, weapon: 'sword', shield: true },
  ranger: { body: 0x34552f, legs: 0x3a2e20, helmet: null, weapon: 'bow', shield: false },
  mage: { body: 0x2f3470, legs: 0x23264f, helmet: 0x2a2d66, weapon: 'staff', shield: false },
};

const usedNames = new Set();
function pickName() {
  const pool = BOT_NAMES.filter((n) => !usedNames.has(n));
  const n = pool.length ? pool[Math.floor(Math.random() * pool.length)] : 'Adventurer' + Math.floor(Math.random() * 99);
  usedNames.add(n);
  if (usedNames.size > BOT_NAMES.length - 4) usedNames.clear();
  return n;
}

function randomGear(cls, depth) {
  const luck = depth - 1 + Math.random();
  const weapons = Object.keys(ITEM_BASES).filter((k) => ITEM_BASES[k].slot === 'weapon' && ITEM_BASES[k].cls === cls);
  const pick = (slot) => {
    const ks = Object.keys(ITEM_BASES).filter((k) => ITEM_BASES[k].slot === slot);
    return ks[Math.floor(Math.random() * ks.length)];
  };
  return {
    weapon: makeItem(Math.random() < 0.35 ? STARTER_WEAPON[cls] : weapons[Math.floor(Math.random() * weapons.length)], rollRarity(luck - 1)),
    head: Math.random() < 0.6 ? makeItem(pick('head'), rollRarity(luck - 1)) : null,
    chest: Math.random() < 0.75 ? makeItem(pick('chest'), rollRarity(luck - 1)) : null,
    trinket: Math.random() < 0.3 ? makeItem(pick('trinket'), rollRarity(luck)) : null,
  };
}

export class Bot extends AIActor {
  constructor(game, pos, depth) {
    const clsIds = Object.keys(CLASSES);
    const cls = clsIds[Math.floor(Math.random() * clsIds.length)];
    const equipment = randomGear(cls, depth);
    const st = computeStats(cls, equipment);
    const name = pickName();
    super(game, { kind: 'bot', name, faction: 'bot_' + name, pos, hp: st.maxHp, armor: st.armor });
    this.cls = cls;
    this.equipment = equipment;
    this.stats = st;
    this.bag = [];
    const pots = Math.floor(Math.random() * 3);
    for (let i = 0; i < pots; i++) this.bag.push(makeItem('health_potion'));
    if (Math.random() < 0.4) this.bag.push(...rollLoot(1, depth - 1));
    this.mana = st.maxMana;
    this.goal = null;
    this.goalTimer = 0;
    this.chestT = 0;
    this.extractT = 0;
    this.reactT = 0;
    this.strafeDir = Math.random() < 0.5 ? 1 : -1;
    this.strafeT = 0;
    this.fireballCd = 4;
    this.skill = 6 + Math.random() * 6;
    this.aim = 0.03 + Math.random() * 0.05; // 조준 오차
    this.courage = Math.random(); // 낮으면 일찍 탈출
    const look = CLASS_LOOK[cls];
    this.mesh = makeHumanoid({
      body: look.body,
      legs: look.legs,
      helmet: equipment.head ? look.helmet ?? 0x6a5a40 : null,
      weapon: look.weapon,
      shield: look.shield,
    });
    game.scene.add(this.mesh);
  }

  get displayName() {
    return `${this.name} (${CLASSES[this.cls].name})`;
  }

  get bagValue() {
    return this.bag.reduce((s, i) => s + i.value, 0);
  }

  onHurt(src) {
    if (src && src.alive && this.hostileTo(src)) {
      const cur = this.target;
      if (!cur || !cur.alive || (src.kind !== 'monster' && cur.kind === 'monster') || Math.random() < 0.3) {
        this.target = src;
        this.reactT = 0.15;
      }
    }
    this.chestT = 0;
    this.extractT = 0;
  }

  potionCount() {
    return this.bag.filter((i) => i.base === 'health_potion' || i.base === 'bandage').length;
  }

  usePotion() {
    const i = this.bag.findIndex((i) => i.base === 'health_potion' || i.base === 'bandage');
    if (i < 0) return false;
    const it = this.bag.splice(i, 1)[0];
    this.applyHeal(ITEM_BASES[it.base].heal, 3);
    return true;
  }

  takeFrom(items, max = 99) {
    // 가치 높은 순으로 가방에 담기 (최대 14칸)
    items.sort((a, b) => b.value - a.value);
    let n = 0;
    while (items.length && this.bag.length < 14 && n < max) {
      this.bag.push(items.shift());
      n++;
    }
    return n;
  }

  update(dt) {
    this.tickCommon(dt);
    if (!this.alive || this.extracted) return;
    if (this.atkCd > 0) this.atkCd -= dt;
    this.fireballCd -= dt;
    if (this.stats.maxMana) this.mana = Math.min(this.stats.maxMana, this.mana + dt * 7);
    if (this.stun > 0) {
      this.windup = 0;
      this.moveAmt = 0;
      return;
    }
    // 위급 시 물약
    if (this.hp < this.maxHp * 0.45 && this.heal <= 0 && this.potionCount() && (!this.target || this.targetDist() > 7)) {
      this.usePotion();
    }

    this.senseTimer -= dt;
    if (this.senseTimer <= 0) {
      this.senseTimer = 0.3;
      if (this.target && (!this.target.alive || this.target.extracted)) this.target = null;
      let seen = this.sense(24);
      if (seen && seen.def && seen.def.boss && this.courage < 0.85 && seen !== this.lastAttacker) seen = null;
      if (seen && (!this.target || (seen !== this.target && this.targetDist() > seen.pos.distanceTo(this.pos) + 5))) {
        if (this.target !== seen) this.reactT = 0.35 + Math.random() * 0.5;
        this.target = seen;
      }
      if (this.target) {
        const d = this.targetDist();
        if (d > 35 || (!this.game.dungeon.los(this.pos.x, this.pos.z, this.target.pos.x, this.target.pos.z) && Math.random() < 0.1)) this.target = null;
      }
    }

    if (this.target) {
      this.combat(dt);
      return;
    }
    this.blocking = false;
    this.aimAnim = false;
    this.explore(dt);
  }

  targetDist() {
    return this.target ? Math.hypot(this.target.pos.x - this.pos.x, this.target.pos.z - this.pos.z) : 1e9;
  }

  combat(dt) {
    const g = this.game;
    const t = this.target;
    const dx = t.pos.x - this.pos.x;
    const dz = t.pos.z - this.pos.z;
    const d = Math.hypot(dx, dz) || 1;
    const seen = g.dungeon.los(this.pos.x, this.pos.z, t.pos.x, t.pos.z);
    const speed = this.stats.baseSpeed * this.stats.speedMul * 0.95;
    this.chestT = 0;
    this.extractT = 0;
    if (this.reactT > 0) {
      this.reactT -= dt;
      this.turnTo(yawTo(dx, dz), dt, 5);
      this.moveAmt = 0;
      return;
    }
    if (this.windup > 0) {
      this.windup -= dt;
      this.turnTo(yawTo(dx, dz), dt, 6);
      if (this.cls !== 'fighter') this.moveAmt = 0;
      else this.move((dx / d) * speed * 0.4, (dz / d) * speed * 0.4, dt);
      if (this.windup <= 0) this.release();
      return;
    }
    this.strafeT -= dt;
    if (this.strafeT <= 0) {
      this.strafeT = 0.8 + Math.random() * 1.5;
      this.strafeDir *= -1;
    }
    if (this.cls === 'fighter') {
      // 상대가 공격 중이면 방어
      const threat = (t.windup > 0 || t.swinging) && d < 4;
      this.blocking = threat && Math.random() < 0.9 && this.atkCd > 0.2;
      if (d > 2.4 || !seen) {
        this.blocking = false;
        this.navTo(t.pos, speed * (d > 8 ? 1.3 : 1), dt, 0.5);
      } else {
        this.turnTo(yawTo(dx, dz), dt, 9);
        this.move((-dz / d) * this.strafeDir * speed * 0.35, (dx / d) * this.strafeDir * speed * 0.35, dt);
        this.moveAmt = 0.5;
        if (this.atkCd <= 0 && !threat) {
          this.blocking = false;
          this.windup = 0.32;
          this.windupMax = 0.32;
        }
      }
    } else {
      const want = this.cls === 'ranger' ? 11 : 12;
      if (!seen || d > want + 8) {
        this.aimAnim = false;
        this.navTo(t.pos, speed, dt, 1);
        return;
      }
      this.turnTo(yawTo(dx, dz), dt, 8);
      let mx = (-dz / d) * this.strafeDir * 0.6;
      let mz = (dx / d) * this.strafeDir * 0.6;
      if (d < want - 4) {
        mx -= dx / d;
        mz -= dz / d;
      } else if (d > want + 3) {
        mx += dx / d;
        mz += dz / d;
      }
      this.move(mx * speed * 0.7, mz * speed * 0.7, dt);
      this.moveAmt = 0.6;
      this.aimAnim = this.cls === 'ranger';
      if (this.atkCd <= 0) {
        if (this.cls === 'mage' && this.mana < 10) return;
        this.windup = this.cls === 'ranger' ? 0.55 : 0.3;
        this.windupMax = this.windup;
      }
    }
  }

  release() {
    const g = this.game;
    const t = this.target;
    this.attackAnim = 0.25;
    if (!t) return;
    const dm = this.stats.dmgMul * (t.kind === 'monster' ? 0.65 : 1);
    if (this.cls === 'fighter') {
      this.atkCd = 1.0 + Math.random() * 0.5;
      sfx.swing(g.distToPlayer(this.pos));
      g.meleeHit(this, 22 * dm, 3.0, 1.4, { knock: 4 });
    } else if (this.cls === 'ranger') {
      this.atkCd = 1.3 + Math.random() * 0.7;
      g.shootAt(this, t, 'arrow', 26 * dm, 48, this.aim);
    } else {
      if (this.fireballCd <= 0 && this.mana >= 30 && this.targetDist() > 5) {
        this.fireballCd = 7;
        this.mana -= 30;
        this.atkCd = 1;
        g.shootAt(this, t, 'fireball', 40 * dm, 24, this.aim);
      } else {
        this.mana -= 10;
        this.atkCd = 0.9 + Math.random() * 0.5;
        g.shootAt(this, t, 'bolt', 18 * dm, 42, this.aim);
      }
    }
  }

  chooseGoal() {
    const g = this.game;
    const tl = g.timeLeft;
    const wantOut = g.exitPortals().length && (tl < 120 + this.courage * 120 || this.bagValue > 700 + this.courage * 1300 || (this.hp < this.maxHp * 0.3 && !this.potionCount()));
    if (wantOut) {
      const p = g.nearest(g.exitPortals(), this.pos);
      if (p) return { type: 'portal', pos: p.pos, ref: p };
    }
    // 근처 전리품 가방
    const bags = g.lootBags.filter((b) => b.items.length && b.pos.distanceTo(this.pos) < 25);
    if (bags.length) {
      const b = g.nearest(bags, this.pos);
      return { type: 'bag', pos: b.pos, ref: b };
    }
    // 열리지 않은 상자
    const chests = g.chests.filter(
      (c) => !c.opened && (!c.claimedBy || c.claimedBy === this || !c.claimedBy.alive) && (!c.room || !c.room.boss || this.courage > 0.85 || g.bossDead),
    );
    if (chests.length && this.bag.length < 14) {
      const c = g.nearest(chests, this.pos);
      c.claimedBy = this;
      return { type: 'chest', pos: c.pos, ref: c };
    }
    const r = g.dungeon.rooms[Math.floor(Math.random() * g.dungeon.rooms.length)];
    return { type: 'wander', pos: g.dungeon.randomPointInRoom(r) };
  }

  explore(dt) {
    const g = this.game;
    this.goalTimer -= dt;
    if (!this.goal || this.goalTimer <= 0 || (this.goal.type === 'chest' && this.goal.ref.opened && this.chestT <= 0)) {
      this.goal = this.chooseGoal();
      this.goalTimer = 25;
    }
    // 탈출 판단은 수시로
    if (this.goal.type !== 'portal' && g.exitPortals().length && Math.random() < dt * 0.5) {
      const ng = this.chooseGoal();
      if (ng.type === 'portal') this.goal = ng;
    }
    const goal = this.goal;
    const speed = this.stats.baseSpeed * this.stats.speedMul * 0.85;
    const stop = goal.type === 'portal' ? 0.8 : goal.type === 'chest' || goal.type === 'bag' ? 1.6 : 1;
    const arrived = this.navTo(goal.pos, speed, dt, stop);
    if (!arrived) return;
    if (goal.type === 'chest') {
      const c = goal.ref;
      if (c.opened) {
        this.takeFrom(c.items, 3);
        this.goal = null;
        return;
      }
      this.chestT += dt;
      this.moveAmt = 0;
      if (this.chestT > 1.6) {
        this.chestT = 0;
        g.openChest(c, this);
        this.takeFrom(c.items, 3);
        this.goal = null;
      }
    } else if (goal.type === 'bag') {
      this.takeFrom(goal.ref.items);
      g.refreshBag(goal.ref);
      this.goal = null;
    } else if (goal.type === 'portal') {
      this.extractT += dt;
      this.moveAmt = 0;
      if (this.extractT > 3) g.botExtract(this, goal.ref);
    } else this.goal = null;
  }

  allItems() {
    return [...Object.values(this.equipment).filter(Boolean), ...this.bag];
  }
}
