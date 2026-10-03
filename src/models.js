// 기본 도형으로 만든 캐릭터/오브젝트 모델
import * as THREE from 'three';
import { woodTexture } from './textures.js';

const matCache = new Map();
function mat(color, opts = {}) {
  const key = color + JSON.stringify(opts);
  if (!matCache.has(key)) matCache.set(key, new THREE.MeshLambertMaterial({ color, ...opts }));
  return matCache.get(key);
}

function box(w, h, d, color, opts) {
  return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color, opts));
}

export function makeWeaponMesh(type) {
  const g = new THREE.Group();
  if (type === 'sword' || type === 'boss_sword') {
    const big = type === 'boss_sword';
    const blade = box(0.08, big ? 1.6 : 1.0, 0.03, 0xc8ccd4);
    blade.position.y = big ? 0.95 : 0.65;
    const guard = box(0.32, 0.06, 0.08, 0x8a6a2a);
    guard.position.y = 0.14;
    const grip = box(0.05, 0.25, 0.05, 0x3a2414);
    g.add(blade, guard, grip);
  } else if (type === 'bow') {
    const curve = new THREE.TorusGeometry(0.6, 0.03, 4, 12, Math.PI * 0.9);
    const limb = new THREE.Mesh(curve, mat(0x6b4423));
    limb.rotation.z = Math.PI / 2 + Math.PI * 0.05;
    const str = box(0.01, 1.15, 0.01, 0xdddddd);
    str.position.x = -0.03;
    limb.position.x = -0.55;
    g.add(limb, str);
    g.userData.string = str;
  } else if (type === 'staff') {
    const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.045, 1.6, 6), mat(0x5b3a1d));
    shaft.position.y = 0.5;
    const orb = new THREE.Mesh(new THREE.IcosahedronGeometry(0.11, 0), new THREE.MeshBasicMaterial({ color: 0x66aaff }));
    orb.position.y = 1.35;
    g.add(shaft, orb);
    g.userData.orb = orb;
  } else if (type === 'club') {
    const c = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.04, 0.8, 6), mat(0x4a3018));
    c.position.y = 0.4;
    g.add(c);
  } else if (type === 'claws') {
    // 맨손
  }
  return g;
}

// 인간형 모델: parts 참조 반환
export function makeHumanoid(o = {}) {
  const {
    skin = 0xd8a982,
    body = 0x555555,
    legs = 0x3a3a3a,
    head = null,
    helmet = null,
    weapon = 'sword',
    shield = false,
    scale = 1,
    eyes = null,
    skeletal = false,
    hunch = 0,
    headScale = 1,
  } = o;
  const root = new THREE.Group();
  const rig = new THREE.Group();
  rig.scale.setScalar(scale);
  root.add(rig);

  const torsoW = skeletal ? 0.38 : 0.55;
  const torso = box(torsoW, 0.7, 0.3, body);
  torso.position.y = 1.25;
  torso.rotation.x = hunch;
  rig.add(torso);
  if (skeletal) {
    for (let i = 0; i < 4; i++) {
      const rib = box(0.5, 0.04, 0.32, 0xd8d0b8);
      rib.position.set(0, 1.05 + i * 0.13, 0);
      rig.add(rib);
    }
  }

  const headG = new THREE.Group();
  headG.position.y = 1.78;
  const hd = box(0.32 * headScale, 0.34 * headScale, 0.32 * headScale, head ?? skin);
  headG.add(hd);
  if (helmet) {
    const h = box(0.36 * headScale, 0.2 * headScale, 0.36 * headScale, helmet);
    h.position.y = 0.1 * headScale;
    headG.add(h);
  }
  if (eyes) {
    const em = new THREE.MeshBasicMaterial({ color: eyes });
    for (const s of [-1, 1]) {
      const e = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.04, 0.02), em);
      e.position.set(s * 0.08 * headScale, 0.02, -0.165 * headScale);
      headG.add(e);
    }
  }
  rig.add(headG);

  const limb = (w, h, color) => {
    const g = new THREE.Group();
    const m = box(w, h, w, color);
    m.position.y = -h / 2;
    g.add(m);
    return g;
  };
  const armColor = skeletal ? 0xd8d0b8 : body;
  const armL = limb(skeletal ? 0.09 : 0.15, 0.7, armColor);
  const armR = limb(skeletal ? 0.09 : 0.15, 0.7, armColor);
  armL.position.set(-(torsoW / 2 + 0.09), 1.55, 0);
  armR.position.set(torsoW / 2 + 0.09, 1.55, 0);
  rig.add(armL, armR);
  const legL = limb(skeletal ? 0.1 : 0.18, 0.85, skeletal ? 0xd8d0b8 : legs);
  const legR = limb(skeletal ? 0.1 : 0.18, 0.85, skeletal ? 0xd8d0b8 : legs);
  legL.position.set(-0.13, 0.88, 0);
  legR.position.set(0.13, 0.88, 0);
  rig.add(legL, legR);

  const wpn = makeWeaponMesh(weapon);
  if (weapon === 'bow') {
    wpn.rotation.set(0, Math.PI / 2, 0);
    wpn.position.set(0, -0.65, -0.05);
    armL.add(wpn);
  } else {
    wpn.position.set(0, -0.68, 0);
    wpn.rotation.x = -Math.PI / 2;
    armR.add(wpn);
  }
  if (shield) {
    const sh = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.32, 0.06, 10), mat(0x6b4a24));
    sh.rotation.z = Math.PI / 2;
    sh.position.set(-0.08, -0.5, 0);
    armL.add(sh);
  }

  root.userData.parts = { rig, torso, headG, armL, armR, legL, legR, wpn };
  return root;
}

