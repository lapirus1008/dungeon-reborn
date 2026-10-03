// 던전 절차적 생성, 메시 구성, 충돌/시야/경로 탐색
import * as THREE from 'three';
import { stoneWallTexture, floorTexture } from './textures.js';

export const T = 4; // 타일 크기 (월드 단위)
export const WALL_H = 5.5;

const EMPTY = 0;
const ROOM = 1;
const CORR = 2;
const PILLAR = 3;

function rint(a, b) {
  return a + Math.floor(Math.random() * (b - a + 1));
}

export class Dungeon {
  constructor(depth = 1) {
    this.depth = depth;
    this.W = depth === 1 ? 46 : 50;
    this.H = this.W;
    this.grid = new Uint8Array(this.W * this.H);
    this.roomId = new Int16Array(this.W * this.H).fill(-1);
    this.rooms = [];
    this.torches = [];
    this.props = [];
    this.generate();
  }

  idx(x, z) {
    return z * this.W + x;
  }
  get(x, z) {
    if (x < 0 || z < 0 || x >= this.W || z >= this.H) return EMPTY;
    return this.grid[this.idx(x, z)];
  }
  tileSolid(x, z) {
    const g = this.get(x, z);
    return g === EMPTY || g === PILLAR;
  }
  toTile(v) {
    return Math.floor(v / T);
  }
  isSolid(x, z) {
    return this.tileSolid(this.toTile(x), this.toTile(z));
  }
  center(tx, tz) {
    return new THREE.Vector3((tx + 0.5) * T, 0, (tz + 0.5) * T);
  }
  roomAt(x, z) {
    const tx = this.toTile(x);
    const tz = this.toTile(z);
    if (tx < 0 || tz < 0 || tx >= this.W || tz >= this.H) return null;
    const id = this.roomId[this.idx(tx, tz)];
    return id >= 0 ? this.rooms[id] : null;
  }

