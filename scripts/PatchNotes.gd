extends RefCounted

# Historical changes reconstructed from version tags; not current balance rules.
const HISTORY := [
	{"version":"v0.8.1","changes":["온라인 결과 화면에 상대 닉네임·덱 카드와 내 온라인 전적 요약(승·패·무, 승률)을 추가했습니다.","리플레이 뷰어에 전세 그래프와 하이라이트 점프를 추가했습니다. 첫 교전·기지 위기·전세 역전·결정타로 한 번에 이동하고 Space, 방향키, N/P 단축키를 쓸 수 있습니다.","리플레이를 텍스트로 복사하고 클립보드에서 가져올 수 있습니다. AI 연습 전투도 리플레이로 저장됩니다.","화면에 표시되는 유닛 설명과 보상 문구의 수치를 실제 규칙 데이터와 항상 일치하도록 정리했습니다."]},
	{"version":"v0.8.0","changes":["메인 메뉴에 리플레이를 추가했습니다. 저장된 전투를 목록에서 골라 일시정지·0.5~8배속·처음부터·시간 막대 이동으로 다시 볼 수 있습니다.","버튼·카드·결과 화면에 UI 효과음을 추가했습니다.","터치 기기에서 버튼과 슬라이더가 손가락 크기로 커집니다.","빠른 대전에 대기 시간 표시와 오래 기다릴 때의 AI 캠페인 안내를 추가했습니다.","덱 편성 화면을 새 구조로 옮겼고, 내부 코드를 정리했습니다."]},
	{"version":"v0.7.2","changes":["제목과 큰 숫자에 한글 디스플레이 글꼴(Black Han Sans)을 적용했습니다.","대기실을 플레이어 카드(아바타·준비 상태·덱 초상)와 방 코드 복사 버튼으로 새로 디자인했습니다.","온라인 전투의 이름표·지연 표시·연결 복구 안내를 알약형 알림으로 바꿨습니다.","전투 시작 배너와 타격·피해 숫자 연출, 기지 창문과 깃발 애니메이션을 추가했습니다.","로비 방 카드에 상태 칩과 인원 표시를 추가했습니다."]},
	{"version":"v0.7.1","changes":["전체 화면 UI를 새 테마로 개편했습니다. 슬라이더·토글·드롭다운과 버튼에 그라데이션과 호버 연출을 적용했습니다.","메인 메뉴에 유닛 쇼케이스와 애니메이션 배경을 추가했습니다.","전투 화면의 체력 바·타이머·자원 바·유닛 카드와 전장 배경을 다시 디자인했습니다.","덱 편성 카드에 유닛 초상을 넣고, 캠페인 단계 타일과 결과 화면(별 연출), 유닛 스탯 화면을 개선했습니다.","일부 안내문에 남아 있던 낡은 수치(마법사 쿨타임 등)를 실제 데이터 기준으로 바로잡았습니다."]},
	{"version":"v0.7.0","changes":["로비에 빠른 대전 버튼을 추가했습니다. 대기열에서 두 플레이어가 자동으로 매칭되어 바로 시작하며 언제든 취소할 수 있습니다.","온라인 전투와 AI 캠페인 전투를 명령 기록으로 저장하는 리플레이 기록을 추가했습니다.","AI 캠페인은 고정 간격으로 진행되어 기기 성능과 무관하게 같은 결과를 냅니다.","서버와 클라이언트를 함께 업데이트해야 접속할 수 있습니다."]},
	{"version":"v0.6.5","changes":["광전사 기본 공격력을 13에서 6으로 낮췄습니다.","체력 50% 이하의 광폭화는 공격력 6을 유지하며 공격속도만 50% 증가합니다. 체력·비용·캠페인 성장·저주 적용은 유지합니다."],"source_tag":"","source_commits":[]},
	{"version":"v0.6.4","changes":["병력 비용을 탱커 45·궁수 50·마법사 25·흑마법사 35·네크로맨서 110으로 조정했습니다. 검사 공격력은 11, 궁수는 14, 흑마법사는 4입니다.","마법사의 지원 주기를 7초에서 4초로 줄였습니다. 공속 +3% 누적·최대 +30%는 유지합니다.","동시 공격을 함께 판정해 진영·유닛 처리 순서에 따른 선공 이점을 줄였습니다. 양쪽 기지가 동시에 파괴되면 무승부가 됩니다.","AI 1~8단계의 덱·병력·수입·구매 주기를 조정하고 필요한 병력 구매 직전에 자원을 낭비하던 행동을 개선했습니다."],"source_tag":"","source_commits":["da6813d feat(balance): add engine tournaments and tune units and eight-stage AI"]},
	{"version":"v0.6.3","changes":["설정에서 병력 3칸과 구조물 3칸의 전투 단축키를 변경할 수 있습니다.","중복 키와 예약 키를 차단하고 기본값 복원·변경 취소·저장을 제공합니다. 전투 카드에도 변경한 키가 표시됩니다.","기존 저장 파일은 1·2·3 / Q·W·E를 유지합니다. 채팅 입력·관전·결과 화면의 단축키 차단도 유지합니다."],"source_tag":"","source_commits":[]},
	{"version":"v0.6.2","changes":["연습에 일시정지·0.5/1/2/4배속·즉시 초기화·상대 덱 설정·무제한 자원을 추가했습니다. 실험 설정은 캠페인 진행과 전적에 반영하지 않습니다.","캠페인 시작 전 상대 덱·단계별 전술 목표·정확한 별 조건·최고 기록을 확인할 수 있습니다. 결과에서 조건별 달성 여부를 표시합니다.","항복은 확인 후 서버가 패배로 처리하며 같은 방의 결과·재대전 흐름을 유지합니다. 관전자는 항복할 수 없습니다.","서버 왕복 지연과 상대 이름을 전투 중 표시합니다. 일시적인 연결 끊김은 20초 동안 전투를 정지하고 자동 복귀를 시도합니다."],"source_tag":"","source_commits":[]},
{
  "version": "v0.6.1",
  "changes": [
    "병력 1·2·3과 구조물 Q·W·E 단축키를 추가했습니다. 채팅·텍스트 입력, 관전, 결과·상세 창에서는 전투 단축키를 차단합니다.",
    "구매 카드에 단축키와 자원 부족·재구매 대기 시간을 구분해 표시합니다. 구조물 선택 중 설치 취소 버튼을 제공하고 Android 채팅 입력을 키보드 위로 이동합니다.",
    "근접·원거리 타격, 병력 사망, 구조물 파괴에 구분되는 효과음을 추가했습니다. 기존 음소거·SFX 설정을 따르며 동시 재생과 반복 소리를 제한합니다.",
    "아군 기지 체력 25% 이하에서 단발 경고와 HUD 강조를 제공합니다. 같은 대상의 빠른 피해 숫자는 합치고 높이를 분리하며 동시 표시 효과 수를 제한합니다.",
    "결과 화면에 양쪽 전투 요약을 추가했습니다. 생산·처치·실제 피해, 사용 자원과 건설 수를 서버에서 집계하며 초과 피해는 제외하고 해골 성과는 네크로맨서에 합산합니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.6.0",
  "changes": [
    "멀티플레이 화면을 여백이 있는 방 카드 목록과 닉네임·덱 선택 영역으로 개편했습니다. 전투 중인 방과 비밀번호 방을 표시하고 한 페이지뿐이면 이동 버튼을 비활성화합니다.",
    "방에 참가해도 즉시 전투가 시작되지 않습니다. 두 플레이어가 준비하면 방장이 시작하며 덱 변경은 준비를 해제합니다. 경기 후 같은 방에서 덱을 바꾸고 재대전할 수 있습니다.",
    "선택형 방 비밀번호와 방 채팅을 추가했습니다. 비밀번호 원문을 목록이나 입장 요청에 싣지 않으며 채팅은 대기실·전투·관전에서 일반 텍스트로 표시합니다.",
    "대기방과 진행 중인 전투를 관전할 수 있습니다. 관전자에게 실제 서버 스냅샷을 전송하며 병력 구매·건설·준비·경기 시작과 개인 승패 기록에서 제외합니다.",
    "방장이 나가면 남은 플레이어에게 방장을 넘기고 전투가 중단되면 대기실로 돌아갑니다. 마지막 플레이어가 나가면 관전자도 목록으로 돌아가며 연결 종료·완료 경기·방 참조를 정리합니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.5.3",
  "changes": [
    "메인 메뉴의 멀티플레이를 누르면 방 목록으로 이동하도록 변경했습니다. 방 이름·인원을 보고 참가할 수 있으며 열린 방이 없을 때도 안내합니다.",
    "방 목록 상단의 방 만들기에서 이름을 입력해 방을 생성합니다. 방장은 대기 화면에서 상대를 기다리며, 두 명이 모이면 기존처럼 전투가 시작됩니다.",
    "방 나가기는 연결을 유지한 채 목록으로 돌아갑니다. 생성·삭제·참가로 목록을 갱신하며 이미 시작된 방에 참가해도 다른 방을 다시 선택할 수 있습니다.",
    "많은 방은 목록 페이지로 나눠 전송하며 방 수나 동시 접속에 대한 앱 수용량 제한을 다시 추가하지 않았습니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.5.2",
  "changes": [
    "짧은 연결 종료가 반복될 때 같은 IP를 120초 동안 차단하던 기능을 제거했습니다. 방을 나갔다 다시 만들거나 재접속해도 이 규칙으로 차단되지 않습니다.",
    "IP당 동시 연결 4개 제한과 진행 중 대전 32개 제한을 제거했습니다. 기존 ENet 연결 상한 128개는 프로토콜이 허용하는 최대값으로 변경했습니다.",
    "잘못된 접속 정보·덱·요청 검증과 업데이트 중 신규 접속 대기는 유지합니다. 수용량 초과로 표시하던 접속 로그와 안내 문구를 정리했습니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.5.1",
  "changes": [
    "온라인 병력 위치를 화면에서만 보간해 이동 끊김을 줄였습니다. 실제 판정·건설 좌표는 유지하며, 새 병력·새 경기·긴 통신 공백은 즉시 정렬합니다.",
    "걷기 포즈를 정지 시 초기화하지 않고 공격·소환 동작의 시작과 끝을 짧게 혼합해 갑작스러운 포즈 전환을 줄였습니다.",
    "광전사 광폭화에 색 변화·발동 섬광·짧은 효과음을 추가했습니다. 반복 패킷으로 효과음이 중복되지 않으며 기존 음소거·효과음 설정을 따릅니다.",
    "흑마법사 장판과 늪의 남은 시간을 표시하고, 네크로맨서 소환 진행 게이지와 영구 공속 중첩 점 표시를 추가했습니다. 타이머는 실제 서버/모델 값에서 계산합니다.",
    "구조물 선택 중에만 건설 구역과 포탑·늪의 실제 범위를 표시합니다. 설치 불가 위치는 빨간색과 한 줄 사유로 안내하며, 터치 드래그 미리보기와 오른쪽 진영의 터치 좌표 변환을 정리했습니다.",
    "짧은 자동 전투에서 저렴한 병력 구매가 발전기·필수 지원·흑마법사 자금을 소모하는 문제를 확인해 안전할 때 해당 구매 자금을 확보하도록 수정했습니다. 캐릭터 수치·경제 수치·단계별 체력은 변경하지 않았습니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.5.0",
  "changes": [
    "AI 적 본진의 현재·최대 체력을 단계별로 함께 설정합니다. 1단계는 320/320, 피해 후에는 250/320처럼 표시하며 체력 막대도 실제 최대 체력을 기준으로 채웁니다.",
    "8단계 AI 덱을 개편해 광전사·흑마법사·네크로맨서와 기존 병력 전체를 활용합니다. 근접 적 대응·전열 보호·영구 공속 지원 필요량·네크로맨서 구매를 위한 자원 저축을 판단합니다.",
    "AI가 안전할 때 후방 발전기를 설치하고, 위협받을 때 적 위치를 기준으로 방벽·포탑·5초 늪을 배치합니다. 불필요한 지원 유닛과 과도한 병력 구매를 줄입니다.",
    "광전사·흑마법사·네크로맨서·해골의 이동 프레임을 흔들리는 발이 아닌 몸통 중심으로 정렬하고 재생 속도를 낮춰 앞뒤 흔들림을 줄였습니다.",
    "덱 안내는 유닛 3종·구조물 3종 선택으로 줄이고, 대기 화면·설정·전적의 기술적인 설명과 중복 안내를 정리했습니다. 기존 저장·APK 자동 콘텐츠 업데이트는 유지합니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.4.20",
  "changes": [
    "덱 편성에서 불필요한 스크롤을 제거했습니다. 패널을 세로로 넓히고 간격을 조정해 유닛 두 줄·구조물 한 줄을 한 화면에 표시합니다.",
    "방벽·늪·포탑·발전기를 4열로 균등 배치해 오른쪽 빈 공간을 없앴습니다. 유닛과 구조물의 열·카드 폭·높이를 맞췄습니다.",
    "덱 선택과 저장 버튼의 실제 입력, 카드 잘림·겹침, 선택 개수 오류 안내가 화면 밖으로 밀리지 않는지 집중 검증했습니다. 게임 규칙과 캐릭터 수치는 변경하지 않았습니다."
  ],
  "source_tag": "",
  "source_commits": []
},
{
  "version": "v0.4.19",
  "changes": [
    "광전사·흑마법사·네크로맨서를 덱에 추가하고 해골을 소환 전용 병력으로 추가했습니다. 네 캐릭터의 흰 배경을 제거하고 이동·공격·소환 애니메이션을 적용했습니다.",
    "광전사: 체력 155·공격 13·사거리 40·비용 40. 체력 50% 이하에서 공격속도 +50%, 공격력 6으로 변경됩니다.",
    "흑마법사: 체력 50·공격 1·사거리 280·비용 45. 공격 대상 위치에 반경 30·적 공격력 -30% 장판을 설치합니다. 5초 유지·시전자당 1개·중첩 없음입니다.",
    "네크로맨서: 체력 50·공격 2·사거리 125·비용 100. 5초마다 추가 자원 없이 해골을 소환합니다. 해골은 체력 30·공격 10·사거리 40입니다.",
    "덱을 7종 중 3종 선택하는 두 줄 배치로 확장하고, 해골을 포함한 상세 스탯은 스크롤로 볼 수 있게 했습니다. 해골은 직접 구매할 수 없습니다.",
    "신규 병력·장판과 기존 영구 공속 중첩을 온라인 스냅샷 검증에 반영했습니다. 서명 키와 네이티브 버전은 유지하면서 최신 콘텐츠가 들어 있는 APK를 매 릴리스 새로 빌드합니다."
  ],
  "source_tag": "",
  "source_commits": []
},
	{
		"version": "v0.4.18",
		"changes": [
			"기본 자원 수입을 9→8/초로 낮추고 발전기 추가 수입을 1→2/초로 높였습니다. 비용 50·체력 90·설치 한도 1은 유지합니다.",
			"마법사 사거리를 125로 복원했습니다. 7초마다 범위 안의 아군 유닛에 공속 +3%를 영구 누적하며 유닛별 상한은 +30%입니다. 사망·새 전투에서 초기화되고 피해·회복은 없습니다.",
			"온라인 양쪽 플레이어 모두 아군 기지·병력이 왼쪽에 보입니다. 설치 입력·효과·이동 방향·체력 표시도 같은 시점으로 맞췄습니다.",
			"AI 캠페인·연습을 8단계로 줄였습니다. 연습은 선택 단계 이전을 모두 클리어한 성장 수치를 적용하지만 실제 기록은 바꾸지 않습니다.",
			"외국어 번역과 언어 선택을 제거하고 한국어 전용으로 변경했습니다. 이전 외국어 설정은 한국어로 복원합니다.",
			"Android 시작 화면도 한국어 전용으로 바꾸기 위해 새 서명 APK를 배포합니다. 기존 설치자는 이번 버전에서 APK 업데이트가 한 번 필요합니다.",
			"v0.3.3부터 모든 출시 버전의 실제 태그·커밋 기록을 바탕으로 패치노트를 작성했습니다."
		],
		"source_commits": []
	},
	{
		"version": "v0.4.17",
		"changes": [
			"마법사 피해·회복을 제거하고 범위 15에 공속 +20%를 5초간 주도록 변경했습니다. 쿨은 시전부터 7초였습니다.",
			"탱커 기본 공격력을 2로 낮췄습니다.",
			"자원 부족 시 구매 카드를 어둡게 비활성화하고 메인 메뉴에 패치노트를 추가했습니다."
		],
		"source_commits": [
			"ede67d3 test(ui): align mage stat expectations with removed healing",
			"dcfb733 feat(balance): timed mage speed buff, tank nerf, purchase states and patch notes"
		]
	},
	{
		"version": "v0.4.16",
		"changes": [
			"전장 이동거리 +15%, 검사 사거리 40, 탱커 이동속도 48·비용 35로 조정했습니다.",
			"늪은 반경 95에서 80% 감속을 주고 설치 5초 후 사라지도록 변경했습니다.",
			"시작 자원 70·수입 9/초·한도 180과 캠페인 첫 클리어 성장 보상을 추가했습니다.",
			"방 연결 재시도·응답 제한시간·코드 표시를 개선했습니다. 마법사는 당시 회복과 공속 +35% 지원을 사용했습니다."
		],
		"source_commits": [
			"ebfd4c7 feat(balance): extend battlefield, add campaign growth, and fix room connections"
		]
	},
	{
		"version": "v0.4.15",
		"changes": [
			"메뉴 유닛 아트·전투 카드 초상·구조물 아이콘·선택 표시를 추가했습니다.",
			"버튼·패널 스타일을 통일하고 설정을 오디오·화면·전투 연출로 구분했습니다."
		],
		"source_commits": [
			"92a70cc feat(ui): unify Cat War menu, battle cards, and settings"
		]
	},
	{
		"version": "v0.4.14",
		"changes": [
			"Android 설정 터치 스크롤을 개선하고 화질 프리셋을 추가했습니다.",
			"신규 설정 기본값을 1920×1080·60FPS·높음으로 정했습니다. 기존 수동 설정은 유지합니다."
		],
		"source_commits": [
			"51c1886 fix: make Android settings swipeable and add graphics presets"
		]
	},
	{
		"version": "v0.4.13",
		"changes": [
			"전장이 버튼 입력을 가로채던 문제를 수정해 유닛 스탯·나가기 버튼을 정상 클릭할 수 있게 했습니다."
		],
		"source_commits": [
			"4e2928d fix: deliver battle action clicks above battlefield"
		]
	},
	{
		"version": "v0.4.12",
		"changes": [
			"전투 버튼 겹침과 설정 화면 잘림을 수정했습니다.",
			"방 코드 대문자 변환 시 커서를 유지해 역순 입력과 삭제 문제를 수정했습니다."
		],
		"source_commits": [
			"abcee5a fix: keep battle controls and settings visible and preserve room-code caret"
		]
	},
	{
		"version": "v0.4.11",
		"changes": [
			"첫 AI 전투에 소환·설치·자원 수급 안내를 추가했습니다.",
			"결과 화면에 기지 체력·전투 시간·사용 덱을 표시하고 같은 덱 재도전을 추가했습니다."
		],
		"source_commits": [
			"9d19df1 feat: guide first AI battle and explain results with same-deck retries"
		]
	},
	{
		"version": "v0.4.10",
		"changes": [
			"저장 파일의 JSON 숫자를 올바르게 읽도록 수정해 캠페인 진행도와 설정 초기화를 방지했습니다.",
			"저장 파일 교체와 서버 매칭 재검증을 개선했습니다."
		],
		"source_commits": [
			"c523daf test: align content version assertion with 0.4.10 release",
			"9ea95d5 chore: release save and connection fixes as content 0.4.10",
			"e511d90 fix: preserve JSON save progress and recheck match admission"
		]
	},
	{
		"version": "v0.4.9",
		"changes": [
			"한국어·영어·프랑스어·중국어·러시아어·스페인어 번역을 추가했습니다. 번역 서비스는 v0.4.18에서 종료됩니다.",
			"번역된 UI의 자동 검사를 안정화했습니다."
		],
		"source_commits": [
			"b073ef6 [verified] Stabilize localized UI tests in CI",
			"a2f17fb [verified] Add six-language localization"
		]
	},
	{
		"version": "v0.4.8",
		"changes": [
			"Android APK 업데이트 정보가 불완전한 경우 업데이트를 실행하지 않도록 검증을 강화했습니다."
		],
		"source_commits": [
			"9ec5e2f [verified] fail closed on incomplete APK metadata for v0.4.8"
		]
	},
	{
		"version": "v0.4.7",
		"changes": [
			"제거된 구조물이 있는 옛 덱을 새 구조물로 이전했습니다.",
			"접속 종료 집계와 비정상 연결 처리 문제를 수정했습니다."
		],
		"source_commits": [
			"b539e07 [verified] migrate legacy decks and fix disconnect accounting for v0.4.7"
		]
	},
	{
		"version": "v0.4.6",
		"changes": [
			"서버 업데이트 대기와 신규 접속 차단 절차를 보강하고 장기전 처리를 안정화했습니다."
		],
		"source_commits": [
			"09fab7f [verified] harden server drain and endless battles for v0.4.6"
		]
	},
	{
		"version": "v0.4.5",
		"changes": [
			"6자리 방 코드로 방 만들기·참가를 할 수 있도록 매칭 방식을 변경했습니다.",
			"점프대를 제거하고 구조물을 4종으로 정리했습니다. 전투 시간 제한을 없애고 AI 장기전 강화를 추가했습니다.",
			"Android 콘텐츠 첫 실행 확인·복구와 APK 교체 안내를 개선했습니다."
		],
		"source_commits": [
			"fcadaa8 [verified] release Cat War v0.4.5"
		]
	},
	{
		"version": "v0.4.4",
		"changes": [
			"Android 콘텐츠 팩 자동 업데이트를 도입했습니다. 일반 게임 업데이트는 APK 재설치 없이 적용됩니다."
		],
		"source_commits": [
			"48438d9 feat(android): auto-update game content packs"
		]
	},
	{
		"version": "v0.4.3",
		"changes": [
			"고정 키로 서명한 Android APK를 Windows 설치 파일과 함께 배포하기 시작했습니다.",
			"Android용 텍스처 압축과 PNG 아이콘을 적용하고 출시 버전 검증을 맞췄습니다."
		],
		"source_commits": [
			"63818b9 test(release): follow configured build version",
			"be9a26a chore(release): prepare Android-enabled v0.4.3",
			"abc3d0d fix(android): use PNG project icon",
			"3a8db8b fix(android): enable mobile texture compression",
			"ec90c0a feat(android): build signed APK releases"
		]
	},
	{
		"version": "v0.4.2",
		"changes": [
			"구조물 배치와 캠페인 진행 판정의 오류를 수정했습니다."
		],
		"source_commits": [
			"ad95075 [verified] Fix v0.4 battle placement and progression rules"
		]
	},
	{
		"version": "v0.4.1",
		"changes": [
			"전체화면·음량·덱 편성 조작을 개선했습니다."
		],
		"source_commits": [
			"4d0a2a8 [verified] Improve fullscreen audio and deck controls"
		]
	},
	{
		"version": "v0.4.0",
		"changes": [
			"단계별 해금·별 평가·기록 저장을 갖춘 AI 캠페인과 자유 연습을 추가했습니다.",
			"유닛·구조물을 각각 3종 선택하는 덱 프리셋 3개, 포탑·발전기와 상세 설정을 도입했습니다."
		],
		"source_commits": [
			"7f510cd [verified] Ship Cat War v0.4 strategy progression update"
		]
	},
	{
		"version": "v0.3.16",
		"changes": [
			"10단계 오프라인 AI 대전과 배경음악을 추가했습니다. 단계 수는 v0.4.18에서 8개로 변경됩니다."
		],
		"source_commits": [
			"c69169a feat(game): add ten-stage AI battles and BGM"
		]
	},
	{
		"version": "v0.3.15",
		"changes": [
			"전용 서버 자동 업데이트와 같은 네트워크에서의 접속 경로를 복원했습니다."
		],
		"source_commits": [
			"f7c63ae [verified] Restore dedicated server updates and LAN routing"
		]
	},
	{
		"version": "v0.3.14",
		"changes": [
			"공식 서버 도메인 연결이 실패할 때 사용할 IP 대체 경로를 추가했습니다."
		],
		"source_commits": [
			"f0eedc5 [verified] Add official server IP fallback for DNS failures"
		]
	},
	{
		"version": "v0.3.13",
		"changes": [
			"탱커 체력을 400으로 조정하고 궁수 사거리를 280으로 복원했습니다."
		],
		"source_commits": [
			"aaf6788 [verified] Set tank health to 400 and restore archer range 280"
		]
	},
	{
		"version": "v0.3.12",
		"changes": [
			"온라인 스냅샷 호환 문제를 수정했습니다.",
			"힐러를 마법사로 개편했습니다. 당시 전투·회복 수치는 이후 패치에서 다시 조정되었습니다."
		],
		"source_commits": [
			"c000607 [verified] Fix online snapshot compatibility and rework healer as mage"
		]
	},
	{
		"version": "v0.3.11",
		"changes": [
			"탱커 체력을 강화하고 검사 화력을 낮췄습니다. 궁수는 장거리·낮은 피해 방향으로 조정했습니다.",
			"시간제 회복 지형을 조정했습니다. 해당 지형은 이후 버전에서 변경되었습니다."
		],
		"source_commits": [
			"b199ba6 [verified] Buff tank HP 2.5x, further nerf swordsman, archer long-range lower-damage, timed heal pad"
		]
	},
	{
		"version": "v0.3.10",
		"changes": [
			"결과 화면 이동과 온라인 재경기 창 정리를 개선했습니다.",
			"유닛 밸런스와 공격 간격을 조정하고 게임 안에 상세 스탯 패널을 추가했습니다."
		],
		"source_commits": [
			"276517b [verified] Add result-screen navigation, online rematch modal cleanup, unit rebalance, attack cadence, and in-game stats panel"
		]
	},
	{
		"version": "v0.3.9",
		"changes": [
			"GitHub 보안 워크플로 변경을 되돌려 기존 빌드·배포 경로를 복원했습니다. 게임 규칙 변경은 없습니다."
		],
		"source_commits": [
			"6bb2daa Revert GitHub security workflow upgrades"
		]
	},
	{
		"version": "v0.3.8",
		"changes": [
			"빌드 워크플로 복원에 맞춰 자동 업데이트 호환성을 조정했습니다. 게임 규칙 변경은 없습니다."
		],
		"source_commits": [
			"fd389fa Prepare updater compatibility for workflow rollback"
		]
	},
	{
		"version": "v0.3.7",
		"changes": [
			"네트워크 요청 검증과 업데이트 공급망 보안을 강화했습니다."
		],
		"source_commits": [
			"c9ff80e [verified] Harden networking and update supply chain"
		]
	},
	{
		"version": "v0.3.6",
		"changes": [
			"추출한 걷기 프레임으로 유닛 이동 애니메이션을 추가했습니다."
		],
		"source_commits": [
			"64de21c Animate units with extracted walk frames"
		]
	},
	{
		"version": "v0.3.5",
		"changes": [
			"Linux 전용 서버에 자동 업데이트를 추가했습니다. 진행 중인 전투를 보호하고 준비가 끝난 뒤 새 버전을 적용합니다."
		],
		"source_commits": [
			"84ef840 feat(server): add safe automatic Linux updates"
		]
	},
	{
		"version": "v0.3.4",
		"changes": [
			"화면 없는 전용 서버의 프레임 속도를 제한해 불필요한 CPU 사용을 줄였습니다."
		],
		"source_commits": [
			"4dc5a09 fix(server): cap headless frame rate"
		]
	},
	{
		"version": "v0.3.3",
		"changes": [
			"Godot 기반 1대1 자동 전투와 전용 서버, Windows 설치 프로그램을 공개했습니다.",
			"비전투 상태에서 적용하는 강제 자동 업데이트와 버전별 릴리스를 도입했습니다."
		],
		"source_commits": [
			"75ccd1c Publish tested builds as versioned GitHub Releases",
			"a384c49 Fix clean-run CI initialization and server update gating",
			"3d86633 Add mandatory idle-safe automatic updates",
			"fb31069 Add Windows installer and release build workflow",
			"71d2352 Replace legacy web game with Godot multiplayer project",
			"3e81c5c Add monster artwork to battle screen",
			"9d3ea75 Upgrade battle HUD layout",
			"934af68 Turn concept page into playable RPG",
			"f571e8d Rebuild tower RPG concept",
			"867418e prototype",
			"05014d6 Initial commit"
		]
	}
]

static func entries() -> Array:
	return HISTORY.duplicate(true)
