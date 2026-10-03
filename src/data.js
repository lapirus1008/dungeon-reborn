// 게임 데이터: 직업, 아이템, 몬스터, 희귀도, 루트 테이블

export const RARITIES = [
  { name: '일반', color: '#b9b9b9', mult: 1.0, value: 1 },
  { name: '고급', color: '#4fd16a', mult: 1.15, value: 2 },
  { name: '희귀', color: '#4a9dff', mult: 1.32, value: 4 },
  { name: '영웅', color: '#b65cff', mult: 1.52, value: 8 },
  { name: '전설', color: '#ff9b2f', mult: 1.8, value: 16 },
];

export const CLASSES = {
  fighter: {
    id: 'fighter',
    name: '전사',
    desc: '검과 방패로 전열을 지키는 근접 전투의 달인. 높은 체력과 방어(우클릭)로 버틴다.',
    hp: 140,
    speed: 5.0,
    weapon: 'sword',
    color: 0x8a6a3a,
    skills: {
      lmb: { name: '베기', desc: '전방 부채꼴 근접 공격' },
      rmb: { name: '방어', desc: '누르고 있는 동안 정면 피해 75% 감소' },
      q: { name: '돌진', desc: '전방으로 돌진하며 적을 강타', cd: 8 },
      e: { name: '분노', desc: '6초간 공격력 +35%, 이동속도 +10%', cd: 22 },
    },
  },
  ranger: {
    id: 'ranger',
    name: '레인저',
    desc: '활을 다루는 원거리 사냥꾼. 당길수록 강해지는 화살과 빠른 기동력.',
    hp: 100,
    speed: 5.5,
    weapon: 'bow',
    color: 0x3f6b3a,
    skills: {
      lmb: { name: '사격', desc: '누르고 있다가 놓아 화살 발사 (충전 시 강화)' },
      rmb: { name: '조준', desc: '시야 확대' },
      q: { name: '연발 사격', desc: '부채꼴로 화살 3발 발사', cd: 7 },
      e: { name: '구르기', desc: '이동 방향으로 빠르게 회피', cd: 5 },
    },
  },
  mage: {
    id: 'mage',
    name: '마법사',
    desc: '비전 마법과 화염을 다루는 술사. 마나를 소모해 강력한 주문을 쏟아낸다.',
    hp: 90,
    speed: 5.0,
    weapon: 'staff',
    color: 0x3a3f8a,
    mana: 100,
    skills: {
      lmb: { name: '마력탄', desc: '빠른 비전 투사체 (마나 10)' },
      rmb: { name: '비전 보호막', desc: '50의 피해를 흡수하는 보호막 (마나 30)', cd: 15 },
      q: { name: '화염구', desc: '폭발하는 화염구 (마나 30)', cd: 6 },
      e: { name: '치유의 빛', desc: '4초간 체력 50 회복 (마나 35)', cd: 18 },
    },
  },
};

