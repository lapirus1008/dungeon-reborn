# 3단계: 사실적인 모델·애니메이션·녹음 소리 받기 (직접 받아서 올려 주기)

1·2단계(조명, 안개, 무게감, 돌 재질)는 코드로 끝났습니다.
지금 "던전본처럼 안 보이는" 가장 큰 원인은 **머리가 큰 귀여운 캐릭터(KayKit)** 와 **상자처럼 생긴 1인칭 손·무기**입니다.
이 부분은 로그인이나 구매가 필요한 사이트에서 받아야 해서 직접 받아 주셔야 합니다.
파일을 올려 주시면 게임에 연결하는 작업(뼈대, 애니메이션 이름, 크기, 손 위치)은 제가 합니다.

> 스팀 출시가 목표이므로 **상업적 사용이 허용된 것**만 받아 주세요. 받은 곳과 라이선스를 아래 "받은 목록" 표에 적어 두면 나중에 크레딧 화면을 만들 때 씁니다.

---

## 순서 요약

1. 아래 **A → B → C → D** 중 원하는 것부터 받기 (A가 효과가 가장 큼)
2. 저장소의 `incoming/` 폴더에 종류별로 올리기 (올리는 방법은 맨 아래)
3. 저에게 "incoming에 올렸어"라고 말하기

---

## A. 캐릭터 + 애니메이션: Mixamo (무료, Adobe 계정 필요)

사람 비율의 캐릭터와 걷기·공격·방어·사망 동작을 한 곳에서 받을 수 있습니다. 상업 게임에 무료로 쓸 수 있습니다.

1. https://www.mixamo.com 접속 → Adobe 계정으로 로그인 (무료 가입 가능)
2. 위쪽 **Characters** 탭에서 캐릭터 고르기. 추천(검색창에 입력):
   - 모험가(사람): `Paladin`, `Knight`, `Erika Archer`, `Maw` 등 갑옷 입은 캐릭터
   - 몬스터: `Skeletonzombie`, `Mutant`, `Warrok`, `Zombie`, `Ghoul`
3. 캐릭터를 고른 상태에서 오른쪽 **DOWNLOAD** → Format **FBX Binary(.fbx)**, Skin **With Skin**, Frames per second **30** → 다운로드
4. **Animations** 탭에서 동작 받기 (같은 캐릭터를 고른 상태에서)
   - 검색어 추천: `Sword And Shield Idle`, `Sword And Shield Walk`, `Sword And Shield Run`, `Sword And Shield Slash`, `Sword And Shield Block`, `Sword And Shield Death`, `Great Sword Slash`, `Standing 1H Magic Attack`, `Hit Reaction`, `Zombie Walk`, `Zombie Attack`
   - 걷기·뛰기 동작은 **In Place** 체크
   - DOWNLOAD → Format **FBX Binary**, Skin **Without Skin** (캐릭터마다 한 번만 With Skin이면 됨)
5. 받은 파일을 `incoming/characters/<캐릭터이름>/` 에 모아서 올리기
   - 예: `incoming/characters/paladin/Paladin.fbx`, `incoming/characters/paladin/Sword And Shield Slash.fbx` …

필요한 개수(대략): 모험가 2~3종, 몬스터 3~4종 × 동작 6~8개

## B. 1인칭 팔·무기 (가장 눈에 띄는 부분)

1인칭 화면에 항상 보이는 팔과 무기라 효과가 큽니다.