  generate() {
    const W = this.W;
    const H = this.H;
    const target = this.depth === 1 ? 14 : 16;
    let attempts = 0;
    while (this.rooms.length < target && attempts < 600) {
      attempts++;
      const big = this.rooms.length === 0;
      const w = big ? rint(8, 10) : rint(4, 8);
      const h = big ? rint(8, 10) : rint(4, 8);
      const x = rint(2, W - w - 3);
      const z = rint(2, H - h - 3);
      let ok = true;
      for (const r of this.rooms) {
        if (x < r.x + r.w + 2 && x + w + 2 > r.x && z < r.z + r.h + 2 && z + h + 2 > r.z) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      const room = { id: this.rooms.length, x, z, w, h, cx: x + w / 2, cz: z + h / 2, boss: big, monsters: 0 };
      this.rooms.push(room);
      for (let i = x; i < x + w; i++)
        for (let j = z; j < z + h; j++) {
          this.grid[this.idx(i, j)] = ROOM;
          this.roomId[this.idx(i, j)] = room.id;
        }
    }

    // 프림 MST로 방 연결 + 추가 루프
    const n = this.rooms.length;
    const inTree = new Set([0]);
    const edges = [];
    while (inTree.size < n) {
      let best = null;
      for (const a of inTree) {
        for (let b = 0; b < n; b++) {
          if (inTree.has(b)) continue;
          const d = Math.hypot(this.rooms[a].cx - this.rooms[b].cx, this.rooms[a].cz - this.rooms[b].cz);
          if (!best || d < best.d) best = { a, b, d };
        }
      }
      inTree.add(best.b);
      edges.push([best.a, best.b]);
    }
    for (let k = 0; k < Math.floor(n / 3); k++) {
      const a = rint(0, n - 1);
      let b = -1;
      let bd = 1e9;
      for (let j = 0; j < n; j++) {
        if (j === a) continue;
        const d = Math.hypot(this.rooms[a].cx - this.rooms[j].cx, this.rooms[a].cz - this.rooms[j].cz);
        if (d < bd && !edges.some(([p, q]) => (p === a && q === j) || (p === j && q === a))) {
          bd = d;
          b = j;
        }
      }
      if (b >= 0) edges.push([a, b]);
    }
    for (const [a, b] of edges) this.carveCorridor(this.rooms[a], this.rooms[b]);

    // 큰 방에 기둥 배치
    for (const r of this.rooms) {
      if (r.w >= 7 && r.h >= 7) {
        const spots = [
          [r.x + 2, r.z + 2],
          [r.x + r.w - 3, r.z + 2],
          [r.x + 2, r.z + r.h - 3],
          [r.x + r.w - 3, r.z + r.h - 3],
        ];
        for (const [px, pz] of spots) {
          this.grid[this.idx(px, pz)] = PILLAR;
          this.props.push({ type: 'pillar', x: (px + 0.5) * T, z: (pz + 0.5) * T });
        }
      }
    }

    // 횃불: 방 둘레 벽면
    for (const r of this.rooms) {
      const count = r.boss ? 6 : rint(2, 3);
      let placed = 0;
      let tries = 0;
      while (placed < count && tries++ < 40) {
        const side = rint(0, 3);
        let tx;
        let tz;
        let nx = 0;
        let nz = 0;
        if (side === 0) {
          tx = rint(r.x, r.x + r.w - 1);
          tz = r.z;
          nz = -1;
        } else if (side === 1) {
          tx = rint(r.x, r.x + r.w - 1);
          tz = r.z + r.h - 1;
          nz = 1;
        } else if (side === 2) {
          tx = r.x;
          tz = rint(r.z, r.z + r.h - 1);
          nx = -1;
        } else {
          tx = r.x + r.w - 1;
          tz = rint(r.z, r.z + r.h - 1);
          nx = 1;
        }
        if (this.get(tx + nx, tz + nz) !== EMPTY) continue;
        if (this.torches.some((t) => t.tx === tx && t.tz === tz)) continue;
        const c = this.center(tx, tz);
        this.torches.push({ tx, tz, x: c.x + nx * (T / 2 - 0.25), y: 3.2, z: c.z + nz * (T / 2 - 0.25), nx, nz });
        placed++;
      }
    }

    // 소품: 통, 뼈 더미
    for (const r of this.rooms) {
      const k = rint(1, 3);
      for (let i = 0; i < k; i++) {
        const tx = rint(r.x, r.x + r.w - 1);
        const tz = Math.random() < 0.5 ? r.z : r.z + r.h - 1;
        if (this.get(tx, tz) !== ROOM) continue;
        const c = this.center(tx, tz);
        this.props.push({ type: Math.random() < 0.6 ? 'barrel' : 'bones', x: c.x + (Math.random() - 0.5) * 2, z: c.z + (tz === r.z ? -1.2 : 1.2) });
      }
    }
  }

  carveCorridor(a, b) {
    let x = Math.floor(a.cx);
    let z = Math.floor(a.cz);
    const x2 = Math.floor(b.cx);
    const z2 = Math.floor(b.cz);
    const horizFirst = Math.random() < 0.5;
    const carve = (i, j) => {
      if (this.get(i, j) === EMPTY) this.grid[this.idx(i, j)] = CORR;
    };
    if (horizFirst) {
      while (x !== x2) {
        carve(x, z);
        x += Math.sign(x2 - x);
      }
      while (z !== z2) {
        carve(x, z);
        z += Math.sign(z2 - z);
      }
    } else {
      while (z !== z2) {
        carve(x, z);
        z += Math.sign(z2 - z);
      }
      while (x !== x2) {
        carve(x, z);
        x += Math.sign(x2 - x);
      }
    }
    carve(x, z);
  }

  // 월드 메시 생성
  buildMeshes(scene) {
    const group = new THREE.Group();
    const deep = this.depth > 1;
    const wallTex = stoneWallTexture(deep ? [95, 60, 55] : [92, 86, 80]);
    const floorTex = floorTexture(deep ? [70, 48, 44] : [70, 66, 60]);
    const wallMat = new THREE.MeshLambertMaterial({ map: wallTex });
    const floorMat = new THREE.MeshLambertMaterial({ map: floorTex });
    const ceilMat = new THREE.MeshLambertMaterial({ map: wallTex, color: 0x555555 });

    const floors = [];
    const walls = [];
    for (let z = 0; z < this.H; z++)
      for (let x = 0; x < this.W; x++) {
        const g = this.get(x, z);
        if (g === ROOM || g === CORR || g === PILLAR) floors.push([x, z]);
        else if (g === EMPTY) {
          let adj = false;
          for (let dz = -1; dz <= 1 && !adj; dz++)
            for (let dx = -1; dx <= 1; dx++) {
              const n = this.get(x + dx, z + dz);
              if (n !== EMPTY) {
                adj = true;
                break;
              }
            }
          if (adj) walls.push([x, z]);
        }
      }

    const m = new THREE.Matrix4();
    const planeGeo = new THREE.PlaneGeometry(T, T);
    planeGeo.rotateX(-Math.PI / 2);
    const floorMesh = new THREE.InstancedMesh(planeGeo, floorMat, floors.length);
    const ceilGeo = planeGeo.clone();
    ceilGeo.rotateX(Math.PI);
    const ceilMesh = new THREE.InstancedMesh(ceilGeo, ceilMat, floors.length);
    floors.forEach(([x, z], i) => {
      m.makeTranslation((x + 0.5) * T, 0, (z + 0.5) * T);
      floorMesh.setMatrixAt(i, m);
      m.makeTranslation((x + 0.5) * T, WALL_H, (z + 0.5) * T);
      ceilMesh.setMatrixAt(i, m);
    });
    group.add(floorMesh, ceilMesh);

    const wallGeo = new THREE.BoxGeometry(T, WALL_H, T);
    const wallMesh = new THREE.InstancedMesh(wallGeo, wallMat, walls.length);
    walls.forEach(([x, z], i) => {
      m.makeTranslation((x + 0.5) * T, WALL_H / 2, (z + 0.5) * T);
      wallMesh.setMatrixAt(i, m);
    });
    group.add(wallMesh);

    // 기둥
    const pillars = this.props.filter((p) => p.type === 'pillar');
    if (pillars.length) {
      const pg = new THREE.CylinderGeometry(1.1, 1.3, WALL_H, 10);
      const pm = new THREE.InstancedMesh(pg, wallMat, pillars.length);
      pillars.forEach((p, i) => {
        m.makeTranslation(p.x, WALL_H / 2, p.z);
        pm.setMatrixAt(i, m);
      });
      group.add(pm);
    }

    // 횃불
    const sconceGeo = new THREE.BoxGeometry(0.15, 0.7, 0.15);
    const sconceMat = new THREE.MeshLambertMaterial({ color: 0x3a2a1a });
    const flameGeo = new THREE.ConeGeometry(0.16, 0.45, 6);
    const flameMat = new THREE.MeshBasicMaterial({ color: deep ? 0xff5a2a : 0xffaa44 });
    this.flames = [];
    for (const t of this.torches) {
      const s = new THREE.Mesh(sconceGeo, sconceMat);
      s.position.set(t.x, t.y - 0.4, t.z);
      s.rotation.x = t.nz * 0.4;
      s.rotation.z = -t.nx * 0.4;
      const f = new THREE.Mesh(flameGeo, flameMat);
      f.position.set(t.x - t.nx * 0.12, t.y + 0.1, t.z - t.nz * 0.12);
      group.add(s, f);
      this.flames.push(f);
    }

    // 통, 뼈
    const barrelGeo = new THREE.CylinderGeometry(0.55, 0.5, 1.2, 10);
    const barrelMat = new THREE.MeshLambertMaterial({ color: 0x5b3b20 });
    const boneMat = new THREE.MeshLambertMaterial({ color: 0xcfc6ad });
    for (const p of this.props) {
      if (p.type === 'barrel') {
        const b = new THREE.Mesh(barrelGeo, barrelMat);
        b.position.set(p.x, 0.6, p.z);
        group.add(b);
      } else if (p.type === 'bones') {
        for (let i = 0; i < 5; i++) {
          const b = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.6), boneMat);
          b.rotation.set(Math.PI / 2, 0, Math.random() * Math.PI);
          b.position.set(p.x + (Math.random() - 0.5), 0.05, p.z + (Math.random() - 0.5));
          group.add(b);
        }
        const skull = new THREE.Mesh(new THREE.SphereGeometry(0.2, 8, 6), boneMat);
        skull.position.set(p.x, 0.18, p.z);
        group.add(skull);
      }
    }

