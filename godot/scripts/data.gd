# 게임 데이터: 직업, 아이템, 몬스터, 희귀도, 루트 테이블 (autoload: Data)
extends Node

const RARITIES := [
	{"name": "일반", "color": Color("#b9b9b9"), "mult": 1.0, "value": 1.0},
	{"name": "고급", "color": Color("#4fd16a"), "mult": 1.15, "value": 2.0},
	{"name": "희귀", "color": Color("#4a9dff"), "mult": 1.32, "value": 4.0},
	{"name": "영웅", "color": Color("#b65cff"), "mult": 1.52, "value": 8.0},
	{"name": "전설", "color": Color("#ff9b2f"), "mult": 1.8, "value": 16.0},
]

# 던전본의 8개 직업. res: 직업 자원 (mana/soul/primal, ""면 없음)
# skills: lmb/rmb/q/e (드루이드는 표범 형태용 lmb_p/rmb_p/e_p 추가)
const CLASSES := {
	"fighter": {
		"id": "fighter", "name": "파이터", "icon": "🛡", "hp": 140, "speed": 5.0, "armor": 5,
		"res": "", "res_max": 0,
		"desc": "검과 방패로 전열을 지키는 근접 전투의 기본. 회전베기로 다수를 상대한다.",
		"skills": {
			"lmb": {"name": "베기", "desc": "전방 부채꼴 근접 공격 (연속 콤보)", "cd": 0.0},
			"rmb": {"name": "방패 방어", "desc": "누르는 동안 정면 피해 75% 감소 (스태미나 소모)", "cd": 0.0},
			"q": {"name": "회오리 베기", "desc": "2초간 회전하며 주변 적을 연속으로 벤다 (스태미나 20)", "cd": 12.0},
			"e": {"name": "돌진", "desc": "전방으로 돌진해 처음 부딪힌 적에게 피해와 기절", "cd": 9.0},
		},
	},
	"swordmaster": {
		"id": "swordmaster", "name": "소드마스터", "icon": "⚔", "hp": 120, "speed": 5.4, "armor": 0,
		"res": "", "res_max": 0,
		"desc": "빠른 장검술과 염동 검을 다루는 검객. 패링으로 적의 공격을 받아친다.",
		"skills": {
			"lmb": {"name": "연속 베기", "desc": "빠르고 넓은 장검 베기", "cd": 0.0},
			"rmb": {"name": "패링", "desc": "짧은 순간 모든 공격을 막고, 근접 공격자를 기절시킨다", "cd": 1.2},
			"q": {"name": "사이오닉 블레이드", "desc": "적을 추적하는 염동 검 4자루를 날린다. 적중 시 체력 회복", "cd": 16.0},
			"e": {"name": "회오리 검", "desc": "8초간 검 하나가 주위를 돌며 베고, 받는 피해 25% 감소", "cd": 18.0},
		},
	},
	"rogue": {
		"id": "rogue", "name": "로그", "icon": "🗡", "hp": 95, "speed": 5.6, "armor": 0,
		"res": "", "res_max": 0,
		"desc": "단검과 독, 은신을 쓰는 암살자. 등 뒤와 은신 상태의 일격이 치명적이다.",
		"skills": {
			"lmb": {"name": "찌르기", "desc": "빠른 단검 공격. 등 뒤에서 1.6배, 은신 중 첫 공격 2.5배", "cd": 0.0},
			"rmb": {"name": "단검 투척", "desc": "단검을 던진다", "cd": 1.5},
			"q": {"name": "석화 독", "desc": "독병을 던져 주변 적을 2초간 묶고 중독시킨다", "cd": 14.0},
			"e": {"name": "은신", "desc": "1.5초 집중 후 15초간 은신. 가까이 오지 않으면 적이 감지하지 못한다", "cd": 20.0},
		},
	},
	"deathknight": {
		"id": "deathknight", "name": "데스나이트", "icon": "💀", "hp": 150, "speed": 4.7, "armor": 10,
		"res": "soul", "res_max": 100,
		"desc": "영혼 에너지를 다루는 중갑 기사. 적을 끌어당기고 생명력을 흡수한다.",
		"skills": {
			"lmb": {"name": "내려베기", "desc": "느리지만 강한 대검 공격. 피해의 10% 흡혈, 영혼 +8", "cd": 0.0},
			"rmb": {"name": "방어", "desc": "누르는 동안 정면 피해 감소", "cd": 0.0},
			"q": {"name": "영혼의 장막", "desc": "5초간 주변 적을 둔화시키고 암흑 피해 (영혼 40)", "cd": 12.0},
			"e": {"name": "무덤의 손아귀", "desc": "적을 붙잡아 끌어당기고 기절. 적중 시 영혼 +20", "cd": 10.0},
		},
	},
	"druid": {
		"id": "druid", "name": "드루이드", "icon": "🌿", "hp": 110, "speed": 5.0, "armor": 0,
		"res": "primal", "res_max": 100,
		"desc": "자연의 힘을 다루는 술사. 표범으로 변신해 추격하거나 트렌트를 불러 싸운다.",
		"skills": {
			"lmb": {"name": "가시 덩굴", "desc": "가시를 날린다", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
			"q": {"name": "원시의 각성", "desc": "표범으로 변신 (이동속도 대폭 증가, 해로운 효과 제거). 원시 에너지 30 + 초당 4 소모. 다시 누르면 해제", "cd": 2.0},
			"e": {"name": "자연의 힘", "desc": "30초간 싸우는 트렌트를 소환하고 보호막 30을 얻는다", "cd": 30.0},
			"lmb_p": {"name": "할퀴기", "desc": "빠른 발톱 공격", "cd": 0.0},
			"rmb_p": {"name": "포효", "desc": "주변 적을 밀어낸다", "cd": 6.0},
			"e_p": {"name": "그림자 습격", "desc": "앞으로 도약해 처음 닿은 적에게 큰 피해 (원시 15)", "cd": 6.0},
		},
	},
	"pyromancer": {
		"id": "pyromancer", "name": "파이로맨서", "icon": "🔥", "hp": 90, "speed": 5.0, "armor": 0,
		"res": "mana", "res_max": 100,
		"desc": "적을 추적하는 화염탄과 폭발로 전장을 불태우는 화염 술사.",
		"skills": {
			"lmb": {"name": "화염탄", "desc": "적을 추적하는 빠른 화염탄 (마나 8)", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
			"q": {"name": "화염 폭발", "desc": "거대한 화염구. 넓은 범위에 큰 피해 (마나 35)", "cd": 8.0},
			"e": {"name": "화염 파동", "desc": "전방 넓은 범위를 불태우고 강하게 밀쳐낸다 (마나 25)", "cd": 10.0},
		},
	},
	"cryomancer": {
		"id": "cryomancer", "name": "크라이오맨서", "icon": "❄", "hp": 90, "speed": 5.0, "armor": 0,
		"res": "mana", "res_max": 100,
		"desc": "냉기로 적을 둔화시키고 얼음 속에서 버티는 냉기 술사.",
		"skills": {
			"lmb": {"name": "얼음 화살", "desc": "적중 시 둔화 (마나 8)", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
			"q": {"name": "얼음 폭풍", "desc": "조준 지점에 4초간 얼음 폭풍. 범위 피해와 둔화 (마나 35)", "cd": 12.0},
			"e": {"name": "서리 장벽", "desc": "3초간 얼음에 갇혀 무적이 되고 체력 40 회복 (마나 30)", "cd": 25.0},
		},
	},
	"priest": {
		"id": "priest", "name": "프리스트", "icon": "✨", "hp": 105, "speed": 5.0, "armor": 5,
		"res": "mana", "res_max": 100,
		"desc": "신성한 힘으로 치유하고 보호막을 거는 성직자. 철퇴로 직접 싸울 수도 있다.",
		"skills": {
			"lmb": {"name": "철퇴", "desc": "철퇴 근접 공격", "cd": 0.0},
			"rmb": {"name": "정화", "desc": "누르고 있다가 놓으면 치유 (오래 모을수록 최대 3배) + 해로운 효과 제거 (마나 15)", "cd": 0.8},
			"q": {"name": "신성한 인도", "desc": "주변 아군 치유·해로운 효과 제거, 주변 적에게 피해 (마나 35)", "cd": 14.0},
			"e": {"name": "수호", "desc": "주변 아군에게 8초간 피해 50을 흡수하는 보호막 (마나 30)", "cd": 18.0},
		},
	},
}

const CLASS_ORDER := ["fighter", "swordmaster", "rogue", "deathknight", "druid", "pyromancer", "cryomancer", "priest"]
const RES_NAMES := {"mana": "마나", "soul": "영혼", "primal": "원시 에너지"}
const RES_COLORS := {"mana": Color(0.29, 0.48, 1.0), "soul": Color(0.6, 0.25, 0.85), "primal": Color(0.35, 0.8, 0.3)}

# ------------------------------------------------------------------ 능력치 (던전본 방식: 능력치가 파생 스탯과 패시브를 결정)
const ATTRS := ["str", "agi", "int", "wil", "vit"]
const ATTR_NAMES := {"str": "힘", "agi": "민첩", "int": "지능", "wil": "의지", "vit": "활력"}
const ATTR_DESC := {
	"str": "물리 직업 피해량",
	"agi": "이동속도, 공격 속도 (로그 피해량)",
	"int": "마법 직업 피해량, 최대 마나",
	"wil": "스킬 재사용 대기시간 감소, 자원 회복 (프리스트 피해량)",
	"vit": "최대 체력",
}
# 직업별 기본 능력치와 피해량을 결정하는 능력치
const CLASS_ATTRS := {
	"fighter": {"str": 18, "agi": 13, "int": 8, "wil": 12, "vit": 20},
	"swordmaster": {"str": 17, "agi": 18, "int": 9, "wil": 14, "vit": 15},
	"rogue": {"str": 12, "agi": 22, "int": 12, "wil": 12, "vit": 13},
	"deathknight": {"str": 20, "agi": 11, "int": 10, "wil": 15, "vit": 19},
	"druid": {"str": 12, "agi": 15, "int": 18, "wil": 17, "vit": 15},
	"pyromancer": {"str": 8, "agi": 13, "int": 22, "wil": 17, "vit": 12},
	"cryomancer": {"str": 9, "agi": 12, "int": 21, "wil": 18, "vit": 14},
	"priest": {"str": 15, "agi": 11, "int": 14, "wil": 21, "vit": 16},
}
const POWER_ATTR := {
	"fighter": "str", "swordmaster": "str", "rogue": "agi", "deathknight": "str",
	"druid": "int", "pyromancer": "int", "cryomancer": "int", "priest": "wil",
}
const MAGIC_CLASSES := ["druid", "pyromancer", "cryomancer", "priest"]

# 능력치 조건을 채우면 열리는 직업 패시브 (첫 번째는 기본 능력치로 열림)
# fx: dmg(피해%), hp, armor, move(이속%), cdr(쿨감%), regen(자원회복%), act(공격속도%), heal(치유량%), 그 외 특수 플래그
const PASSIVES := {
	"fighter": [
		{"name": "방패 숙련", "req": {"vit": 20}, "desc": "방어 중 스태미나 소모 30% 감소", "fx": {"block_eff": 0.3}},
		{"name": "무기 숙련", "req": {"str": 24}, "desc": "피해량 +8%", "fx": {"dmg": 0.08}},
		{"name": "불굴", "req": {"vit": 28}, "desc": "최대 체력 +20", "fx": {"hp": 20}},
	],
	"swordmaster": [
		{"name": "검무", "req": {"agi": 18}, "desc": "공격 속도 +10%", "fx": {"act": 0.10}},
		{"name": "명경지수", "req": {"wil": 20}, "desc": "스킬 재사용 대기시간 -10%", "fx": {"cdr": 0.10}},
		{"name": "칼날 폭풍", "req": {"str": 25}, "desc": "피해량 +8%", "fx": {"dmg": 0.08}},
	],
	"rogue": [
		{"name": "그림자 걸음", "req": {"agi": 22}, "desc": "이동속도 +5%", "fx": {"move": 0.05}},
		{"name": "급소 노리기", "req": {"agi": 28}, "desc": "등 뒤 공격 1.6배 → 1.9배", "fx": {"backstab": 0.3}},
		{"name": "독 연구", "req": {"int": 17}, "desc": "석화 독 지속 피해 +60%", "fx": {"poison": 0.6}},
	],
	"deathknight": [
		{"name": "영혼 흡수", "req": {"wil": 15}, "desc": "근접 흡혈 10% → 15%", "fx": {"lifesteal": 0.05}},
		{"name": "공포의 갑주", "req": {"vit": 24}, "desc": "방어도 +15", "fx": {"armor": 15}},
		{"name": "학살자", "req": {"str": 26}, "desc": "피해량 +8%", "fx": {"dmg": 0.08}},
	],
	"druid": [
		{"name": "자연의 가호", "req": {"wil": 17}, "desc": "마나/원시 에너지 회복 +25%", "fx": {"regen": 0.25}},
		{"name": "야수의 힘", "req": {"agi": 21}, "desc": "표범 형태 피해 +15%", "fx": {"beast": 0.15}},
		{"name": "숲의 수호", "req": {"vit": 22}, "desc": "최대 체력 +20", "fx": {"hp": 20}},
	],
	"pyromancer": [
		{"name": "마력 순환", "req": {"wil": 17}, "desc": "마나 회복 +25%", "fx": {"regen": 0.25}},
		{"name": "불꽃 친화", "req": {"int": 27}, "desc": "피해량 +10%", "fx": {"dmg": 0.10}},
		{"name": "열기", "req": {"wil": 23}, "desc": "스킬 재사용 대기시간 -8%", "fx": {"cdr": 0.08}},
	],
	"cryomancer": [
		{"name": "마력 순환", "req": {"wil": 18}, "desc": "마나 회복 +25%", "fx": {"regen": 0.25}},
		{"name": "얼음 심장", "req": {"vit": 20}, "desc": "방어도 +12", "fx": {"armor": 12}},
		{"name": "냉기 숙련", "req": {"int": 27}, "desc": "피해량 +10%", "fx": {"dmg": 0.10}},
	],
	"priest": [
		{"name": "신앙", "req": {"wil": 21}, "desc": "치유량 +20%", "fx": {"heal": 0.2}},
		{"name": "축복받은 무기", "req": {"str": 20}, "desc": "피해량 +8%", "fx": {"dmg": 0.08}},
		{"name": "인내", "req": {"vit": 22}, "desc": "최대 체력 +20", "fx": {"hp": 20}},
	],
}

# 무작위 옵션 (희귀도가 높을수록 개수와 수치가 커짐). r = 희귀도 0~4
const AFFIXES := {
	"str": {"name": "힘", "fmt": "+%d 힘", "w": 10},
	"agi": {"name": "민첩", "fmt": "+%d 민첩", "w": 10},
	"int": {"name": "지능", "fmt": "+%d 지능", "w": 10},
	"wil": {"name": "의지", "fmt": "+%d 의지", "w": 10},
	"vit": {"name": "활력", "fmt": "+%d 활력", "w": 10},
	"all": {"name": "모든 능력치", "fmt": "+%d 모든 능력치", "w": 3},
	"hp": {"name": "최대 체력", "fmt": "+%d 최대 체력", "w": 8},
	"armor": {"name": "방어도", "fmt": "+%d 방어도", "w": 8},
	"phys": {"name": "물리 피해", "fmt": "+%d%% 물리 피해", "w": 6},
	"magic": {"name": "마법 피해", "fmt": "+%d%% 마법 피해", "w": 6},
	"move": {"name": "이동속도", "fmt": "+%d%% 이동속도", "w": 5},
	"cdr": {"name": "재사용 대기시간 감소", "fmt": "+%d%% 재사용 대기시간 감소", "w": 5},
	"regen": {"name": "자원 회복", "fmt": "+%d%% 자원 회복", "w": 5},
	"act": {"name": "공격 속도", "fmt": "+%d%% 공격 속도", "w": 5},
}


# 옵션 수치 범위 [최소, 최대]
func affix_range(k: String, r: int) -> Vector2i:
	match k:
		"str", "agi", "int", "wil", "vit":
			return Vector2i(1 + r / 2, 2 + r)
		"all":
			return Vector2i(1, 1 + r / 2)
		"hp":
			return Vector2i(4 + r * 2, 8 + r * 4)
		"armor":
			return Vector2i(3 + r * 2, 6 + r * 3)
		"phys", "magic":
			return Vector2i(2 + r, 3 + r * 2)
		"move":
			return Vector2i(1, 2 + r / 2)
		"cdr", "act":
			return Vector2i(2 + r / 2, 3 + r)
		"regen":
			return Vector2i(5 + r * 2, 8 + r * 4)
	return Vector2i(1, 1)


const SLOT_NAMES := {
	"weapon": "무기", "head": "머리", "chest": "상의", "hands": "장갑", "legs": "하의", "feet": "신발",
	"necklace": "목걸이", "ring1": "반지", "ring2": "반지", "ring": "반지",
}
const GEAR_SLOTS := ["weapon", "head", "chest", "hands", "legs", "feet", "necklace", "ring1", "ring2"]
const ITEM_SLOT_TO_GEAR := {"ring": ["ring1", "ring2"]}

# size: 인벤토리에서 차지하는 칸 [가로, 세로] (회전 가능)
const ITEM_BASES := {
	# 무기 (classes: 장착 가능한 직업)
	"rusty_sword": {"name": "녹슨 장검", "slot": "weapon", "classes": ["fighter", "swordmaster"], "dmg": 1.0, "value": 15, "icon": "🗡", "model": "sword", "size": [1, 3]},
	"arming_sword": {"name": "기사의 장검", "slot": "weapon", "classes": ["fighter", "swordmaster"], "dmg": 1.18, "value": 40, "icon": "🗡", "model": "sword", "size": [1, 3]},
	"war_axe": {"name": "전투 도끼", "slot": "weapon", "classes": ["fighter"], "dmg": 1.3, "value": 60, "icon": "🪓", "model": "sword", "size": [2, 3]},
	"zweihander": {"name": "츠바이핸더", "slot": "weapon", "classes": ["swordmaster", "deathknight"], "dmg": 1.45, "value": 95, "icon": "⚔", "model": "greatsword", "size": [2, 4]},
	"training_longsword": {"name": "수련용 장검", "slot": "weapon", "classes": ["swordmaster"], "dmg": 1.0, "value": 15, "icon": "🗡", "model": "longsword", "size": [1, 4]},
	"katana": {"name": "카타나", "slot": "weapon", "classes": ["swordmaster"], "dmg": 1.32, "value": 70, "icon": "🗡", "model": "longsword", "size": [1, 4]},
	"rusty_dagger": {"name": "녹슨 단검", "slot": "weapon", "classes": ["rogue"], "dmg": 1.0, "value": 15, "icon": "🔪", "model": "dagger", "size": [1, 2]},
	"twin_daggers": {"name": "쌍단검", "slot": "weapon", "classes": ["rogue"], "dmg": 1.18, "value": 40, "icon": "🔪", "model": "dagger", "size": [2, 2]},
	"venom_dagger": {"name": "독날 단검", "slot": "weapon", "classes": ["rogue"], "dmg": 1.3, "value": 65, "icon": "🔪", "model": "dagger", "size": [1, 2]},
	"shadow_dagger": {"name": "그림자 단검", "slot": "weapon", "classes": ["rogue"], "dmg": 1.45, "value": 95, "icon": "🔪", "model": "dagger", "size": [1, 2]},
	"rusty_greatsword": {"name": "녹슨 대검", "slot": "weapon", "classes": ["deathknight"], "dmg": 1.0, "value": 15, "icon": "⚔", "model": "greatsword", "size": [2, 4]},
	"reaper_scythe": {"name": "사신의 낫", "slot": "weapon", "classes": ["deathknight"], "dmg": 1.3, "value": 70, "icon": "☠", "model": "greatsword", "size": [2, 4]},
	"oak_staff": {"name": "참나무 지팡이", "slot": "weapon", "classes": ["druid", "pyromancer", "cryomancer"], "dmg": 1.0, "value": 15, "icon": "🪄", "model": "staff", "size": [1, 4]},
	"crystal_staff": {"name": "수정 지팡이", "slot": "weapon", "classes": ["druid", "pyromancer", "cryomancer"], "dmg": 1.18, "value": 40, "icon": "🪄", "model": "staff", "size": [1, 4]},
	"living_staff": {"name": "생명의 지팡이", "slot": "weapon", "classes": ["druid"], "dmg": 1.32, "value": 70, "icon": "🌿", "model": "staff", "size": [1, 4]},
	"spellbook": {"name": "마도서", "slot": "weapon", "classes": ["pyromancer", "cryomancer", "priest"], "dmg": 1.3, "value": 65, "icon": "📕", "model": "staff", "size": [2, 2]},
	"archmage_staff": {"name": "대마법사의 지팡이", "slot": "weapon", "classes": ["pyromancer", "cryomancer"], "dmg": 1.45, "value": 95, "icon": "🔮", "model": "staff", "size": [1, 4]},
	"iron_mace": {"name": "철 철퇴", "slot": "weapon", "classes": ["priest"], "dmg": 1.0, "value": 15, "icon": "🔨", "model": "mace", "size": [1, 3]},
	"holy_mace": {"name": "성스러운 철퇴", "slot": "weapon", "classes": ["priest"], "dmg": 1.25, "value": 55, "icon": "🔨", "model": "mace", "size": [1, 3]},
	"sun_mace": {"name": "태양의 철퇴", "slot": "weapon", "classes": ["priest"], "dmg": 1.45, "value": 95, "icon": "🔨", "model": "mace", "size": [2, 3]},
	# 머리 (작은 장비 2x2)
	"leather_cap": {"name": "가죽 모자", "slot": "head", "armor": 8, "value": 12, "icon": "🧢", "size": [2, 2]},
	"iron_helm": {"name": "철 투구", "slot": "head", "armor": 16, "value": 30, "icon": "⛑", "size": [2, 2]},
	"great_helm": {"name": "그레이트 헬름", "slot": "head", "armor": 24, "speed": -0.03, "value": 55, "icon": "🪖", "size": [2, 2]},
	"wizard_hat": {"name": "마법사 모자", "slot": "head", "armor": 6, "mana": 25, "value": 40, "icon": "🎩", "size": [2, 2]},
	# 상의 (큰 장비 2x3)
	"padded_tunic": {"name": "누빔 튜닉", "slot": "chest", "armor": 12, "value": 15, "icon": "👕", "size": [2, 3]},
	"chain_mail": {"name": "사슬 갑옷", "slot": "chest", "armor": 28, "speed": -0.04, "value": 45, "icon": "🥋", "size": [2, 3]},
	"plate_armor": {"name": "판금 갑옷", "slot": "chest", "armor": 45, "speed": -0.08, "value": 80, "icon": "🛡", "size": [2, 3]},
	"ranger_coat": {"name": "사냥꾼 외투", "slot": "chest", "armor": 18, "speed": 0.04, "value": 50, "icon": "🧥", "size": [2, 3]},
	"arcane_robe": {"name": "비전 로브", "slot": "chest", "armor": 10, "mana": 40, "value": 55, "icon": "👘", "size": [2, 3]},
	# 장갑 (2x2)
	"leather_gloves": {"name": "가죽 장갑", "slot": "hands", "armor": 4, "value": 12, "icon": "🧤", "size": [2, 2]},
	"chain_gauntlets": {"name": "사슬 건틀릿", "slot": "hands", "armor": 9, "value": 30, "icon": "🧤", "size": [2, 2]},
	"plate_gauntlets": {"name": "판금 건틀릿", "slot": "hands", "armor": 14, "speed": -0.01, "value": 50, "icon": "🧤", "size": [2, 2]},
	# 하의 (2x3)
	"cloth_pants": {"name": "천 바지", "slot": "legs", "armor": 6, "value": 12, "icon": "👖", "size": [2, 3]},
	"leather_leggings": {"name": "가죽 각반", "slot": "legs", "armor": 12, "value": 30, "icon": "👖", "size": [2, 3]},
	"plate_greaves": {"name": "판금 다리갑옷", "slot": "legs", "armor": 22, "speed": -0.03, "value": 55, "icon": "👖", "size": [2, 3]},
	# 신발 (2x2)
	"leather_boots": {"name": "가죽 장화", "slot": "feet", "armor": 4, "speed": 0.02, "value": 15, "icon": "🥾", "size": [2, 2]},
	"chain_boots": {"name": "사슬 장화", "slot": "feet", "armor": 9, "value": 30, "icon": "🥾", "size": [2, 2]},
	"plate_sabatons": {"name": "판금 철각", "slot": "feet", "armor": 14, "speed": -0.02, "value": 50, "icon": "🥾", "size": [2, 2]},
	# 목걸이/반지 (1x1)
	"wolf_pendant": {"name": "늑대 목걸이", "slot": "necklace", "speed": 0.04, "value": 50, "icon": "📿", "size": [1, 1]},
	"skull_amulet": {"name": "해골 부적", "slot": "necklace", "dmgBonus": 0.06, "value": 70, "icon": "💀", "size": [1, 1]},
	"bone_necklace": {"name": "뼈 목걸이", "slot": "necklace", "hp": 12, "value": 35, "icon": "📿", "size": [1, 1]},
	"copper_ring": {"name": "구리 반지", "slot": "ring", "hp": 8, "value": 20, "icon": "💍", "size": [1, 1]},
	"ruby_ring": {"name": "루비 반지", "slot": "ring", "hp": 18, "value": 50, "icon": "💍", "size": [1, 1]},
	"silver_ring": {"name": "은 반지", "slot": "ring", "mana": 15, "value": 40, "icon": "💍", "size": [1, 1]},
	# 소모품
	"health_potion": {"name": "체력 물약", "slot": "consumable", "heal": 45, "value": 15, "icon": "🧪", "size": [1, 1]},
	"bandage": {"name": "붕대", "slot": "consumable", "heal": 20, "value": 6, "icon": "🩹", "size": [1, 1]},
	# 보물
	"gold_coins": {"name": "금화 주머니", "slot": "treasure", "value": 25, "icon": "💰", "size": [1, 1]},
	"silver_goblet": {"name": "은 술잔", "slot": "treasure", "value": 35, "icon": "🏆", "size": [1, 2]},
	"ruby": {"name": "루비", "slot": "treasure", "value": 60, "icon": "🔴", "size": [1, 1]},
	"sapphire": {"name": "사파이어", "slot": "treasure", "value": 70, "icon": "🔵", "size": [1, 1]},
	"golden_crown": {"name": "황금 왕관", "slot": "treasure", "value": 160, "icon": "👑", "size": [2, 2]},
	"ancient_relic": {"name": "고대 유물", "slot": "treasure", "value": 220, "icon": "🗿", "size": [2, 2]},
	"dragon_heart": {"name": "용의 심장석", "slot": "treasure", "value": 400, "icon": "💎", "size": [2, 2]},
}

const STARTER_WEAPON := {
	"fighter": "rusty_sword", "swordmaster": "training_longsword", "rogue": "rusty_dagger", "deathknight": "rusty_greatsword",
	"druid": "oak_staff", "pyromancer": "oak_staff", "cryomancer": "oak_staff", "priest": "iron_mace",
}

# 이전 버전(레인저/마법사) 세이브 변환용
const LEGACY_CLASS := {"ranger": "rogue", "mage": "pyromancer"}
const LEGACY_ITEM := {"short_bow": "rusty_dagger", "hunting_bow": "twin_daggers", "long_bow": "venom_dagger", "elven_bow": "shadow_dagger"}

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
	return base_of(item)["slot"] in ["weapon", "head", "chest", "hands", "legs", "feet", "necklace", "ring"]


# 아이템이 들어갈 수 있는 장비 칸 (반지는 두 칸)
func gear_slots_for(item: Dictionary) -> Array:
	var sl: String = base_of(item)["slot"]
	if sl == "ring":
		return ["ring1", "ring2"]
	if sl in GEAR_SLOTS:
		return [sl]
	return []


# 인벤토리 칸 크기 (회전하면 가로세로 교체)
func item_size(item: Dictionary) -> Vector2i:
	var sz: Array = base_of(item).get("size", [1, 1])
	if item.get("r", false):
		return Vector2i(sz[1], sz[0])
	return Vector2i(sz[0], sz[1])


func _roll_affix_key(used: Dictionary) -> String:
	var total := 0
	for k in AFFIXES:
		if not used.has(k):
			total += AFFIXES[k].w
	var r := randi() % maxi(1, total)
	for k in AFFIXES:
		if used.has(k):
			continue
		r -= AFFIXES[k].w
		if r < 0:
			return k
	return "vit"


# 아이템 생성: 기본 수치(희귀도 배율 + 무작위 편차) + 희귀도만큼 무작위 옵션
func make_item(base_id: String, rarity: int = 0) -> Dictionary:
	var b: Dictionary = ITEM_BASES[base_id]
	if b["slot"] == "consumable":
		rarity = 0
	var r: Dictionary = RARITIES[rarity]
	var stats := {}
	if b.has("dmg"):
		stats["dmg"] = snappedf(b["dmg"] * (1.0 + (r["mult"] - 1.0) * 0.6) * randf_range(0.95, 1.05), 0.01)
	if b.has("armor"):
		stats["armor"] = maxi(1, roundi(b["armor"] * r["mult"] * randf_range(0.85, 1.15)))
	if b.has("hp"):
		stats["hp"] = roundi(b["hp"] * r["mult"])
	if b.has("mana"):
		stats["mana"] = roundi(b["mana"] * r["mult"])
	if b.has("speed"):
		stats["speed"] = snappedf(b["speed"] * r["mult"] if b["speed"] > 0 else b["speed"], 0.001)
	if b.has("dmgBonus"):
		stats["dmgBonus"] = snappedf(b["dmgBonus"] * r["mult"], 0.001)
	var affixes := []
	if is_gear({"base": base_id}):
		var used := {}
		for i in rarity:
			var k := _roll_affix_key(used)
			used[k] = true
			var rg := affix_range(k, rarity)
			affixes.append({"k": k, "v": randi_range(rg.x, rg.y)})
	var value_mult: float = (1.0 + rarity * 0.5) if b["slot"] == "treasure" else float(r["value"])
	return {
		"id": uid(),
		"base": base_id,
		"rarity": rarity,
		"stats": stats,
		"affixes": affixes,
		"value": roundi(b["value"] * value_mult * randf_range(0.9, 1.1) * (1.0 + affixes.size() * 0.1)),
	}


func stat_label(k: String, v) -> String:
	match k:
		"dmg":
			return "무기 공격력 x%.2f" % v
		"armor":
			return "방어도 %d" % v
		"hp":
			return "최대 체력 +%d" % v
		"mana":
			return "최대 마나 +%d" % v
		"speed":
			return "이동속도 %s%d%%" % ["+" if v >= 0 else "", roundi(v * 100)]
		"dmgBonus":
			return "피해량 +%d%%" % roundi(v * 100)
	return ""


func affix_label(a: Dictionary) -> String:
	return AFFIXES[a.k].fmt % a.v


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
		if is_gear({"base": k}):
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


func class_names(classes: Array) -> String:
	var out := []
	for c in classes:
		out.append(CLASSES[c].name)
	return ", ".join(out)


func can_equip(item: Dictionary, cls: String) -> bool:
	var b := base_of(item)
	if not is_gear(item):
		return false
	if b["slot"] == "weapon" and not (cls in b["classes"]):
		return false
	return true


# 장비의 능력치/옵션 합계 -> 능력치, 열린 패시브, 파생 스탯
func compute_stats(cls: String, equipment: Dictionary) -> Dictionary:
	var c: Dictionary = CLASSES[cls]
	var attrs: Dictionary = CLASS_ATTRS[cls].duplicate()
	var hp: float = c["hp"]
	var armor: float = c.get("armor", 0)
	var speed := 0.0
	var dmg_bonus := 0.0
	var phys := 0.0
	var magic := 0.0
	var cdr := 0.0
	var regen := 0.0
	var act := 0.0
	var res_max: float = c["res_max"]
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
		# 마나 옵션은 마나를 쓰는 직업에만 적용
		if c["res"] == "mana":
			res_max += s.get("mana", 0)
		for a in it.get("affixes", []):
			var v: float = a["v"]
			match a["k"]:
				"str", "agi", "int", "wil", "vit":
					attrs[a["k"]] += int(v)
				"all":
					for k in ATTRS:
						attrs[k] += int(v)
				"hp":
					hp += v
				"armor":
					armor += v
				"phys":
					phys += v / 100.0
				"magic":
					magic += v / 100.0
				"move":
					speed += v / 100.0
				"cdr":
					cdr += v / 100.0
				"regen":
					regen += v / 100.0
				"act":
					act += v / 100.0
	# 패시브: 능력치 조건을 채우면 열림
	var unlocked := []
	var flags := {}
	for i in PASSIVES[cls].size():
		var p: Dictionary = PASSIVES[cls][i]
		var ok := true
		for k in p.req:
			if attrs[k] < p.req[k]:
				ok = false
		if not ok:
			continue
		unlocked.append(i)
		for k in p.fx:
			var v: float = p.fx[k]
			match k:
				"dmg":
					dmg_bonus += v
				"hp":
					hp += v
				"armor":
					armor += v
				"move":
					speed += v
				"cdr":
					cdr += v
				"regen":
					regen += v
				"act":
					act += v
				_:
					flags[k] = flags.get(k, 0.0) + v
	# 능력치 -> 파생 스탯 (15를 기준으로)
	var pw: int = attrs[POWER_ATTR[cls]]
	hp += (attrs.vit - 15) * 3.0
	speed += (attrs.agi - 15) * 0.003
	act += (attrs.agi - 15) * 0.005
	cdr += maxf(0.0, attrs.wil - 15) * 0.004
	regen += (attrs.wil - 15) * 0.02
	if c["res"] == "mana":
		res_max += (attrs.int - 15) * 1.5
	var type_bonus := magic if cls in MAGIC_CLASSES else phys
	return {
		"max_hp": maxf(30.0, hp),
		"armor": armor,
		"speed_mul": clampf(1.0 + speed, 0.6, 1.5),
		"dmg_mul": dmg * (1.0 + (pw - 15) * 0.012) * (1.0 + dmg_bonus + type_bonus),
		"res": c["res"],
		"res_max": res_max,
		"base_speed": c["speed"],
		"attrs": attrs,
		"passives": unlocked,
		"flags": flags,
		"cd_mul": clampf(1.0 - cdr, 0.6, 1.0),
		"regen_mul": maxf(0.3, 1.0 + regen),
		"act_mul": clampf(1.0 + act, 0.7, 1.5),
		"heal_mul": 1.0 + flags.get("heal", 0.0),
	}


func weapon_model(cls: String, equipment: Dictionary) -> String:
	var w = equipment.get("weapon")
	if w != null:
		return base_of(w).get("model", "sword")
	return ITEM_BASES[STARTER_WEAPON[cls]]["model"]


func items_value(items: Array) -> int:
	var s := 0
	for it in items:
		if it != null:
			s += int(it["value"])
	return s
