# Keepfall

> 게임 이름은 Cat War에서 Keepfall로 바뀌었습니다. 실행 파일(`CatWar.exe`), 설치 프로그램, 서버 서비스, 저장 파일 이름은 기존 설치와 자동 업데이트가 끊기지 않도록 당분간 이전 이름을 그대로 씁니다.

밸런스 자동 대전과 데이터 수집 방법: [반복 가능한 밸런스 실험](docs/BALANCE_BENCHMARK.md).

Godot 4로 만든 1대1 자동 전투 + 전장 개조 게임입니다. 온라인 대전은 별도 전용 서버가 모든 규칙과 전투를 판정하며, 서버 없이 실행되는 오프라인 AI 대전도 제공합니다.

## 프로그램 구성

이 저장소에는 **게임 클라이언트와 전용 서버 코드가 모두 포함**되어 있습니다. 두 프로그램은 서로 다른 코드 복사본이 아니라 같은 Godot 프로젝트와 같은 `BattleModel` 규칙을 공유합니다.

| 실행 방식 | 동작 |
|---|---|
| `CatWar.exe` | 게임 클라이언트와 오프라인 AI 대전 |
| `CatWar.apk` | Android 클라이언트와 오프라인 AI 대전 |
| `CatWar.exe --headless -- --server --port=7777` | 화면 없는 전용 서버 |
| 설치 후 시작 메뉴의 `Cat War Dedicated Server` | UDP 7777 전용 서버 실행 |

전용 서버가 같은 EXE를 서버 모드로 실행하는 구조이므로 클라이언트와 서버의 전투 규칙 버전이 어긋나지 않습니다. 서버 PC에는 `CatWar.exe`와 `StartServer.cmd`만 복사해도 됩니다.

## 주요 기능

게임 규칙의 세부 수치(비용·체력·공격력 등)는 README에 적지 않습니다. 실제 값은 `data/units`, `data/structures`의 `.tres` 리소스가 정하고, 현재 표는 [docs/UNITS.md](docs/UNITS.md)에 자동 생성됩니다. 변경 이력은 게임 내 패치노트와 `CHANGELOG.md`에 있습니다.

**전투**
- 1대1 자동 전투와 전장 개조: 7종 유닛 중 3종, 4종 구조물 중 3종으로 덱을 구성하고 자원으로 병력을 생산하거나 구조물을 설치합니다.
- 서버 권한형 판정: 자원·생산·이동·공격·승패를 전용 서버가 같은 `BattleModel` 규칙으로 계산하고 스냅샷으로 동기화합니다.
- 동시 공격 판정, 지원·광폭화·장판·소환 같은 유닛별 특수 능력, 방벽·늪·포탑·발전기 구조물.
- 기지가 먼저 파괴된 쪽이 패배하며 시간 제한은 없습니다.

**온라인**
- 방 기반 멀티플레이: 대기방·준비·방장 시작·같은 방 재대전·비밀번호·방 채팅·관전. 연결이 끊기면 제한 시간 동안 재접속을 기다리며 전투를 일시정지합니다.
- **빠른 대전**: 로비의 버튼 하나로 대기열에 들어가 먼저 기다린 두 플레이어가 자동으로 방을 만들고 바로 시작합니다. 언제든 취소할 수 있습니다.
- 온라인에서는 양쪽 모두 아군이 왼쪽인 시점으로 표시합니다. 서버 좌표는 바뀌지 않습니다.

**오프라인**
- 서버 없이 즐기는 8단계 AI 캠페인(별 1~3개 평가, 진행·성장 저장)과 자유 연습.
- 첫 AI 전투에서 소환→설치→자원 회복을 실제 행동에 맞춰 안내합니다(건너뛰기 가능).

**일일 도전·업적·덱 시뮬레이터**

- 메인 메뉴의 **일일 도전**은 매일 모두에게 같은 덱·AI 단계·규칙 변형을 주고 점수와 연속 클리어를 기록합니다.
- 기록 화면의 **업적**에서 달성한 배지를 볼 수 있고, 덱 편성의 **덱 시뮬레이션**은 AI와 자동 전투를 돌려 승률과 약점을 알려 줍니다.

**보조 서버와 계산 돕기**