    scene.add(group);
    this.group = group;
    return group;
  }

  dispose(scene) {
    if (!this.group) return;
    scene.remove(this.group);
    this.group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) {
        if (o.material.map) o.material.map.dispose();
        o.material.dispose();
      }
    });
  }

  // 원형 충돌체를 벽 밖으로 밀어냄
  resolveCircle(pos, r) {
    const tx = this.toTile(pos.x);
    const tz = this.toTile(pos.z);
    for (let dz = -1; dz <= 1; dz++)
      for (let dx = -1; dx <= 1; dx++) {
        const x = tx + dx;
        const z = tz + dz;
        const g = this.get(x, z);
        if (g === PILLAR) {
          const cx = (x + 0.5) * T;
          const cz = (z + 0.5) * T;
          const ddx = pos.x - cx;
          const ddz = pos.z - cz;
          const d = Math.hypot(ddx, ddz);
          const min = 1.3 + r;
          if (d < min && d > 1e-4) {
            pos.x = cx + (ddx / d) * min;
            pos.z = cz + (ddz / d) * min;
          }
          continue;
        }
        if (g !== EMPTY) continue;
        const minX = x * T;
        const minZ = z * T;
        const px = Math.max(minX, Math.min(pos.x, minX + T));
        const pz = Math.max(minZ, Math.min(pos.z, minZ + T));
        const ddx = pos.x - px;
        const ddz = pos.z - pz;
        const d2 = ddx * ddx + ddz * ddz;
        if (d2 < r * r) {
          const d = Math.sqrt(d2);
          if (d > 1e-4) {
            pos.x = px + (ddx / d) * r;
            pos.z = pz + (ddz / d) * r;
          } else {
            // 내부에 박힌 경우: 가장 가까운 면으로
            const cx = minX + T / 2;
            const cz = minZ + T / 2;
            if (Math.abs(pos.x - cx) > Math.abs(pos.z - cz)) pos.x = pos.x > cx ? minX + T + r : minX - r;
            else pos.z = pos.z > cz ? minZ + T + r : minZ - r;
          }
        }
      }
  }

  // 시야 확인
  los(ax, az, bx, bz) {
    const dx = bx - ax;
    const dz = bz - az;
    const d = Math.hypot(dx, dz);
    const steps = Math.ceil(d / 0.5);
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      const x = ax + dx * t;
      const z = az + dz * t;
      const tx = this.toTile(x);
      const tz = this.toTile(z);
      const g = this.get(tx, tz);
      if (g === EMPTY) return false;
      if (g === PILLAR) {
        const cx = (tx + 0.5) * T;
        const cz = (tz + 0.5) * T;
        if (Math.hypot(x - cx, z - cz) < 1.2) return false;
      }
    }
    return true;
  }

  // BFS 경로 탐색 -> 월드 좌표 웨이포인트
  path(ax, az, bx, bz) {
    const sx = this.toTile(ax);
    const sz = this.toTile(az);
    const ex = this.toTile(bx);
    const ez = this.toTile(bz);
    if (this.tileSolid(ex, ez) || this.tileSolid(sx, sz)) return null;
    const W = this.W;
    const prev = new Int32Array(W * this.H).fill(-2);
    const q = new Int32Array(W * this.H);
    let qh = 0;
    let qt = 0;
    const s = this.idx(sx, sz);
    const e = this.idx(ex, ez);
    prev[s] = -1;
    q[qt++] = s;
    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    while (qh < qt) {
      const c = q[qh++];
      if (c === e) break;
      const cx = c % W;
      const cz = (c / W) | 0;
      for (const [dx, dz] of dirs) {
        const nx = cx + dx;
        const nz = cz + dz;
        if (this.tileSolid(nx, nz)) continue;
        const ni = this.idx(nx, nz);
        if (prev[ni] !== -2) continue;
        prev[ni] = c;
        q[qt++] = ni;
      }
    }
    if (prev[e] === -2) return null;
    const tiles = [];
    for (let c = e; c !== -1; c = prev[c]) tiles.push(c);
    tiles.reverse();
    // 시야 기반 경로 단순화
    const pts = tiles.map((c) => this.center(c % W, (c / W) | 0));
    pts[pts.length - 1] = new THREE.Vector3(bx, 0, bz);
    const out = [];
    let anchor = new THREE.Vector3(ax, 0, az);
    let i = 0;
    while (i < pts.length) {
      let j = pts.length - 1;
      while (j > i && !this.wideLos(anchor, pts[j])) j--;
      out.push(pts[j]);
      anchor = pts[j];
      i = j + 1;
    }
    return out;
  }

  // 몸통 폭을 고려한 시야 (경로 단순화용)
  wideLos(a, b) {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const d = Math.hypot(dx, dz) || 1;
    const px = (-dz / d) * 0.7;
    const pz = (dx / d) * 0.7;
    return this.los(a.x + px, a.z + pz, b.x + px, b.z + pz) && this.los(a.x - px, a.z - pz, b.x - px, b.z - pz);
  }

  randomPointInRoom(room, margin = 1) {
    for (let k = 0; k < 30; k++) {
      const tx = rint(room.x + margin, room.x + room.w - 1 - margin);
      const tz = rint(room.z + margin, room.z + room.h - 1 - margin);
      if (this.get(tx, tz) === ROOM) {
        const c = this.center(tx, tz);
        c.x += (Math.random() - 0.5) * 2;
        c.z += (Math.random() - 0.5) * 2;
        return c;
      }
    }
    return this.center(Math.floor(room.cx), Math.floor(room.cz));
  }
}