export function makeChest(tier = 0) {
  const g = new THREE.Group();
  const wt = woodTexture();
  const color = tier === 2 ? 0xffd27a : tier === 1 ? 0xc9a070 : 0xffffff;
  const bodyM = new THREE.MeshLambertMaterial({ map: wt, color });
  const base = new THREE.Mesh(new THREE.BoxGeometry(1.3, 0.7, 0.85), bodyM);
  base.position.y = 0.35;
  const lidG = new THREE.Group();
  lidG.position.set(0, 0.7, 0.42);
  const lid = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 1.3, 10, 1, false, 0, Math.PI), bodyM);
  lid.rotation.z = Math.PI / 2;
  lid.rotation.y = Math.PI / 2;
  lid.position.z = -0.42;
  lidG.add(lid);
  const metal = mat(tier === 2 ? 0xffcc33 : 0x777777);
  const band1 = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.72, 0.88), metal);
  band1.position.set(-0.45, 0.35, 0);
  const band2 = band1.clone();
  band2.position.x = 0.45;
  const lock = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.2, 0.06), metal);
  lock.position.set(0, 0.62, -0.45);
  g.add(base, lidG, band1, band2, lock);
  g.userData.lid = lidG;
  return g;
}

export function makeLootBag(color = 0x6b5030) {
  const g = new THREE.Group();
  const b = new THREE.Mesh(new THREE.SphereGeometry(0.4, 8, 6), mat(color));
  b.scale.set(1, 0.8, 1);
  b.position.y = 0.3;
  const knot = new THREE.Mesh(new THREE.ConeGeometry(0.15, 0.3, 6), mat(color));
  knot.position.y = 0.72;
  const glow = new THREE.Mesh(new THREE.RingGeometry(0.5, 0.65, 16), new THREE.MeshBasicMaterial({ color: 0xffd060, transparent: true, opacity: 0.5, side: THREE.DoubleSide }));
  glow.rotation.x = -Math.PI / 2;
  glow.position.y = 0.03;
  g.add(b, knot, glow);
  return g;
}

export function makePortal(kind = 'exit') {
  const color = kind === 'exit' ? 0x4ab8ff : 0xff3a2a;
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.TorusGeometry(1.5, 0.15, 8, 32), new THREE.MeshBasicMaterial({ color }));
  ring.position.y = 1.8;
  const disc = new THREE.Mesh(
    new THREE.CircleGeometry(1.4, 32),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.45, side: THREE.DoubleSide, depthWrite: false }),
  );
  disc.position.y = 1.8;
  const floor = new THREE.Mesh(
    new THREE.RingGeometry(0.2, 2.2, 32),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false }),
  );
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = 0.04;
  g.add(ring, disc, floor);
  // 떠다니는 입자
  const pts = new THREE.BufferGeometry();
  const N = 60;
  const arr = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) {
    const a = Math.random() * Math.PI * 2;
    const r = Math.random() * 2;
    arr[i * 3] = Math.cos(a) * r;
    arr[i * 3 + 1] = Math.random() * 3.5;
    arr[i * 3 + 2] = Math.sin(a) * r;
  }
  pts.setAttribute('position', new THREE.BufferAttribute(arr, 3));
  const particles = new THREE.Points(pts, new THREE.PointsMaterial({ color, size: 0.08 }));
  g.add(particles);
  g.userData = { ring, disc, particles, color };
  return g;
}

