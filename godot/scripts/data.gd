# 게임 데이터: 직업, 아이템, 몬스터, 희귀도, 루트 테이블 (autoload: Data)
extends Node

const RARITIES := [
	{"name": "일반", "color": Color("#b9b9b9"), "mult": 1.0, "value": 1.0},
	{"name": "고급", "color": Color("#4fd16a"), "mult": 1.15, "value": 2.0},
	{"name": "희귀", "color": Color("#4a9dff"), "mult": 1.32, "value": 4.0},
	{"name": "영웅", "color": Color("#b65cff"), "mult": 1.52, "value": 8.0},
	{"name": "전설", "color": Color("#ff9b2f"), "mult": 1.8, "value": 16.0},
]

const CLASSES := {
	"fighter": {
		"id": "fighter", "name": "전사", "icon": "🛡",
		"desc": "검과 방패로 전열을 지키는 근접 전투의 달인. 높은 체력과 방어(우클릭)로 버틴다.",
		"hp": 140, "speed": 5.0, "mana": 0,
		"skills": {
			"lmb": {"name": "베기", "desc": "전방 부채꼴 근접 공격 (연속 콤보)", "cd": 0.0},
			"rmb": {"name": "방어", "desc": "누르고 있는 동안 정면 피해 75% 감소", "cd": 0.0},
			"q": {"name": "돌진", "desc": "전방으로 돌진하며 적을 강타하고 기절", "cd": 8.0},
			"e": {"name": "분노", "desc": "6초간 공격력 +35%, 이동속도 +10%", "cd": 22.0},
		},
	},
	"ranger": {
		"id": "ranger", "name": "레인저", "icon": "🏹",
		"desc": "활을 다루는 원거리 사냥꾼. 당길수록 강해지는 화살과 빠른 기동력.",
		"hp": 100, "speed": 5.5, "mana": 0,
		"skills": {
			"lmb": {"name": "사격", "desc": "누르고 있다가 놓아 발사 (충전 시 강화, 헤드샷 1.5배)", "cd": 0.0},
			"rmb": {"name": "조준", "desc": "시야 확대", "cd": 0.0},
			"q": {"name": "연발 사격", "desc": "부채꼴로 화살 3발 발사", "cd": 7.0},
			"e": {"name": "구르기", "desc": "이동 방향으로 빠르게 회피 (무적)", "cd": 5.0},
		},
	},
	"mage": {
		"id": "mage", "name": "마법사", "icon": "🔮",
		"desc": "비전 마법과 화염을 다루는 술사. 마나를 소모해 강력한 주문을 쏟아낸다.",
		"hp": 90, "speed": 5.0, "mana": 100,
		"skills": {
			"lmb": {"name": "마력탄", "desc": "빠른 비전 투사체 (마나 10)", "cd": 0.0},
			"rmb": {"name": "비전 보호막", "desc": "8초간 피해 50 흡수 (마나 30)", "cd": 15.0},
			"q": {"name": "화염구", "desc": "폭발하는 화염구 (마나 30)", "cd": 6.0},
			"e": {"name": "치유의 빛", "desc": "4초간 체력 50 회복 (마나 35)", "cd": 18.0},
		},
	},
}

const SLOT_NAMES := {"weapon": "무기", "head": "머리", "chest": "몸통", "trinket": "장신구"}
const GEAR_SLOTS := ["weapon", "head", "chest", "trinket"]