- 별도 설정 없이 도우미를 받습니다(인증 없음, 가벼운 제한만 있음). `CATWAR_ASSIST=off`로 끌 수 있습니다. 자세한 구조는 [보조 서버·계산 돕기 설계](docs/ASSIST_DESIGN.md)를 참고하세요.
- **보조 서버**: 설치 후 시작 메뉴의 `Keepfall Assist Server`(또는 `server/StartAssist.cmd`)를 실행하면 창이 열립니다. 메인 서버 주소와 토큰을 넣고 연결하면, 체크한 종류의 작업만 받아 계산하고 현재 작업과 로그를 보여 줍니다. **종료 (마무리 후)**는 하던 조각을 끝내고 결과를 보낸 뒤 알리며, 남은 일은 메인 서버가 다시 배정합니다. 포트포워딩은 필요 없습니다(모든 연결을 도우미가 먼저 겁니다).
- **계산 돕기**: 게임 설정의 같은 이름 항목에 토큰을 넣고 켜면, 메뉴 화면에서 남는 CPU로 서버의 계산을 돕습니다. 전투 중에는 쉬고, 멀티플레이와는 별도 연결을 씁니다.
- 도우미가 없어도 메인 서버가 같은 작업을 낮은 우선순위로 직접 처리합니다.

**데이터 초기화**

- 설정 화면 맨 아래의 **데이터 전체 초기화**는 이 기기에 저장된 전적·진행도·업적·덱·설정·리플레이·통계 캐시를 모두 지우고 처음 상태로 돌립니다. 지워지는 항목을 확인한 뒤 잠시 기다려야 삭제할 수 있고, 서버에 이미 올라간 기록은 지워지지 않습니다.

**시작 목표와 라이브 전투 목록**

- 메인 메뉴의 **시작 목표** 칩이 처음 해 볼 만한 일(첫 승리, 덱 만들기, 일일 도전, 드래프트, 리플레이 보기, 온라인 대전)을 체크리스트로 보여 주고 바로 이동하게 해 줍니다. 결과 화면에도 방금 달성한 목표와 다음 추천이 나옵니다.
- 멀티플레이 방 목록은 진행 중인 전투의 닉네임·덱·진행 시간을 보여 주고(잠긴 방은 제외), **전체 / 대기 중 / 라이브 전투** 필터를 제공합니다. 어느 전투든 목록에서 바로 관전할 수 있습니다.

**주간 도전·드래프트**

- 메인 메뉴의 **주간 도전**은 한 주 동안 모두에게 같은 덱과 두 가지 규칙 변형을 주는 더 어려운 도전이고, 일일 도전과 별도로 점수와 순위표가 있습니다.
- **드래프트**는 AI와 번갈아 병력을 뽑아 덱을 만든 뒤 싸웁니다. 한 번 뽑힌 병력은 상대가 쓸 수 없고, 결과는 전적에 기록되지 않습니다.
- 메인 메뉴의 **새 기능** 칩과 NEW 표시가 아직 써 보지 않은 기능을 알려 줍니다.
- 기지가 파괴되면 결과 화면 전에 슬로모션 붕괴 연출이 나옵니다.

**전체 플레이어 통계와 일일 순위표**

- 서버는 온라인 대전이 끝날 때마다 덱 조합별 승패 카운터만 익명으로 집계합니다(닉네임·IP·명령 기록은 저장하지 않음). 덱 분석과 덱 시뮬레이터에서 "전체 플레이어 승률"로 확인할 수 있고, 규칙 버전이 바뀌면 새로 집계합니다.
- 설정 없이 읽을 수 있고, **내 결과 보내기**를 켠 경우에만 캠페인·연습·일일 도전 결과와 일일 점수가 서버로 전송됩니다(기본 꺼짐). 순위표에는 닉네임이 표시됩니다.
- 보고된 결과는 현재 클라이언트가 보낸 대로 믿습니다. 서버는 온라인 대전 집계와 보고 집계를 따로 보관하고 `ServerDailyBoard.verifier`를 걸 수 있어, 이상치가 생기면 검증을 추가할 수 있습니다.