// 아이템 베이스
export const ITEM_BASES = {
  // 무기
  rusty_sword: { name: '녹슨 장검', slot: 'weapon', cls: 'fighter', dmg: 1.0, value: 15, icon: '🗡️' },
  arming_sword: { name: '기사의 장검', slot: 'weapon', cls: 'fighter', dmg: 1.18, value: 40, icon: '🗡️' },
  war_axe: { name: '전투 도끼', slot: 'weapon', cls: 'fighter', dmg: 1.3, value: 60, icon: '🪓' },
  zweihander: { name: '츠바이핸더', slot: 'weapon', cls: 'fighter', dmg: 1.45, value: 95, icon: '⚔️' },
  short_bow: { name: '단궁', slot: 'weapon', cls: 'ranger', dmg: 1.0, value: 15, icon: '🏹' },
  hunting_bow: { name: '사냥꾼의 활', slot: 'weapon', cls: 'ranger', dmg: 1.18, value: 40, icon: '🏹' },
  long_bow: { name: '장궁', slot: 'weapon', cls: 'ranger', dmg: 1.32, value: 65, icon: '🏹' },
  elven_bow: { name: '엘프의 활', slot: 'weapon', cls: 'ranger', dmg: 1.45, value: 95, icon: '🏹' },
  oak_staff: { name: '참나무 지팡이', slot: 'weapon', cls: 'mage', dmg: 1.0, value: 15, icon: '🪄' },
  crystal_staff: { name: '수정 지팡이', slot: 'weapon', cls: 'mage', dmg: 1.18, value: 40, icon: '🪄' },
  spellbook: { name: '마도서', slot: 'weapon', cls: 'mage', dmg: 1.3, value: 65, icon: '📕' },
  archmage_staff: { name: '대마법사의 지팡이', slot: 'weapon', cls: 'mage', dmg: 1.45, value: 95, icon: '🔮' },
  // 머리
  leather_cap: { name: '가죽 모자', slot: 'head', armor: 8, value: 12, icon: '🧢' },
  iron_helm: { name: '철 투구', slot: 'head', armor: 16, value: 30, icon: '⛑️' },
  great_helm: { name: '그레이트 헬름', slot: 'head', armor: 24, speed: -0.03, value: 55, icon: '🪖' },
  wizard_hat: { name: '마법사 모자', slot: 'head', armor: 6, mana: 25, value: 40, icon: '🎩' },
  // 몸통
  padded_tunic: { name: '누빔 튜닉', slot: 'chest', armor: 12, value: 15, icon: '👕' },
  chain_mail: { name: '사슬 갑옷', slot: 'chest', armor: 28, speed: -0.04, value: 45, icon: '🥋' },
  plate_armor: { name: '판금 갑옷', slot: 'chest', armor: 45, speed: -0.08, value: 80, icon: '🛡️' },
  ranger_coat: { name: '레인저 외투', slot: 'chest', armor: 18, speed: 0.04, value: 50, icon: '🧥' },
  arcane_robe: { name: '비전 로브', slot: 'chest', armor: 10, mana: 40, value: 55, icon: '👘' },
  // 장신구
  copper_ring: { name: '구리 반지', slot: 'trinket', hp: 10, value: 20, icon: '💍' },
  ruby_ring: { name: '루비 반지', slot: 'trinket', hp: 25, value: 50, icon: '💍' },
  wolf_pendant: { name: '늑대 목걸이', slot: 'trinket', speed: 0.06, value: 50, icon: '📿' },
  skull_amulet: { name: '해골 부적', slot: 'trinket', dmgBonus: 0.08, value: 70, icon: '☠️' },
  // 소모품
  health_potion: { name: '체력 물약', slot: 'consumable', heal: 45, value: 15, icon: '🧪', stack: true },
  bandage: { name: '붕대', slot: 'consumable', heal: 20, value: 6, icon: '🩹', stack: true },
  // 보물
  gold_coins: { name: '금화 주머니', slot: 'treasure', value: 25, icon: '💰' },
  silver_goblet: { name: '은 술잔', slot: 'treasure', value: 35, icon: '🏆' },
  ruby: { name: '루비', slot: 'treasure', value: 60, icon: '🔴' },
  sapphire: { name: '사파이어', slot: 'treasure', value: 70, icon: '🔵' },
  golden_crown: { name: '황금 왕관', slot: 'treasure', value: 160, icon: '👑' },
  ancient_relic: { name: '고대 유물', slot: 'treasure', value: 220, icon: '🗿' },
  dragon_heart: { name: '용의 심장석', slot: 'treasure', value: 400, icon: '❤️‍🔥' },
};

export const STARTER_WEAPON = { fighter: 'rusty_sword', ranger: 'short_bow', mage: 'oak_staff' };

let uidCounter = Date.now() % 100000;
export function uid() {
  return 'i' + (uidCounter++).toString(36) + Math.floor(Math.random() * 1e4).toString(36);
}

export function makeItem(baseId, rarity = 0) {
  const b = ITEM_BASES[baseId];
  if (!b) throw new Error('unknown item ' + baseId);
  if (b.slot === 'consumable' || b.slot === 'treasure') rarity = b.slot === 'treasure' ? rarity : 0;
  const r = RARITIES[rarity];
  const item = { id: uid(), base: baseId, rarity };
  const stats = {};
  if (b.dmg) stats.dmg = +(b.dmg * (1 + (r.mult - 1) * 0.6)).toFixed(2);
  if (b.armor) stats.armor = Math.round(b.armor * r.mult);
  if (b.hp) stats.hp = Math.round(b.hp * r.mult);
  if (b.mana) stats.mana = Math.round(b.mana * r.mult);
  if (b.speed) stats.speed = +(b.speed > 0 ? b.speed * r.mult : b.speed).toFixed(3);
  if (b.dmgBonus) stats.dmgBonus = +(b.dmgBonus * r.mult).toFixed(3);
  // 희귀도 높은 장비는 추가 옵션
  if (rarity >= 2 && b.slot !== 'consumable' && b.slot !== 'treasure') {
    const extras = ['hp', 'dmgBonus', 'speed', 'armor'];
    const n = rarity - 1;
    for (let i = 0; i < n; i++) {
      const k = extras[Math.floor(Math.random() * extras.length)];
      if (k === 'hp') stats.hp = (stats.hp || 0) + 5 + rarity * 4;
      if (k === 'dmgBonus') stats.dmgBonus = +((stats.dmgBonus || 0) + 0.02 * rarity).toFixed(3);
      if (k === 'speed') stats.speed = +((stats.speed || 0) + 0.015 * rarity).toFixed(3);
      if (k === 'armor') stats.armor = (stats.armor || 0) + 3 * rarity;
    }
  }
  item.stats = stats;
  item.value = Math.round(b.value * (b.slot === 'treasure' ? 1 + rarity * 0.5 : r.value) * (0.9 + Math.random() * 0.2));
  return item;
}