const ITEM_BASES := {
	# 무기
	"rusty_sword": {"name": "녹슨 장검", "slot": "weapon", "cls": "fighter", "dmg": 1.0, "value": 15, "icon": "🗡"},
	"arming_sword": {"name": "기사의 장검", "slot": "weapon", "cls": "fighter", "dmg": 1.18, "value": 40, "icon": "🗡"},
	"war_axe": {"name": "전투 도끼", "slot": "weapon", "cls": "fighter", "dmg": 1.3, "value": 60, "icon": "🪓"},
	"zweihander": {"name": "츠바이핸더", "slot": "weapon", "cls": "fighter", "dmg": 1.45, "value": 95, "icon": "⚔"},
	"short_bow": {"name": "단궁", "slot": "weapon", "cls": "ranger", "dmg": 1.0, "value": 15, "icon": "🏹"},
	"hunting_bow": {"name": "사냥꾼의 활", "slot": "weapon", "cls": "ranger", "dmg": 1.18, "value": 40, "icon": "🏹"},
	"long_bow": {"name": "장궁", "slot": "weapon", "cls": "ranger", "dmg": 1.32, "value": 65, "icon": "🏹"},
	"elven_bow": {"name": "엘프의 활", "slot": "weapon", "cls": "ranger", "dmg": 1.45, "value": 95, "icon": "🏹"},
	"oak_staff": {"name": "참나무 지팡이", "slot": "weapon", "cls": "mage", "dmg": 1.0, "value": 15, "icon": "🪄"},
	"crystal_staff": {"name": "수정 지팡이", "slot": "weapon", "cls": "mage", "dmg": 1.18, "value": 40, "icon": "🪄"},
	"spellbook": {"name": "마도서", "slot": "weapon", "cls": "mage", "dmg": 1.3, "value": 65, "icon": "📕"},
	"archmage_staff": {"name": "대마법사의 지팡이", "slot": "weapon", "cls": "mage", "dmg": 1.45, "value": 95, "icon": "🔮"},
	# 머리
	"leather_cap": {"name": "가죽 모자", "slot": "head", "armor": 8, "value": 12, "icon": "🧢"},
	"iron_helm": {"name": "철 투구", "slot": "head", "armor": 16, "value": 30, "icon": "⛑"},
	"great_helm": {"name": "그레이트 헬름", "slot": "head", "armor": 24, "speed": -0.03, "value": 55, "icon": "🪖"},
	"wizard_hat": {"name": "마법사 모자", "slot": "head", "armor": 6, "mana": 25, "value": 40, "icon": "🎩"},
	# 몸통
	"padded_tunic": {"name": "누빔 튜닉", "slot": "chest", "armor": 12, "value": 15, "icon": "👕"},
	"chain_mail": {"name": "사슬 갑옷", "slot": "chest", "armor": 28, "speed": -0.04, "value": 45, "icon": "🥋"},
	"plate_armor": {"name": "판금 갑옷", "slot": "chest", "armor": 45, "speed": -0.08, "value": 80, "icon": "🛡"},
	"ranger_coat": {"name": "레인저 외투", "slot": "chest", "armor": 18, "speed": 0.04, "value": 50, "icon": "🧥"},
	"arcane_robe": {"name": "비전 로브", "slot": "chest", "armor": 10, "mana": 40, "value": 55, "icon": "👘"},
	# 장신구
	"copper_ring": {"name": "구리 반지", "slot": "trinket", "hp": 10, "value": 20, "icon": "💍"},
	"ruby_ring": {"name": "루비 반지", "slot": "trinket", "hp": 25, "value": 50, "icon": "💍"},
	"wolf_pendant": {"name": "늑대 목걸이", "slot": "trinket", "speed": 0.06, "value": 50, "icon": "📿"},
	"skull_amulet": {"name": "해골 부적", "slot": "trinket", "dmgBonus": 0.08, "value": 70, "icon": "💀"},
	# 소모품
	"health_potion": {"name": "체력 물약", "slot": "consumable", "heal": 45, "value": 15, "icon": "🧪"},
	"bandage": {"name": "붕대", "slot": "consumable", "heal": 20, "value": 6, "icon": "🩹"},
	# 보물
	"gold_coins": {"name": "금화 주머니", "slot": "treasure", "value": 25, "icon": "💰"},
	"silver_goblet": {"name": "은 술잔", "slot": "treasure", "value": 35, "icon": "🏆"},
	"ruby": {"name": "루비", "slot": "treasure", "value": 60, "icon": "🔴"},
	"sapphire": {"name": "사파이어", "slot": "treasure", "value": 70, "icon": "🔵"},
	"golden_crown": {"name": "황금 왕관", "slot": "treasure", "value": 160, "icon": "👑"},
	"ancient_relic": {"name": "고대 유물", "slot": "treasure", "value": 220, "icon": "🗿"},
	"dragon_heart": {"name": "용의 심장석", "slot": "treasure", "value": 400, "icon": "💎"},
}

