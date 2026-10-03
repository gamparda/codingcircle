# 반복 가능한 밸런스 실험

실제 Godot 4.7.2의 `BattleModel`과 `ServerAI`를 화면과 대기 없이 실행합니다. 게임 규칙을 Python으로 재구현한 추정 모델이 아닙니다. 기본 0.1초 간격은 대량 탐색용이고, `--dt=0.03333333333333333`은 온라인 서버와 같은 30Hz 확인용입니다. 시뮬레이션 계산이 끝나는 속도로 실행하므로 게임 내 배속을 바꾸지 않아도 빠르게 돌아갑니다.

## 실행

프로젝트를 한 번 가져온 뒤 결과를 저장할 폴더를 만듭니다.

```powershell
godot --headless --editor --import --path .
New-Item -ItemType Directory -Force balance-data
godot --headless --single-threaded-scene --path . --script res://tools/balance_benchmark.gd -- --suite=pvp --seeds=2 --output=balance-data/pvp.jsonl
godot --headless --single-threaded-scene --path . --script res://tools/balance_benchmark.gd -- --suite=campaign --seeds=2 --output=balance-data/campaign.jsonl
godot --headless --single-threaded-scene --path . --script res://tools/balance_benchmark.gd -- --suite=mirror --seeds=2 --output=balance-data/mirror.jsonl
python tools/analyze_balance.py 'balance-data/*.jsonl' --output balance-report --label baseline
```

Godot 실행 파일이 PATH에 없다면 해당 콘솔 실행 파일의 경로로 바꿉니다. 전체는 PvP 7,140경기, 캠페인 3,360경기, 동일 덱 420경기입니다. `--seeds=4`로 두 배를 실행할 수 있습니다. 상대 단계를 임의로 강화하거나 유닛을 직접 삽입하지 않고 구매와 건설 API만 사용합니다.

`--shards=6 --shard=0`부터 `--shard=5`까지 서로 다른 파일로 동시에 실행하면 같은 대결 목록을 여섯 부분으로 나눕니다. 분석할 때 모든 부분을 함께 입력합니다. `--limit=20`은 빠른 실행 확인용입니다. 상대는 600초를 초과하면 승패를 부여하지 않고 `timeout`으로 남깁니다. `--timeout=900`으로 늘릴 수 있습니다.

30Hz 확인은 대량 탐색과 다른 폴더에 보관합니다.

```powershell
godot --headless --single-threaded-scene --path . --script res://tools/balance_benchmark.gd -- --suite=pvp --seeds=1 --dt=0.03333333333333333 --shards=10 --shard=0 --output=balance-data/30hz-pvp.jsonl
```

이 예시는 전체 PvP의 1/10 표본입니다. 전체 순위를 대신하지 않습니다. 30Hz 파일을 0.1초 데이터 폴더와 섞지 않습니다.

GitHub Actions의 **Balance engine tournament**는 수동으로 실행하며 같은 실험을 병렬 수행하고 원본 및 보고서를 아티팩트로 보관합니다. 출시·배포 작업을 실행하지 않습니다.

## 실험 설계

- 7종에서 3장을 고르는 35개 유닛 덱. PvP는 모든 595개 서로 다른 덱 쌍을 비교합니다.
- 순환 구매, 전술 점수 구매, 시드별 선호 가중치 구매를 각각 실행합니다. 구매 봇에는 캠페인 AI 보너스가 없습니다.
- 각 대결의 덱·구조물 덱·시드·논리적 구매 순서를 고정하고 파랑/빨강을 교환합니다. 두 진영 결과를 독립 표본으로 취급하지 않습니다.
- 구조물 덱은 시드로 배정합니다. 모든 구조물 조합·건설 위치·구매 전략을 완전 탐색한 연구는 아닙니다.
- 캠페인은 실제 시작 자원 `35 + 단계 × 10`, 기지 `300 + 단계 × 20`, 성장 `단계 - 1`을 적용합니다. 기존 저장의 더 많은 성장이나 해금 제한은 적용하지 않습니다. `--growth=none`으로 성장을 제거한 실험도 별도로 할 수 있습니다.
- 캠페인 보고서는 실제 플레이어 위치인 파랑만 난이도에 집계합니다. 빨강 플레이어 경기는 방향 편향 확인용입니다.

원본 JSONL에는 실행 조건, 엔진 버전, 적용 수치, 규칙/AI/구매 봇의 SHA-256, 개별 승패·경기 시간·기지 체력·최대 병력·유닛별 구매/실제 피해/처치/소환 기록이 들어갑니다. 지원 버프와 저주 횟수도 수집합니다. 직접 피해가 없는 지원 유닛을 피해량만으로 평가하면 안 됩니다.

분석기는 완료 표시가 없는 파일, 중복 경기, 진영 교환 누락, 서로 다른 규칙이 섞인 파일을 거부합니다. 실행 중 상태 확인에는 `--allow-partial`을 쓰지만 최종 보고서에는 사용하지 않습니다. 승점률은 완료 경기의 승리 1, 무승부 0.5이며 시간 초과를 패배로 바꾸지 않습니다. 덱의 95% 구간은 두 진영을 함께 재표집한 500회 부트스트랩입니다. 인간 승률의 통계적 신뢰구간이 아닙니다.

변경 후 같은 대결 목록을 재실행해 비교합니다. 변경 전 파일에 추가 반복이 있으면 현재 대결과 일치하는 경기만 비교 표에 사용합니다.

```powershell
python tools/analyze_balance.py 'after/*.jsonl' --output comparison --label tuned --compare 'before/*.jsonl'
```

자동 대전은 특정 구매 정책에 대한 균형을 확인합니다. 실제 사용자의 반응 속도, 클릭 정확도, 학습, 해금 경로와 재미를 측정하지 않습니다. 최종 인간 플레이 테스트에서는 각 단계의 첫 시도/재시도, 사용 덱, 경기 시간과 패배 원인을 함께 기록해 별도 검증합니다.
