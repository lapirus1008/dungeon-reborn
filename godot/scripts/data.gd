# 게임 데이터 (autoload: Data)
# 던전본 위키(방어구/무기/몬스터)와 직업 스킬·패시브 자료를 기준으로 구성
extends Node

# ------------------------------------------------------------------ 희귀도 (지도 범례: 일반/고급/희귀/영웅/전설)
const RARITIES := [
	{"name": "낡음", "color": Color("#8e8e8e"), "value": 1.0}, # 0등급 회색 (흰색보다 아래): 기본 장비·소모품
	{"name": "고급", "color": Color("#4fd16a"), "value": 2.0},
	{"name": "희귀", "color": Color("#4a9dff"), "value": 4.0},
	{"name": "영웅", "color": Color("#b65cff"), "value": 8.0},
	{"name": "전설", "color": Color("#ff6a2a"), "value": 16.0},
]

# ------------------------------------------------------------------ 능력치 (던전본 6능력치)
const ATTRS := ["str", "agi", "vit", "int", "wil", "fai"]
const ATTR_NAMES := {"str": "힘", "agi": "민첩", "vit": "기력", "int": "지능", "wil": "의지", "fai": "신념"}
const ATTR_ICONS := {"str": "💪", "agi": "🦶", "vit": "❤", "int": "📖", "wil": "🛡", "fai": "🙏"}
const ATTR_DESC := {
	"str": "물리 직업 피해량",
	"agi": "이동 속도, 공격 속도, 치명타 확률 (로그 피해량)",
	"vit": "최대 생명력, 스태미나",
	"int": "마법 직업 피해량, 최대 마나",
	"wil": "재사용 대기시간 감소, 자원 회복",
	"fai": "치유량, 프리스트 피해량",
}

const CLASS_ORDER := ["fighter", "swordmaster", "rogue", "deathknight", "druid", "pyromancer", "cryomancer", "priest"]
const RES_NAMES := {"mana": "마나", "soul": "영혼 에너지", "primal": "암흑 에너지"}
const RES_COLORS := {"mana": Color(0.29, 0.48, 1.0), "soul": Color(0.35, 0.85, 0.45), "primal": Color(0.55, 0.3, 0.85)}

