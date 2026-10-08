# 온라인(클라우드) 서버 운영 — AWS 기준

친구 PC를 호스트로 쓰는 방식(포트포워딩/Tailscale 필요) 대신, **클라우드에 항상 켜진 서버**를 두는 방식입니다.

```
 [플레이어 PC] ──UDP 7777──▶ [클라우드 서버: Godot 전용 서버 (Docker)]
 [플레이어 PC] ──UDP 7777──▶        │  레이드 시뮬레이션 (서버 권한)
                                    └─ 계정 DB  /data/accounts  (디스크/볼륨)
```

- **계정**: 이름 + PIN으로 로그인. 처음 접속하면 계정이 생깁니다.
- **서버 저장**: 보관함·골드·장비·통계는 서버 계정 DB가 원본입니다. 상점 구매/판매/장착 같은 로비 조작도 서버가 검사해서 처리합니다 (클라이언트가 장비나 골드를 조작할 수 없음).
- **레이드**: 입장할 때 서버가 계정에서 장비를 꺼내고, 탈출/사망 결과도 서버가 계정에 기록합니다. 레이드 중 접속이 끊기면 사망 처리됩니다.
- 내 PC의 오프라인 저장 파일은 건드리지 않습니다 (혼자 하기/친구 호스트용으로 그대로 남음).

## 0. 수용 인원 (공개 서비스 기준)

- **동시 접속 100명** (`Net.SERVER_CAP`). 101번째 사람에게는 "서버가 가득 찼습니다 (100/100)" 안내 후 접속 종료.
- **레이드는 여러 개 동시에** 진행됩니다. 같은 맵 대기방에서 최대 **12명**(`Net.RAID_MAX`)씩 묶어 레이드 하나로 보내고, 남은 사람은 다음 레이드로.
- **부하 측정** (서버 PC에서): `godot --headless --path godot -- --loadtest 9` → 레이드 9개 × 11명(99명)을 동시에 돌려 서버 한 틱 시간을 출력.
  - 개발 환경(4코어 클라우드 VM) 측정: 99명·액터 약 1000개에서 **틱 평균 약 21ms (초당 약 47틱)**, 메모리 약 450MB. 서버는 스냅샷을 초당 20번 보내므로 여유가 있음.
  - 권장 서버: **vCPU 2개 · 메모리 2~4GB** 이상 (Lightsail 2GB/4GB 요금제, EC2 t3.medium / c6i.large 등). 게임 로직은 한 코어를 주로 씀 → 코어 성능이 높을수록 좋음.
- **네트워크**: 플레이어 한 명당 약 40KB/s (주변 75m 안의 캐릭터만 보냄) → 100명이면 약 4MB/s. 데이터 전송량 한도가 있는 요금제는 한도를 확인하세요.
- **계정 보호**: 같은 계정 PIN 5번 실패 → 5분 잠금, 같은 주소(IP)에서 새 계정은 1시간에 3개까지. PIN은 소금(salt)을 친 반복 해시로 저장.
- 아직 남은 공개 서비스 준비: 통신 암호화(DTLS), 이메일/비밀번호 같은 정식 로그인, 사람이 더 많아지면 서버 여러 대로 나누기.

## 1. AWS Lightsail로 서버 만들기 (가장 쉬움)

