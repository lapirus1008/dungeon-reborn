# 그래픽 교체 가이드 (블록 모델 → 실제 3D 모델)

지금 게임은 모든 그래픽을 코드로 만든 블록 모델로 그립니다.
`godot/assets/` 폴더에 정해진 이름으로 3D 파일을 넣으면 **코드 수정 없이** 그 모델이 대신 쓰입니다.
파일이 없으면 지금의 블록 모델이 그대로 사용되므로, 하나씩 천천히 바꿔 나가면 됩니다.

지원 형식: `.glb` / `.gltf` (권장), `.tscn` / `.scn`, 단일 메시는 `.obj` / `.tres` / `.res`

## 폴더와 파일 이름

| 폴더 | 파일 이름 | 용도 | 기준 |
|---|---|---|---|
| `assets/characters/` | `fighter`, `swordmaster`, `rogue`, `deathknight`, `druid`, `pyromancer`, `cryomancer`, `priest` | AI 모험가 모델 (직업별) | 키 약 1.9m, 발이 원점, -Z가 앞 |
| | `panther` | 드루이드 표범 형태 | 〃 |
| | `treant` | 드루이드 소환수 | 키 약 3m |
| | `skeleton`, `skeleton_archer`, `goblin`, `ghoul`, `wraith_knight` | 몬스터 | 〃 |
| `assets/viewmodels/` | 직업 id, `panther` | 1인칭 손/무기 | 카메라 기준 좌표. 자식 노드 `R`, `L`이 있으면 손 애니메이션 적용 |
| `assets/weapons/` | `sword`, `longsword`, `dagger`, `greatsword`, `mace`, `staff`, `boss_sword`, `club` | 손에 드는 무기 | 손잡이가 원점, +Y 방향이 칼날 |
| `assets/dungeon/` | `floor`, `ceiling`, `wall`, `pillar`, `barrel` | 던전 타일 (MultiMesh로 대량 배치) | 타일 4m × 4m, 벽 높이 5.5m, 원점은 중심 |
| `assets/props/` | `chest_0`, `chest_1`, `chest_2` | 상자 (나무/장식/황금) | 뚜껑 노드 이름을 `Lid`로 두면 열리는 애니메이션 적용 |

## 캐릭터 애니메이션

캐릭터 `.glb` 안에 `AnimationPlayer`가 있으면 아래 이름의 애니메이션을 상황에 맞게 재생합니다.

`idle`, `walk`, `attack`, `cast`, `block`, `hit`, `death`

애니메이션 이름이 다르면 같은 폴더에 `<id>.json`을 두고 매핑합니다.

```json
{ "animations": { "walk": "Run_Forward", "attack": "Sword_Slash", "death": "Death_A" } }
```

게임 로직은 `CharacterRig.animate(dt, state)` 하나만 호출하므로 (`scripts/character_rig.gd`),
모델을 바꿔도 전투·AI 코드는 건드릴 필요가 없습니다.

## 무료로 쓸 수 있는 에셋 예시

- [KayKit (Kay Lousberg)](https://kaylousberg.itch.io/) — 던전, 캐릭터, 무기 팩 (CC0, 애니메이션 포함)
- [Quaternius](https://quaternius.com/) — 판타지 캐릭터, 몬스터 (CC0)
- [Poly Pizza](https://poly.pizza/) — 다양한 로우폴리 모델 (라이선스 개별 확인)

에셋을 넣은 뒤 Godot 에디터를 한 번 열면 자동으로 가져오기(import)됩니다.
