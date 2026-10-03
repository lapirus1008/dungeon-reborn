// 레이드(던전) 진행: 월드, 플레이어 조작, 전투, 투사체, 포탈, 상자
import * as THREE from 'three';
import { Dungeon, WALL_H } from './dungeon.js';
import { makeChest, makeLootBag, makePortal, makeArrow, makeOrb, makeViewModel } from './models.js';
import { CLASSES, ITEM_BASES, rollLoot } from './data.js';
import { Actor, Monster, Bot, computeStats, angleDiff, yawTo, fwd } from './actors.js';
import { sfx } from './audio.js';

export const RAID_TIME = 900; // 15분
const LIGHT_POOL = 8;
const EYE = 1.65;
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();

function rint(a, b) {
  return a + Math.floor(Math.random() * (b - a + 1));
}

class Player extends Actor {
  constructor(game, pos, cls, equipment, bag) {
    const st = computeStats(cls, equipment);
    super(game, { kind: 'player', name: '나', faction: 'player', pos, hp: st.maxHp, armor: st.armor, radius: 0.4 });
    this.cls = cls;
    this.equipment = equipment;
    this.bag = bag;
    this.stats = st;
    this.pitch = 0;
    this.vy = 0;
    this.stamina = 100;
    this.staminaDelay = 0;
    this.mana = st.maxMana;
    this.cd = { lmb: 0, rmb: 0, q: 0, e: 0, potion: 0 };
    this.swing = null;
    this.draw = -1;
    this.dash = null;
    this.rage = 0;
    this.bob = 0;
    this.extractT = 0;
    this.interactT = 0;
    this.kills = 0;
    this.pvpKills = 0;
    this.stepT = 0;
  }
  get swinging() {
    return !!this.swing;
  }
  get displayName() {
    return '당신';
  }
  recalc() {
    const st = computeStats(this.cls, this.equipment);
    const ratio = this.hp / this.maxHp;
    this.stats = st;
    this.maxHp = st.maxHp;
    this.hp = Math.min(this.maxHp, Math.max(1, ratio * this.maxHp));
    this.armor = st.armor;
    this.mana = Math.min(this.mana, st.maxMana);
  }
  onBlock(amount) {
    this.stamina -= amount * 0.7;
    this.staminaDelay = 0.8;
    sfx.block();
    if (this.stamina <= 0) {
      this.stamina = 0;
      this.blocking = false;
      this.stun = 0.6;
      this.game.ui.toast('방어가 무너졌다!');
    }
  }
}

export class Game {
  constructor(renderer, ui, input) {
    this.renderer = renderer;
    this.ui = ui;
    this.input = input;
    this.camera = new THREE.PerspectiveCamera(75, innerWidth / innerHeight, 0.05, 200);
    this.camera.rotation.order = 'YXZ';
    this.flashMat = new THREE.MeshBasicMaterial({ color: 0xff3333 });
    this.running = false;
    this.sensitivity = 0.0022;
  }

  // ------------------------------------------------------------------ 설정
  start(loadout) {
    this.loadout = loadout;
    this.time = 0;
    this.timeLeft = RAID_TIME;
    this.depth = 1;
    this.result = null;
    this.endTimer = -1;
    this.player = null;
    this.buildLevel(1, loadout);
    this.running = true;
    this.ui.announce('던전에 입장했습니다', '보물을 모아 탈출 포탈로 살아 나가세요');
  }

  buildLevel(depth, loadout) {
    if (this.scene) this.dungeon.dispose(this.scene);
    this.depth = depth;
    this.levelTime = 0;
    this.scene = new THREE.Scene();
    const deep = depth > 1;
    this.scene.background = new THREE.Color(deep ? 0x0a0202 : 0x020203);
    this.scene.fog = new THREE.FogExp2(deep ? 0x120404 : 0x050404, 0.045);
    this.baseFog = 0.045;
    this.scene.add(new THREE.AmbientLight(deep ? 0x553333 : 0x48464a, 1.1));
    this.scene.add(new THREE.HemisphereLight(0x9a8f88, 0x1a1410, 0.6));
    this.torchLight = new THREE.PointLight(0xffb070, 9, 20, 1.4);
    this.scene.add(this.torchLight);
    this.lights = [];
    for (let i = 0; i < LIGHT_POOL; i++) {
      const l = new THREE.PointLight(0xff9944, 0, 16, 1.3);
      this.scene.add(l);
      this.lights.push(l);
    }
    this.transientLights = [];
    this.dungeon = new Dungeon(depth);
    this.dungeon.buildMeshes(this.scene);
    this.explored = new Uint8Array(this.dungeon.W * this.dungeon.H);
    this.actors = [];
    this.projectiles = [];
    this.effects = [];
    this.chests = [];
    this.lootBags = [];
    this.portals = [];
    this.portalSchedule = deep
      ? [
          { at: 45, kind: 'exit', n: 2 },
          { at: 200, kind: 'exit', n: 2 },
        ]
      : [
          { at: 120, kind: 'exit', n: 2 },
          { at: 210, kind: 'descend', n: 1 },
          { at: 400, kind: 'exit', n: 2 },
          { at: 640, kind: 'exit', n: 1 },
        ];
    this.warned = false;
    this.bossDead = false;

    const rooms = this.dungeon.rooms;
    const boss = rooms.find((r) => r.boss);
    const normal = rooms.filter((r) => !r.boss);
    // 플레이어 시작 방: 보스 방에서 가장 먼 방 중 랜덤
    normal.sort((a, b) => Math.hypot(b.cx - boss.cx, b.cz - boss.cz) - Math.hypot(a.cx - boss.cx, a.cz - boss.cz));
    const startRoom = normal[rint(0, Math.min(3, normal.length - 1))];
    const spawn = this.dungeon.randomPointInRoom(startRoom, 1);

    if (!this.player) {
      this.player = new Player(this, spawn, loadout.cls, loadout.equipment, loadout.bag);
    } else {
      this.player.pos.copy(spawn);
      this.player.game = this;
    }
    this.player.yaw = Math.random() * Math.PI * 2;
    this.actors.push(this.player);
    this.scene.add(this.camera);
    if (this.viewModel) this.camera.remove(this.viewModel);
    this.viewModel = makeViewModel(this.player.cls);
    this.camera.add(this.viewModel);

    // 경쟁 모험가 스폰 방 (플레이어와 멀리)
    const others = normal.filter((r) => r !== startRoom).sort((a, b) => Math.hypot(b.cx - startRoom.cx, b.cz - startRoom.cz) - Math.hypot(a.cx - startRoom.cx, a.cz - startRoom.cz));
    const botCount = deep ? 3 : 4;
    const botRooms = new Set();
    for (let i = 0; i < botCount && i < others.length; i++) {
      const room = others[Math.min(others.length - 1, i * 2)];
      botRooms.add(room);
      this.actors.push(new Bot(this, this.dungeon.randomPointInRoom(room, 1), depth));
    }

    // 몬스터와 상자
    const mul = deep ? 1.5 : 1;
    const luck = deep ? 1.2 : 0;
    for (const r of rooms) {
      if (r === startRoom) {
        this.spawnChest(r, 0, luck);
        continue;
      }
      if (r.boss) {
        this.actors.push(new Monster(this, 'wraith_knight', this.dungeon.center(Math.floor(r.cx), Math.floor(r.cz)), r, mul));
        for (let i = 0; i < 2; i++) this.actors.push(new Monster(this, 'skeleton', this.dungeon.randomPointInRoom(r), r, mul));
        this.spawnChest(r, 2, luck + 2.5);
        this.spawnChest(r, 1, luck + 1);
        continue;
      }
      const area = r.w * r.h;
      const n = botRooms.has(r) ? 0 : Math.min(4, 1 + Math.floor(area / 18) + (deep ? 1 : 0));
      for (let i = 0; i < n; i++) {
        const roll = Math.random();
        const type = roll < 0.35 ? 'skeleton' : roll < 0.55 ? 'skeleton_archer' : roll < 0.8 ? 'goblin' : 'ghoul';
        this.actors.push(new Monster(this, type, this.dungeon.randomPointInRoom(r), r, mul));
      }
      this.spawnChest(r, Math.random() < 0.25 ? 1 : 0, luck);
      if (area > 30 && Math.random() < 0.5) this.spawnChest(r, 0, luck);
    }
  }

