# 유닛·구조물 수치

<!-- 자동 생성: python tools/gen_unit_docs.py. 직접 수정하지 마세요. 수치는 data/units, data/structures의 .tres에서 바꿉니다. -->

이 표는 전투·UI·AI가 실제로 읽는 `data/` 리소스에서 생성됩니다. 능력 설명(특수 효과)은 `scripts/BattleModel.gd`가 정의합니다.

## 유닛

| 유닛 | 비용 | 체력 | 공격력 | 공격 간격(초) | 이동 | 사거리 |
|---|---:|---:|---:|---:|---:|---:|
| 탱커 | 55 | 350 | 2 | 1.5 | 48 | 34 |
| 검사 | 30 | 76 | 11 | 1.4 | 44 | 40 |
| 궁수 | 55 | 64 | 12 | 1.5 | 34 | 280 |
| 마법사 | 20 | 95 | 0 | 4 | 34 | 125 |
| 광전사 | 40 | 155 | 8 | 1.4 | 44 | 40 |
| 흑마법사 | 35 | 50 | 4 | 1.5 | 34 | 280 |
| 네크로맨서 | 85 | 65 | 2 | 1.5 | 34 | 125 |
| 좀비 | 40 | 140 | 7 | 1.6 | 30 | 40 |
| 성기사 | 65 | 200 | 9 | 1.5 | 40 | 45 |
| 저격수 | 60 | 65 | 30 | 4.5 | 30 | 400 |
| 마왕 | 140 | 480 | 16 | 1.6 | 28 | 45 |
| 해골 (소환 전용) | 0 | 48 | 9 | 1.4 | 44 | 40 |

## 구조물

| 구조물 | 비용 | 체력 | 추가 수치 |
|---|---:|---:|---|
| 방벽 | 35 | 230 | max_count 2 |
| 늪 | 30 | 100 | speed_scale 0.2, radius 95, lifetime 5 |
| 포탑 | 45 | 115 | damage 9, interval 1.5, range 240, max_count 1 |
| 발전기 | 75 | 90 | income 1.7, max_count 1 |
| 낙뢰 | 55 | 1 | spell True, effect strike, zone any, cooldown 12, delay 0.6, radius 70, damage 120 |
| 화염구 | 50 | 1 | spell True, effect blast, zone any, cooldown 12, delay 0.25, speed 900, radius 75, damage 36 |
| 빙결 | 40 | 1 | spell True, effect freeze, zone any, cooldown 15, delay 0.4, radius 90, duration 2 |
| 축복 | 30 | 1 | spell True, effect bless, zone any, cooldown 12, delay 0, radius 140, duration 7, heal_fraction 0.35, attack_speed 1.5 |
| 천사 강림 | 100 | 1 | spell True, effect resurrect, zone own, cooldown 40, delay 1, radius 60, revive_count 5, revive_fraction 0.35, max_uses 2 |