1. [AWS Lightsail](https://lightsail.aws.amazon.com/) → **인스턴스 생성**
   - 지역: 서울 (ap-northeast-2)
   - 플랫폼: Linux/Unix → **OS 전용** → **Ubuntu 24.04 LTS**
   - 요금제: **메모리 1GB 이상** (서버는 CPU 1개, 메모리 수백 MB 정도 사용). 정확한 가격은 Lightsail 화면에서 확인하세요.
2. 인스턴스 → **네트워킹** 탭
   - **고정 IP 생성** 후 인스턴스에 연결 (재시작해도 주소가 안 바뀌게)
   - **IPv4 방화벽 → 규칙 추가**: 애플리케이션 `사용자 지정`, 프로토콜 **UDP**, 포트 **7777**
3. **SSH를 사용하여 연결** (브라우저 터미널) 후:

```bash
# Docker 설치
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# 게임 코드 받기 (작업 브랜치)
git clone -b claude/youthful-davinci-idnz60 https://github.com/lapirus1008/dungeon-reborn.git
cd dungeon-reborn

# 서버 빌드 + 실행 (재부팅 시 자동 시작)
docker compose -f server/docker-compose.yml up -d --build

# 로그 확인: "[server] ... UDP 포트 7777, 계정 서버 저장" 이 보이면 성공
docker compose -f server/docker-compose.yml logs -f
```

> 저장소가 비공개(private)라면 `git clone` 할 때 GitHub 개인 액세스 토큰이 필요합니다.

4. 게임에서: 로비 → **함께하기** → 주소에 **고정 IP**, 포트 7777, 이름과 **PIN** 입력 → **🔗 접속**
   - **⚔ 던전 입장 → 맵 선택**으로 대기방에 들어가면 같은 맵을 고른 사람끼리 최소 10초 ~ 최대 60초 뒤 함께 입장합니다.
   - 오른쪽 위 골드 옆에 `☁ 이름` 이 보이면 서버 계정을 쓰는 중입니다.

### EC2를 쓰는 경우

Lightsail 대신 EC2(t3.micro/t3.small 등, Ubuntu)도 같습니다. **보안 그룹 인바운드 규칙**에 `UDP 7777 / 0.0.0.0/0` 을 추가하고 Elastic IP를 연결한 뒤 위 3번 명령을 그대로 실행하세요.

## 2. 업데이트

게임 코드를 고친 뒤 (모든 플레이어도 같은 버전이어야 접속됩니다):

```bash
cd dungeon-reborn
git pull
docker compose -f server/docker-compose.yml up -d --build
```

계정 데이터는 `server/data/accounts/` (컨테이너 안 `/data`)에 있어 업데이트해도 유지됩니다.

## 3. 백업

- 간단: `server/data/accounts/` 폴더를 주기적으로 복사 (`tar czf accounts-$(date +%F).tgz server/data`)
- AWS: Lightsail **스냅샷** 자동 생성 켜기 (인스턴스 → 스냅샷 → 자동 스냅샷), EC2면 EBS 스냅샷/AWS Backup
- S3로 보내기 (선택): `aws s3 cp accounts-*.tgz s3://내-버킷/` 를 cron으로

## 4. 서버 옵션

| 옵션 | 뜻 |
|---|---|
| `--port 7777` | UDP 포트 |
| `--accounts /data/accounts` | 계정 DB 폴더 (기본: Godot user:// 아래 accounts) |
| `--no-accounts` | 계정 없이 각자 PC 저장 파일 사용 (예전 방식) |
| `--pvp` | 개인전 서버 (같이 들어간 사람도 적) |

Docker 없이 실행: `godot --headless --path godot -- --server --port 7777 --accounts ~/dr-accounts`

## 5. 확장 / 다른 DB로 옮기기

지금 계정 DB는 **계정별 JSON 파일**(서버 디스크)입니다. 서버 한 대에 친구~수십 명 규모면 이걸로 충분하고 비용도 서버 한 대 값뿐입니다.

더 커지면 `godot/scripts/account_store.gd` 의 `_read` / `_write` 두 함수만 바꾸면 됩니다.

| 단계 | 구성 |
|---|---|
| 지금 | Lightsail/EC2 한 대 + Docker + 디스크(JSON) + 스냅샷 백업 |
| 서버 여러 대 | 계정 저장소를 공용 DB로: **DynamoDB**(키 = 계정 키, 값 = JSON) 또는 **RDS PostgreSQL**(jsonb 컬럼). 서버는 IAM 역할로 접근 |
| 매치메이킹 | 로비 서버(접속·계정) + 레이드 서버(ECS/GameLift로 필요할 때 띄움)로 분리 |

## 보안 참고

자세한 위협 모델, 적용한 대책, 남은 한계, 운영 점검표는 [SECURITY.md](../SECURITY.md)를 보세요.

- 게임 통신은 **DTLS로 암호화**됩니다 (서버 키는 `data/accounts/_server_tls.key`에 처음 실행 때 생성).
  다만 클라이언트가 서버 인증서를 검증하지는 않으므로 **다른 곳에서 쓰는 비밀번호를 PIN으로 쓰지 마세요.**
- PIN은 서버에 **솔트 + 반복 해시**로만 저장됩니다. 새 계정 PIN은 6자 이상.
- 같은 계정으로 동시에 두 번 접속할 수 없습니다.
- 서버가 레이드와 로비 조작을 모두 검사하므로, 클라이언트를 고쳐도 아이템/골드를 만들어 낼 수 없습니다.
  이동은 반응성을 위해 클라이언트 위치를 받아들이되, **이동 속도 한도 안에서만** 따라갑니다.