# 직업: 기본 체력/속도/자원, 장착 가능한 무기 종류, 좌·우클릭, Q/E 선택지
# weapons: sword(한손검) longsword(양손검) shield(방패) dagger(단검) mace(철퇴) staff(지팡이) orb(오브) crossbow(중석궁)
const CLASSES := {
	"fighter": {
		"id": "fighter", "name": "파이터", "icon": "🛡", "hp": 170, "speed": 5.0, "armor": 0,
		"res": "", "res_max": 0, "weapons": ["sword", "longsword", "shield", "mace", "crossbow"],
		"desc": "한손검과 방패, 또는 양손검으로 전열을 지키는 전사. 소용돌이로 다수를 상대한다.",
		"q": ["fighter_whirlwind", "fighter_warcry"], "e": ["fighter_charge", "fighter_inspire"],
		"skills": {
			"lmb": {"name": "베기", "desc": "무기 근접 공격 (연속 콤보)", "cd": 0.0},
			"rmb": {"name": "방어", "desc": "누르는 동안 정면 피해 감소 (방패 97~100%, 무기 75%)", "cd": 0.0},
		},
	},
	"swordmaster": {
		"id": "swordmaster", "name": "소드마스터", "icon": "⚔", "hp": 150, "speed": 5.3, "armor": 0,
		"res": "", "res_max": 0, "weapons": ["sword", "longsword", "shield"],
		"desc": "검 슬롯의 검으로 영검을 소환해 싸우는 검객. 패링으로 적의 공격을 받아친다.",
		"q": ["sm_psionic"], "e": ["sm_blade_dance"],
		"skills": {
			"lmb": {"name": "연속 베기", "desc": "빠르고 넓은 검 베기", "cd": 0.0},
			"rmb": {"name": "패링", "desc": "짧은 순간 모든 공격을 막고, 근접 공격자를 기절시킨다", "cd": 1.2},
		},
	},
	"rogue": {
		"id": "rogue", "name": "로그", "icon": "🗡", "hp": 130, "speed": 5.6, "armor": 0,
		"res": "", "res_max": 0, "weapons": ["dagger", "crossbow"],
		"desc": "쌍단검과 독, 은신을 쓰는 암살자. 등 뒤와 은신 상태의 일격이 치명적이다.",
		"q": ["rogue_petrify", "rogue_blades"], "e": ["rogue_stealth", "rogue_quick_conceal", "rogue_shadow_veil"],
		"skills": {
			"lmb": {"name": "찌르기", "desc": "빠른 단검 공격. 등 뒤에서 1.6배", "cd": 0.0},
			"rmb": {"name": "단검 투척", "desc": "단검을 던진다", "cd": 1.5},
		},
	},
	"deathknight": {
		"id": "deathknight", "name": "데스나이트", "icon": "💀", "hp": 175, "speed": 4.8, "armor": 0,
		"res": "soul", "res_max": 100, "weapons": ["longsword", "sword", "shield"],
		"desc": "영혼 에너지를 다루는 언데드 기사. 쓰러진 적의 영혼을 흡수하고 적을 끌어당긴다.",
		"q": ["dk_wraith_guard", "dk_soul_storm"], "e": ["dk_soul_chain"],
		"skills": {
			"lmb": {"name": "내려베기", "desc": "느리지만 강한 공격. 피해의 10% 흡혈", "cd": 0.0},
			"rmb": {"name": "방어", "desc": "누르는 동안 정면 피해 감소", "cd": 0.0},
		},
	},
	"druid": {
		"id": "druid", "name": "드루이드", "icon": "🌿", "hp": 140, "speed": 5.0, "armor": 0,
		"res": "primal", "res_max": 100, "weapons": ["staff", "orb"],
		"desc": "엘프 드루이드. 표범으로 변신해 그림자 돌격으로 추격하고 나무 정령을 불러 싸운다.",
		"q": ["druid_primal"], "e": ["druid_nature"],
		"skills": {
			"lmb": {"name": "가시 덩굴", "desc": "가시를 날린다", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
			"lmb_p": {"name": "할퀴기", "desc": "빠른 발톱 공격 (암흑 에너지 +20)", "cd": 0.0},
			"rmb_p": {"name": "포효", "desc": "주변 적을 밀어낸다", "cd": 6.0},
		},
	},
	"pyromancer": {
		"id": "pyromancer", "name": "파이로맨서", "icon": "🔥", "hp": 125, "speed": 5.0, "armor": 0,
		"res": "mana", "res_max": 120, "weapons": ["staff", "orb", "sword", "shield"],
		"desc": "추적하는 화염구와 고리 모양 화염으로 전장을 불태우는 화염 술사.",
		"q": ["pyro_pyroblast"], "e": ["pyro_fireshock"],
		"skills": {
			"lmb": {"name": "화염탄", "desc": "적을 추적하는 빠른 화염탄 (마나 6)", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
		},
	},
	"cryomancer": {
		"id": "cryomancer", "name": "크라이오맨서", "icon": "❄", "hp": 130, "speed": 5.0, "armor": 0,
		"res": "soul", "res_max": 100, "weapons": ["staff", "orb"],
		"desc": "언데드 냉기 술사. 쓰러진 적의 영혼 에너지로 눈보라와 서리의 저주를 다룬다.",
		"q": ["cryo_blizzard", "cryo_frost_curse"], "e": ["cryo_ice_armor", "cryo_ice_barrier"],
		"skills": {
			"lmb": {"name": "얼음 화살", "desc": "적중 시 둔화", "cd": 0.0},
			"rmb": {"name": "지팡이 치기", "desc": "근접 공격으로 적을 밀어낸다", "cd": 0.8},
		},
	},
	"priest": {
		"id": "priest", "name": "프리스트", "icon": "✨", "hp": 145, "speed": 5.0, "armor": 0,
		"res": "mana", "res_max": 120, "weapons": ["mace", "shield", "staff", "orb"],
		"desc": "신성한 빛으로 아군을 치유하고 보호하는 성직자. 철퇴와 방패로 직접 싸울 수도 있다.",
		"q": ["priest_revelation", "priest_heal"], "e": ["priest_holy_ward", "priest_protection"],
		"skills": {
			"lmb": {"name": "철퇴/성광", "desc": "철퇴 근접 공격 (지팡이·오브는 신성한 빛)", "cd": 0.0},
			"rmb": {"name": "방어", "desc": "방패/무기로 막기", "cd": 0.0},
		},
	},
}

# 직업별 기본 능력치와 피해량을 결정하는 능력치
const CLASS_ATTRS := {
	"fighter": {"str": 30, "agi": 18, "vit": 28, "int": 8, "wil": 14, "fai": 6},
	"swordmaster": {"str": 28, "agi": 26, "vit": 20, "int": 8, "wil": 14, "fai": 6},
	"rogue": {"str": 18, "agi": 32, "vit": 16, "int": 12, "wil": 12, "fai": 6},
	"deathknight": {"str": 30, "agi": 14, "vit": 26, "int": 14, "wil": 16, "fai": 4},
	"druid": {"str": 16, "agi": 22, "vit": 18, "int": 24, "wil": 20, "fai": 12},
	"pyromancer": {"str": 8, "agi": 18, "vit": 16, "int": 32, "wil": 22, "fai": 8},
	"cryomancer": {"str": 8, "agi": 14, "vit": 18, "int": 30, "wil": 24, "fai": 10},
	"priest": {"str": 14, "agi": 10, "vit": 22, "int": 18, "wil": 22, "fai": 32},
}
const POWER_ATTR := {
	"fighter": "str", "swordmaster": "str", "rogue": "agi", "deathknight": "str",
	"druid": "int", "pyromancer": "int", "cryomancer": "int", "priest": "fai",
}
const MAGIC_CLASSES := ["druid", "pyromancer", "cryomancer", "priest"]

# ------------------------------------------------------------------ 스킬 (Q/E 선택지, 로비/대기방에서 교체)
# req: "2h"(양손 무기), "caster"(지팡이/오브), "sword_slot"(검 슬롯에 검)
const SKILLS := {
	# 파이터
	"fighter_whirlwind": {"name": "소용돌이", "icon": "🌀", "cd": 12.0, "req": "2h",
		"desc": "파이터가 손에 든 무기를 들고 회전하며 빠르게 공격합니다. 매회 타격 시 51.12(75%)의 직접 피해를 입힙니다. (양손 무기 착용 시 사용 가능)"},
	"fighter_warcry": {"name": "광기의 포효", "icon": "😤", "cd": 25.0,
		"desc": "전투의 함성을 내뿜습니다. 30%의 공격력과 30%의 물리 저항이 증가하고 30%의 흡혈을 얻습니다. 효과는 5초 동안 유지됩니다."},
	"fighter_charge": {"name": "돌진", "icon": "💨", "cd": 9.0,
		"desc": "전방을 향해 짧은 거리를 빠르게 돌진합니다. 사용 시 진행 중이던 동작을 중단하지 않습니다."},
	"fighter_inspire": {"name": "격려", "icon": "📯", "cd": 20.0,
		"desc": "자신과 주변 동료의 사기를 높여 이동 속도를 150만큼 증가시킵니다. 효과는 3초 동안 유지됩니다."},
	# 프리스트
	"priest_revelation": {"name": "신의 계시", "icon": "🔆", "cd": 12.0, "cost": 30.0, "req": "caster",
		"desc": "성스러운 빛의 힘을 인도하여 지정한 위치에 신의 계시를 소환합니다. 잠깐의 시간이 흐른 후 범위 내 아군 대상의 HP를 89.41(50%) 치료하고, 적에게 49.78(75%)의 신성 직접 피해를 입힙니다. (스태프/오브 착용 시 사용 가능)"},
	"priest_heal": {"name": "치료", "icon": "➕", "cd": 1.5, "cost": 20.0, "req": "caster",
		"desc": "성스러운 빛의 힘을 인도하여 아군 대상의 HP를 53.64(30%)만큼 치료합니다. [F]로 자신을 치료할 수 있습니다. 오랫동안 시전하면 효과가 143.05(80%)만큼 강화됩니다. (스태프/오브 착용 시 사용 가능)"},
	"priest_holy_ward": {"name": "성스러운 가호", "icon": "👼", "cd": 30.0, "cost": 30.0,
		"desc": "아군 대상에게 '성스러운 보호막'을 부여하여 3초 동안 모든 피해로부터 면역되게 합니다. [F]로 자신에게 보호막을 부여합니다."},
	"priest_protection": {"name": "수호", "icon": "🔰", "cd": 30.0, "cost": 40.0, "req": "caster",
		"desc": "자신과 주변의 동료들에게 133.85(75%)의 실드를 부여하며, 60초 유지됩니다. (스태프/오브 착용 시 사용 가능)"},
	# 파이로맨서
	"pyro_pyroblast": {"name": "화염 폭발", "icon": "☄", "cd": 2.0, "cost": 15.0, "req": "caster",
		"desc": "최대 2단계까지 응축할 수 있습니다. 1단계: 대상을 추적하는 화염구 3발을 발사하여 각각 45.70(60%) 화염 직접 피해. 2단계: 큰 화염구가 충돌한 지점 주변에 불길이 뻗어나가며 182.82(240%)의 화염 직접 피해 (2단계는 마나 35). (스태프/오브 착용 시 사용 가능)"},
	"pyro_fireshock": {"name": "화염 충격", "icon": "💥", "cd": 12.0, "cost": 25.0,
		"desc": "고리 모양의 화염을 발사하여 주변의 적을 밀쳐내고 48.82의 화염 직접 피해를 입힌 후 1초 동안 85% 둔화. 사용 시 진행 중이던 동작을 중단하지 않습니다."},
	# 로그
	"rogue_petrify": {"name": "석화 중독", "icon": "🧪", "cd": 18.0,
		"desc": "근거리 또는 원거리 무기에 독을 바릅니다. 다음 공격이 명중하면 대상이 '석화'됩니다. '석화'된 상태에서는 움직일 수 없고 받는 피해가 100% 감소합니다. 공격을 받으면 해제됩니다."},
	"rogue_blades": {"name": "칼날 뿌리기", "icon": "🔪", "cd": 12.0,
		"desc": "전방의 여러 적에게 6자루의 단검을 던져 8.60(20%)의 직접 피해를 입히고 3초 70%의 둔화 효과를 부여합니다."},
	"rogue_stealth": {"name": "은신", "icon": "👤", "cd": 30.0,
		"desc": "3초의 준비 후 '은신' 상태로 진입합니다. 지속 시간 30초. 은신 상태에서는 치명타 피해가 증가합니다."},
	"rogue_quick_conceal": {"name": "신속한 은폐", "icon": "🌫", "cd": 25.0,
		"desc": "즉시 '은신' 상태로 진입합니다. 지속 시간 6초. 은신 상태에서는 치명타 피해가 증가합니다."},
	"rogue_shadow_veil": {"name": "어둠의 장막", "icon": "🌑", "cd": 40.0,
		"desc": "3초의 준비 후 주변의 인간 형태 아군에게 '은신' 상태를 부여합니다. 지속 시간 15초. '은신' 상태에서는 로그의 치명타 피해가 증가합니다."},
	# 데스나이트
	"dk_wraith_guard": {"name": "악령의 보호", "icon": "👻", "cd": 16.0, "cost": 30.0,
		"desc": "악령을 소환하여 자신을 주위를 감쌉니다. 발동 시 주위의 모든 적에게 1초 동안 25% 둔화, 이후 일정 시간 동안 주변 적들에게 27.20의 암흑 간접 피해. 스킬이 발동하는 동안 받는 피해가 15% 감소합니다."},
	"dk_soul_storm": {"name": "영혼폭풍", "icon": "🌪", "cd": 3.0, "cost": 10.0,
		"desc": "영혼 에너지를 방출하여 주위의 적에게 지속적으로 13.60의 암흑 간접 피해를 입힙니다. 시전 중에는 지속적으로 영혼 에너지가 소모되며, 언제든지 시전을 중지할 수 있습니다(다시 누르기). 받는 피해가 15% 감소합니다."},
	"dk_soul_chain": {"name": "영혼의 족쇄", "icon": "⛓", "cd": 12.0,
		"desc": "대상에게 영혼 족쇄를 발사하여 73.38(100%)의 암흑 직접 피해를 입히고 대상을 가까이 끌어당깁니다. 아군 대상은 이 피해를 받지 않습니다. 적을 명중 시 소량의 영혼 에너지를 회복합니다."},
	# 크라이오맨서
	"cryo_blizzard": {"name": "눈보라", "icon": "🌨", "cd": 14.0, "cost": 30.0, "req": "caster",
		"desc": "작은 얼음 폭풍을 유도하여 조준 지점으로 이동시킵니다. 이동 중에는 적에게 6.55(8%) 간접 피해와 40% 둔화. 채널링이 끝나면 제자리에서 눈보라를 펼쳐 9.83(12%)의 직접 피해를 입히고 80% 둔화. (스태프/오브 착용 시 사용 가능)"},
	"cryo_frost_curse": {"name": "서리의 저주", "icon": "❄", "cd": 8.0, "cost": 15.0, "req": "caster",
		"desc": "대상에게 24.56(30%)의 직접 피해와 1초 60% 둔화. 서리 저주를 걸어 10초 동안 매초 10.32의 지속 피해를 입히고, 시전자는 매초 6.55의 생명력을 회복합니다. 동일 대상에게 최대 1중첩. (스태프/오브 착용 시 사용 가능)"},
	"cryo_ice_armor": {"name": "아이스 아머", "icon": "🧊", "cd": 30.0, "cost": 25.0, "req": "caster",
		"desc": "아군 대상에게 60초 동안 지속되는 150.63(90%) 실드. 근접 공격으로 인한 피해를 받을 때 공격자에게 2초 60% 둔화 (1회). [F]로 자신에게 부여. (스태프/오브 착용 시 사용 가능)"},
	"cryo_ice_barrier": {"name": "얼음 베리어", "icon": "🔷", "cd": 45.0,
		"desc": "얼음 베리어에 자신을 8초 동안 봉인합니다. 이 시간 동안 피해를 입지 않고 초당 2.61%의 HP를 회복합니다. 다시 누르면 언제든지 해제할 수 있습니다."},
	# 소드마스터
	"sm_psionic": {"name": "심령의 검", "icon": "🗡", "cd": 8.0, "req": "sword_slot",
		"desc": "검 슬롯에서 최대 4자루의 영검을 소환하여 적을 추적해 62.75(80%)의 직접 피해를 입히며, 쿨타임은 검의 수에 따라 결정됩니다. 희귀 이상 품질을 사용하면 영검이 입히는 피해가 상승합니다."},
	"sm_blade_dance": {"name": "검날의 춤", "icon": "⚔", "cd": 20.0, "req": "sword_slot",
		"desc": "검 슬롯에서 1자루의 영검을 소환하여 8초 동안 자신의 주위를 맴돌며 주위의 적을 공격하게 합니다. 공격이 적에게 명중할 때마다 35.30(45%)의 간접 피해."},
	# 드루이드
	"druid_primal": {"name": "야성의 각성", "icon": "🐆", "cd": 2.0,
		"desc": "표범의 모습으로 변신합니다(임의의 무기 착용 필요). 변신 시 모든 디버프가 제거되며 변신 기간 동안 '자연의 힘'이 '그림자 돌격'으로 대체됩니다. 표범의 일반 공격과 그림자 돌격이 적에게 피해를 입힐 시 20의 암흑 에너지가 회복됩니다. 다시 사용 시 인간의 모습으로 돌아갑니다."},
	"druid_nature": {"name": "자연의 힘", "icon": "🌳", "cd": 1.0, "charges": 1, "recharge": 60.0, "req": "caster",
		"desc": "지정된 위치에 나무 정령을 소환하고 30초 동안 머무르게 합니다. 나무 정령은 주변의 적을 공격하여 98.37(165%) 피해를 주며 드루이드에게 실드를 시전합니다. 시전 시 소량의 암흑 에너지를 회복합니다. (스태프/오브 착용 시 사용 가능)"},
	"druid_shadow_assault": {"name": "그림자 돌격", "icon": "🌑", "cd": 6.0, "cost": 25.0,
		"desc": "어둠의 에너지를 소모하여 앞으로 돌진하며, 착지 시 주변에 74.43(115%)의 어둠 직접 피해를 입힙니다."},
}

# ------------------------------------------------------------------ 패시브 (능력치 조건을 채우면 자동 활성, 5개 모두 사용)
# fx 키는 skills.gd/player.gd 에서 효과로 처리
const PASSIVES := {
	"fighter": [
		{"name": "힘줄 절단", "req": {"str": 50}, "desc": "'광기의 포효' 사용 중 무기를 통해 적을 명중하면 20% 감소(둔화)를 부여합니다.", "fx": "hamstring"},
		{"name": "흥분", "req": {"str": 87}, "desc": "적 유저를 처치하면 '격려'의 쿨타임이 초기화됩니다.", "fx": "excite"},
		{"name": "방어 반격", "req": {"agi": 33}, "desc": "블로킹 성공 시 다음 공격이 반드시 명중(치명타)합니다.", "fx": "counter"},
		{"name": "무기 마스터", "req": {"vit": 42}, "desc": "'광기의 포효' 시전 시 200의 실드를 획득합니다.", "fx": "weapon_master"},
		{"name": "신중", "req": {"wil": 27}, "desc": "아군 파티원을 공격해도 피해를 주지 않으며, 파티원으로부터 피해를 받지 않는다.", "fx": "careful"},
	],
	"priest": [
		{"name": "신념", "req": {"vit": 30}, "desc": "치명타 시 5의 MP를 회복합니다.", "fx": "faith_mp"},
		{"name": "부응", "req": {"wil": 36}, "desc": "'수호' 시전 시 아군 대상 여러 명을 동시에 보호할 때, 해당 대상의 이동 속도가 1초 동안 100 증가합니다.", "fx": "answer"},
		{"name": "성자", "req": {"int": 48}, "desc": "'수호'는 사용 횟수 2회까지 저장할 수 있습니다.", "fx": "saint"},
		{"name": "세례", "req": {"fai": 38}, "desc": "'수호' 시전 시 아군의 모든 디버프 효과를 정화하며, 2초 동안 모든 디버프 효과에 면역이 됩니다.", "fx": "baptism"},
		{"name": "부활", "req": {"fai": 75}, "desc": "사망한 동료에게 '치료'를 시전하면 부활합니다. 모험 도중 단 1회만 사용할 수 있습니다.", "fx": "resurrect"},
	],
	"pyromancer": [
		{"name": "급속 시전", "req": {"agi": 30}, "desc": "'화염 충격'으로 적을 명중한 뒤 10초간 '급속 시전'. 다음 '화염 폭발'의 채널링 시간이 절반으로 감소합니다.", "fx": "quick_cast"},
		{"name": "화염 부활", "req": {"vit": 24}, "desc": "'화염 충격' 사용 시 HP 50을 회복하며, 상대 하나를 명중할 때마다 추가로 50 회복 (최대 200).", "fx": "fire_heal"},
		{"name": "발화", "req": {"int": 50}, "desc": "'화염 폭발' 2단계와 '화염 충격'이 5중첩의 '연소'를 부여합니다. '연소'는 2초마다 1중첩을 지우며 10의 화염 피해.", "fx": "ignite"},
		{"name": "불의 눈", "req": {"int": 87}, "desc": "'화염 폭발' 사용 시 불씨가 '불의 눈'이 되어 자신을 보호하며 주위의 적을 공격해 3중첩 '연소'를 부여합니다.", "fx": "fire_eye"},
		{"name": "화환 갱신", "req": {"wil": 42}, "desc": "적 플레이어 처치 시 '화염 충격'의 쿨타임이 초기화됩니다.", "fx": "wreath"},
	],
	"rogue": [
		{"name": "숨겨진 독", "req": {"str": 29}, "desc": "'은신' 상태에서 블로킹되지 않은 공격을 가하면 0.5초마다 25의 '중독' 피해 (3초).", "fx": "hidden_poison"},
		{"name": "잠복", "req": {"str": 60}, "desc": "'은신' 상태에서 50% 흡혈 효과를 얻으며, '은신'이 해제된 후에는 사라집니다.", "fx": "ambush"},
		{"name": "암살", "req": {"agi": 62}, "desc": "적을 처치한 후 '은신' 상태가 됩니다.", "fx": "assassinate"},
		{"name": "페더 스텝", "req": {"agi": 93}, "desc": "'은신' 상태에 들어서면 이동 속도가 200 증가하고 5초 동안 천천히 감소합니다.", "fx": "feather"},
		{"name": "무형의 독", "req": {"vit": 36}, "desc": "'칼날 뿌리기' 시전 후 '은신' 상태에 들어갑니다.", "fx": "formless"},
	],
	"deathknight": [
		{"name": "영혼 채집", "req": {"str": 54}, "desc": "'영혼의 족쇄'가 적 대상에게 명중하면 20의 영혼 에너지를 회복합니다.", "fx": "soul_harvest"},
		{"name": "쇠퇴", "req": {"agi": 33}, "desc": "'영혼폭풍'의 영향을 받은 적은 이동 속도가 15% 감소합니다 (0.5초).", "fx": "decay"},
		{"name": "영혼 방패", "req": {"vit": 39}, "desc": "'영혼폭풍' 시전 시 200의 실드가 3초 동안 부여됩니다. 시전 간격 30초.", "fx": "soul_shield"},
		{"name": "생명 흡수", "req": {"wil": 24}, "desc": "영혼 에너지볼 1개를 흡수할 때마다 14의 HP를 회복합니다.", "fx": "life_drain"},
		{"name": "사신", "req": {"int": 42}, "desc": "적 플레이어 처치 시 '영혼의 족쇄'의 쿨타임을 초기화합니다.", "fx": "reaper"},
	],
	"cryomancer": [
		{"name": "끝없는 한기", "req": {"agi": 31}, "desc": "상대에 치명타 피해를 입히면 영혼 에너지 1을 회복합니다.", "fx": "endless_chill"},
		{"name": "서리의 메아리", "req": {"vit": 33}, "desc": "아군이 '눈보라'의 영향을 받은 상대에게 블로킹 없이 피해를 입히면 40점의 영구 실드를 획득합니다 (중복 안 됨).", "fx": "frost_echo"},
		{"name": "혹한의 추위", "req": {"int": 59}, "desc": "'서리의 저주'의 첫 번째 단계에서 입히는 피해가 50% 증가합니다.", "fx": "bitter_cold"},
		{"name": "극한의 추위", "req": {"wil": 49}, "desc": "대상과의 거리가 15m를 넘으면 '서리의 저주' 피해가 증가하며, 25m에서 최대 30%.", "fx": "extreme_cold"},
		{"name": "서리 비늘", "req": {"fai": 24}, "desc": "냉기 피해를 입힐 때 '서리 비늘'을 얻고, 다음 '아이스 아머'가 중첩당 0.5의 실드를 추가합니다.", "fx": "frost_scale"},
	],
	"swordmaster": [
		{"name": "치유의 검집", "req": {"str": 54}, "desc": "'심령의 검'이 블로킹되지 않은 직접 공격을 가하면 30의 HP를 회복합니다.", "fx": "healing_sheath"},
		{"name": "승리의 추격", "req": {"agi": 35}, "desc": "'심령의 검'이 적을 명중한 뒤 5초 동안 치명타 확률이 50% 증가합니다.", "fx": "pursuit"},
		{"name": "발 저지", "req": {"agi": 72}, "desc": "'심령의 검'이 치명타를 발생시키면 적의 이동 속도가 5초 동안 60 감소합니다.", "fx": "hobble"},
		{"name": "회피", "req": {"vit": 36}, "desc": "'검날의 춤' 지속 시간 동안 받는 모든 피해가 50% 감소합니다.", "fx": "evasion"},
		{"name": "칼날 벼락", "req": {"wil": 27}, "desc": "동시에 3, 4개의 '심령의 검'을 발사하면 쿨타임이 각각 10, 15초로 감소합니다.", "fx": "blade_storm"},
	],
	"druid": [
		{"name": "사냥꾼의 감각", "req": {"agi": 36}, "desc": "표범 형태일 때 반경 30미터 내의 적 플레이어를 감지할 수 있습니다.", "fx": "hunter_sense"},
		{"name": "자연의 숨결", "req": {"vit": 27}, "desc": "'자연의 힘' 나무 정령이 소환될 때 150 실드를 얻습니다.", "fx": "nature_breath"},
		{"name": "자연의 민첩함", "req": {"int": 44}, "desc": "'자연의 힘'의 에너지 충전 시간이 30초로 감소합니다.", "fx": "nature_agility"},
		{"name": "사냥감 조준", "req": {"int": 81}, "desc": "'그림자 돌격'으로 적에게 피해를 입히면 암흑 에너지 20 회복.", "fx": "prey_aim"},
		{"name": "자연의 씨앗", "req": {"wil": 45}, "desc": "'자연의 힘' 사용 기회를 1회 추가 비축할 수 있습니다.", "fx": "nature_seed"},
	],
}

# ------------------------------------------------------------------ 장비 칸 (던전본 인벤토리 배치)
# w1/w1o: 무기 세트 1 (주무기/보조, 1키), w2/w2o: 세트 2 (2키), c3/c4/c5: 소모품 칸 (3/4/5키, 각 최대 3개), torch: 횃불 칸 (G키), sw1~sw4: 소드마스터 검 슬롯
const GEAR_SLOTS := ["w1", "w1o", "w2", "w2o", "head", "chest", "necklace", "ring1", "legs", "ring2", "hands", "feet"]
const QUICK_SLOTS := ["c3", "c4", "c5"]
const UTIL_SLOTS := ["c3", "c4", "c5", "torch"]
const SWORD_SLOTS := ["sw1", "sw2", "sw3", "sw4"]
const ALL_SLOTS := GEAR_SLOTS + UTIL_SLOTS + SWORD_SLOTS
const SLOT_NAMES := {
	"w1": "세트 1", "w1o": "세트 1 보조", "w2": "세트 2", "w2o": "세트 2 보조",
	"head": "머리", "chest": "상의", "hands": "장갑", "legs": "하의", "feet": "신발",
	"necklace": "목걸이", "ring1": "반지", "ring2": "반지", "ring": "반지",
	"c3": "3", "c4": "4", "c5": "5", "torch": "횃불",
	"sw1": "검 슬롯", "sw2": "검 슬롯", "sw3": "검 슬롯", "sw4": "검 슬롯",
}
const WEAPON_NAMES := {
	"sword": "한손검", "longsword": "양손검", "shield": "방패", "dagger": "단검", "mace": "철퇴",
	"staff": "지팡이", "orb": "오브", "crossbow": "중석궁",
}
const TWO_HANDED := ["longsword", "staff", "crossbow"]
const OFFHAND := ["shield", "orb"]
const ARMOR_TYPES := {"plate": "판금", "leather": "가죽", "cloth": "천"}
const DMG_TYPES := {"phys": "물리", "holy": "신성", "fire": "화염", "shadow": "암흑", "lightning": "번개", "cold": "냉기"}

# 무기 종류별 기준 공격력 (일반 등급 기본 무기) -> 아이템 공격력 / 기준 = 무기 배율
const WEAPON_REF := {"sword": 110.0, "longsword": 145.0, "dagger": 80.0, "mace": 110.0, "staff": 120.0, "orb": 120.0, "crossbow": 140.0, "shield": 110.0}

# ------------------------------------------------------------------ 수치 옵션
# 고정 옵션/무작위 옵션 공용 키
const MOD_FMT := {
	"str": "+%d 힘", "agi": "+%d 민첩", "vit": "+%d 기력", "int": "+%d 지능", "wil": "+%d 의지", "fai": "+%d 신념", "all": "+%d 모든 능력치",
	"pdmg": "+%.1f%% 물리 피해", "edmg": "+%.1f%% 모든 원소 피해", "dmg": "+%.1f%% 피해", "wdmg": "+%.1f%% 무기 피해",
	"cdmg": "+%.1f%% 치명타 피해", "crit": "+%.1f%% 치명타 확률", "hp": "+%.1f 최대 생명력", "pres": "+%.1f%% 물리 저항",
	"mres": "+%.1f%% 마법 저항", "ms": "%+d 이동 속도", "act": "+%.1f%% 공격 속도", "lifesteal": "+%.1f%% 생명력 흡수",
	"regen_ooc": "비전투 시 생명력 재생 %d", "life_on_kill": "처치 시 생명력 %d 회복", "crit_full": "+%.1f%% 생명력이 가득할 때 치명타 확률",
	"crit_ooc": "+%.1f%% 비전투 시 치명타 확률", "ls_ooc": "+%.1f%% 비전투 시 생명력 흡수", "ms_ooc": "%+d 비전투 시 이동 속도",
	"lightning_add": "공격에 번개 피해 +%d", "cold_add": "공격에 냉기 피해 +%d", "cdr": "+%.1f%% 재사용 대기시간 감소",
	"armor": "+%d 방어도", "set": "%s +%d",
}
# 무작위 옵션 풀 (공격/방어). 등급: Ω(강) Φ(중) Δ(약)
const MOD_POOL := {
	"off": ["str", "agi", "int", "pdmg", "edmg", "crit", "cdmg", "act", "lifesteal", "wdmg"],
	"def": ["vit", "wil", "fai", "hp", "pres", "mres", "ms", "armor", "regen_ooc"],
}
const MOD_TIERS := {
	# 키: [Δ, Φ, Ω] 각 [최소, 최대]
	"attr": [[1, 3], [3, 5], [5, 7]],
	"pct": [[2.0, 4.0], [4.0, 6.0], [6.0, 8.0]],
	"hp": [[5.0, 9.0], [10.0, 14.0], [15.0, 20.0]],
	"ms": [[2, 4], [5, 7], [8, 10]],
	"armor": [[3, 5], [6, 9], [10, 14]],
	"regen_ooc": [[1, 1], [1, 2], [2, 3]],
}
const TIER_NAMES := ["Δ", "Φ", "Ω"]

# 장비 세트 효과 (각 장비에 포인트가 붙고 합계로 발동)
const SET_PERKS := {
	"midas": {"name": "미다스의 손", "max": 3, "tiers": [[3, "대상 처치 시 30 코인 획득"], [6, "상자를 처음 열 때 60 코인 획득"], [9, "탈출 성공 시 1800 코인 획득"]]},
	"dragon": {"name": "용비늘", "max": 6, "tiers": [[10, "피격 시 받는 피해 50% 감소 (60초마다)"], [20, "감소 효과가 3회 또는 3초 동안 지속"]]},
	"alchemist": {"name": "술 취한 연금술사", "max": 3, "tiers": [[8, "비전투 상태에서 적 유저에게 피해 시 무작위 물약 효과 (30초마다)"]]},
	"faery": {"name": "호수의 요정", "max": 3, "tiers": [[10, "피해 시 요정이 추격해 폭발: 50 신성 피해 + 주변 아군 50 실드"], [20, "피해·실드 2배"], [30, "요정 속도 증가, 귀환 시 자신 주변에도 효과"]]},
	"trinity": {"name": "삼위일체의 힘", "max": 5, "tiers": [[10, "3초 안에 3회 직접 피해 시 주변 적에게 100 물리 피해"], [20, "범위 대상 5초간 20% 취약"], [30, "범위 대상 80% 둔화 (5초간 감소)"]]},
	"pity": {"name": "죽음의 연민", "max": 4, "tiers": [[6, "치명상을 입어도 죽지 않고 HP가 70이 됨 (1회)"], [12, "120초마다 여러 번 발동"]]},
	"storm": {"name": "폭풍의 분노", "max": 3, "tiers": [[10, "이동으로 충전, 100 충전 시 피해에 연쇄 번개 + 0.75초 75% 둔화"], [15, "발동 시 1초간 이동 속도 40%"], [30, "연쇄 번개 3대상, 튕길 때마다 200 번개 피해"]]},
	"chain": {"name": "얽히는 사슬", "max": 6, "tiers": [[10, "적 유저 4m 안에 3초 머문 뒤 피해 시 100 실드 3초 (15초마다)"], [15, "발동 시 3초간 이동 속도 +90"], [30, "발동 시 3초간 초당 70 생명력 재생"]]},
	"torment": {"name": "작은 고문", "max": 3, "tiers": [[6, "피해 시 대상이 0.5초마다 5 고정 피해 (5초, 15초마다)"]]},
}

# ------------------------------------------------------------------ 아이템
var ITEM_BASES: Dictionary = {}

const STARTER_WEAPON := {
	"fighter": "old_sword", "swordmaster": "old_sword", "rogue": "old_dagger", "deathknight": "old_longsword",
	"druid": "old_staff", "pyromancer": "old_staff", "cryomancer": "old_staff", "priest": "old_mace",
}
const STARTER_OFFHAND := {"fighter": "old_shield", "swordmaster": "", "rogue": "old_dagger", "deathknight": "", "druid": "", "pyromancer": "", "cryomancer": "", "priest": "old_shield"}
const STARTER_ARMOR := {
	"fighter": "plate", "swordmaster": "leather", "rogue": "leather", "deathknight": "plate",
	"druid": "leather", "pyromancer": "cloth", "cryomancer": "cloth", "priest": "cloth",
}

# 이전 버전 세이브 변환용
const LEGACY_CLASS := {"ranger": "rogue", "mage": "pyromancer"}
const LEGACY_ITEM := {
	"mana_potion": "health_potion",
	"throwing_knife": "fire_flask",
	"short_bow": "old_dagger", "hunting_bow": "steel_dagger", "long_bow": "exquisite_dagger", "elven_bow": "finely_blade",
	"rusty_sword": "old_sword", "arming_sword": "traveler_sword", "war_axe": "soldier_sword", "zweihander": "soldier_longsword",
	"training_longsword": "old_sword", "katana": "finely_sword", "rusty_dagger": "old_dagger", "twin_daggers": "steel_dagger",
	"venom_dagger": "exquisite_dagger", "shadow_dagger": "finely_blade", "rusty_greatsword": "old_longsword", "reaper_scythe": "soldier_longsword",
	"oak_staff": "old_staff", "crystal_staff": "pyro_staff", "living_staff": "searing_staff", "spellbook": "grandmaster_orb",
	"archmage_staff": "sunblight_staff", "iron_mace": "old_mace", "holy_mace": "pernach", "sun_mace": "pernach_order",
	"leather_cap": "wanderer_mask", "iron_helm": "traveler_helmet", "great_helm": "soldier_bascinet", "wizard_hat": "villager_mask",
	"padded_tunic": "villager_vest", "chain_mail": "traveler_armor", "plate_armor": "soldier_armor", "ranger_coat": "wanderer_vest",
	"arcane_robe": "apprentice_vest", "leather_gloves": "wanderer_mitts", "chain_gauntlets": "traveler_gauntlets",
	"plate_gauntlets": "soldier_gauntlets", "cloth_pants": "villager_hose", "leather_leggings": "wanderer_hose",
	"plate_greaves": "traveler_chausses", "leather_boots": "wanderer_shoes", "chain_boots": "traveler_boots", "plate_sabatons": "soldier_boots",
}


func _ready() -> void:
	_build_items()


func _add(id: String, d: Dictionary) -> void:
	d["id"] = id
	ITEM_BASES[id] = d


# 위키 표를 그대로 옮긴 장비 목록
func _build_items() -> void:
	ITEM_BASES = {}
	# ---- 방어구: [이름 3단계(고급/희귀/영웅)], 슬롯, 고정 옵션
	var hp_mod := ["hp", 12.8, 16.0]
	var armor := {
		"plate": {
			"head": [["traveler_helmet", "여행자의 투구"], ["soldier_bascinet", "병사의 바서넷"], ["knight_bascinet", "기사의 바서넷"], [["pdmg", 8.0, 10.0], hp_mod], "⛑"],
			"chest": [["traveler_armor", "여행자의 갑옷"], ["soldier_armor", "병사의 갑옷"], ["knight_armor", "기사의 갑옷"], [["pdmg", 8.0, 10.0], hp_mod], "🛡"],
			"hands": [["traveler_gauntlets", "여행자의 건틀릿"], ["soldier_gauntlets", "병사의 건틀릿"], ["knight_gauntlets", "기사의 건틀릿"], [["dmg", 8.0, 10.0], hp_mod], "🧤"],
			"legs": [["traveler_chausses", "여행자의 쇼스"], ["soldier_chausses", "병사의 쇼스"], ["knight_chausses", "기사의 쇼스"], [["pres", 8.0, 10.0], hp_mod], "👖"],
			"feet": [["traveler_boots", "여행자의 장화"], ["soldier_boots", "병사의 장화"], ["knight_boots", "기사의 장화"], [["dmg", 8.0, 10.0], hp_mod], "🥾"],
		},
		"leather": {
			"head": [["wanderer_mask", "방랑자의 가면"], ["bandit_hood", "도적의 두건"], ["assassin_hood", "암살자의 두건"], [["cdmg", 9.6, 12.0], hp_mod], "🎭"],
			"chest": [["wanderer_vest", "방랑자의 조끼"], ["bandit_vest", "도적의 조끼"], ["assassin_vest", "암살자의 조끼"], [["cdmg", 9.6, 12.0], hp_mod], "🦺"],
			"hands": [["wanderer_mitts", "방랑자의 장갑"], ["bandit_mitts", "도적의 장갑"], ["assassin_mitts", "암살자의 장갑"], [["wdmg", 16.0, 20.0], hp_mod], "🧤"],
			"legs": [["wanderer_hose", "방랑자의 바지"], ["bandit_hose", "도적의 바지"], ["assassin_hose", "암살자의 바지"], [["pres", 8.0, 10.0], hp_mod], "👖"],
			"feet": [["wanderer_shoes", "방랑자의 신발"], ["bandit_shoes", "도적의 신발"], ["assassin_shoes", "암살자의 신발"], [["ms", 12, 15], ["pdmg", 8.0, 10.0]], "👞"],
		},
		"cloth": {
			"head": [["villager_mask", "마을 사람의 가면"], ["apprentice_hood", "견습생의 두건"], ["hood_of_faith", "신앙의 두건"], [["edmg", 8.0, 10.0], hp_mod], "🧙"],
			"chest": [["villager_vest", "마을 사람의 조끼"], ["apprentice_vest", "견습생의 조끼"], ["devout_vest", "독실한 자의 조끼"], [["edmg", 8.0, 10.0], ["pres", 8.0, 10.0]], "👘"],
			"hands": [["villager_mitts", "마을 사람의 장갑"], ["apprentice_mitts", "견습생의 장갑"], ["devout_mitts", "독실한 자의 장갑"], [["dmg", 8.0, 10.0], hp_mod], "🧤"],
			"legs": [["villager_hose", "마을 사람의 바지"], ["apprentice_hose", "견습생의 바지"], ["devout_hose", "독실한 자의 바지"], [["pres", 8.0, 10.0], hp_mod], "👖"],
			"feet": [["villager_shoes", "마을 사람의 신발"], ["apprentice_shoes", "견습생의 신발"], ["devout_shoes", "독실한 자의 신발"], [["dmg", 8.0, 10.0], ["crit", 25.6, 32.0]], "🥿"],
		},
	}
	# 부위별 기본 방어도 (Defense Level 1당) - 판금 > 가죽 > 천
	var arm_per := {"head": 6, "chest": 10, "legs": 8, "hands": 0, "feet": 0}
	var type_mul := {"plate": 1.0, "leather": 0.7, "cloth": 0.45}
	var sizes := {"head": [2, 2], "chest": [2, 3], "hands": [2, 2], "legs": [2, 3], "feet": [2, 2]}
	var plate_ms := {"head": -3, "chest": -8, "legs": -5, "hands": 0, "feet": -2}
	for t in armor:
		for slot in armor[t]:
			var row: Array = armor[t][slot]
			var fixed: Array = row[3]
			var defensive = slot in ["head", "chest", "legs"]
			var gear_mods := [["random_midas"], ["random", "def:3"], ["random", "def:3", "def:2"]]
			if not defensive:
				gear_mods = [["random_midas"], ["random", "off:3"], ["random", "off:3", "off:2"]]
			if slot == "feet":
				gear_mods = [["random_midas"], ["random", "any:2"], ["random", "any:2", "off:o"]]
			# 일반 등급 (기본 지급): 고정 옵션 없음
			var old_names := {"plate": "낡은 판금 ", "leather": "낡은 가죽 ", "cloth": "낡은 천 "}
			var slot_word := {"head": "투구", "chest": "상의", "hands": "장갑", "legs": "하의", "feet": "신발"}
			_add("old_%s_%s" % [t, slot], {
				"name": old_names[t] + slot_word[slot], "slot": slot, "cat": t, "rarity": 0, "lvl": 1, "icon": row[4], "size": sizes[slot],
				"armor": int(arm_per[slot] * type_mul[t] * 1), "ms": plate_ms[slot] if t == "plate" else 0, "fixed": [], "mods": [], "value": 8,
			})
			for i in 3:
				var nm: Array = row[i]
				_add(nm[0], {
					"name": nm[1], "slot": slot, "cat": t, "rarity": i + 1, "lvl": i + 2, "icon": row[4], "size": sizes[slot],
					"armor": int(arm_per[slot] * type_mul[t] * (i + 2)), "ms": plate_ms[slot] if t == "plate" else 0,
					"fixed": fixed, "mods": gear_mods[i], "value": [20, 45, 90][i],
				})
	# ---- 무기 (위키 무기 표)
	var W := func(id: String, name: String, cat: String, rar: int, lvl: int, dmg: Array, dtype: String, fixed: Array, mods: Array, value: int, unique := "", ufx := ""):
		var b := {"name": name, "slot": "weapon", "cat": cat, "rarity": rar, "lvl": lvl, "dmg": dmg, "dtype": dtype, "fixed": fixed,
			"mods": mods, "value": value, "icon": _weapon_icon(cat), "size": _weapon_size(cat), "model": _weapon_model(cat)}
		if unique != "":
			b["unique"] = unique
			b["ufx"] = ufx
		_add(id, b)
	var common := []
	var mods_u := ["off_or_spec_midas"]
	var mods_m := ["off_or_spec", "off:3"]
	var mods_e := ["off_or_spec", "off:3"]
	var mods_l := ["off_or_spec", "off:2"]
	# 일반 등급 기본 무기 (직업별 지급용)
	W.call("old_sword", "낡은 검", "sword", 0, 1, [110, 110], "phys", [], common, 6)
	W.call("old_longsword", "낡은 장검", "longsword", 0, 1, [145, 145], "phys", [], common, 6)
	W.call("old_dagger", "낡은 단검", "dagger", 0, 1, [80, 80], "phys", [], common, 6)
	W.call("old_mace", "낡은 철퇴", "mace", 0, 1, [110, 110], "phys", [], common, 6)
	W.call("old_staff", "낡은 지팡이", "staff", 0, 1, [120, 120], "phys", [], common, 6)
	W.call("old_shield", "낡은 방패", "shield", 0, 1, [0, 0], "phys", [], common, 6)
	W.call("old_crossbow", "낡은 석궁", "crossbow", 0, 1, [140, 140], "phys", [], common, 6)
	# 한손검
	W.call("traveler_sword", "여행자의 검", "sword", 1, 2, [123, 123], "phys", [["agi", 4, 6], ["crit", 16.0, 20.0]], mods_u, 25)
	W.call("soldier_sword", "병사의 검", "sword", 2, 3, [124, 124], "phys", [["agi", 5, 7], ["crit", 16.7, 20.8]], mods_m, 50)
	W.call("finely_sword", "정교한 검", "sword", 3, 4, [124, 137], "phys", [["agi", 4, 7], ["crit", 17.6, 22.0], ["regen_ooc", 1, 1]], mods_e, 100)
	W.call("knight_sword", "기사의 검", "sword", 3, 4, [124, 137], "shadow", [["int", 6, 7], ["crit", 17.6, 22.0], ["life_on_kill", 16, 18]], mods_e, 100)
	W.call("white_star_sword", "백성 기사의 검", "sword", 4, 5, [142, 142], "phys", [["all", 2, 2], ["agi", 6, 7], ["crit", 17.6, 22.0]], mods_l, 300,
		"근접 공격이 대상을 명중하면 잠시 생명력 흡수 중첩을 얻습니다 (최대 10중첩).", "lifesteal_stack")
	W.call("high_elf_sword", "하이 엘프 수호자의 검", "sword", 4, 5, [142, 142], "fire", [["all", 2, 2], ["agi", 6, 7], ["crit", 17.6, 22.0]], mods_l, 300,
		"근접 공격이 명중하면 3초에 걸쳐 감소하는 150 이동 속도를 얻습니다 (8초 재사용).", "elf_speed")
	W.call("sacred_grove_relic", "성스러운 숲의 유물", "sword", 4, 6, [126, 128], "phys", [["all", 2, 2], ["agi", 4, 6], ["crit", 12.8, 16.0]], mods_l, 400,
		"근접 공격이 명중하면 대상을 80%, 자신을 60% 둔화시킵니다.", "grove_slow")
	# 양손검
	W.call("traveler_longsword", "여행자의 장검", "longsword", 1, 2, [159, 159], "phys", [["str", 8, 12], ["dmg", 8.0, 10.0]], mods_u, 30)
	W.call("soldier_longsword", "병사의 장검", "longsword", 2, 3, [161, 161], "phys", [["str", 10, 14], ["dmg", 8.4, 10.4]], mods_m, 60)
	W.call("finely_longsword", "정교한 장검", "longsword", 3, 4, [161, 178], "phys", [["str", 12, 14], ["dmg", 8.8, 11.0], ["regen_ooc", 2, 2]], mods_e, 120)
	W.call("knight_longsword", "기사의 장검", "longsword", 3, 4, [161, 178], "phys", [["agi", 12, 14], ["dmg", 8.8, 11.0], ["life_on_kill", 32, 36]], mods_e, 120)
	W.call("the_17th_key", "17번째 열쇠", "longsword", 4, 5, [184, 184], "phys", [["all", 4, 4], ["str", 12, 14], ["dmg", 8.8, 11.0]], mods_l, 350,
		"고유한 차지 공격. 완전히 충전한 뒤 자세를 유지하면 잠시 이동 속도가 증가합니다.", "key_charge")
	W.call("soul_reaver", "소울 리버", "longsword", 4, 6, [194, 194], "phys", [["all", 4, 4], ["str", 12, 14], ["dmg", 8.8, 11.0]], mods_l, 450,
		"칼날이 더 길고 피해가 크며, 약공격이 방어를 무너뜨립니다.", "long_blade")
	W.call("thunder_knight_blade", "천둥 기사의 검", "longsword", 4, 6, [184, 184], "phys", [["all", 4, 4], ["str", 12, 14], ["lightning_add", 11, 14]], mods_l, 450,
		"완벽한 방어 후 반격이 최대 5회 튕기는 연쇄 번개를 소환합니다.", "chain_lightning")
	W.call("the_mistake", "실수", "longsword", 4, 6, [184, 184], "phys", [["all", 4, 4], ["str", 12, 14], ["dmg", 8.8, 11.0]], mods_l, 450,
		"적 플레이어를 처치하면 생명력이 가득 회복됩니다.", "mistake")
	# 방패 (보조)
	W.call("traveler_shield", "여행자의 방패", "shield", 1, 2, [0, 0], "phys", [["vit", 4, 6], ["pres", 4.0, 5.0]], mods_u, 25)
	W.call("soldier_shield", "병사의 방패", "shield", 2, 3, [0, 0], "phys", [["vit", 5, 7], ["pres", 4.2, 5.2]], mods_m, 50)
	W.call("royal_shield", "왕실 방패", "shield", 3, 4, [0, 0], "phys", [["vit", 4, 6], ["pres", 4.4, 5.5], ["life_on_kill", 16, 18]], mods_e, 100)
	W.call("knight_shield", "기사의 방패", "shield", 3, 4, [0, 0], "phys", [["vit", 6, 7], ["pres", 4.4, 5.5], ["regen_ooc", 1, 1]], mods_e, 100)
	W.call("cloudwall", "구름벽", "shield", 4, 5, [0, 0], "phys", [["all", 2, 2], ["vit", 4, 6], ["pres", 4.0, 5.0], ["set_dragon", 3, 3]], mods_l, 300,
		"용비늘의 재사용 대기시간이 30초로 감소합니다.", "cloudwall")
	W.call("silver_defender", "은빛 수호자", "shield", 4, 5, [0, 0], "phys", [["all", 2, 2], ["vit", 6, 7], ["pres", 4.4, 5.5]], mods_l, 300,
		"방어에 성공하면 공격자가 1.5초 동안 둔화됩니다.", "block_slow")
	W.call("umbral_ward", "그림자 수호벽", "shield", 4, 6, [0, 0], "phys", [["all", 2, 2], ["vit", 4, 6], ["pres", 4.4, 5.5]], mods_l, 400,
		"방어 중 좌클릭으로 최대 3회 튕기는 추적 방패를 던져 피해와 둔화 (5초마다).", "shield_throw")
	# 중석궁
	W.call("hardwood_crossbow", "단단한 나무 석궁", "crossbow", 1, 2, [156, 159], "phys", [["agi", 8, 12], ["cdmg", 9.6, 12.0]], mods_u, 30)
	W.call("steel_crossbow", "강철촉 석궁", "crossbow", 2, 3, [161, 161], "phys", [["agi", 10, 14], ["cdmg", 10.0, 12.5]], mods_m, 60)
	W.call("punishment_crossbow", "징벌의 석궁", "crossbow", 3, 4, [161, 178], "phys", [["agi", 12, 14], ["cdmg", 10.6, 13.2], ["ls_ooc", 21.2, 26.4]], mods_e, 120)
	W.call("reprimand_crossbow", "질책의 석궁", "crossbow", 3, 4, [161, 178], "phys", [["str", 12, 14], ["cdmg", 10.6, 13.2], ["crit_ooc", 44.0, 55.0]], mods_e, 120)
	W.call("galeflight", "질풍", "crossbow", 4, 5, [194, 194], "phys", [["all", 4, 4], ["agi", 12, 14], ["cdmg", 10.6, 13.2]], mods_l, 350,
		"조준과 재장전 중에도 이동 속도가 줄지 않습니다.", "galeflight")
	W.call("scorpion_sting", "전갈의 침", "crossbow", 4, 6, [184, 184], "phys", [["all", 4, 4], ["agi", 12, 14], ["cold_add", 11, 14]], mods_l, 450,
		"얼음 화살을 발사하여 대상을 2초 동안 얼립니다.", "freeze_bolt")
	# 지팡이
	W.call("pyro_staff", "화염술사의 지팡이", "staff", 1, 2, [135, 135], "fire", [["int", 8, 12], ["edmg", 8.0, 10.0]], mods_u, 30)
	W.call("stormcaller_staff", "폭풍술사의 지팡이", "staff", 1, 2, [135, 135], "lightning", [["int", 8, 12], ["edmg", 8.0, 10.0]], mods_u, 30)
	W.call("searing_staff", "작열하는 태양 지팡이", "staff", 2, 3, [136, 136], "fire", [["int", 10, 14], ["edmg", 8.4, 10.4]], mods_m, 60)
	W.call("thunderbinder_staff", "뇌전 결속 지팡이", "staff", 2, 3, [136, 136], "lightning", [["int", 10, 14], ["edmg", 8.4, 10.4]], mods_m, 60)
	W.call("sunblight_staff", "태양 역병 지팡이", "staff", 3, 4, [135, 150], "fire", [["int", 12, 14], ["edmg", 8.8, 11.0], ["life_on_kill", 32, 36]], mods_e, 120)
	W.call("thunder_justice_staff", "천둥의 심판 지팡이", "staff", 3, 4, [135, 150], "lightning", [["int", 12, 14], ["edmg", 8.8, 11.0], ["life_on_kill", 32, 36]], mods_e, 120)
	W.call("endor_scorchwood", "엔도르의 불타는 나무 지팡이", "staff", 4, 5, [156, 156], "fire", [["all", 4, 4], ["int", 12, 14], ["edmg", 8.8, 11.0]], mods_l, 350,
		"화염 광선의 마지막 폭발이 범위 피해를 주고 대상에게 약한 점화를 겁니다.", "scorch")
	W.call("stormcaller", "스톰콜러", "staff", 4, 5, [156, 156], "lightning", [["all", 4, 4], ["int", 12, 14], ["edmg", 8.8, 11.0]], mods_l, 350,
		"지팡이 기술 '폭풍 소환'을 3회까지 충전합니다.", "storm_charges")
	W.call("immortal_lightning_staff", "불멸의 번개 지팡이", "staff", 4, 6, [156, 156], "lightning", [["all", 4, 4], ["int", 12, 14], ["edmg", 8.8, 11.0]], mods_l, 450,
		"더 강력한 '폭풍 소환'을 얻습니다.", "storm_plus")
	# 오브 (보조)
	W.call("grandmaster_orb", "대가의 오브", "orb", 1, 2, [120, 120], "holy", [["wil", 4, 6], ["hp", 6.4, 8.0]], mods_u, 25)
	W.call("mastery_orb", "숙련의 오브", "orb", 2, 3, [122, 122], "holy", [["wil", 5, 7], ["hp", 6.7, 8.4]], mods_m, 50)
	W.call("contemplation_orb", "명상의 오브", "orb", 3, 4, [124, 136], "holy", [["wil", 6, 7], ["hp", 7.1, 8.8], ["life_on_kill", 16, 18]], mods_e, 100)
	W.call("endor_orb", "엔도르의 오브", "orb", 4, 5, [140, 140], "holy", [["all", 2, 2], ["wil", 6, 7], ["hp", 7.1, 8.8]], mods_l, 300,
		"방어에 성공하면 오브 에너지(자원)를 조금 회복합니다.", "orb_energy")
	# 단검
	W.call("steel_dagger", "강철 단검", "dagger", 1, 2, [88, 88], "phys", [["agi", 4, 6], ["cdmg", 4.8, 6.0]], mods_u, 25)
	W.call("exquisite_dagger", "정교한 단검", "dagger", 2, 3, [89, 89], "phys", [["agi", 5, 7], ["cdmg", 5.0, 6.3]], mods_m, 50)
	W.call("finely_blade", "정교하게 다듬은 칼날", "dagger", 3, 4, [89, 98], "phys", [["agi", 6, 7], ["cdmg", 5.3, 6.6], ["life_on_kill", 16, 18]], mods_e, 100)
	W.call("bloody_blade", "피 묻은 칼날", "dagger", 3, 4, [89, 98], "phys", [["str", 6, 7], ["cdmg", 5.3, 6.6], ["crit_full", 15.9, 19.8]], mods_e, 100)
	W.call("thunderbolt_dagger", "벼락 단검", "dagger", 4, 5, [89, 91], "lightning", [["agi", 4, 6], ["crit", 4.8, 6.0], ["all", 2, 2], ["set_storm", 9, 9]], mods_l, 300,
		"폭풍의 분노 세트 효과 단계를 크게 올립니다.", "storm_set")
	W.call("rogues_edge", "도적의 칼날", "dagger", 4, 5, [102, 102], "phys", [["all", 2, 2], ["agi", 6, 7], ["cdmg", 5.3, 6.6]], mods_l, 300,
		"주무기일 때 차지 공격의 사거리가 길어집니다.", "long_charge")
	W.call("wizardspike", "마법사 꼬챙이", "dagger", 4, 6, [102, 102], "phys", [["all", 2, 2], ["agi", 6, 7], ["cdmg", 5.3, 6.6]], mods_l, 400,
		"주무기일 때 차지 공격이 대상의 실드를 모두 흡수해 10초 동안 유지합니다.", "shield_steal")
	# 철퇴
	W.call("pernach", "광택 나는 페르나흐", "mace", 1, 2, [123, 123], "phys", [["vit", 4, 6], ["hp", 6.4, 8.0]], mods_u, 25)
	W.call("guard_morgenstern", "경비병의 모르겐슈테른", "mace", 2, 3, [124, 124], "phys", [["vit", 5, 7], ["hp", 6.7, 8.4]], mods_m, 50)
	W.call("pernach_order", "질서의 페르나흐", "mace", 3, 4, [124, 137], "holy", [["fai", 4, 6], ["hp", 7.1, 8.8], ["regen_ooc", 1, 1]], mods_e, 100)
	W.call("morgenstern_execution", "처형의 모르겐슈테른", "mace", 3, 4, [124, 137], "phys", [["vit", 6, 7], ["hp", 7.1, 8.8], ["ms_ooc", 9, 10]], mods_e, 100)
	W.call("sanctum_smasher", "성소 파쇄자", "mace", 4, 5, [157, 157], "holy", [["all", 2, 2], ["vit", 6, 7], ["hp", 7.1, 8.8]], mods_l, 350,
		"매우 높은 공격력을 가집니다.", "")
	W.call("celestial_morgenstern", "천상의 모르겐슈테른", "mace", 4, 5, [142, 142], "phys", [["all", 2, 2], ["vit", 6, 7], ["hp", 7.1, 8.8]], mods_l, 300,
		"방어에 성공하면 이동 속도가 크게 증가합니다.", "block_speed")
	W.call("beastlord_mallet", "야수왕의 망치", "mace", 4, 6, [142, 142], "phys", [["all", 2, 2], ["vit", 6, 7], ["hp", 7.1, 8.8]], mods_l, 400,
		"철퇴와 방패 차지 공격의 2단계가 지면 범위 공격으로 바뀝니다.", "ground_slam")
	# ---- 장신구 (위키 자료 없음: 무작위 옵션 위주)
	var acc := [
		["copper_ring", "구리 반지", "ring", 1, "💍", 20], ["silver_ring", "은 반지", "ring", 2, "💍", 45], ["ruby_ring", "루비 반지", "ring", 3, "💍", 90],
		["bone_necklace", "뼈 목걸이", "necklace", 1, "📿", 20], ["wolf_pendant", "늑대 목걸이", "necklace", 2, "📿", 45], ["skull_amulet", "해골 부적", "necklace", 3, "💀", 90],
	]
	for a in acc:
		var m = [["random"], ["random", "any:3"], ["random", "any:3", "any:2"]][a[3] - 1]
		_add(a[0], {"name": a[1], "slot": a[2], "cat": a[2], "rarity": a[3], "lvl": a[3] + 1, "icon": a[4], "size": [1, 1], "fixed": [], "mods": m, "value": a[5]})
	# ---- 소모품 / 투척 / 보물
	_add("health_potion", {"name": "체력 물약", "slot": "consumable", "heal": 60, "drink": "heal", "value": 15, "icon": "🧪", "size": [1, 1], "rarity": 1, "stack": 3,
		"desc": "좌클릭으로 마시면 마시는 동작이 끝난 뒤 3초에 걸쳐 체력을 회복합니다."})
	_add("bandage", {"name": "붕대", "slot": "consumable", "heal": 30, "value": 6, "icon": "🩹", "size": [1, 1], "rarity": 0, "stack": 3})
	_add("bolts", {"name": "석궁 볼트", "slot": "ammo", "value": 1, "icon": "➶", "size": [1, 2], "rarity": 0, "stack": 30,
		"desc": "석궁에 장전하는 볼트. 가방에 들고 다니면 R키로 1개씩 석궁에 끼웁니다."})
	_add("torch", {"name": "횃불", "slot": "torch", "value": 3, "icon": "🕯", "size": [1, 2], "rarity": 0, "stack": 3, "burn": 120.0,
		"desc": "G키로 불을 붙여 손에 듭니다. 2분 동안 주변을 밝게 비추고, 좌클릭으로 휘두를 수 있습니다."})
	# 플라스크: 체력 물약을 뺀 모든 플라스크는 20초 재사용 대기를 공유 (FLASK_CD)
	#  투척: 소모품 칸에서 꺼내 좌클릭으로 던짐 (포물선 미리보기) · 마시기: 좌클릭으로 마신 뒤 효과
	_add("fire_flask", {"name": "화염 플라스크", "slot": "consumable", "throw": "fire", "dmg": 0, "value": 12, "icon": "🔥", "size": [1, 1], "rarity": 1, "stack": 3,
		"desc": "10초 동안 반경 3m의 지면을 불태웁니다. 뜨거운 지면을 밟으면 2.5초 동안 0.5초마다 16 피해. (플라스크 공유 재사용 대기 20초)"})
	_add("rock_flask", {"name": "대지 플라스크", "slot": "consumable", "throw": "rock", "dmg": 0, "value": 12, "icon": "🪨", "size": [1, 1], "rarity": 1, "stack": 3,
		"desc": "깨진 자리에 돌기둥 4개를 가로로 세워 길을 막습니다. 10초 뒤 사라지며, 피해를 많이 받으면 먼저 무너집니다. (플라스크 공유 재사용 대기 20초)"})
	_add("lightning_flask", {"name": "전기 플라스크", "slot": "consumable", "throw": "lightning", "dmg": 80, "value": 15, "icon": "⚡", "size": [1, 1], "rarity": 2, "stack": 3,
		"desc": "적중 시 80 번개 피해, 범위 내 적의 이동 속도를 4.5초 동안 75% 감소. (플라스크 공유 재사용 대기 20초)"})
	_add("mimic_flask", {"name": "미믹 플라스크", "slot": "consumable", "drink": "mimic", "value": 20, "icon": "📦", "size": [1, 1], "rarity": 2, "stack": 3,
		"desc": "마시면 상자로 변신합니다. 아주 느리게 움직일 수 있고, 공격받거나 우클릭하면 풀립니다. (플라스크 공유 재사용 대기 20초)"})
	_add("protection_flask", {"name": "방어 플라스크", "slot": "consumable", "drink": "shield", "shield": 60, "shield_t": 12.0, "value": 18, "icon": "🛡", "size": [1, 1], "rarity": 1, "stack": 3,
		"desc": "마시면 12초 동안 피해 60을 막는 보호막이 생깁니다. (플라스크 공유 재사용 대기 20초)"})
	_add("gold_coins", {"name": "금화", "slot": "treasure", "value": 1, "icon": "🪙", "size": [1, 1], "rarity": 0, "stack": 999})
	_add("silver_goblet", {"name": "은 술잔", "slot": "treasure", "value": 35, "icon": "🏆", "size": [1, 2], "rarity": 1})
	_add("ruby", {"name": "루비", "slot": "treasure", "value": 60, "icon": "🔴", "size": [1, 1], "rarity": 2})
	_add("sapphire", {"name": "사파이어", "slot": "treasure", "value": 70, "icon": "🔵", "size": [1, 1], "rarity": 2})
	_add("golden_crown", {"name": "황금 왕관", "slot": "treasure", "value": 160, "icon": "👑", "size": [2, 2], "rarity": 3})
	_add("ancient_relic", {"name": "고대 유물", "slot": "treasure", "value": 220, "icon": "🗿", "size": [2, 2], "rarity": 3})
	_add("dragon_heart", {"name": "용의 심장석", "slot": "treasure", "value": 400, "icon": "💎", "size": [2, 2], "rarity": 4})


func _weapon_icon(cat: String) -> String:
	return {"sword": "🗡", "longsword": "⚔", "shield": "🛡", "dagger": "🔪", "mace": "🔨", "staff": "🪄", "orb": "🔮", "crossbow": "🏹"}.get(cat, "🗡")


func _weapon_size(cat: String) -> Array:
	# 양손 무기(양손검·지팡이·석궁)는 가로 2칸
	return {"sword": [1, 3], "longsword": [2, 4], "shield": [2, 3], "dagger": [1, 2], "mace": [1, 3], "staff": [2, 4], "orb": [2, 2], "crossbow": [2, 3]}.get(cat, [1, 3])


func _weapon_model(cat: String) -> String:
	return {"sword": "sword", "longsword": "greatsword", "shield": "sword", "dagger": "dagger", "mace": "mace", "staff": "staff", "orb": "staff", "crossbow": "crossbow"}.get(cat, "sword")


# ------------------------------------------------------------------ 몬스터 (위키 몬스터 목록)
# ai: melee/ranged/charge/flyer/caster(마법진)/stinger(제자리)/shield/fleeing/harmless/mimic/emerge
const MONSTERS := {
	"skeleton_swordsman": {"name": "해골 검사", "hp": 170, "dmg": 22, "speed": 3.6, "range": 2.6, "cd": 1.4, "sight": 16.0, "ai": "melee", "scale": 1.0, "boss": false,
		"tip": "가장 기본적인 해골. 사거리가 긴 내려찍기를 조심하세요."},
	"skeleton_spearman": {"name": "해골 창병", "hp": 150, "dmg": 20, "speed": 3.4, "range": 3.6, "cd": 1.5, "sight": 16.0, "ai": "melee", "scale": 1.0, "boss": false,
		"tip": "왼쪽으로 천천히 돌면서 상대하세요."},
	"skeleton_warrior": {"name": "해골 전사", "hp": 220, "dmg": 18, "speed": 3.2, "range": 2.4, "cd": 1.5, "sight": 16.0, "ai": "shield", "scale": 1.05, "boss": false,
		"tip": "방패를 듭니다. 차지 공격으로 자세를 무너뜨리세요."},
	"skeleton_archer": {"name": "해골 궁수", "hp": 130, "dmg": 16, "speed": 3.3, "range": 16.0, "cd": 2.0, "sight": 20.0, "ai": "ranged", "scale": 1.0, "boss": false,
		"tip": "원거리 해골. 천천히 돌면서 접근하세요."},
	"demon_eye": {"name": "악마의 눈", "hp": 110, "dmg": 34, "speed": 3.0, "range": 12.0, "cd": 3.5, "sight": 18.0, "ai": "caster", "scale": 1.0, "boss": false, "fly": 2.4,
		"tip": "공중에 떠서 바닥에 마법진을 그립니다. 마법진은 큰 피해를 줍니다."},
	"goblin_axeman": {"name": "고블린 도끼병", "hp": 120, "dmg": 16, "speed": 4.6, "range": 2.2, "cd": 1.0, "sight": 15.0, "ai": "fleeing", "scale": 0.75, "boss": false,
		"tip": "피해를 충분히 주면 도망칩니다."},
	"goblin_thief": {"name": "고블린 도둑", "hp": 100, "dmg": 24, "speed": 5.0, "range": 2.0, "cd": 2.6, "sight": 15.0, "ai": "charge", "scale": 0.72, "boss": false,
		"tip": "치명적인 돌진 공격. 옆으로 피하며 공격하세요."},
	"goblin_crossbowman": {"name": "고블린 석궁병", "hp": 100, "dmg": 22, "speed": 4.2, "range": 15.0, "cd": 2.4, "sight": 18.0, "ai": "ranged", "scale": 0.75, "boss": false, "flee": true,
		"tip": "쏘기 전에 먼저 공격하세요. 체력이 낮으면 도망칩니다."},
	"giant_bat": {"name": "거대 박쥐", "hp": 60, "dmg": 14, "speed": 5.5, "range": 2.0, "cd": 2.2, "sight": 14.0, "ai": "charge", "scale": 1.0, "boss": false, "fly": 1.8,
		"tip": "물러났다가 돌진합니다. 돌진 직전 옆으로 비키세요."},
	"giant_beetle": {"name": "거대 딱정벌레", "hp": 90, "dmg": 14, "speed": 3.4, "range": 2.0, "cd": 1.8, "sight": 10.0, "ai": "stinger", "scale": 1.0, "boss": false,
		"tip": "제자리에 멈춰 침을 쏩니다. 멈추면 물러났다가 공격하세요."},
	"zombie": {"name": "좀비", "hp": 210, "dmg": 26, "speed": 2.4, "range": 2.2, "cd": 2.2, "sight": 12.0, "ai": "emerge", "scale": 1.0, "boss": false,
		"tip": "땅에서 기어 나옵니다. 공격이 느리니 유인한 뒤 싸우세요."},
	"mimic": {"name": "미믹", "hp": 260, "dmg": 30, "speed": 3.8, "range": 2.4, "cd": 1.6, "sight": 8.0, "ai": "mimic", "scale": 1.0, "boss": false,
		"tip": "상자로 위장합니다. 계속 물러나며 공격하세요."},
	"pest": {"name": "해충", "hp": 25, "dmg": 0, "speed": 4.5, "range": 1.0, "cd": 9.0, "sight": 8.0, "ai": "harmless", "scale": 1.0, "boss": false,
		"tip": "무해하지만 공격받으면 도망칩니다."},
	"giant_rat": {"name": "거대 쥐", "hp": 90, "dmg": 28, "speed": 4.8, "range": 2.2, "cd": 1.8, "sight": 14.0, "ai": "melee", "scale": 1.0, "boss": false,
		"tip": "강력한 연속 공격. 콤보를 유도한 뒤 공격하세요."},
	"boar": {"name": "거대 멧돼지", "hp": 110, "dmg": 34, "speed": 4.6, "range": 2.4, "cd": 3.0, "sight": 16.0, "ai": "charge", "scale": 1.0, "boss": false,
		"tip": "강한 돌진 공격. 옆으로 피하세요."},
	"mimic_book": {"name": "미믹 책", "hp": 80, "dmg": 18, "speed": 3.6, "range": 7.0, "cd": 2.0, "sight": 14.0, "ai": "caster", "scale": 1.0, "boss": false, "fly": 1.6,
		"tip": "조용히 다가옵니다. 사거리가 길어요."},
	"apparition": {"name": "망령", "hp": 60, "dmg": 40, "speed": 4.8, "range": 2.0, "cd": 2.6, "sight": 15.0, "ai": "charge", "scale": 1.0, "boss": false,
		"tip": "치명적인 돌진. 휘두른 직후에만 공격하세요."},
	"treant_wild": {"name": "트렌트", "hp": 420, "dmg": 36, "speed": 2.6, "range": 3.2, "cd": 2.4, "sight": 14.0, "ai": "melee", "scale": 1.4, "boss": false, "weak": "fire",
		"tip": "불에 매우 약합니다."},
	"tentacle": {"name": "촉수", "hp": 150, "dmg": 30, "speed": 0.0, "range": 3.8, "cd": 2.2, "sight": 9.0, "ai": "emerge", "scale": 1.0, "boss": false, "rooted": true,
		"tip": "바닥의 작은 구멍을 조심하세요. 차지 공격으로 자세를 무너뜨리세요."},
	"living_armor_warrior": {"name": "살아있는 갑옷 전사", "hp": 260, "dmg": 22, "speed": 3.2, "range": 2.4, "cd": 1.6, "sight": 15.0, "ai": "shield", "scale": 1.05, "boss": false,
		"tip": "방패를 들었을 때 공격하면 큰 피해를 받습니다. 차지 공격으로 무너뜨리세요."},
	"living_armor_swordsman": {"name": "살아있는 갑옷 검사", "hp": 240, "dmg": 26, "speed": 3.4, "range": 2.8, "cd": 1.8, "sight": 15.0, "ai": "melee", "scale": 1.05, "boss": false, "combo": 2,
		"tip": "베기 후 강한 찌르기. 두 번째 공격 이후에 접근하세요."},
	# 정예/보스
	"khazra": {"name": "카즈라", "hp": 600, "dmg": 34, "speed": 4.4, "range": 2.6, "cd": 1.3, "sight": 18.0, "ai": "melee", "scale": 1.3, "boss": false, "elite": true, "combo": 2,
		"tip": "정예 몬스터."},
	"reaper": {"name": "사신", "hp": 800, "dmg": 42, "speed": 3.8, "range": 3.6, "cd": 1.7, "sight": 18.0, "ai": "melee", "scale": 1.45, "boss": true, "elite": true,
		"tip": "정예 보스. 넓은 낫 휘두르기."},
	"headsman": {"name": "망나니", "hp": 950, "dmg": 55, "speed": 3.2, "range": 3.2, "cd": 2.0, "sight": 18.0, "ai": "melee", "scale": 1.5, "boss": true, "elite": true,
		"tip": "정예 보스. 느리지만 강력한 내려찍기."},
}

# ------------------------------------------------------------------ 맵
# 지도 이미지에서 추출한 타일 지도(assets/maps/*.json) + 출현 몬스터
const MAPS := {
	"clouseau_castle": {
		"name": "클루조 성", "file": "res://assets/maps/clouseau_castle.json", "icon": "🏰",
		"desc": "성벽과 탑으로 둘러싸인 큰 성(안뜰·본성 큰 홀·막사·창고), 서쪽의 어두운 숲, 남서쪽의 버려진 성당.",
		"monsters": {"goblin_axeman": 22, "goblin_thief": 12, "goblin_crossbowman": 12, "giant_rat": 9, "boar": 6, "mimic_book": 6, "apparition": 6,
			"living_armor_warrior": 8, "living_armor_swordsman": 8, "giant_bat": 6, "giant_beetle": 5, "pest": 4, "treant_wild": 3},
		"boss": "headsman", "elites": ["khazra"], "mimic": 0.06, "floor": 1,
	},
	"sinners_end_1": {
		"name": "죄인의 끝 1층", "file": "res://assets/maps/sinners_end_1.json", "icon": "🪦",
		"desc": "해골과 끔찍한 괴물들이 사는 여러 층의 미궁. (2층은 준비 중)",
		"monsters": {"skeleton_swordsman": 22, "skeleton_spearman": 14, "skeleton_warrior": 12, "skeleton_archer": 12, "demon_eye": 7, "zombie": 10,
			"tentacle": 5, "giant_bat": 6, "giant_beetle": 6, "pest": 4},
		"boss": "reaper", "elites": ["khazra"], "mimic": 0.06, "floor": 1,
	},
}
const MAP_ORDER := ["clouseau_castle", "sinners_end_1"]

const BOT_NAMES := [
	"검은늑대", "은빛매", "그림자칼날", "철벽수호자", "붉은여우", "방랑자K", "던전킹", "초보탈출러", "도적왕", "불꽃술사",
	"서리마녀", "활쏘는곰", "무덤지기", "Aldric", "Mirelle", "Kael", "Thorne", "Sylvara", "Brom", "Vex",
]

var _uid := 0


func uid() -> String:
	_uid += 1
	return "i%d_%d_%d" % [Time.get_ticks_msec(), _uid, randi() % 1000]


func base_of(item: Dictionary) -> Dictionary:
	return ITEM_BASES[item["base"]]


func is_weapon(item: Dictionary) -> bool:
	return base_of(item)["slot"] == "weapon"


func is_gear(item: Dictionary) -> bool:
	return base_of(item)["slot"] in ["weapon", "head", "chest", "hands", "legs", "feet", "necklace", "ring"]


func max_stack(item: Dictionary) -> int:
	return int(base_of(item).get("stack", 1))


# 아이템이 들어갈 수 있는 장비 칸
func gear_slots_for(item: Dictionary, cls := "") -> Array:
	var b := base_of(item)
	match b.slot:
		"weapon":
			var cat: String = b.cat
			if cat in OFFHAND:
				return ["w1o", "w2o"]
			var out := ["w1", "w2"]
			# 로그 쌍단검: 단검은 보조 손에도
			if cat == "dagger":
				out.append_array(["w1o", "w2o"])
			if cat == "sword" and (cls == "swordmaster" or cls == ""):
				out.append_array(SWORD_SLOTS)
			return out
		"ring":
			return ["ring1", "ring2"]
		"consumable":
			return QUICK_SLOTS
		"torch":
			return ["torch"]
		"head", "chest", "hands", "legs", "feet", "necklace":
			return [b.slot]
	return []


# 인벤토리 칸 크기 (회전하면 가로세로 교체)
func item_size(item: Dictionary) -> Vector2i:
	var sz: Array = base_of(item).get("size", [1, 1])
	if item.get("r", false):
		return Vector2i(sz[1], sz[0])
	return Vector2i(sz[0], sz[1])


func _mod_kind(k: String) -> String:
	if k in ATTRS or k == "all":
		return "attr"
	if k in ["hp", "ms", "armor", "regen_ooc"]:
		return k
	return "pct"


# 무작위 옵션 하나 굴리기. pool: off/def/any, tiers: "3"=Ω/Φ/Δ, "2"=Ω/Φ, "o"=Ω
func _roll_mod(pool: String, tiers: String, used: Dictionary) -> Dictionary:
	var keys: Array = []
	if pool == "any":
		keys = MOD_POOL.off + MOD_POOL.def
	else:
		keys = MOD_POOL[pool].duplicate()
	keys = keys.filter(func(k): return not used.has(k))
	if keys.is_empty():
		return {}
	var k: String = keys.pick_random()
	var tier := 0
	match tiers:
		"o":
			tier = 2
		"2":
			tier = 2 if randf() < 0.4 else 1
		_:
			var r := randf()
			tier = 2 if r < 0.2 else (1 if r < 0.55 else 0)
	var rg: Array = MOD_TIERS[_mod_kind(k)][tier]
	var v
	if rg[0] is float:
		v = snappedf(randf_range(rg[0], rg[1]), 0.1)
	else:
		v = randi_range(rg[0], rg[1])
	used[k] = true
	return {"k": k, "v": v, "t": tier}


# 아이템 생성: 고정 옵션은 범위 안에서 굴리고, 무작위 옵션/세트 포인트를 붙임
func make_item(base_id: String, _rarity: int = -1) -> Dictionary:
	var b: Dictionary = ITEM_BASES[base_id]
	var rar: int = b.get("rarity", 0)
	# 소모품/횃불은 등급이 없음: 같은 종류는 모두 같은 아이템으로 합쳐짐
	var plain: bool = b.slot in ["consumable", "torch", "ammo"]
	if plain:
		rar = 0
	var stats := {}
	if b.has("dmg") and b.dmg is Array:
		stats["dmg"] = randi_range(b.dmg[0], b.dmg[1])
	if b.has("armor") and b.armor > 0:
		stats["armor"] = int(b.armor)
	var fixed := []
	for f in b.get("fixed", []):
		var v
		if str(f[0]).begins_with("set_"):
			fixed.append({"k": "set", "set": str(f[0]).substr(4), "v": int(f[1])})
			continue
		if f[1] is float:
			v = snappedf(randf_range(f[1], f[2]), 0.1)
		else:
			v = randi_range(f[1], f[2])
		fixed.append({"k": f[0], "v": v, "min": f[1], "max": f[2]})
	var affixes := []
	var used := {}
	for m in b.get("mods", []):
		var spec: String = m
		if spec == "random_midas" or spec == "off_or_spec_midas":
			if randf() < 0.3:
				var sp: Array = SET_PERKS.keys()
				var sk: String = sp.pick_random()
				affixes.append({"k": "set", "set": sk, "v": randi_range(1, SET_PERKS[sk].max)})
				continue
			spec = "random" if spec == "random_midas" else "off_or_spec"
		var a := {}
		match spec:
			"random":
				a = _roll_mod("any", "3", used)
			"off_or_spec":
				a = _roll_mod("off", "o", used)
			_:
				var parts := spec.split(":")
				a = _roll_mod(parts[0], parts[1], used)
		if not a.is_empty():
			affixes.append(a)
	var value_mult: float = 1.0 + affixes.size() * 0.15
	return {
		"id": uid(),
		"base": base_id,
		"rarity": rar,
		"stats": stats,
		"fixed": fixed,
		"affixes": affixes,
		"count": 1,
		"value": int(b.get("value", 1)) if plain or b.get("stack", 1) > 1 else roundi(b.get("value", 1) * value_mult * randf_range(0.9, 1.1)),
	}


func mod_label(a: Dictionary) -> String:
	if a.k == "set":
		return MOD_FMT.set % [SET_PERKS.get(a.set, {}).get("name", a.set), a.v]
	var fmt: String = MOD_FMT.get(a.k, a.k + " %s")
	return fmt % a.v


func stat_label(k: String, v) -> String:
	match k:
		"dmg":
			return "공격력 %d" % v
		"armor":
			return "방어도 %d" % v
	return ""


# 몬스터/상자 루트
func roll_rarity(luck: float = 0.0) -> int:
	var r := randf() * 100.0 - luck * 9.0
	if r < 1.0:
		return 4
	if r < 6.0:
		return 3
	if r < 20.0:
		return 2
	if r < 50.0:
		return 1
	return 0


const TREASURE_POOL := [
	["gold_coins", 40.0], ["silver_goblet", 22.0], ["ruby", 12.0], ["sapphire", 10.0],
	["golden_crown", 4.0], ["ancient_relic", 2.5], ["dragon_heart", 0.8],
]


func _gear_by_rarity(rar: int) -> Array:
	var out := []
	for k in ITEM_BASES:
		var b: Dictionary = ITEM_BASES[k]
		if is_gear({"base": k}) and int(b.get("rarity", 0)) == rar:
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
	for i in count:
		var r := randf()
		if r < 0.45:
			var pool := _gear_by_rarity(roll_rarity(luck))
			if pool.is_empty():
				pool = _gear_by_rarity(1)
			items.append(make_item(pool.pick_random()))
		elif r < 0.65:
			var c = ["health_potion", "health_potion", "bandage", "bandage", "fire_flask", "rock_flask", "lightning_flask", "mimic_flask", "protection_flask", "torch"].pick_random()
			var it := make_item(c)
			it.count = randi_range(1, 2)
			items.append(it)
		else:
			var t := _weighted_treasure(luck)
			var it := make_item(t)
			if t == "gold_coins":
				it.count = randi_range(10, 40)
			items.append(it)
	return items


func class_names(classes: Array) -> String:
	var out := []
	for c in classes:
		out.append(CLASSES[c].name)
	return ", ".join(out)


# 무기 종류를 쓸 수 있는 직업 목록
func weapon_classes(cat: String) -> Array:
	var out := []
	for c in CLASS_ORDER:
		if cat in CLASSES[c].weapons:
			out.append(c)
	return out


func can_equip(item: Dictionary, cls: String) -> bool:
	var b := base_of(item)
	if not is_gear(item) and not (b.slot in ["consumable", "utility", "torch"]):
		return false
	if b.slot == "weapon" and not (b.cat in CLASSES[cls].weapons):
		return false
	return true


# 장착 중인 무기 세트 (1/2)
func active_weapons(equipment: Dictionary, wset: int) -> Array:
	var m = equipment.get("w%d" % wset)
	var o = equipment.get("w%do" % wset)
	return [m, o].filter(func(w): return w != null)


func weapon_cat(equipment: Dictionary, wset: int) -> String:
	var w = equipment.get("w%d" % wset)
	return base_of(w).cat if w != null else ""


func offhand_cat(equipment: Dictionary, wset: int) -> String:
	var w = equipment.get("w%do" % wset)
	return base_of(w).cat if w != null else ""


# 장비의 능력치/옵션 합계 -> 능력치, 열린 패시브, 파생 스탯
func compute_stats(cls: String, equipment: Dictionary, wset: int = 1) -> Dictionary:
	var c: Dictionary = CLASSES[cls]
	var attrs: Dictionary = CLASS_ATTRS[cls].duplicate()
	var t := {"hp": 0.0, "armor": 0.0, "ms": 0.0, "pdmg": 0.0, "edmg": 0.0, "dmg": 0.0, "wdmg": 0.0, "cdmg": 0.0, "crit": 0.0,
		"pres": 0.0, "mres": 0.0, "act": 0.0, "lifesteal": 0.0, "regen_ooc": 0.0, "life_on_kill": 0.0, "crit_full": 0.0,
		"crit_ooc": 0.0, "ls_ooc": 0.0, "ms_ooc": 0.0, "lightning_add": 0.0, "cold_add": 0.0, "cdr": 0.0}
	var sets := {}
	var uniques := []
	var weapon_dmg := 0.0
	var dtype := "phys"
	var block := 0.0
	var wcat := ""
	var slots := ["head", "chest", "hands", "legs", "feet", "necklace", "ring1", "ring2", "w%d" % wset, "w%do" % wset]
	for slot in slots:
		var it = equipment.get(slot)
		if it == null:
			continue
		var b := base_of(it)
		var s: Dictionary = it.get("stats", {})
		t.armor += s.get("armor", 0)
		t.ms += b.get("ms", 0)
		if b.slot == "weapon":
			if slot.ends_with("o") and b.cat in OFFHAND:
				block = maxf(block, 97.0 if b.cat == "shield" else 75.0)
				if b.cat == "orb" and weapon_dmg <= 0.0:
					weapon_dmg = float(s.get("dmg", 120))
					dtype = b.dtype
					wcat = "orb"
			elif not slot.ends_with("o"):
				weapon_dmg = float(s.get("dmg", WEAPON_REF.get(b.cat, 110.0)))
				dtype = b.get("dtype", "phys")
				wcat = b.cat
				# 무기로 막기: 단검은 약하게
				block = maxf(block, 50.0 if b.cat == "dagger" else 75.0)
				t.ms += {"sword": -10, "longsword": -30, "mace": -15, "staff": -30, "crossbow": -30, "dagger": 0}.get(b.cat, 0) - b.get("ms", 0)
			if b.has("ufx") and b.ufx != "":
				uniques.append(b.ufx)
		for a in it.get("fixed", []) + it.get("affixes", []):
			var k: String = a.k
			if k == "set":
				sets[a.set] = sets.get(a.set, 0) + int(a.v)
			elif k in ATTRS:
				attrs[k] += int(a.v)
			elif k == "all":
				for ak in ATTRS:
					attrs[ak] += int(a.v)
			elif t.has(k):
				t[k] += float(a.v)
	# 패시브: 능력치 조건을 채우면 자동 활성 (던전본처럼 5개 모두 사용)
	var unlocked := []
	var flags := {}
	for i in PASSIVES[cls].size():
		var p: Dictionary = PASSIVES[cls][i]
		var ok := true
		for k in p.req:
			if attrs[k] < p.req[k]:
				ok = false
		if ok:
			unlocked.append(i)
			flags[p.fx] = true
	# 능력치 -> 파생 스탯
	var pw: int = attrs[POWER_ATTR[cls]]
	var max_hp: float = c.hp + (attrs.vit - 15) * 2.0 + t.hp
	var magic: bool = cls in MAGIC_CLASSES
	var type_bonus: float = (t.edmg if magic else t.pdmg) + t.dmg
	var wmul: float = (weapon_dmg / WEAPON_REF.get(wcat, 110.0)) if weapon_dmg > 0.0 else 0.85
	var res_max: float = c.res_max
	if c.res == "mana":
		res_max += (attrs.int - 15) * 1.0 + (attrs.fai - 10) * (1.0 if cls == "priest" else 0.0)
	var crit: float = 5.0 + (attrs.agi - 15) * 0.15 + t.crit * 0.25
	return {
		"max_hp": maxf(60.0, max_hp),
		"armor": t.armor,
		"pres": clampf(t.pres / 100.0, 0.0, 0.6),
		"mres": clampf(t.mres / 100.0, 0.0, 0.6),
		"speed_mul": clampf((300.0 + t.ms + (attrs.agi - 15) * 0.6) / 300.0, 0.6, 1.5),
		"dmg_mul": wmul * (1.0 + (pw - 15) * 0.008) * (1.0 + type_bonus / 100.0 + t.wdmg / 200.0),
		"weapon_dmg": weapon_dmg,
		"wcat": wcat,
		"dtype": dtype,
		"block_pct": block,
		"res": c.res,
		"res_max": res_max,
		"base_speed": c.speed,
		"attrs": attrs,
		"passives": unlocked,
		"flags": flags,
		"crit": clampf(crit, 0.0, 75.0) / 100.0,
		"crit_mul": 1.5 + t.cdmg / 100.0,
		"cd_mul": clampf(1.0 - maxf(0.0, attrs.wil - 15) * 0.003 - t.cdr / 100.0, 0.6, 1.0),
		"regen_mul": maxf(0.3, 1.0 + (attrs.wil - 15) * 0.015),
		"act_mul": clampf(1.0 + (attrs.agi - 15) * 0.004 + t.act / 100.0, 0.7, 1.5),
		"heal_mul": 1.0 + maxf(0.0, attrs.fai - 10) * 0.01,
		"lifesteal": t.lifesteal / 100.0,
		"regen_ooc": t.regen_ooc,
		"life_on_kill": t.life_on_kill,
		"lightning_add": t.lightning_add,
		"cold_add": t.cold_add,
		"crit_full": t.crit_full / 100.0,
		"sets": sets,
		"uniques": uniques,
	}


func set_tier(st: Dictionary, set_id: String) -> int:
	var pts: int = st.get("sets", {}).get(set_id, 0)
	var tier := 0
	for tr in SET_PERKS[set_id].tiers:
		if pts >= tr[0]:
			tier += 1
	return tier


func weapon_model(cls: String, equipment: Dictionary, wset: int = 1) -> String:
	var w = equipment.get("w%d" % wset)
	if w != null:
		return base_of(w).get("model", "sword")
	var o = equipment.get("w%do" % wset)
	if o != null and base_of(o).cat == "orb":
		return "orb"
	if o != null and base_of(o).cat == "dagger":
		return "dagger"
	return "unarmed" # 이 세트에 무기가 없으면 맨손


func items_value(items: Array) -> int:
	var s := 0
	for it in items:
		if it != null:
			s += int(it["value"]) * int(it.get("count", 1))
	return s