export function makeArrow() {
  const g = new THREE.Group();
  const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.8, 4), mat(0x8a6a3a));
  shaft.rotation.x = Math.PI / 2;
  const tip = new THREE.Mesh(new THREE.ConeGeometry(0.04, 0.12, 4), mat(0x999999));
  tip.rotation.x = -Math.PI / 2;
  tip.position.z = -0.45;
  g.add(shaft, tip);
  return g;
}

export function makeOrb(color, size = 0.18) {
  const g = new THREE.Group();
  const core = new THREE.Mesh(new THREE.SphereGeometry(size, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }));
  const halo = new THREE.Mesh(new THREE.SphereGeometry(size * 1.8, 8, 6), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.45, depthWrite: false }));
  g.add(core, halo);
  return g;
}

// 1인칭 뷰모델
export function makeViewModel(cls) {
  const g = new THREE.Group();
  const armMat = mat(cls === 'mage' ? 0x2f3470 : cls === 'ranger' ? 0x34552f : 0x5a5f68);
  const handMat = mat(0x9a7458);
  const arm = (side) => {
    const a = new THREE.Group();
    const sleeve = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.12, 0.6), armMat);
    sleeve.position.z = 0.15;
    const hand = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.1, 0.12), handMat);
    hand.position.z = -0.18;
    a.add(sleeve, hand);
    a.position.set(side * 0.28, -0.3, -0.45);
    return a;
  };
  const R = arm(1);
  const L = arm(-1);
  g.add(R, L);
  let weapon;
  if (cls === 'fighter') {
    weapon = makeWeaponMesh('sword');
    weapon.position.set(0, 0, -0.2);
    weapon.rotation.set(-0.5, 0, -0.25);
    weapon.scale.setScalar(0.7);
    R.add(weapon);
    const sh = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.04, 12), mat(0x4a3218));
    sh.rotation.x = Math.PI / 2;
    sh.position.set(-0.06, -0.02, -0.3);
    const boss = new THREE.Mesh(new THREE.SphereGeometry(0.045, 6, 4), mat(0x777777));
    boss.position.set(-0.06, -0.02, -0.33);
    L.add(sh, boss);
    L.userData.shield = sh;
  } else if (cls === 'ranger') {
    weapon = makeWeaponMesh('bow');
    weapon.rotation.set(0, Math.PI / 2, 0.15);
    weapon.position.set(0, 0.05, -0.2);
    weapon.scale.setScalar(0.6);
    L.add(weapon);
    const ar = makeArrow();
    ar.position.set(0.24, 0.05, -0.35);
    ar.scale.setScalar(0.9);
    g.add(ar);
    g.userData.arrow = ar;
  } else {
    weapon = makeWeaponMesh('staff');
    weapon.position.set(0, -0.2, -0.2);
    weapon.rotation.set(-0.25, 0, -0.1);
    weapon.scale.setScalar(0.6);
    R.add(weapon);
  }
  g.userData.R = R;
  g.userData.L = L;
  g.userData.weapon = weapon;
  return g;
}

export function makeHealthBar() {
  const g = new THREE.Group();
  const bg = new THREE.Mesh(new THREE.PlaneGeometry(1, 0.1), new THREE.MeshBasicMaterial({ color: 0x220000, depthTest: false, transparent: true }));
  const fg = new THREE.Mesh(new THREE.PlaneGeometry(1, 0.1), new THREE.MeshBasicMaterial({ color: 0xcc2222, depthTest: false, transparent: true }));
  fg.position.z = 0.001;
  bg.renderOrder = 999;
  fg.renderOrder = 1000;
  g.add(bg, fg);
  g.userData.fg = fg;
  g.visible = false;
  return g;
}
