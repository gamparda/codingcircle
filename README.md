# Sidebeat Lanes

오른쪽에서 왼쪽으로 노트가 이동하는 브라우저 리듬게임과 관리자용 채보 제작 스튜디오입니다.

## 화면 분리

- 플레이어 메인 UI: <http://localhost:5173/>
- 관리자 채보 스튜디오: <http://localhost:5173/admin.html>

메인 UI는 게임 플레이에 집중합니다. 관리자 스튜디오에서 곡/채보를 저장하면 플레이 화면의 라이브러리 선택에서 바로 불러와 실행할 수 있습니다.

## 실행

```bash
npm install
npm start
```

## 빌드/검증

```bash
npm test
```

`npm test`는 Vitest 단위 테스트, 스모크 테스트, TypeScript/Vite 빌드를 함께 실행합니다.

## TypeScript 모듈 구조

```txt
src/
  main.ts                  # 플레이 전용 진입점
  admin.ts                 # 관리자 스튜디오 진입점/오케스트레이션
  admin/
    Timeline.ts            # 관리자 타임라인 캔버스/드래그 편집
    LibraryPanel.ts        # 관리자 라이브러리 패널
    ChartList.ts           # 노트 목록 패널
    CommentList.ts         # 타임스탬프 리뷰 메모 목록
  core/
    types.ts               # 채보 포맷/게임 타입
    chart.ts               # 채보 파싱/정규화/데모 채보
    difficulty.ts          # 채보 난이도 자동 측정
    judgement.ts           # 판정/랭크
  game/
    GameApp.ts             # 플레이 엔진/렌더링/입력/라이브러리 로드
  library/
    storage.ts             # IndexedDB 곡+채보+오디오 저장소
    package.ts             # .sidebeat.zip 가져오기/내보내기
    records.ts             # 로컬 플레이 기록/최고기록
  ui/
    dom.ts                 # DOM 헬퍼
```

## 채보/곡 저장

- 채보 표준 포맷은 `sidebeat-lanes-chart-v3`입니다.
- 관리자 스튜디오의 “곡/채보 저장”은 IndexedDB에 채보와 오디오 Blob을 함께 저장합니다.
- 예전 localStorage 채보 라이브러리는 첫 로드 시 IndexedDB로 자동 마이그레이션합니다.
- “패키지 내보내기”는 `chart.json`, `metadata.json`, `audio/*`를 담은 `.sidebeat.zip`을 생성합니다.
- “패키지 가져오기”는 `.sidebeat.zip`을 읽어 라이브러리에 저장합니다.

```json
{
  "title": "Example Song",
  "format": "sidebeat-lanes-chart-v3",
  "difficulty": "normal",
  "bpm": 128,
  "offset": 0,
  "latencyMs": 0,
  "audioFileName": "example.mp3",
  "generator": "tools/chartgen/generate_chart.py",
  "comments": [
    { "time": 42000, "text": "여기 노트 밀도 점검", "createdAt": 1770000000000 }
  ],
  "analysis": {
    "score": 4.2,
    "label": "normal",
    "density": 2.1,
    "peakDensity": 4.8,
    "longNoteRatio": 0.1,
    "chordRatio": 0.02,
    "jackRatio": 0.04
  },
  "notes": [
    { "lane": 0, "time": 1200, "duration": 0 },
    { "lane": 2, "time": 2400, "duration": 900 }
  ]
}
```

- `lane`: 0~3 (`D/F/J/K`)
- `time`: 노트 시작 시각(ms)
- `duration`: 0이면 탭 노트, 0보다 크면 롱노트(ms)
- `comments`: 관리자 스튜디오 리뷰 메모입니다.
- `analysis`: 노트 밀도, 피크 밀도, 롱노트/동시치기/연타 비율 기반 자동 난이도 측정 결과입니다.

## Python 자동 채보/BPM 감지

CLI 초안 생성:

```bash
python -m venv .venv-chartgen
source .venv-chartgen/bin/activate
pip install -r tools/chartgen/requirements.txt
python tools/chartgen/generate_chart.py song.mp3 --difficulty hard --out examples/charts/song-hard.json
```

선택형 FastAPI 서버:

```bash
source .venv-chartgen/bin/activate
uvicorn tools.chartgen.server:app --host 127.0.0.1 --port 8000
```

서버가 켜져 있으면 `/admin.html`에서 곡 파일을 업로드한 뒤 “업로드한 곡으로 자동 생성”을 눌러 브라우저에서 직접 채보 초안을 받을 수 있습니다.

자동 채보는 완성본이 아니라 초안 생성기입니다. 최종 재미는 관리자 스튜디오에서 다듬는 흐름을 전제로 합니다.

## 현재 구현된 기능

- Canvas 기반 4레인 횡스크롤 리듬게임
- 탭 노트 + 롱노트
- 결과 화면과 로컬 플레이 기록/최고기록
- 히트 이펙트
- 플레이 화면 라이브러리 곡 로드
- 관리자용 채보 편집기 분리
- BPM/오프셋/스냅 기반 타임라인
- 타임스탬프 리뷰 메모
- 채보 난이도 자동 측정
- JSON 채보 내보내기/불러오기
- IndexedDB 기반 곡+채보+오디오 라이브러리
- `.sidebeat.zip` 패키지 가져오기/내보내기
- Python `librosa` 기반 BPM 감지 + 자동 채보 초안 생성
- 선택형 FastAPI chartgen 서버
- Vitest 단위 테스트

## 다음 개발 후보

- FastAPI 서버 URL 설정 UI
- 패키지 드래그 앤 드롭
- 플레이 기록 상세 히스토리 UI
- WebGL/WASM 렌더러 실험
- 모바일 터치 입력/접근성 확대