**리플레이**
- 서버가 진행한 모든 온라인 전투와 AI 캠페인·(도구를 쓰지 않은) AI 연습 전투는 플레이어 명령만 `user://replays/`에 JSON으로 저장됩니다(최근 50개 유지). 전투가 결정론적이므로 같은 규칙으로 다시 계산하면 결과가 똑같이 재현됩니다.
- 메인 메뉴의 **리플레이**에서 저장된 전투를 목록으로 보고 재생·삭제할 수 있습니다. 재생 화면은 일시정지, 0.5~8배속, 처음부터 다시 보기, 시간 막대로 원하는 지점 이동을 지원합니다.
- **전세 그래프:** 재생 화면 아래에 어느 쪽이 앞서는지 보여주는 곡선(파랑 위·빨강 아래)이 그려지고, 첫 교전·구조물 파괴·기지 체력 위기·전세 역전·결정타가 마커로 표시됩니다. 곡선이나 마커를 눌러 이동하거나 **이전/다음 순간** 버튼으로 하이라이트를 건너뛸 수 있습니다. 단축키: Space 일시정지, ←/→ 5초 이동, N/P 다음/이전 순간.
- 리플레이는 **코드** 버튼으로 서버에 올려 짧은 코드로 공유하고, **코드로 열기**로 코드를 입력해 봅니다. **최근 온라인 전투**에는 서버가 기록한 온라인 전투가 공개 목록으로 나옵니다(덱과 명령만 담기며 닉네임은 담기지 않습니다). 이 기능들은 필요할 때 자동으로 서버에 접속합니다(접속하지 못하면 이유를 안내합니다).
- 재생 화면에서 **구간 반복**(시작·끝 지점 지정), 유닛을 눌러 보는 **정보 패널**, 마우스 휠 **확대**와 가운데 버튼 **이동**을 쓸 수 있습니다.
- 재생 화면에서 장면마다 **메모**를 남길 수 있고, 메모는 리플레이와 함께 저장·공유됩니다.
- 리플레이는 **복사** 버튼으로 한 줄 텍스트가 되어 클립보드에 복사되고, 다른 사람이 **클립보드에서 가져오기**로 목록에 추가할 수 있습니다(손상·조작된 텍스트는 거부).
- 리플레이 뷰어의 **클립** 버튼은 명장면 앞뒤 10초를 텍스트로 복사하고, **되감기 실험**은 원하는 순간부터 직접 이어서 플레이합니다. 목록의 **고스트 대전**은 리플레이 속 상대의 행동을 재현한 상대와 겨루고, **덱 분석**은 저장된 리플레이로 덱 성적을 모아 보여 줍니다.
- 규칙이 바뀐 뒤에도 결과가 같은지 검증하거나 밸런스·버그 재현에 쓸 수도 있습니다. [리플레이 사용법](#리플레이-사용법)을 참고하세요.

**기타**
- 한국어 전용, 오디오(BGM·효과음)·화면·전투 연출·키 설정. 버튼·전투 카드·결과 화면의 UI 효과음은 실행 중 합성하므로 별도 음원 파일이 없습니다.
- 터치 기기에서는 모든 버튼과 슬라이더가 손가락 크기(최소 높이 58)로 커집니다. 제목과 큰 숫자에는 번들 글꼴 Black Han Sans(OFL)를 씁니다.
- 개인 전적과 덱 프리셋 저장, 투명 PNG 캐릭터와 픽셀아트 렌더링.
- Windows 설치·제거 프로그램, Android ARMv7·ARM64 서명 APK와 설치 화면 없이 갱신되는 콘텐츠 팩.

## 설치 프로그램 사용

`dist/CatWarSetup.exe`를 더블 클릭하면 일반 Windows 응용프로그램처럼 설치됩니다.

설치되는 항목:

- `%LOCALAPPDATA%\Programs\Cat War\CatWar.exe`
- 시작 메뉴의 `Cat War`
- 시작 메뉴의 `Cat War Dedicated Server`
- 선택 가능한 바탕 화면 바로가기
- Windows 설정의 앱 제거 항목

현재 설치 파일은 코드 서명 인증서로 서명하지 않았으므로 다른 PC에서는 Windows SmartScreen 경고가 표시될 수 있습니다.

Android에서는 Release의 `CatWar.apk`를 내려받아 최초 한 번 설치합니다. 이후 일반적인 게임 코드·장면·이미지·음원 업데이트는 실행 시 `CatWarContent.pck`를 자동으로 내려받아 적용하므로 APK 설치 화면이 나타나지 않습니다. Godot 엔진, Android 권한 또는 네이티브 설정이 변경된 때만 새 APK 설치가 필요합니다. 매 릴리스 최신 콘텐츠를 포함한 APK를 같은 전용 키로 새로 빌드하며, 콘텐츠만 바뀐 경우 네이티브 버전을 유지해 기존 설치자에게 불필요한 APK 업데이트를 강제하지 않습니다.

## 강제 자동 업데이트

`main` 브랜치에 코드가 푸시될 때마다 `.github/workflows/build-and-deploy.yml`이 다음 작업을 수행합니다.

1. 테스트 묶음(unit · network · ui · security · balance · release)을 병렬 job으로 실행
2. `release.json`에 지정된 출시 버전과 대상 커밋으로 새 빌드 생성
3. Windows 게임/서버 EXE·설치 프로그램, Android APK와 콘텐츠 팩 생성
4. 설치 프로그램·APK·콘텐츠 팩의 SHA-256 및 APK 서명 검증
5. 새 버전일 때만 버전 태그와 GitHub Release 생성(기존 태그는 덮어쓰지 않음)
6. GitHub Pages에 `update.json`, `CatWarSetup.exe`, `CatWar.apk`, `CatWarContent.pck` 배포

게임은 `https://gamparda.github.io/codingcircle/update.json`을 시작 시점과 비전투 상태에서 60초마다 확인합니다. 최신 버전이 발견되면 업데이트를 건너뛸 수 없으며, 설치 파일을 다운로드하고 SHA-256을 검증한 다음 게임을 종료해 무인 설치하고 자동 재실행합니다.

Android 부트스트랩은 실행 직후 같은 메타데이터를 확인합니다. APK 자체 교체가 필요하면 **APK 업데이트가 필요합니다.** 안내와 다운로드 버튼을 표시합니다. 콘텐츠 팩만 더 최신이면 앱 전용 저장소로 자동 다운로드하고 SHA-256을 검증한 뒤 원자적으로 교체합니다. 새 팩은 메인 장면이 5초 이상 안정적으로 실행된 뒤에만 부팅 성공으로 확정하며, 그 전에 종료되면 다음 실행에서 보관한 이전 팩 또는 APK 내장 버전으로 복구합니다. 네트워크가 끊겼을 때는 **현재 버전으로 시작**할 수 있으며 다음 실행에서 다시 자동 확인합니다.

- 메뉴·매칭 대기·결과 화면: 즉시 강제 업데이트
- 진행 중인 경기: 새 버전만 감지하고 다운로드·설치는 경기 종료까지 대기
- 전용 서버: 활성 매치가 없을 때만 설치 및 재시작
- 업데이트 서버 접속 실패: 현재 실행은 유지하고 나중에 자동 재시도

테스트를 통과한 최신 `main` 빌드가 곧 자동 업데이트 채널(GitHub Pages)이 됩니다. GitHub Release는 **새 버전 번호일 때만** 만들어집니다.

### 버전 관리

버전은 **`release.json` 한 곳에서만** 고칩니다.

```json
{ "content_version": "0.15.2", "windows_version": "0.15.2", "android_binary_version": "0.4.18", "update_url": "..." }
```

```powershell
python tools/release_meta.py sync    # release.json → build_info.json, project.godot, export_presets.cfg
python tools/release_meta.py check   # 생성 파일이 release.json과 어긋나면 실패(CI가 실행)
```

Android 네이티브 바이너리 버전은 콘텐츠·Windows 버전과 독립적으로 유지합니다. 빌드 스크립트는 `build_info.json`의 커밋 값을 실제 대상 SHA로 교체하고, Pages용 `update.json`은 workflow가 SHA-256과 배포 시각을 포함해 생성합니다.

### 정식 릴리스와 개발 빌드

- `release.json`의 `content_version`이 **새 값**이면 `v<버전>` 태그와 GitHub Release가 만들어집니다.
- 이미 존재하는 태그는 **덮어쓰지 않습니다.** 같은 버전으로 다시 푸시하면 업데이트 채널(Pages)만 갱신되고 산출물은 `dev-build-*` workflow 아티팩트(14일 보관)로만 남습니다. 정식 릴리스를 새로 내려면 `release.json`의 버전을 올리세요.
- GitHub Pages 배포가 처음이라면 저장소의 **Settings → Pages → Source**가 `GitHub Actions`로 설정되어 있어야 합니다.

각 Release에는 다음 파일이 포함됩니다.

- `CatWarSetup.exe`
- `CatWar.apk`
- `CatWarContent.pck`
- `update.json`
- `SHA256SUMS.txt`
- GitHub가 자동 생성하는 소스 ZIP과 TAR.GZ
- 이전 버전 이후의 자동 변경 내역

버전별 수동 다운로드는 [GitHub Releases](https://github.com/gamparda/codingcircle/releases)에서 할 수 있습니다.

## 개발 환경 준비

Windows PowerShell에서 필요한 프로그램을 설치합니다.

```powershell
winget install --id GodotEngine.GodotEngine --exact; winget install --id JRSoftware.InnoSetup --exact
```

Godot 4.7.2 편집기에서 **Editor → Manage Export Templates**를 열고 같은 버전의 Export Templates를 설치해야 Windows EXE를 내보낼 수 있습니다.

## 한 번에 전체 빌드

저장소 루트에서 다음 한 줄을 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1
```

스크립트가 순서대로 수행하는 작업:

1. 게임 규칙·v0.4 기능·UI 흐름 테스트 실행
2. Windows용 게임/서버 겸용 `CatWar.exe` 생성
3. 생성된 EXE의 오프라인 AI 모드 실행 검증
4. Inno Setup으로 설치 프로그램 생성

결과물:

```text
builds/CatWar.exe

dist/CatWarSetup.exe
```

Godot 또는 Inno Setup을 사용자 지정 위치에 설치했다면 다음처럼 경로를 넘길 수 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1 -GodotPath "C:\경로\godot_console.exe" -IsccPath "C:\경로\ISCC.exe"
```

대상 커밋을 지정하거나 테스트를 건너뛸 수 있습니다. 버전 번호는 인자로 바꾸지 않고 `release.json`을 고칩니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1 -Version "0.4.2" -Commit "테스트커밋SHA"
```

## 수동 빌드

### 1. 테스트

```powershell
python tools/run_suite.py all        # unit · network · ui · security · balance · release
python tools/run_suite.py unit ui    # 일부만
```

자세한 구성은 [테스트](#테스트)를 참고하세요.

### 2. 게임과 서버 겸용 EXE

```powershell
godot --headless --path . --export-release "Windows Desktop" "$PWD\builds\CatWar.exe"
```

### 3. 설치 프로그램

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" .\installer\CatWar.iss
```

## 실행 방법

### 게임 클라이언트

```powershell
.\builds\CatWar.exe
```

온라인 대전은 주소 입력 없이 공식 서버 `ruellyya.kr:7777`에 연결됩니다. 일반 클라이언트에서는 다른 서버 주소로 변경할 수 없습니다.

### 전용 서버

```powershell
.\builds\CatWar.exe --headless -- --server --port=7777
```

또는 다음 런처를 사용합니다.

```powershell
.\server\StartServer.cmd 7777
```

서버는 **UDP**를 사용합니다. 서버 PC의 Windows 방화벽, 공유기 포트 포워딩 또는 클라우드 보안 그룹에서 선택한 UDP 포트를 허용해야 합니다.

### 오프라인 AI 대전

Windows 또는 Android 클라이언트를 실행하고 **AI 캠페인** 또는 **AI 연습**을 선택합니다. 서버나 인터넷 연결이 필요하지 않습니다.

## 소스 구조

```text
project.godot                 Godot 프로젝트 설정
release.json                  버전의 유일한 원본 (콘텐츠·Windows·Android 바이너리)
build_info.json               release.json에서 생성되는 빌드 버전·커밋·업데이트 주소
data/units, data/structures   유닛·구조물 수치 (.tres Resource) — 전투·UI·AI 공용
scenes/Bootstrap.tscn         Android 콘텐츠 확인·복구 후 게임을 여는 시작 장면
scenes/Main.tscn              메인 게임 장면
scenes/ui/                    화면 프레임·기록·패치노트·덱 편성·리플레이 목록 등 .tscn 화면
scripts/Main.gd               실행 모드, 입력, 화면 전환, 클라이언트/서버 연결
scripts/screens/              Main에서 분리한 화면과 흐름: MenuScreens, DeckScreen, SettingsScreen,
                              BattleHud, BattleFlow, LobbyFlow, ResultScreens, ReplayScreens,
                              UpdateOverlay, Tutorial, PracticeUI
scripts/net/                  NetworkController에서 분리한 서버·클라이언트 흐름:
                              SessionFlow, ReconnectFlow, ClientSessionFlow
scripts/ui/                   UIKit(팔레트·테마·그라데이션 스타일), UISounds, HeroShowcase, HpBar,
                              ToastLabel, ReplayViewer, MomentumGraph, .tscn 화면에 붙는 스크립트
assets/fonts/                 Black Han Sans(OFL)와 라이선스
scripts/MultiplayerUI.gd      로비·대기실·방 만들기 UI
scripts/BattleModel.gd        서버 권한형 전투 규칙
scripts/data/                 UnitDef·StructureDef Resource와 GameData 로더
scripts/BattleReplay.gd       리플레이 기록·검증·재생
scripts/ReplayAnalysis.gd     리플레이 전세 곡선·하이라이트 분석
scripts/AutoPlayer.gd         자동 플레이 봇(시뮬레이터·밸런스 도구 공용)
scripts/DeckSimulator.gd      덱 자동 전투 시뮬레이션
scripts/DeckAnalysis.gd       리플레이 기반 덱 성적 집계
scripts/Achievements.gd       업적 정의·판정
scripts/GhostOpponent.gd      리플레이 행동을 재현하는 고스트 상대
scripts/DailyChallenge.gd     일일·주간 도전 생성·점수
scripts/DraftMatch.gd         드래프트 규칙·AI 선택·전투 구성
scripts/NewFeatures.gd        새 기능 안내와 NEW 표시
scripts/DataReset.gd          데이터 전체 초기화
scripts/jobs/                 작업 큐·실행기·메인 서버 허브(AssistHub)
scripts/assist/               보조 서버 창·작업자·계산 돕기 서비스
scripts/Goals.gd              시작 목표 체크리스트
scripts/ServerReplayShelf.gd  서버 리플레이 코드 보관함
scripts/screens/DraftScreen.gd 드래프트 화면
scripts/ServerStats.gd        서버 덱 통계 집계·저장
scripts/ServerDailyBoard.gd   서버 일일 순위표
scripts/MetaStats.gd          클라이언트 통계 캐시·결과 전송 큐
scripts/screens/MetaStatsUI.gd 통계 카드·순위표·공유 스위치
scripts/NetworkController.gd  ENet 연결, RPC 진입점, 방·재접속·빠른 대전 흐름
scripts/NetworkProtocol.gd    네트워크 페이로드 검증과 프로토콜 상수
scripts/PeerAdmission.gd      요청 속도 제한과 주소별 접속 수
scripts/ServerBattle.gd       서버 전투 틱·스냅샷 주기·진행 중 매치
scripts/ServerReplays.gd      서버 리플레이 기록과 저장
scripts/QuickQueue.gd         빠른 대전 대기열
scripts/RoomSessions.gd       방·멤버·준비·채팅 상태
scripts/MatchRegistry.gd      매치와 진영 배정
scripts/ServerAI.gd           오프라인 AI 판단
scripts/SaveData.gd           덱·캠페인·전적·설정 저장 및 검증
scripts/UpdateManager.gd      버전 확인, 다운로드, 해시 검증, 무인 업데이트
scripts/BattleView.gd         전장과 캐릭터 렌더링
assets/units/                 최종 투명 캐릭터 PNG
assets/source/role_sheets/    사용자가 제공한 원본 시트
tools/run_suite.py            테스트 묶음 실행기 (tests/suites.json)
tools/release_meta.py         release.json 동기화·검증
tools/gen_unit_docs.py        data/ → docs/UNITS.md 생성
tools/replay_tool.gd          저장된 리플레이 재계산·검증
tools/build_release.ps1       테스트·EXE·설치 파일 통합 빌드
installer/CatWar.iss          Inno Setup 설치 프로그램 정의
.github/workflows/            푸시별 자동 테스트·빌드·Pages 배포
server/                       Windows 서버 런처, Linux 자동 업데이트 서비스·타이머
tests/                        suites.json 으로 묶인 회귀 테스트
```

## 데이터와 밸런스

- 유닛·구조물 수치는 `data/units/*.tres`, `data/structures/*.tres`에서 **한 번만** 정의합니다. 새 파일을 추가하면 `scripts/data/GameData.gd`의 목록에도 등록해야 하며 `tests/unit_data_test.gd`가 누락을 잡습니다.
- 수치를 바꾼 뒤 `python tools/gen_unit_docs.py`로 [docs/UNITS.md](docs/UNITS.md)를 갱신합니다(테스트가 최신 여부를 확인).
- 대규모 자동 대전 실험은 [docs/BALANCE_BENCHMARK.md](docs/BALANCE_BENCHMARK.md), 지난 조정 결과는 [docs/BALANCE_RESULTS.md](docs/BALANCE_RESULTS.md)를 참고하세요.

## 테스트

`tests/suites.json`이 모든 테스트를 묶음으로 나눕니다. 새 테스트 파일은 반드시 한 묶음에 등록해야 하며 `suites_cover_all_tests_test.py`가 확인합니다.

| 묶음 | 내용 |
|---|---|
| `unit` | 전투 규칙, 데이터, AI, 저장, 리플레이 |
| `network` | 프로토콜, 방·재접속·빠른 대전(실제 2~4 클라이언트 RPC 포함) |
| `ui` | 메뉴·덱·전투 HUD·대기방·.tscn 화면·리플레이 뷰어·터치 크기 검사 |
| `security` | 업데이트 스크립트와 설치 프로그램 보안 |
| `balance` | 벤치마크 구매 정책, 밸런스 데이터 무결성, 수치 문서 최신 여부 |
| `release` | 버전 정책, 번역 카탈로그, 묶음 누락 검사 |
| `render` · `production` | `all`에 포함되지 않음. 실제 화면(xvfb/GPU)이나 운영 서버가 필요한 수동 점검 |

```powershell
python tools/run_suite.py all
```

## 리플레이 사용법

```powershell
# 저장된 모든 리플레이를 다시 계산해 기록된 결과와 같은지 검증 (규칙이 바뀌면 실패)
godot --headless --path . --script res://tools/replay_tool.gd -- --all
# 특정 파일
godot --headless --path . --script res://tools/replay_tool.gd -- --file=user://replays/파일.json
```

파일에는 초기 덱·자원·기지 체력, 틱 번호가 붙은 생산/설치 명령, AI 단계(있는 경우), 결과 해시만 들어 있어 보통 수 KB입니다. 서버 매치는 30Hz 고정 간격, 캠페인 전투도 30Hz 고정 간격으로 진행되어 결과가 정확히 재현됩니다.

## 캐릭터 PNG 재생성

```powershell
python -m pip install -r .\tools\requirements.txt; python .\tools\extract_sprites.py
```

스크립트는 캔버스 외곽과 연결된 밝은 배경만 제거해 힐러의 흰 의상과 장비를 보존합니다. 원본 이미지 사용 안내는 `ASSET_SOURCES.md`를 참고하세요.

## 온라인 배포 체크리스트

1. 서버와 클라이언트를 같은 커밋에서 빌드합니다.
2. 중앙 Linux 전용 서버의 updater가 최신 `main`을 설치하도록 합니다. 플레이어 호스트/LAN 대전은 지원하지 않습니다.
3. 외부 UDP 7777을 전용 서버로 전달하고 방화벽에서 허용합니다.
4. `catwar-server.service`와 `catwar-update.timer`가 활성 상태인지 확인합니다.
5. 두 클라이언트가 공식 서버에 접속해 서로 다른 진영과 같은 매치 스냅샷을 받는지 확인합니다.
6. 같은 LAN에서는 NAT loopback 우회를 위해 `192.168.0.4:7777`, 외부에서는 `ruellyya.kr:7777`과 공인 IP fallback을 사용합니다. 모두 동일한 중앙 서버 경로입니다.

## 방 기반 멀티플레이

멀티플레이 → 닉네임·덱 선택 → 방 생성/참가 → 준비 → 방장 시작 → 결과 → 같은 방에서 재대전. 비밀번호는 선택이며 관전 입장에도 적용됩니다. 대기실과 전투에서 방 채팅을 사용할 수 있고, 진행 중인 경기에도 관전할 수 있습니다. 관전자에게 전투 조작 권한이나 개인 승패 기록은 부여하지 않습니다. 방장 이탈 시 남은 플레이어에게 소유권을 넘기고, 마지막 플레이어가 나가면 방을 정리합니다. 방 비밀번호는 게임 입장용이며 ENet 게임·채팅 전체의 TLS/종단간 암호화를 의미하지 않습니다.