const STARTER_WEAPON := {"fighter": "rusty_sword", "ranger": "short_bow", "mage": "oak_staff"}

const MONSTERS := {
	"skeleton": {"name": "스켈레톤 전사", "hp": 80, "dmg": 13, "speed": 3.6, "range": 2.3, "cd": 1.3, "sight": 16.0, "ranged": false, "scale": 1.0, "boss": false},
	"skeleton_archer": {"name": "스켈레톤 궁수", "hp": 60, "dmg": 11, "speed": 3.3, "range": 15.0, "cd": 2.0, "sight": 20.0, "ranged": true, "scale": 1.0, "boss": false},
	"goblin": {"name": "고블린", "hp": 50, "dmg": 9, "speed": 5.2, "range": 2.0, "cd": 0.9, "sight": 14.0, "ranged": false, "scale": 0.75, "boss": false},
	"ghoul": {"name": "구울", "hp": 140, "dmg": 18, "speed": 2.8, "range": 2.4, "cd": 1.6, "sight": 12.0, "ranged": false, "scale": 1.1, "boss": false},
	"wraith_knight": {"name": "망령 기사", "hp": 950, "dmg": 30, "speed": 3.4, "range": 3.2, "cd": 1.7, "sight": 18.0, "ranged": false, "scale": 1.55, "boss": true},
}

const BOT_NAMES := [
	"검은늑대", "은빛매", "그림자칼날", "철벽수호자", "붉은여우", "방랑자K", "던전킹", "초보탈출러", "도적왕", "불꽃술사",
	"서리마녀", "활쏘는곰", "무덤지기", "Aldric", "Mirelle", "Kael", "Thorne", "Sylvara", "Brom", "Vex",
]

var _uid := 0


func uid() -> String:
	_uid += 1
	return "i%d_%d" % [Time.get_ticks_msec(), _uid]


func base_of(item: Dictionary) -> Dictionary:
	return ITEM_BASES[item["base"]]


func is_gear(item: Dictionary) -> bool:
	return base_of(item)["slot"] in GEAR_SLOTS


func make_item(base_id: String, rarity: int = 0) -> Dictionary:
	var b: Dictionary = ITEM_BASES[base_id]
	if b["slot"] == "consumable":
		rarity = 0
	var r: Dictionary = RARITIES[rarity]
	var stats := {}
	if b.has("dmg"):
		stats["dmg"] = snappedf(b["dmg"] * (1.0 + (r["mult"] - 1.0) * 0.6), 0.01)
	if b.has("armor"):
		stats["armor"] = roundi(b["armor"] * r["mult"])
	if b.has("hp"):
		stats["hp"] = roundi(b["hp"] * r["mult"])
	if b.has("mana"):
		stats["mana"] = roundi(b["mana"] * r["mult"])
	if b.has("speed"):
		stats["speed"] = snappedf(b["speed"] * r["mult"] if b["speed"] > 0 else b["speed"], 0.001)
	if b.has("dmgBonus"):
		stats["dmgBonus"] = snappedf(b["dmgBonus"] * r["mult"], 0.001)
	# 희귀도 높은 장비는 추가 옵션
	if rarity >= 2 and b["slot"] in GEAR_SLOTS:
		for i in range(rarity - 1):
			match randi() % 4:
				0:
					stats["hp"] = stats.get("hp", 0) + 5 + rarity * 4
				1:
					stats["dmgBonus"] = snappedf(stats.get("dmgBonus", 0.0) + 0.02 * rarity, 0.001)
				2:
					stats["speed"] = snappedf(stats.get("speed", 0.0) + 0.015 * rarity, 0.001)
				3:
					stats["armor"] = stats.get("armor", 0) + 3 * rarity
	var value_mult: float = (1.0 + rarity * 0.5) if b["slot"] == "treasure" else float(r["value"])
	return {
		"id": uid(),
		"base": base_id,
		"rarity": rarity,
		"stats": stats,
		"value": roundi(b["value"] * value_mult * randf_range(0.9, 1.1)),
	}