- **Fab** (https://www.fab.com, Epic 계정) 에서 `FPS arms`, `first person arms medieval`, `medieval weapons pack` 검색
- **Sketchfab** (https://sketchfab.com) 에서 같은 검색어 + 왼쪽 필터 **Downloadable** 체크 → 라이선스가 `CC0` 또는 `CC Attribution` 인 것
- 받을 때 형식은 **glTF / glb** 가 가장 좋고, 없으면 **FBX**
- 확인할 것:
  - 라이선스에 **다른 엔진(Godot) 사용**과 **상업적 사용**이 허용되는지 (Fab은 상품 페이지의 License 항목)
  - 팔에 뼈대(rig)가 있으면 더 좋음 (손가락이 무기를 쥘 수 있음). 없어도 제가 손 위치에 붙일 수 있음
- 올릴 곳: `incoming/viewmodel/` (팔), `incoming/weapons/` (한손검, 장검, 단검, 둔기, 지팡이, 방패, 석궁, 횃불)

## C. 던전 소품·벽 장식 (선택)

벽·바닥은 이미 사진 기반 돌 재질(Poly Haven)로 바꿨습니다. 소품이 더 있으면 좋습니다.

- Fab / Sketchfab 에서 `medieval dungeon props`, `wooden chest`, `wall torch`, `barrel`, `iron door`, `candle`
- 올릴 곳: `incoming/props/`

## D. 녹음된 효과음 (지금은 합성 소리)

녹음된 실제 소리로 바꾸면 칼이 부딪히는 손맛이 확 달라집니다.

- **Sonniss GDC Game Audio Bundle** (https://sonniss.com/gameaudiogdc) — 무료, 상업적 사용 가능. 용량이 매우 크니 아래 소리만 골라 주세요
- **Kenney RPG Audio** (https://kenney.nl/assets/rpg-audio) — CC0, 작고 바로 쓰기 좋음
- **freesound.org** — 검색 후 라이선스 필터 **Creative Commons 0**

필요한 소리 (이름을 아래처럼 바꿔서 `godot/assets/sfx_recorded/` 에 바로 넣어도 되고, 아무 이름으로 `incoming/sfx/` 에 올려도 됩니다):

| 게임 속 이름 | 무엇 | 개수 |
|---|---|---|
| `step` | 돌바닥 발소리 (가죽 장화) | 4~6 |
| `swing` | 칼 휘두르는 바람 소리 | 3 |
| `hit` | 칼이 살/갑옷을 베는 소리 | 3~4 |
| `block` | 칼과 칼이 부딪히는 쇳소리 | 2~3 |
| `shield_hit` | 나무 방패에 맞는 소리 | 2 |
| `door` / `door_shut` | 나무문 삐걱 열기 / 쾅 닫기 | 1씩 |
| `chest` | 나무 상자 뚜껑 열기 | 1~2 |
| `coin` / `pickup` / `drop` | 동전, 물건 줍기, 내려놓기 | 2씩 |
| `hurt` / `death` | 남자 신음, 쓰러지는 소리 | 2 / 1 |
| `growl` | 몬스터 으르렁 | 2~3 |
| `fire` / `magic` / `heal` | 불 붙는 소리, 마법, 치유 | 1~2씩 |
| `bandage` / `potion_open` | 천 감는 소리, 코르크 따는 소리 | 1씩 |

이름 규칙: `step.ogg`, `step_2.ogg`, `step_3.ogg` … (wav·ogg·mp3 모두 됨). 같은 이름이 여러 개면 무작위로 골라 재생합니다.

---

## 올리는 방법 (GitHub 웹사이트에서)

1. https://github.com/lapirus1008/dungeon-reborn 접속 → 위에서 브랜치를 `claude/youthful-davinci-idnz60` 로 바꾸기
2. **Add file → Upload files**
3. 폴더째 끌어다 놓기 (예: `incoming` 폴더를 만들어 그 안에 `characters/paladin/...`)
4. 아래 **Commit changes** 누르기

주의:
- 웹 업로드는 **파일 하나에 25MB까지**입니다. 더 크면 zip으로 나누거나, 텍스처 해상도가 낮은 버전(1K/2K)을 받아 주세요.
- 너무 큰 묶음(수 GB)은 필요한 파일만 골라 주세요.

## 받은 목록 (크레딧용으로 채워 주세요)

| 파일/묶음 | 받은 곳 (링크) | 만든 사람 | 라이선스 |
|---|---|---|---|
| | | | |