export function itemName(item) {
  return ITEM_BASES[item.base].name;
}
export function itemBase(item) {
  return ITEM_BASES[item.base];
}

export const STAT_LABELS = {
  dmg: (v) => `무기 공격력 x${v.toFixed(2)}`,
  armor: (v) => `방어도 +${v}`,
  hp: (v) => `최대 체력 +${v}`,
  mana: (v) => `최대 마나 +${v}`,
  speed: (v) => `이동속도 ${v >= 0 ? '+' : ''}${Math.round(v * 100)}%`,
  dmgBonus: (v) => `피해량 +${Math.round(v * 100)}%`,
};

// 희귀도 굴림: luck 0 = 기본, 높을수록 좋은 아이템
export function rollRarity(luck = 0) {
  const r = Math.random() * 100 - luck * 9;
  if (r < 1.2) return 4;
  if (r < 6) return 3;
  if (r < 18) return 2;
  if (r < 42) return 1;
  return 0;
}

const GEAR_POOL = Object.keys(ITEM_BASES).filter((k) => ['weapon', 'head', 'chest', 'trinket'].includes(ITEM_BASES[k].slot));
const TREASURE_POOL = [
  ['gold_coins', 40],
  ['silver_goblet', 22],
  ['ruby', 12],
  ['sapphire', 10],
  ['golden_crown', 4],
  ['ancient_relic', 2.5],
  ['dragon_heart', 0.8],
];

function weighted(list, luck = 0) {
  const adjusted = list.map(([k, w], i) => [k, w * (1 + (luck * i) / 4)]);
  const total = adjusted.reduce((s, [, w]) => s + w, 0);
  let r = Math.random() * total;
  for (const [k, w] of adjusted) {
    if ((r -= w) <= 0) return k;
  }
  return adjusted[0][0];
}

export function rollLoot(count, luck = 0) {
  const items = [];
  for (let i = 0; i < count; i++) {
    const r = Math.random();
    if (r < 0.42) items.push(makeItem(GEAR_POOL[Math.floor(Math.random() * GEAR_POOL.length)], rollRarity(luck)));
    else if (r < 0.62) items.push(makeItem(Math.random() < 0.7 ? 'health_potion' : 'bandage'));
    else items.push(makeItem(weighted(TREASURE_POOL, luck), Math.random() < 0.15 + luck * 0.1 ? 1 : 0));
  }
  return items;
}

export const MONSTERS = {
  skeleton: { name: '스켈레톤 전사', hp: 80, dmg: 13, speed: 3.6, range: 2.3, cd: 1.3, sight: 16, ranged: false, scale: 1.0 },
  skeleton_archer: { name: '스켈레톤 궁수', hp: 60, dmg: 11, speed: 3.3, range: 15, cd: 2.0, sight: 20, ranged: 'arrow', scale: 1.0 },
  goblin: { name: '고블린', hp: 50, dmg: 9, speed: 5.2, range: 2.0, cd: 0.9, sight: 14, ranged: false, scale: 0.75 },
  ghoul: { name: '구울', hp: 140, dmg: 18, speed: 2.8, range: 2.4, cd: 1.6, sight: 12, ranged: false, scale: 1.1 },
  wraith_knight: { name: '망령 기사', hp: 950, dmg: 30, speed: 3.4, range: 3.2, cd: 1.7, sight: 18, ranged: false, scale: 1.55, boss: true },
};

export const BOT_NAMES = [
  '검은늑대', '은빛매', '그림자칼날', '철벽수호자', '붉은여우', '방랑자K', '던전킹', '초보탈출러', '도적왕', '불꽃술사',
  '서리마녀', '활쏘는곰', '무덤지기', 'Aldric', 'Mirelle', 'Kael', 'Thorne', 'Sylvara', 'Brom', 'Vex',
];
