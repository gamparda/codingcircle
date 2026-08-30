# Cat War

Godot 4로 만든 1대1 자동 전투 + 전장 개조 게임입니다. 온라인 대전은 별도 전용 서버가 모든 규칙과 전투를 판정하며, 서버 없이 실행되는 오프라인 AI 대전도 제공합니다.

## 프로그램 구성

이 저장소에는 **게임 클라이언트와 전용 서버 코드가 모두 포함**되어 있습니다. 두 프로그램은 서로 다른 코드 복사본이 아니라 같은 Godot 프로젝트와 같은 `BattleModel` 규칙을 공유합니다.

| 실행 방식 | 동작 |
|---|---|
| `CatWar.exe` | 게임 클라이언트와 오프라인 AI 대전 |
| `CatWar.exe --headless -- --server --port=7777` | 화면 없는 전용 서버 |
| 설치 후 시작 메뉴의 `Cat War Dedicated Server` | UDP 7777 전용 서버 실행 |

전용 서버가 같은 EXE를 서버 모드로 실행하는 구조이므로 클라이언트와 서버의 전투 규칙 버전이 어긋나지 않습니다. 서버 PC에는 `CatWar.exe`와 `StartServer.cmd`만 복사해도 됩니다.

## 주요 기능

- 중앙 전용 서버의 자동 1대1 매칭
- 서버 판정 자원, 생산, 이동, 공격, 회복, 피해, 승패
- 인터넷 없이 실행되는 오프라인 AI 대전
- 탱커 / 힐러 / 궁수 / 검사
- 벽 / 점프대 / 늪과 진영별 설치 구역
- 실시간 상태 스냅샷 동기화
- 연결 종료 처리와 양쪽 동의 재경기
- 투명 PNG 캐릭터와 픽셀아트 렌더링
- Windows 설치·제거 프로그램

## 설치 프로그램 사용

`dist/CatWarSetup.exe`를 더블 클릭하면 일반 Windows 응용프로그램처럼 설치됩니다.

설치되는 항목:

- `%LOCALAPPDATA%\Programs\Cat War\CatWar.exe`
- 시작 메뉴의 `Cat War`
- 시작 메뉴의 `Cat War Dedicated Server`
- 선택 가능한 바탕 화면 바로가기
- Windows 설정의 앱 제거 항목

현재 설치 파일은 코드 서명 인증서로 서명하지 않았으므로 다른 PC에서는 Windows SmartScreen 경고가 표시될 수 있습니다.

## 강제 자동 업데이트

`main` 브랜치에 코드가 푸시될 때마다 `.github/workflows/build-and-deploy.yml`이 다음 작업을 수행합니다.

1. 테스트 실행
2. 커밋과 GitHub Actions 실행 번호가 들어간 새 버전 빌드
3. Windows 게임/서버 EXE와 설치 프로그램 생성
4. 설치 프로그램 SHA-256 계산
5. 버전 태그와 GitHub Release 생성
6. GitHub Pages에 `update.json`과 `CatWarSetup.exe` 배포

게임은 `https://gamparda.github.io/codingcircle/update.json`을 시작 시점과 비전투 상태에서 60초마다 확인합니다. 최신 버전이 발견되면 업데이트를 건너뛸 수 없으며, 설치 파일을 다운로드하고 SHA-256을 검증한 다음 게임을 종료해 무인 설치하고 자동 재실행합니다.

- 메뉴·매칭 대기·결과 화면: 즉시 강제 업데이트
- 진행 중인 경기: 새 버전만 감지하고 다운로드·설치는 경기 종료까지 대기
- 전용 서버: 활성 매치가 없을 때만 설치 및 재시작
- 업데이트 서버 접속 실패: 현재 실행은 유지하고 나중에 자동 재시도

테스트를 통과한 최신 `main` 빌드가 곧 자동 업데이트 채널이자 GitHub Release가 됩니다. GitHub Pages 배포가 처음이라면 저장소의 **Settings → Pages → Source**가 `GitHub Actions`로 설정되어 있어야 합니다.

각 Release에는 다음 파일이 포함됩니다.

- `CatWarSetup.exe`
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

1. 게임 규칙 테스트 실행
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

버전을 직접 지정해 빌드할 수도 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1 -Version "0.3.12" -Commit "테스트커밋SHA"
```

## 수동 빌드

### 1. 테스트

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

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

`CatWar.exe`를 실행하고 **AI 훈련장**을 선택합니다. 서버나 인터넷 연결이 필요하지 않습니다.

## 소스 구조

```text
project.godot                 Godot 프로젝트 설정
scenes/Main.tscn              메인 장면
scripts/Main.gd               메뉴, HUD, 클라이언트/서버 실행 모드
scripts/BattleModel.gd        서버 권한형 전투 규칙
scripts/NetworkController.gd  ENet 연결, RPC, 서버 스냅샷
scripts/MatchRegistry.gd      1대1 매칭과 진영 배정
scripts/ServerAI.gd           오프라인 AI 판단
scripts/UpdateManager.gd      버전 확인, 다운로드, 해시 검증, 무인 업데이트
scripts/BattleView.gd         전장과 캐릭터 렌더링
build_info.json               현재 빌드 버전·커밋·업데이트 주소
assets/units/                 최종 투명 캐릭터 PNG
assets/source/role_sheets/    사용자가 제공한 원본 시트
tools/extract_sprites.py      원본 시트 배경 제거 도구
tools/build_release.ps1       테스트·EXE·설치 파일 통합 빌드
installer/CatWar.iss          Inno Setup 설치 프로그램 정의
.github/workflows/            푸시별 자동 테스트·빌드·Pages 배포
server/StartServer.cmd        Windows 서버 실행 런처
server/linux/                 Linux 자동 업데이트 서비스·타이머
tests/run_tests.gd            전투·회복·구조물·매칭 테스트
```

## 캐릭터 PNG 재생성

```powershell
python -m pip install -r .\tools\requirements.txt; python .\tools\extract_sprites.py
```

스크립트는 캔버스 외곽과 연결된 밝은 배경만 제거해 힐러의 흰 의상과 장비를 보존합니다. 원본 이미지 사용 안내는 `ASSET_SOURCES.md`를 참고하세요.

## 온라인 배포 체크리스트

1. 서버와 클라이언트를 같은 커밋에서 빌드합니다.
2. 공인 IP가 있는 Windows 서버에 `CatWar.exe`와 `StartServer.cmd`를 복사합니다.
3. UDP 7777 또는 선택한 포트를 허용합니다.
4. 서버를 먼저 실행합니다.
5. 클라이언트에서 서버 IP와 포트를 입력합니다.
6. 두 클라이언트가 접속해 한 경기를 완료하는지 확인합니다.