func stat_label(k: String, v) -> String:
	match k:
		"dmg":
			return "무기 공격력 x%.2f" % v
		"armor":
			return "방어도 +%d" % v
		"hp":
			return "최대 체력 +%d" % v
		"mana":
			return "최대 마나 +%d" % v
		"speed":
			return "이동속도 %s%d%%" % ["+" if v >= 0 else "", roundi(v * 100)]
		"dmgBonus":
			return "피해량 +%d%%" % roundi(v * 100)
	return ""


# luck 0 = 기본, 높을수록 좋은 아이템
func roll_rarity(luck: float = 0.0) -> int:
	var r := randf() * 100.0 - luck * 9.0
	if r < 1.2:
		return 4
	if r < 6.0:
		return 3
	if r < 18.0:
		return 2
	if r < 42.0:
		return 1
	return 0


const TREASURE_POOL := [
	["gold_coins", 40.0], ["silver_goblet", 22.0], ["ruby", 12.0], ["sapphire", 10.0],
	["golden_crown", 4.0], ["ancient_relic", 2.5], ["dragon_heart", 0.8],
]


func _gear_pool() -> Array:
	var out := []
	for k in ITEM_BASES:
		if ITEM_BASES[k]["slot"] in GEAR_SLOTS:
			out.append(k)
	return out


func _weighted_treasure(luck: float) -> String:
	var total := 0.0
	var ws := []
	for i in TREASURE_POOL.size():
		var w: float = TREASURE_POOL[i][1] * (1.0 + luck * i / 4.0)
		ws.append(w)
		total += w
	var r := randf() * total
	for i in TREASURE_POOL.size():
		r -= ws[i]
		if r <= 0.0:
			return TREASURE_POOL[i][0]
	return TREASURE_POOL[0][0]


func roll_loot(count: int, luck: float = 0.0) -> Array:
	var items := []
	var gear := _gear_pool()
	for i in count:
		var r := randf()
		if r < 0.42:
			items.append(make_item(gear.pick_random(), roll_rarity(luck)))
		elif r < 0.62:
			items.append(make_item("health_potion" if randf() < 0.7 else "bandage"))
		else:
			items.append(make_item(_weighted_treasure(luck), 1 if randf() < 0.15 + luck * 0.1 else 0))
	return items


func can_equip(item: Dictionary, cls: String) -> bool:
	var b := base_of(item)
	if not (b["slot"] in GEAR_SLOTS):
		return false
	if b["slot"] == "weapon" and b["cls"] != cls:
		return false
	return true


func compute_stats(cls: String, equipment: Dictionary) -> Dictionary:
	var c: Dictionary = CLASSES[cls]
	var hp: float = c["hp"]
	var armor := 0.0
	var speed := 0.0
	var dmg_bonus := 0.0
	var mana: float = c["mana"]
	var dmg := 0.85
	for slot in GEAR_SLOTS:
		var it = equipment.get(slot)
		if it == null:
			continue
		var s: Dictionary = it["stats"]
		if slot == "weapon":
			dmg = s.get("dmg", 1.0)
		hp += s.get("hp", 0)
		armor += s.get("armor", 0)
		speed += s.get("speed", 0.0)
		dmg_bonus += s.get("dmgBonus", 0.0)
		if c["mana"] > 0:
			mana += s.get("mana", 0)
	return {
		"max_hp": hp,
		"armor": armor,
		"speed_mul": maxf(0.6, 1.0 + speed),
		"dmg_mul": dmg * (1.0 + dmg_bonus),
		"max_mana": mana,
		"base_speed": c["speed"],
	}


func items_value(items: Array) -> int:
	var s := 0
	for it in items:
		if it != null:
			s += int(it["value"])
	return s