  spawnChest(room, tier, luck) {
    let pos;
    for (let k = 0; k < 20; k++) {
      pos = this.dungeon.randomPointInRoom(room, 0);
      if (!this.chests.some((c) => c.pos.distanceTo(pos) < 3)) break;
    }
    const mesh = makeChest(tier);
    mesh.position.copy(pos);
    mesh.rotation.y = Math.random() * Math.PI * 2;
    this.scene.add(mesh);
    const count = tier === 2 ? 6 : tier === 1 ? rint(3, 4) : rint(1, 3);
    this.chests.push({ pos, mesh, tier, room, opened: false, items: rollLoot(count, luck + tier), name: tier === 2 ? '황금 보물상자' : tier === 1 ? '장식된 상자' : '나무 상자' });
  }

  // ------------------------------------------------------------------ 관계/검색
  hostile(a, b) {
    if (a === b) return false;
    if (a.faction === 'monster' && b.faction === 'monster') return false;
    return true;
  }
  nearest(list, pos) {
    let best = null;
    let bd = 1e9;
    for (const o of list) {
      const d = o.pos.distanceToSquared(pos);
      if (d < bd) {
        bd = d;
        best = o;
      }
    }
    return best;
  }
  exitPortals() {
    return this.portals.filter((p) => p.kind === 'exit');
  }
  distToPlayer(pos) {
    return this.player ? this.player.pos.distanceTo(pos) : 0;
  }
  nearestAdventurerDist(pos) {
    let bd = 1e9;
    for (const a of this.actors) {
      if (a.kind === 'monster' || !a.alive) continue;
      const d = Math.abs(a.pos.x - pos.x) + Math.abs(a.pos.z - pos.z);
      if (d < bd) bd = d;
    }
    return bd;
  }

  // ------------------------------------------------------------------ 전투
  meleeHit(attacker, dmg, range, arc, opts = {}) {
    let hits = 0;
    for (const a of this.actors) {
      if (!a.alive || !this.hostile(attacker, a) || a.extracted) continue;
      const dx = a.pos.x - attacker.pos.x;
      const dz = a.pos.z - attacker.pos.z;
      const d = Math.hypot(dx, dz);
      if (d > range + a.radius) continue;
      if (d > 0.6 && Math.abs(angleDiff(yawTo(dx, dz), attacker.yaw)) > arc / 2) continue;
      if (!this.dungeon.los(attacker.pos.x, attacker.pos.z, a.pos.x, a.pos.z)) continue;
      const k = opts.knock || 0;
      a.takeDamage(dmg, attacker, { knock: { x: (dx / (d || 1)) * k, z: (dz / (d || 1)) * k }, stun: opts.stun, from: attacker.pos });
      hits++;
      if (opts.single) break;
    }
    if (hits) sfx.hit(this.distToPlayer(attacker.pos));
    return hits;
  }

  shootAt(src, target, kind, dmg, speed, spread) {
    const from = new THREE.Vector3(src.pos.x, src.pos.y + src.height * 0.75, src.pos.z);
    const f = fwd(src.yaw);
    from.x += f.x * 0.6;
    from.z += f.z * 0.6;
    const to = target.center(new THREE.Vector3());
    // 간단한 리드샷
    const d = from.distanceTo(to);
    if (target.lastVel) to.addScaledVector(target.lastVel, (d / speed) * 0.6);
    const dir = to.sub(from).normalize();
    dir.x += (Math.random() - 0.5) * spread * 2;
    dir.y += (Math.random() - 0.5) * spread;
    dir.z += (Math.random() - 0.5) * spread * 2;
    dir.normalize();
    this.spawnProjectile(src, kind, from, dir, speed, dmg);
  }

