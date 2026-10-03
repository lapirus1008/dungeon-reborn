// 로컬 저장소 (보관함, 골드, 장비, 통계)
import { makeItem } from './data.js';

const KEY = 'dungeon_reborn_save_v1';

function fresh() {
  return {
    cls: 'fighter',
    gold: 150,
    equipment: { weapon: makeItem('rusty_sword'), head: null, chest: makeItem('padded_tunic'), trinket: null },
    bag: [makeItem('health_potion'), makeItem('health_potion')],
    stash: [makeItem('short_bow'), makeItem('oak_staff'), makeItem('leather_cap'), makeItem('bandage'), makeItem('bandage')],
    stats: { raids: 0, extracts: 0, deaths: 0, kills: 0, pvpKills: 0, bestHaul: 0 },
  };
}

export function loadSave() {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const s = JSON.parse(raw);
      const f = fresh();
      return { ...f, ...s, equipment: { ...f.equipment, ...s.equipment }, stats: { ...f.stats, ...s.stats } };
    }
  } catch (e) {
    /* 저장소 사용 불가 */
  }
  return fresh();
}

export function writeSave(save) {
  try {
    localStorage.setItem(KEY, JSON.stringify(save));
  } catch (e) {
    /* 무시 */
  }
}

export function resetSave() {
  const s = fresh();
  writeSave(s);
  return s;
}

export const STASH_SIZE = 60;
export const BAG_SIZE = 16;