  spawnProjectile(owner, kind, pos, dir, speed, dmg) {
    let mesh;
    let gravity = 0;
    let radius = 0.15;
    let light = null;
    if (kind === 'arrow') {
      mesh = makeArrow();
      gravity = 5;
      sfx.bow(this.distToPlayer(pos));
    } else if (kind === 'bolt') {
      mesh = makeOrb(0x7a6aff, 0.12);
      light = 0x7a6aff;
      sfx.magic(this.distToPlayer(pos));
    } else if (kind === 'fireball') {
      mesh = makeOrb(0xff6a1a, 0.25);
      light = 0xff6a1a;
      radius = 0.3;
      sfx.fire(this.distToPlayer(pos));
    }
    mesh.position.copy(pos);
    this.scene.add(mesh);
    this.projectiles.push({ owner, kind, mesh, pos: pos.clone(), vel: dir.clone().multiplyScalar(speed), dmg, gravity, radius, life: 4, light, stuck: 0 });
  }

  updateProjectiles(dt) {
    const dg = this.dungeon;
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      if (p.stuck > 0) {
        p.stuck -= dt;
        if (p.stuck <= 0) {
          this.scene.remove(p.mesh);
          this.projectiles.splice(i, 1);
        }
        continue;
      }
      p.life -= dt;
      const steps = Math.ceil((p.vel.length() * dt) / 0.3);
      const sdt = dt / steps;
      let done = false;
      for (let s = 0; s < steps && !done; s++) {
        p.vel.y -= p.gravity * sdt;
        p.pos.addScaledVector(p.vel, sdt);
        // 벽/바닥/천장
        if (dg.isSolid(p.pos.x, p.pos.z) || p.pos.y < 0.02 || p.pos.y > WALL_H - 0.05) {
          done = true;
          if (p.kind === 'fireball') this.explode(p.pos, 4, p.dmg, p.owner, 'fire');
          else if (p.kind === 'arrow') {
            p.stuck = 6;
            p.mesh.position.copy(p.pos);
            continue;
          } else this.spark(p.pos, 0x8a7aff);
          break;
        }
        // 액터 충돌
        for (const a of this.actors) {
          if (!a.alive || a === p.owner || a.extracted) continue;
          if (p.owner && !this.hostile(p.owner, a)) continue;
          const dx = a.pos.x - p.pos.x;
          const dz = a.pos.z - p.pos.z;
          if (dx * dx + dz * dz > (a.radius + p.radius) ** 2) continue;
          if (p.pos.y < a.pos.y - 0.1 || p.pos.y > a.pos.y + a.height + 0.1) continue;
          done = true;
          if (p.kind === 'fireball') this.explode(p.pos, 4, p.dmg, p.owner, 'fire');
          else {
            const head = p.pos.y > a.pos.y + a.height * 0.82;
            const dmg = p.dmg * (head ? 1.5 : 1);
            const vn = _v.copy(p.vel).setY(0).normalize();
            a.takeDamage(dmg, p.owner, { knock: { x: vn.x * 2, z: vn.z * 2 }, from: p.owner ? p.owner.pos : p.pos, headshot: head });
            sfx.hit(this.distToPlayer(a.pos));
            if (p.kind === 'bolt') this.spark(p.pos, 0x8a7aff);
          }
          break;
        }
      }
      if (done && p.stuck <= 0) {
        this.scene.remove(p.mesh);
        this.projectiles.splice(i, 1);
        continue;
      }
      if (p.life <= 0) {
        this.scene.remove(p.mesh);
        this.projectiles.splice(i, 1);
        continue;
      }
      p.mesh.position.copy(p.pos);
      if (p.kind === 'arrow') p.mesh.lookAt(_v.copy(p.pos).sub(p.vel));
    }
  }

  explode(pos, radius, dmg, owner, kind) {
    for (const a of this.actors) {
      if (!a.alive || a.extracted || (owner && !this.hostile(owner, a))) continue;
      const dx = a.pos.x - pos.x;
      const dz = a.pos.z - pos.z;
      const d = Math.hypot(dx, dz);
      if (d > radius + a.radius) continue;
      if (!this.dungeon.los(pos.x - dx * 0.01, pos.z - dz * 0.01, a.pos.x, a.pos.z) && d > 1) continue;
      const f = 1 - Math.min(1, d / radius) * 0.5;
      a.takeDamage(dmg * f, owner, { knock: { x: (dx / (d || 1)) * 8, z: (dz / (d || 1)) * 8 }, from: pos, stun: kind === 'slam' ? 0.4 : 0 });
    }
    const color = kind === 'fire' ? 0xff6a1a : 0x9a3aff;
    const m = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.6, depthWrite: false }));
    m.position.copy(pos);
    if (kind === 'slam') m.position.y = 0.2;
    this.scene.add(m);
    this.effects.push({
      mesh: m,
      t: 0,
      dur: 0.45,
      update: (e, k) => {
        e.mesh.scale.setScalar(0.3 + k * radius);
        e.mesh.material.opacity = 0.6 * (1 - k);
      },
    });
    this.transientLights.push({ pos: pos.clone(), color, t: 0.4, intensity: 30 });
    sfx.fire(this.distToPlayer(pos));
    if (this.distToPlayer(pos) < 10) this.shake = 0.3;
  }

  spark(pos, color) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(0.3, 8, 6), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.8, depthWrite: false }));
    m.position.copy(pos);
    this.scene.add(m);
    this.effects.push({
      mesh: m,
      t: 0,
      dur: 0.2,
      update: (e, k) => {
        e.mesh.scale.setScalar(1 + k * 2);
        e.mesh.material.opacity = 0.8 * (1 - k);
      },
    });
  }

  spawnTelegraph(pos, radius, dur) {
    const m = new THREE.Mesh(new THREE.RingGeometry(radius - 0.25, radius, 40), new THREE.MeshBasicMaterial({ color: 0xff2222, transparent: true, opacity: 0.7, side: THREE.DoubleSide, depthWrite: false }));
    m.rotation.x = -Math.PI / 2;
    m.position.set(pos.x, 0.06, pos.z);
    const inner = new THREE.Mesh(new THREE.CircleGeometry(radius, 40), new THREE.MeshBasicMaterial({ color: 0xff2222, transparent: true, opacity: 0.25, side: THREE.DoubleSide, depthWrite: false }));
    inner.rotation.x = -Math.PI / 2;
    inner.position.set(pos.x, 0.05, pos.z);
    this.scene.add(m, inner);
    this.effects.push({
      mesh: m,
      extra: inner,
      t: 0,
      dur,
      update: (e, k) => e.extra.scale.setScalar(Math.max(0.01, k)),
    });
  }

  onDamage(target, dmg, src, blocked, info) {
    const p = this.player;
    if (src === p && target !== p) {
      this.ui.damageNumber(target.center(new THREE.Vector3()), dmg, blocked ? '#9aa' : info.headshot ? '#ffd23a' : '#fff');
      this.ui.hitMarker(target.hp <= 0);
    }
    if (target === p && dmg > 0) {
      this.ui.hurt(dmg / p.maxHp);
      sfx.hurt();
      p.interactT = 0;
    }
  }

  onDeath(actor, src) {
    const sname = src ? src.displayName : '어둠';
    if (actor.kind !== 'monster' || src === this.player) this.ui.killfeed(`${sname} ➜ ${actor.displayName}`, src === this.player || actor === this.player);
    sfx.death(this.distToPlayer(actor.pos));
    actor.windup = 0;
    if (actor.kind === 'monster') {
      if (src === this.player) this.player.kills++;
      const isBoss = actor.def.boss;
      if (isBoss) {
        this.bossDead = true;
        this.ui.announce('망령 기사가 쓰러졌습니다', '황금 보물상자를 차지하세요');
      }
      const luck = (this.depth > 1 ? 1.2 : 0) + (isBoss ? 3 : 0);
      if (isBoss) this.dropBag(actor.pos, rollLoot(5, luck), '망령 기사의 유해', 0xffcc33);
      else if (Math.random() < 0.4) this.dropBag(actor.pos, rollLoot(rint(1, 2), luck), actor.name + '의 유해');
      setTimeout(() => actor.removeFromScene(), 8000);
    } else if (actor.kind === 'bot') {
      if (src === this.player) this.player.pvpKills++;
      this.dropBag(actor.pos, actor.allItems(), actor.name + '의 시체', 0x3355aa);
      actor.hpBar.visible = false;
      setTimeout(() => actor.removeFromScene(), 30000);
    } else if (actor === this.player) {
      this.endRaid(false, src ? src.displayName : '어둠');
    }
  }

  dropBag(pos, items, name, color) {
    if (!items.length) return;
    const mesh = makeLootBag(color);
    const p = pos.clone();
    p.y = 0;
    mesh.position.copy(p);
    this.scene.add(mesh);
    this.lootBags.push({ pos: p, mesh, items, name });
  }

  refreshBag(bag) {
    if (bag.items.length === 0) {
      this.scene.remove(bag.mesh);
      this.lootBags = this.lootBags.filter((b) => b !== bag);
      if (this.ui.container === bag) this.ui.closeContainer();
    }
  }

  openChest(chest, by) {
    if (chest.opened) return;
    chest.opened = true;
    sfx.chest();
    chest.mesh.userData.lid.rotation.x = -1.9;
    void by;
  }

  botExtract(bot, portal) {
    bot.extracted = true;
    bot.alive = false;
    bot.removeFromScene();
    this.ui.killfeed(`${bot.displayName} 이(가) 탈출했습니다`, false, true);
    void portal;
  }

  // ------------------------------------------------------------------ 포탈
  spawnPortal(kind) {
    const rooms = this.dungeon.rooms.filter((r) => !r.boss && !this.portals.some((p) => this.dungeon.roomAt(p.pos.x, p.pos.z) === r));
    const room = rooms[Math.floor(Math.random() * rooms.length)];
    if (!room) return;
    const pos = this.dungeon.center(Math.floor(room.cx), Math.floor(room.cz));
    if (this.dungeon.isSolid(pos.x, pos.z)) pos.copy(this.dungeon.randomPointInRoom(room));
    const mesh = makePortal(kind);
    mesh.position.copy(pos);
    this.scene.add(mesh);
    this.portals.push({ kind, pos, mesh, life: kind === 'descend' ? 150 : Infinity });
  }

  updatePortals(dt) {
    const elapsed = this.levelTime;
    for (const s of this.portalSchedule) {
      if (!s.done && elapsed >= s.at) {
        s.done = true;
        for (let i = 0; i < s.n; i++) this.spawnPortal(s.kind);
        sfx.bell();
        if (s.kind === 'exit') this.ui.announce('탈출 포탈이 열렸습니다', '지도(M)에서 파란 포탈 위치를 확인하세요');
        else this.ui.announce('심연의 포탈이 열렸습니다', '붉은 포탈: 더 깊은 층으로 내려갑니다 (더 강한 적, 더 좋은 보물)');
      }
    }
    for (let i = this.portals.length - 1; i >= 0; i--) {
      const p = this.portals[i];
      p.life -= dt;
      const u = p.mesh.userData;
      u.ring.rotation.z += dt;
      u.disc.material.opacity = 0.35 + Math.sin(this.time * 3) * 0.1;
      u.particles.rotation.y += dt * 0.6;
      u.disc.lookAt(this.camera.position.x, u.disc.getWorldPosition(_v).y, this.camera.position.z);
      u.ring.quaternion.copy(u.disc.quaternion);
      if (p.life <= 0) {
        this.scene.remove(p.mesh);
        this.portals.splice(i, 1);
        this.ui.toast('심연의 포탈이 닫혔습니다');
      }
    }
    // 플레이어 탈출 채널링
    const pl = this.player;
    if (!pl.alive) return;
    const portal = this.portals.find((p) => Math.hypot(p.pos.x - pl.pos.x, p.pos.z - pl.pos.z) < 1.8);
    if (portal) {
      if (pl.extractT === 0) sfx.portal();
      pl.extractT += dt;
      this.ui.channel(portal.kind === 'exit' ? '탈출 중...' : '심연으로 내려가는 중...', pl.extractT / 3);
      if (pl.extractT >= 3) {
        pl.extractT = 0;
        if (portal.kind === 'exit') this.endRaid(true);
        else this.descend();
      }
    } else if (pl.extractT > 0) {
      pl.extractT = 0;
    }
  }

  descend() {
    this.ui.closeContainer();
    this.timeLeft = Math.max(this.timeLeft, 360);
    this.buildLevel(this.depth + 1, this.loadout);
    this.ui.announce('심연 2층', '적이 더 강해지고 보물이 더 값집니다');
    sfx.portal();
  }

  // ------------------------------------------------------------------ 종료
  endRaid(success, killer) {
    if (this.result) return;
    const pl = this.player;
    const items = [...Object.values(pl.equipment).filter(Boolean), ...pl.bag];
    const value = items.reduce((s, i) => s + i.value, 0);
    this.result = { success, killer, items, value, kills: pl.kills, pvpKills: pl.pvpKills, depth: this.depth, time: this.time, equipment: pl.equipment, bag: pl.bag };
    this.endTimer = success ? 0.3 : 2.5;
    this.ui.closeContainer();
    if (success) sfx.portal();
  }

  // ------------------------------------------------------------------ 플레이어
  get uiOpen() {
    return this.ui.isPanelOpen();
  }

  updatePlayer(dt) {
    const p = this.player;
    const inp = this.input;
    const cls = p.cls;
    p.tickCommon(dt);
    for (const k in p.cd) if (p.cd[k] > 0) p.cd[k] -= dt;
    if (p.rage > 0) p.rage -= dt;
    if (p.stats.maxMana) p.mana = Math.min(p.stats.maxMana, p.mana + dt * 7);

    if (!p.alive) {
      this.viewModel.visible = false;
      // 사망 카메라
      p.pitch = Math.min(1.2, p.pitch + dt);
      this.camera.position.y = Math.max(0.3, this.camera.position.y - dt * 2);
      this.camera.rotation.z = Math.min(0.8, this.camera.rotation.z + dt);
      return;
    }

    const looking = inp.locked && !this.uiOpen;
    if (looking) {
      p.yaw -= inp.dx * this.sensitivity * (this.zoom ? 0.55 : 1);
      p.pitch -= inp.dy * this.sensitivity * (this.zoom ? 0.55 : 1);
      p.pitch = Math.max(-1.5, Math.min(1.5, p.pitch));
    }

    const stunned = p.stun > 0;
    // 이동 입력
    let ix = 0;
    let iz = 0;
    if (!stunned) {
      if (inp.keys.has('KeyW')) iz += 1;
      if (inp.keys.has('KeyS')) iz -= 1;
      if (inp.keys.has('KeyA')) ix -= 1;
      if (inp.keys.has('KeyD')) ix += 1;
    }
    const f = fwd(p.yaw);
    const rx = Math.cos(p.yaw);
    const rz = -Math.sin(p.yaw);
    let wx = f.x * iz + rx * ix;
    let wz = f.z * iz + rz * ix;
    const wl = Math.hypot(wx, wz);
    if (wl > 0) {
      wx /= wl;
      wz /= wl;
    }
    const sprinting = inp.keys.has('ShiftLeft') && iz > 0 && p.stamina > 1 && !p.blocking && p.draw < 0;
    let speed = p.stats.baseSpeed * p.stats.speedMul;
    if (sprinting) speed *= 1.45;
    if (p.blocking) speed *= 0.55;
    if (p.draw >= 0) speed *= 0.6;
    if (p.rage > 0) speed *= 1.1;
    if (p.slow > 0) speed *= 0.6;
    if (iz < 0) speed *= 0.8;

    if (p.dash) {
      p.dash.t -= dt;
      p.move(p.dash.x * p.dash.speed, p.dash.z * p.dash.speed, dt);
      if (p.dash.hit !== undefined && !p.dash.hitDone) {
        // 돌진 타격
        for (const a of this.actors) {
          if (!a.alive || a === p || a.extracted) continue;
          if (Math.hypot(a.pos.x - p.pos.x, a.pos.z - p.pos.z) < a.radius + 1.2) {
            a.takeDamage(p.dash.hit, p, { knock: { x: p.dash.x * 12, z: p.dash.z * 12 }, stun: 0.9, from: p.pos });
            sfx.hit();
            this.shake = 0.25;
            p.dash.hitDone = true;
            p.dash.t = 0;
            break;
          }
        }
      }
      if (p.dash.t <= 0) p.dash = null;
    } else {
      p.move(wx * speed, wz * speed, dt);
    }
    p.lastVel = new THREE.Vector3(wx * speed, 0, wz * speed);
    const moving = wl > 0 && !p.dash;
    if (moving) {
      p.bob += dt * speed * 1.9;
      p.stepT -= dt * speed;
      if (p.stepT <= 0) {
        p.stepT = 2.6;
        sfx.step();
      }
    }

    // 점프
    if (inp.pressed.has('Space') && p.pos.y <= 0.001 && p.stamina > 10 && !stunned) {
      p.vy = 6.2;
      p.stamina -= 10;
      p.staminaDelay = 0.6;
    }
    p.vy -= 20 * dt;
    p.pos.y = Math.max(0, p.pos.y + p.vy * dt);
    if (p.pos.y === 0) p.vy = 0;

    // 스태미나
    if (sprinting && moving) {
      p.stamina -= 18 * dt;
      p.staminaDelay = 0.7;
    } else if (p.staminaDelay > 0) p.staminaDelay -= dt;
    else p.stamina = Math.min(100, p.stamina + (p.blocking ? 8 : 28) * dt);
    p.stamina = Math.max(0, p.stamina);

    // 전투 입력
    const canAct = !stunned && !this.uiOpen && inp.locked;
    const dm = p.stats.dmgMul * (p.rage > 0 ? 1.35 : 1);
    this.zoom = false;
    if (cls === 'fighter') {
      p.blocking = canAct && inp.mouse.r && p.stamina > 0 && !p.swing && !p.dash;
      if (canAct && inp.mouse.l && !p.swing && !p.blocking && p.cd.lmb <= 0 && p.stamina >= 6) {
        p.swing = { t: 0, dur: 0.42, hitAt: 0.17, done: false, side: (p.swingSide = -(p.swingSide || 1)) };
        p.stamina -= 9;
        p.staminaDelay = 0.6;
        p.cd.lmb = 0.48;
        sfx.swing();
      }
      if (canAct && inp.pressed.has('KeyQ') && p.cd.q <= 0 && p.stamina >= 15) {
        p.cd.q = CLASSES.fighter.skills.q.cd;
        p.stamina -= 15;
        p.dash = { x: f.x, z: f.z, speed: 22, t: 0.32, hit: 36 * dm };
        sfx.swing();
      }
      if (canAct && inp.pressed.has('KeyE') && p.cd.e <= 0) {
        p.cd.e = CLASSES.fighter.skills.e.cd;
        p.rage = 6;
        sfx.growl();
        this.ui.toast('분노!');
      }
      if (p.swing) {
        p.swing.t += dt;
        if (!p.swing.done && p.swing.t >= p.swing.hitAt) {
          p.swing.done = true;
          this.meleeHit(p, 26 * dm, 3.1, 1.5, { knock: 5 });
        }
        if (p.swing.t >= p.swing.dur) p.swing = null;
      }
    } else if (cls === 'ranger') {
      this.zoom = canAct && inp.mouse.r;
      if (canAct && inp.mouse.l && p.cd.lmb <= 0) {
        if (p.draw < 0) p.draw = 0;
        p.draw += dt;
      } else if (p.draw >= 0) {
        if (p.draw > 0.15 && !stunned) {
          const charge = Math.min(1, p.draw / 0.9);
          this.firePlayerProjectile('arrow', 32 + 36 * charge, (14 + 30 * charge) * dm, 0);
          p.cd.lmb = 0.25;
        }
        p.draw = -1;
      }
      if (canAct && inp.pressed.has('KeyQ') && p.cd.q <= 0) {
        p.cd.q = CLASSES.ranger.skills.q.cd;
        for (const s of [-0.12, 0, 0.12]) this.firePlayerProjectile('arrow', 52, 24 * dm, s);
      }
      if (canAct && inp.pressed.has('KeyE') && p.cd.e <= 0 && p.stamina >= 12) {
        p.cd.e = CLASSES.ranger.skills.e.cd;
        p.stamina -= 12;
        const dx = wl > 0 ? wx : -f.x;
        const dz = wl > 0 ? wz : -f.z;
        p.dash = { x: dx, z: dz, speed: 17, t: 0.3 };
        p.invuln = 0.3;
      }
    } else if (cls === 'mage') {
      if (canAct && inp.mouse.l && p.cd.lmb <= 0 && p.mana >= 10) {
        p.mana -= 10;
        p.cd.lmb = 0.42;
        this.firePlayerProjectile('bolt', 44, 21 * dm, 0);
        p.cast = 0.2;
      }
      if (canAct && inp.mouse.rPressed && p.cd.rmb <= 0 && p.mana >= 30) {
        p.mana -= 30;
        p.cd.rmb = CLASSES.mage.skills.rmb.cd;
        p.shield = 50;
        p.shieldT = 8;
        sfx.heal();
      }
      if (canAct && inp.pressed.has('KeyQ') && p.cd.q <= 0 && p.mana >= 30) {
        p.mana -= 30;
        p.cd.q = CLASSES.mage.skills.q.cd;
        this.firePlayerProjectile('fireball', 26, 48 * dm, 0);
        p.cast = 0.3;
      }
      if (canAct && inp.pressed.has('KeyE') && p.cd.e <= 0 && p.mana >= 35) {
        p.mana -= 35;
        p.cd.e = CLASSES.mage.skills.e.cd;
        p.applyHeal(50, 4);
        sfx.heal();
      }
      if (p.shieldT > 0) {
        p.shieldT -= dt;
        if (p.shieldT <= 0) p.shield = 0;
      }
      if (p.cast > 0) p.cast -= dt;
    }

    // 물약
    if (!stunned && (inp.pressed.has('Digit1') || inp.pressed.has('Digit2')) && p.cd.potion <= 0) {
      const base = inp.pressed.has('Digit1') ? 'health_potion' : 'bandage';
      const i = p.bag.findIndex((it) => it.base === base);
      if (i >= 0) {
        if (p.hp >= p.maxHp) this.ui.toast('체력이 가득 찼습니다');
        else {
          this.usePlayerConsumable(i);
        }
      } else this.ui.toast(`${ITEM_BASES[base].name}이(가) 없습니다`);
    }

    this.updateInteract(dt, inp);

    // 카메라
    const bob = p.pos.y === 0 && moving ? Math.sin(p.bob) * 0.05 : 0;
    this.camera.position.set(p.pos.x, p.pos.y + EYE + bob, p.pos.z);
    let shakeX = 0;
    let shakeY = 0;
    if (this.shake > 0) {
      this.shake -= dt;
      shakeX = (Math.random() - 0.5) * this.shake * 0.15;
      shakeY = (Math.random() - 0.5) * this.shake * 0.15;
    }
    this.camera.rotation.set(p.pitch + shakeX, p.yaw + shakeY, 0);
    const targetFov = this.zoom ? 45 : sprinting && moving ? 82 : 75;
    this.camera.fov += (targetFov - this.camera.fov) * Math.min(1, dt * 10);
    this.camera.updateProjectionMatrix();
    this.animateViewModel(dt, moving, bob);
  }

  usePlayerConsumable(i) {
    const p = this.player;
    const it = p.bag[i];
    const b = ITEM_BASES[it.base];
    p.bag.splice(i, 1);
    p.applyHeal(b.heal, it.base === 'health_potion' ? 3 : 2);
    p.cd.potion = 1.2;
    p.slow = 1.0;
    sfx.heal();
    this.ui.toast(`${b.name} 사용`);
    this.ui.refreshPanels();
  }

  firePlayerProjectile(kind, speed, dmg, yawOffset) {
    const cam = this.camera;
    const dir = new THREE.Vector3(0, 0, -1).applyEuler(new THREE.Euler(cam.rotation.x, cam.rotation.y + yawOffset, 0, 'YXZ'));
    const from = cam.position.clone().addScaledVector(dir, 0.5);
    from.y -= 0.12;
    this.spawnProjectile(this.player, kind, from, dir, speed, dmg);
  }

  // 상호작용 (상자, 전리품)
  findInteractable() {
    const p = this.player;
    const f = fwd(p.yaw);
    let best = null;
    let bs = -1e9;
    const consider = (o, type) => {
      const dx = o.pos.x - p.pos.x;
      const dz = o.pos.z - p.pos.z;
      const d = Math.hypot(dx, dz);
      if (d > 2.6) return;
      const dot = (dx * f.x + dz * f.z) / (d || 1);
      if (dot < 0.2 && d > 1.3) return;
      const s = dot * 2 - d;
      if (s > bs) {
        bs = s;
        best = { o, type };
      }
    };
    for (const c of this.chests) consider(c, 'chest');
    for (const b of this.lootBags) consider(b, 'bag');
    return best;
  }

  updateInteract(dt, inp) {
    const p = this.player;
    const it = this.findInteractable();
    this.interactTarget = it;
    // 컨테이너 창이 열려 있는데 멀어지면 닫음
    if (this.ui.container && this.ui.container.pos.distanceTo(p.pos) > 3.5) this.ui.closeContainer();
    if (!it) {
      p.interactT = 0;
      this.ui.prompt(null);
      return;
    }
    const o = it.o;
    if (it.type === 'chest' && !o.opened) {
      if (inp.keys.has('KeyF') && !this.uiOpen) {
        p.interactT += dt;
        this.ui.channel('상자 여는 중...', p.interactT / 1.2);
        if (p.interactT >= 1.2) {
          p.interactT = 0;
          this.openChest(o, p);
          this.ui.openContainer(o);
        }
      } else p.interactT = 0;
      this.ui.prompt(`[F] 길게 눌러 ${o.name} 열기`);
    } else {
      this.ui.prompt(`[F] ${o.name} 살펴보기 (${o.items.length})`);
      if (inp.pressed.has('KeyF') && this.ui.container !== o) this.ui.openContainer(o);
    }
  }

  animateViewModel(dt, moving, bob) {
    const vm = this.viewModel;
    const p = this.player;
    const { R, L, weapon } = vm.userData;
    vm.position.set(Math.sin(p.bob * 0.5) * (moving ? 0.015 : 0), bob * 0.4, 0);
    if (p.cls === 'fighter') {
      R.rotation.set(0, 0, 0);
      R.position.set(0.28, -0.3, -0.45);
      if (p.swing) {
        const k = p.swing.t / p.swing.dur;
        const s = p.swing.side;
        const a = k < 0.35 ? k / 0.35 : 1 - (k - 0.35) / 0.65;
        R.rotation.set(-0.6 * a, s * (1.4 - k * 2.8) * a, s * 0.6 * a);
        R.position.x = 0.28 - s * 0.1 * a;
      }
      L.position.set(p.blocking ? -0.12 : -0.28, p.blocking ? -0.15 : -0.32, p.blocking ? -0.4 : -0.45);
      L.rotation.y = p.blocking ? 0.5 : 0;
    } else if (p.cls === 'ranger') {
      const k = p.draw >= 0 ? Math.min(1, p.draw / 0.9) : 0;
      L.position.set(-0.15, -0.2, -0.55);
      R.position.set(0.12, -0.2, -0.35 + k * 0.15);
      const arrow = vm.userData.arrow;
      arrow.visible = p.cd.lmb <= 0.05;
      arrow.position.set(-0.02, -0.12, -0.55 + k * 0.18);
      weapon.rotation.z = 0.15 - k * 0.1;
    } else {
      R.position.set(0.28, -0.3 + (p.cast > 0 ? 0.08 : 0), -0.45 - (p.cast > 0 ? 0.1 : 0));
      L.position.set(-0.28, -0.32, -0.45);
      L.visible = true;
      if (weapon.userData.orb) {
        weapon.userData.orb.material.color.setHSL(0.6 + Math.sin(this.time * 3) * 0.05, 1, 0.6);
      }
    }
  }

  // ------------------------------------------------------------------ 조명
  updateLights(dt) {
    const cam = this.camera.position;
    const p = this.player;
    const tf = fwd(p.yaw);
    this.torchLight.position.set(cam.x - tf.x * 0.8, cam.y + 0.9, cam.z - tf.z * 0.8);
    this.torchLight.intensity = 8 + Math.sin(this.time * 13) * 0.4 + Math.sin(this.time * 7.3) * 0.5;
    const srcs = [];
    for (const t of this.transientLights) {
      t.t -= dt;
      srcs.push({ x: t.pos.x, y: t.pos.y + 0.5, z: t.pos.z, color: t.color, intensity: t.intensity * Math.max(0, t.t / 0.4), dist: 18, pri: 3 });
    }
    this.transientLights = this.transientLights.filter((t) => t.t > 0);
    for (const pr of this.projectiles) if (pr.light && pr.stuck <= 0) srcs.push({ x: pr.pos.x, y: pr.pos.y, z: pr.pos.z, color: pr.light, intensity: 6, dist: 10, pri: 2 });
    for (const po of this.portals) srcs.push({ x: po.pos.x, y: 2, z: po.pos.z, color: po.mesh.userData.color, intensity: 14, dist: 18, pri: 2 });
    for (let i = 0; i < this.dungeon.torches.length; i++) {
      const t = this.dungeon.torches[i];
      const fl = Math.sin(this.time * 11 + i * 3.7) * 0.5 + Math.sin(this.time * 5.3 + i) * 0.4;
      srcs.push({ x: t.x - t.nx * 0.4, y: t.y + 0.2, z: t.z - t.nz * 0.4, color: this.depth > 1 ? 0xff5a2a : 0xff9a44, intensity: 7 + fl, dist: 16, pri: 1 });
      const fm = this.dungeon.flames[i];
      fm.scale.set(1 + fl * 0.1, 1 + fl * 0.25, 1 + fl * 0.1);
    }
    for (const s of srcs) s.score = Math.hypot(s.x - cam.x, s.z - cam.z) - s.pri * 12;
    srcs.sort((a, b) => a.score - b.score);
    for (let i = 0; i < LIGHT_POOL; i++) {
      const l = this.lights[i];
      const s = srcs[i];
      if (s && Math.hypot(s.x - cam.x, s.z - cam.z) < 45) {
        l.position.set(s.x, s.y, s.z);
        l.color.setHex(s.color);
        l.intensity = s.intensity;
        l.distance = s.dist;
      } else l.intensity = 0;
    }
  }

  // ------------------------------------------------------------------ 메인 루프
  update(dt) {
    if (!this.running) return;
    dt = Math.min(dt, 0.05);
    this.time += dt;
    this.levelTime += dt;
    if (!this.result) this.timeLeft -= dt;
    const p = this.player;

    if (this.timeLeft <= 120 && !this.warned) {
      this.warned = true;
      sfx.bell();
      this.ui.announce('던전이 무너지고 있습니다!', '2분 안에 탈출하지 못하면 어둠에 삼켜집니다');
    }
    if (this.timeLeft <= 120) this.scene.fog.density = this.baseFog + (1 - this.timeLeft / 120) * 0.05;
    if (this.timeLeft <= 0 && p.alive && !this.result) {
      p.hp = 0;
      p.alive = false;
      this.endRaid(false, '무너지는 던전');
    }

    this.updatePlayer(dt);
    for (const a of this.actors) {
      if (a !== p) {
        const prev = a.lastPos || a.pos.clone();
        a.update(dt);
        a.lastVel = a.lastVel || new THREE.Vector3();
        a.lastVel.set((a.pos.x - prev.x) / dt, 0, (a.pos.z - prev.z) / dt);
        a.lastPos = a.lastPos || new THREE.Vector3();
        a.lastPos.copy(a.pos);
      }
    }
    this.separate();
    for (const a of this.actors) {
      if (a.mesh && !a.extracted) {
        a.animate(dt);
        a.updateHpBar(this.camera);
      }
    }
    this.updateProjectiles(dt);
    for (let i = this.effects.length - 1; i >= 0; i--) {
      const e = this.effects[i];
      e.t += dt;
      const k = Math.min(1, e.t / e.dur);
      e.update(e, k);
      if (k >= 1) {
        this.scene.remove(e.mesh);
        if (e.extra) this.scene.remove(e.extra);
        this.effects.splice(i, 1);
      }
    }
    for (const b of this.lootBags) b.mesh.rotation.y += dt;
    this.updatePortals(dt);
    this.updateLights(dt);
    this.updateExplored();
    // 죽은/탈출한 액터 정리
    this.actors = this.actors.filter((a) => a === p || a.alive || (!a.extracted && a.deathT < 10));

    if (this.result) {
      this.endTimer -= dt;
      if (this.endTimer <= 0) {
        this.running = false;
        this.ui.raidEnded(this.result);
      }
    }
  }

  separate() {
    const as = this.actors;
    for (let i = 0; i < as.length; i++) {
      const a = as[i];
      if (!a.alive || a.extracted) continue;
      for (let j = i + 1; j < as.length; j++) {
        const b = as[j];
        if (!b.alive || b.extracted) continue;
        const dx = b.pos.x - a.pos.x;
        const dz = b.pos.z - a.pos.z;
        const min = a.radius + b.radius;
        const d2 = dx * dx + dz * dz;
        if (d2 >= min * min || d2 < 1e-6) continue;
        const d = Math.sqrt(d2);
        const push = (min - d) / 2;
        const nx = dx / d;
        const nz = dz / d;
        a.pos.x -= nx * push;
        a.pos.z -= nz * push;
        b.pos.x += nx * push;
        b.pos.z += nz * push;
      }
    }
    for (const a of as) if (a.alive) this.dungeon.resolveCircle(a.pos, a.radius);
  }

  updateExplored() {
    const p = this.player;
    const dg = this.dungeon;
    const tx = dg.toTile(p.pos.x);
    const tz = dg.toTile(p.pos.z);
    const R = 4;
    for (let z = tz - R; z <= tz + R; z++)
      for (let x = tx - R; x <= tx + R; x++) {
        if (x < 0 || z < 0 || x >= dg.W || z >= dg.H) continue;
        if ((x - tx) ** 2 + (z - tz) ** 2 > R * R) continue;
        this.explored[dg.idx(x, z)] = 1;
      }
  }

  // 조준 중인 대상 (이름 표시용)
  aimedActor() {
    const cam = this.camera;
    const dir = _v2.set(0, 0, -1).applyQuaternion(cam.quaternion);
    let best = null;
    let bd = 30;
    for (const a of this.actors) {
      if (a === this.player || !a.alive || a.extracted) continue;
      const c = a.center(_v);
      const to = c.sub(cam.position);
      const d = to.length();
      if (d > bd) continue;
      const ang = to.normalize().dot(dir);
      if (ang < Math.cos(Math.atan2(a.radius + 0.3, d))) continue;
      if (!this.dungeon.los(cam.position.x, cam.position.z, a.pos.x, a.pos.z)) continue;
      best = a;
      bd = d;
    }
    return best;
  }

  render() {
    if (this.scene) this.renderer.render(this.scene, this.camera);
  }
}
