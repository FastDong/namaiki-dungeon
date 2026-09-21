# 최종 계획서 — 마왕의 던전: 죽을수록 똑똑해지는 용사

- 작성 시각: 2026-09-21 10:45 (마감 2026-09-22 00:00, 잔여 13시간 15분)
- 제출물: PPT 1개 (실제 동작하는 Flutter web 앱의 스크린샷 + 구조 + RL 설명 + Firebase 활용 포함)
- 확인된 환경: Flutter 3.47.5 stable 설치 완료(`C:\Users\gnfle\flutter\bin\flutter --version` 정상), Chrome 있음, Python 3.11 + matplotlib 3.10 있음, Firebase 프로젝트 없음, Firebase CLI 없음
- 뼈대: 심사 승자 계획 1. 심사자가 지적한 결함(범위 초과, 학습 결과를 납기 기준으로 삼음, 규칙 왕복, 루프/함정 유인 약함)을 고치고 계획 0·2의 이식 아이디어(체크포인트 타임라인, 상대 강도 특징, 두뇌 패널, 스모크 학습, featureSpecVersion, 고정 레이아웃 혼합, 버퍼 2회)를 붙였다.

---

## 1. 한 줄 컨셉 + 게임 이름 후보

**한 줄 컨셉**: 플레이어는 마왕. 7x7 던전에 마물과 함정을 배치해 침입하는 용사를 막는다. 용사는 PC에서 미리 "마왕 봇 vs 용사 봇" 전투 수십만 판으로 학습한 Q-learning 정책이며, 5웨이브를 막을 때마다 더 많이 학습한 상위 단계(1→2→3단계) 용사가 Firestore에서 내려와 등장한다.

게임 이름 후보:
1. **마왕의 던전: 죽을수록 똑똑해지는 용사** (Namaiki Dungeon RL) — 권장
2. **용사 주제에 학습한다** (Hero Learns Too Much)
3. **Q-Hero Defense**

---

## 2. 범위

### must (이게 다 되면 제출 완료)
1. `dungeon_core` 순수 Dart 패키지: 7x7 기둥 맵, 마물 3종 + 가시함정, 턴제 이동/공격/물약, 결정론 시뮬레이터, 자기중심 상태 인코더, 스파스 Q-테이블 JSON 코덱, 배치 봇(easy/medium/hard/adversarial + 고정 레이아웃 6종)
2. `bin/train.dart` 표 기반 Q-learning 커리큘럼 학습 + `bin/evaluate.dart` 고정 평가셋 300개로 체크포인트 평가 → `policy_stage1~3.json`, `curve.csv`, `eval.json`
3. Flutter web 앱: 메뉴 → 빌드 페이즈(팔레트 탭 배치, 마나) → 웨이브 실행(용사 자동 이동, 경로 트레일, HUD) → 결과 다이얼로그 → 15웨이브, 웨이브 5/10 클리어 시 "용사가 진화했다" 배너(승률 수치 표시)
4. 앱이 Firebase 없이도 완주 가능: `assets/policies/*.json` 폴백
5. Firebase: 익명 Auth + Firestore `policies/{stage}(+chunks)` 정책 배포 + `runs` 리더보드(상위 20). 정책 업로드는 Dart CLI(REST)로 Flutter 빌드와 분리
6. 진화 가시화: 경로 트레일, 단계 뱃지(학습 에피소드 수·승률), **admin 단계 강제 토글**(같은 배치에서 stage1/2/3 순서로 돌려 스크린샷 3장), 용사 두뇌 패널(현재 상태 특징 + 5행동 Q값 막대)
7. 데모 레이아웃 프리셋 버튼 1개(함정 지름길 + 슬라임 밭 + 왕좌 앞 오크)
8. matplotlib 학습곡선 PNG + 단계별 행동통계 표
9. PPT 13장 + 발표자 노트

### nice (18:30 이후 시간이 남을 때만, 최대 1개)
- Compare 화면: 같은 배치·같은 시드로 stage1 vs stage3 보드 2개 lockstep 실행, 경로 빨강/초록, 요약 배너
- `curves/run1` Firestore 문서 + 앱 내 AI Lab 학습곡선 차트
- 닉네임 입력 + `players/{uid}` 최고 기록
- 용사 말풍선("함정이다, 돌아가자")

### cut (하지 않는다)
- XP/레벨업 시스템 (규칙·상태 공간·디버깅 면적만 키움)
- 마물 학습, self-play, 앱 내 실시간 학습
- DQN/신경망/PPO, Python 학습기
- Android/Windows 빌드, 에뮬레이터, Firebase Hosting, Cloud Functions, Storage(신규 프로젝트는 Blaze 필요), Firebase CLI/flutterfire configure
- Flame, CustomPainter 보간 애니메이션, 스프라이트 아트, 사운드
- 다중 맵/맵 에디터/이동하는 마물/보스/아이템
- 다른 유저 던전 도전, 실시간 대전

---

## 3. 게임 규칙 (숫자 확정)

### 맵
- 7x7 그리드, 좌표 `(col, row)`. 입구 `(0,0)`, 마왕의 왕좌 `(6,6)`. 맨해튼 거리 12.
- 기둥(벽) 9칸: `(1,1),(1,3),(1,5),(3,1),(3,3),(3,5),(5,1),(5,3),(5,5)`. 막다른 길이 없어 국소 관측만으로도 항상 진행 가능한 경로가 존재한다(계획 2의 막다른 골목 문제 회피).
- 배치 가능 칸: 49 − 9(기둥) − 1(입구) − 1(왕좌) − 2(입구 인접 `(1,0),(0,1)`) = 36칸. 한 칸에 하나.

### 마물/함정 (학습하지 않음, 이동하지 않음)
| 종류 | id | HP | ATK | 마나 | 비고 |
|---|---|---|---|---|---|
| 슬라임 | `slime` | 10 | 2 | 1 | 값싼 시간 끌기. 처음부터 '약함' |
| 고블린 | `goblin` | 24 | 5 | 3 | 웨이브 5(ATK 12)부터 '약함'으로 관측 |
| 오크 | `orc` | 40 | 9 | 6 | 왕좌 수문장. 웨이브 13(ATK 20)부터 '약함' |
| 가시함정 | `trap` | - | 진입 시 15 | 2 | 막지 않음, 영구, 공격 불가. 1단계는 밟고 3단계는 피함 |

- '약함' 정의(상태 인코딩용): `monster.hp <= 2 * hero.atk` (2턴 안에 죽일 수 있음). 용사가 성장해도 같은 Q-테이블이 유효.
- 웨이브가 끝나도 살아있는 마물은 유지(HP 전회복), 죽은 마물은 사라짐. 함정은 영구.

### 자원
- 마나: 시작 12, 웨이브 클리어마다 +5 (웨이브 w 시작 시 누적 지급량 = 12 + 5(w−1), 웨이브 15면 82). 미사용분 이월.
- 빌드 페이즈 중 배치 취소 시 전액 환불. 웨이브 중 배치 불가.

### 용사
- 웨이브 w 스탯: `HP = 50 + 6(w−1)`, `ATK = 8 + (w−1)`, 물약 2개(HP +25, 즉시). 웨이브 15: HP 134, ATK 22.
- 행동 5개: 상/하/좌/우 이동, 물약. 마물 칸으로 이동 = 그 마물을 1회 공격(용사 ATK), 마물이 살아있으면 즉시 반격(마물 ATK). 용사는 제자리. 마물 사망 시 칸이 빈다(다음 턴에 진입 가능). 벽/맵 밖 이동 = 제자리(턴 소모). 물약 0개일 때 물약 = 무효(턴 소모).
- 함정 칸 진입 시 15 피해, 함정 유지.
- 턴 제한 80: 초과 시 용사 퇴각 = 방어 성공.
- 예시: 웨이브 1 용사(ATK 8)가 오크(40/9)를 잡으려면 5회 공격, 반격 4회 = 36 피해(HP 50 중). 고블린은 3회 공격/10 피해, 슬라임은 2회/2 피해.

### 웨이브 / AI 단계
- 총 15웨이브. 웨이브 1~5 = `stage1`, 6~10 = `stage2`, 11~15 = `stage3`. `stage = 1 + (wave−1) ~/ 5`.
- 웨이브 5, 10 클리어 직후 전체화면 배너: "용사가 N번의 죽음에서 배웠다 — AI Stage 2 (평가 승률 12% → 48%)" (수치는 정책 메타데이터 `episodes`, `winRate`).
- 플레이 시 ε = 0.03 (모든 단계 동일). 단계 차이는 오직 학습량/커리큘럼.

### 승패
- 용사 HP ≤ 0 또는 80턴 초과 → 웨이브 방어 성공, 마나 +5, 다음 웨이브.
- 용사가 왕좌 도달 → 게임 오버. `runs`에 `wavesCleared`(0~15), `stageReached` 기록.
- 15웨이브 방어 → 승리 화면(`wavesCleared = 15`).

### 결정론
- 시뮬레이터에 난수 없음. 난수는 (a) 정책의 ε 탐험 (b) 배치 봇 뿐. 둘 다 `Random(seed)` 주입. 같은 배치 + 같은 정책 + 같은 시드 = 같은 경로.

---

## 4. 아키텍처

### 폴더 구조 (`C:\Users\gnfle\fly`)
```
fly/
  PLAN.md
  dungeon_core/                      # 순수 Dart 패키지. Flutter 의존 0. 앱과 학습기가 공유
    pubspec.yaml                     # deps: http(업로더 전용), dev: test
    lib/dungeon_core.dart            # export 모음
    lib/src/balance.dart             # 모든 숫자 상수(스탯/비용/보상/맵/하이퍼파라미터) 한 곳
    lib/src/models.dart              # Pos, Cell, MonsterType, Monster, HeroStats, HeroAction, Outcome, Event, StepResult
    lib/src/grid_map.dart            # GridMap: 7x7+기둥, 배치/제거, JSON 직렬화, 배치 가능 칸
    lib/src/game_sim.dart            # GameSim: step(action) → StepResult, 결정론, trail, clone()
    lib/src/feature_encoder.dart     # FeatureEncoder.encode(sim) → int, decode → StateFeatures(두뇌 패널용)
    lib/src/qtable.dart              # QTable: Float32List dense + sparse JSON 입출력 + 청크 분할
    lib/src/policy.dart              # HeroPolicy, QTablePolicy(ε-greedy), GreedyPolicy(왕좌 방향 직진 스텁)
    lib/src/layout_generator.dart    # LayoutGenerator: easy/medium/hard/adversarial, fixedLayouts(6), demoLayout, evalSet(300)
    lib/src/trainer.dart             # Trainer.run(config, onCheckpoint) — 학습 루프 본체(테스트 가능하게 lib에 둠)
    lib/src/evaluator.dart           # Evaluator.evaluate(policy, layouts) → EvalStats
    bin/train.dart                   # dart run bin/train.dart --episodes 200000 --seed 7 --out out/
    bin/evaluate.dart                # 체크포인트 전부 평가 → 단계 선정 → policy_stage{1,2,3}.json + eval.json
    bin/upload_policy.dart           # Firestore REST PATCH: policies/{stage} + chunks (+ curves/run1)
    test/                            # game_sim_test, encoder_test, qtable_test, layout_test, trainer_smoke_test
    out/                             # checkpoints/ep_*.json, curve.csv, eval.json, policy_stage*.json
  namaiki_dungeon/                   # flutter create --platforms web
    pubspec.yaml                     # dungeon_core: path: ../dungeon_core, firebase_core, firebase_auth, cloud_firestore, provider
    lib/main.dart                    # FirebaseBootstrap(실패해도 계속) → MenuScreen
    lib/firebase_options.dart        # 학생이 콘솔에서 복사한 웹 config 6개 값 수기 입력
    lib/game/game_controller.dart    # ChangeNotifier: phase, mana, wave, stage, Timer 200ms step, trail, 통계
    lib/game/wave_rules.dart         # 웨이브별 HeroStats, stageForWave, 마나 곡선
    lib/services/firebase_bootstrap.dart   # initializeApp + signInAnonymously (try/catch, 3초 타임아웃)
    lib/services/policy_repository.dart    # Firestore chunks 병합 → QTablePolicy, featureSpecVersion 검사, assets 폴백
    lib/services/run_repository.dart       # runs add / top20 query
    lib/ui/menu_screen.dart, play_screen.dart, leaderboard_screen.dart
    lib/ui/board_grid.dart           # GridView 7x7, 셀 = 색 Container + 이모지 텍스트 + 트레일 알파
    lib/ui/build_panel.dart          # 팔레트(4종)·마나·데모 배치·웨이브 시작
    lib/ui/hud.dart                  # HP바/물약/턴/함정 횟수/처치 수/단계 뱃지
    lib/ui/brain_panel.dart          # StateFeatures 텍스트 + 5행동 Q값 막대
    lib/ui/evolve_overlay.dart       # 진화 배너
    lib/ui/result_dialog.dart
    lib/ui/admin_sheet.dart          # 단계 강제 토글, 같은 배치 재실행
    assets/policies/policy_stage{1,2,3}.json   # trainer 산출물 복사(오프라인 폴백)
  tool/plot_curves.py                # curve.csv, eval.json → learning_curve.png, stage_stats.png
  docs/ppt/                          # 스크린샷, 그래프, 다이어그램, 최종 pptx
```

### 모듈별 책임
| 모듈 | 책임 | Flutter 의존 |
|---|---|---|
| `dungeon_core` | 규칙·시뮬·인코딩·Q-테이블·배치 봇·학습·평가·업로드 CLI | 없음 |
| `namaiki_dungeon` | 화면, 입력, 타이머, Firebase 읽기/쓰기 | 있음 |
| `tool/plot_curves.py` | 그래프 PNG | 없음 |

의존 방향: `namaiki_dungeon → dungeon_core ← bin/*.dart`. 게임 규칙과 `FeatureEncoder`는 코어 한 곳에만 존재한다. 앱은 규칙을 한 줄도 다시 구현하지 않는다.

### 데이터 흐름 (텍스트 다이어그램)
```
[학생 PC 오프라인 학습]
  LayoutGenerator(마왕 봇) ──배치──▶ GameSim ◀──행동── QTablePolicy(용사 봇)
        ▲                                │ reward, next state
        │ adversarial: 현재 정책으로       ▼
        │ 후보 8개 롤아웃, 최악 채택    QTable.update  ── 2k ep마다 ──▶ out/checkpoints/ep_N.json + curve.csv
                                                                              │
  bin/evaluate.dart: 모든 체크포인트 × 고정 300 배치 ──▶ 승률 구간으로 stage1/2/3 선정 ──▶ policy_stage{1,2,3}.json, eval.json
                                                                              │
              ┌───────────────────────────────────────────────────────────────┤
              ▼                                                               ▼
  (a) namaiki_dungeon/assets/policies/ 복사 (폴백)        (b) bin/upload_policy.dart ──REST PATCH──▶ Firestore policies/{stage}/chunks/{i}

[앱 실행]
  main → FirebaseBootstrap(익명 로그인) → PolicyRepository.loadAll()
        Firestore policies/* 읽기 ──성공──▶ QTablePolicy ×3 (메모리 캐시)
                               ──실패/버전 불일치──▶ assets/policies/*.json
  PlayScreen: 빌드 페이즈(GridMap 편집) → 웨이브: GameController가 200ms마다 sim.step(policy.act(sim))
        → BoardGrid/HUD/BrainPanel 리빌드 → 종료 → ResultDialog → 웨이브 5/10 후 EvolveOverlay
  게임오버/승리 → RunRepository.add(run) → LeaderboardScreen(runs orderBy wavesCleared desc limit 20)

[PPT]
  tool/plot_curves.py(curve.csv, eval.json) → PNG; Chrome 스크린샷; Firebase 콘솔 스크린샷 → docs/ppt/ → pptx
```

---

## 5. RL 설계

### 5.1 상태 벡터 (자기중심·이산, 총 466,560 상태)
절대 좌표를 넣지 않는다 → 플레이어의 임의 배치에 일반화되고, 정책은 "주변을 보고 판단"한다.

| # | 특징 | 값 | 크기 | 근거 |
|---|---|---|---|---|
| 1 | `goalDir` = (sign(왕좌.x − 용사.x), sign(왕좌.y − 용사.y)) | 3×3 | 9 | 기둥 맵은 막다른 길이 없어 방향만으로 진행 가능 |
| 2 | `adj[4]` 상/하/좌/우 인접 칸 내용 | {벽·맵밖, 빈칸, 약한 마물, 강한 마물, 함정, 왕좌} 각 6 | 6⁴ = 1,296 | 싸울지/우회할지/함정 피할지의 근거. 약함 = `hp <= 2*heroAtk` |
| 3 | `hpBucket` HP 비율 | {≤25%, ≤50%, ≤75%, >75%} | 4 | 물약·회피 판단 |
| 4 | `hasPotion` | {0, 1} | 2 | 물약 행동 유효성 |
| 5 | `lastMove` 직전 이동 방향 | {none, up, down, left, right} | 5 | 두 칸 왕복 루프 억제(심사 지적 반영). 공격/물약은 갱신하지 않음 |

인덱스 = 혼합 진법 `((((goalDir*1296 + adj)*4 + hp)*2 + potion)*5 + lastMove)`, 범위 0..466,559. 학습기는 dense `Float32List(466560*5)` = 9.3MB, 저장은 방문 상태만 sparse JSON(예상 3만~8만 상태, 소수 2자리). `featureSpecVersion = 1`을 정책 메타에 기록.

### 5.2 행동 (5개)
`up, down, left, right, potion`. 마물 칸 방향 = 공격(제자리), 벽 방향 = 무효, 물약 0개 = 무효.

### 5.3 보상 (숫자 확정, `balance.dart`에 상수로)
| 사건 | 보상 |
|---|---|
| 왕좌 도달 (종료) | +100 |
| 사망 (종료) | −100 |
| 80턴 초과 퇴각 (종료) | −50 |
| 매 턴 | −1 |
| 마물 처치 | +5 |
| HP 손실 1당 | −0.3 (오크 반격 9 = −2.7, 함정 15 = −4.5) |
| 함정 밟음 (HP 손실 벌점에 추가) | −5 (함정 1회 총 −9.5 ≫ 우회 2턴 −2 → 회피가 확실히 유리, 심사 지적 반영) |
| 벽/맵 밖 이동 시도 | −2 |
| 직전 이동의 정반대 이동 (되돌아가기) | −1 (루프 억제; 전투 후 후퇴는 이동이 아니므로 영향 없음) |
| 물약: HP > 75%일 때 사용 / 0개일 때 사용 | −3 / −2 |

리턴 범위 대략 [−180, +90]. 종단 보상이 쉐이핑 합보다 커서 "왕좌 도달"이 항상 지배적 목표.

### 5.4 알고리즘: 표 기반 Q-learning
`Q(s,a) ← Q(s,a) + α [ r + γ max_a' Q(s',a') − Q(s,a) ]` (종료 시 max 항 0)

| 하이퍼파라미터 | 초기값 |
|---|---|
| γ | 0.97 |
| α | 0.1 (전체 에피소드 70% 지점부터 0.03) |
| ε (학습) | 1.0 → 0.05, 전체 에피소드의 60% 지점까지 선형 감소 후 고정 |
| ε (플레이/평가) | 0.03 (모든 단계 동일) |
| Q 초기값 | 왕좌에 가까워지는 방향 이동 행동 +2, 나머지 0 (낙관적 사전값 → 초기 정책이 자연스럽게 "직진 돌격형" = 1단계 캐릭터) |
| 총 에피소드 | 200,000 (부족하면 500,000) |
| 체크포인트 | 2,000 에피소드마다 (100개) |

선택 근거: (1) 13시간 안에 Dart로 구현·검증 가능(라이브러리 0개), (2) Q값을 앱에서 그대로 막대로 보여줄 수 있어 "설명 가능한 RL", (3) JSON 그대로 Firestore 배포, (4) 결정론적 유한 MDP라 수렴 안정, (5) 수업 내용(Q-learning)과 일치.

### 5.5 배치 봇 (마왕 봇, 규칙 기반, 학습 안 함)
`LayoutGenerator.generate(tier, rng, {adversary})`. 예산 B를 다 쓸 때까지 배치 가능 칸에 설치.

| tier | 예산 B | 규칙 |
|---|---|---|
| easy | U[6,12] | 슬라임/함정만, 왕좌 인접 3칸 우선 확률 0.5 |
| medium | U[12,22] | 4종 전부, 입구→왕좌 최단경로(BFS) 위 칸에 확률 0.6으로 함정 |
| hard | U[20,35] | 오크 ≥1 왕좌 인접 강제, 함정 ≥3, 고블린으로 병목 |
| adversarial | hard와 동일 | hard 후보 8개 생성 → 현재 greedy 정책으로 각 2회 롤아웃 → 용사 평균 리턴이 가장 낮은 배치 채택 ("마왕 봇이 용사의 약점을 노린다" — 학생이 말한 '봇끼리 전투') |
| fixed | — | 사람이 만든 6종(입구 앞 벽, 왕좌 포위, 함정 복도, 슬라임 밭, 좌우 분기 함정, 오크 2연속). 실제 플레이어 배치와의 분포 차이 완화 |

용사 스탯은 에피소드마다 웨이브 w를 샘플: easy는 w∈1..6, medium은 w∈3..11, hard/adversarial/fixed는 w∈6..15 균등.

### 5.6 학습 절차
1. **스모크 런 (12:45까지)**: `dart run bin/train.dart --episodes 3000 --tier easy --smoke` → 60초 이내 종료, 마지막 500ep 승률이 첫 500ep보다 높아야 함. 실패 시 인코더/보상 버그 수정 후 재시도(본 학습 전 게이트).
2. **본 학습 (13:15~)**: 200,000 에피소드. 커리큘럼: 0~20% easy, 20~60% medium, 60~100% = hard 40% + adversarial 40% + fixed 20%. 2,000ep마다 체크포인트 JSON + `curve.csv`(ep, 최근 2k 승률, 평균 리턴, 평균 턴, tier).
3. **평가 (`bin/evaluate.dart`)**: 고정 평가셋 300개(seed 42; easy/medium/hard 각 100, 웨이브 스탯 1·6·11 순환)에서 모든 체크포인트를 ε=0.03으로 평가. 승률·평균 턴·함정 밟은 횟수·물약 사용·처치 수 → `eval.json`. 데모 레이아웃 결과도 함께 기록.
4. **단계 선정**: 아래 5.7.
5. 산출물 복사 `out/policy_stage{1,2,3}.json → namaiki_dungeon/assets/policies/`, 업로드 `bin/upload_policy.dart`.

### 5.7 단계 정의
단계 = **한 학습 런의 체크포인트 중 고정 평가셋 승률 구간으로 선정한 것**. 차이는 학습량(그 시점까지 상대한 커리큘럼 포함)뿐이고 플레이 ε은 동일.
- stage1 "풋내기": 승률 ≥ 10%인 첫 체크포인트(사실상 2k~6k ep, 직진 돌격형)
- stage2 "노련한": 승률 ≥ 45%인 첫 체크포인트
- stage3 "각성한": 최고 승률 체크포인트(목표 ≥ 75%)
- **목표치**(완료 기준 아님): 단계 간 격차 ≥ 25%p, 데모 레이아웃에서 stage1 패·stage3 승.
- **폴백 규칙(자동)**: 구간에 도달하는 체크포인트가 없으면 stage1 = 학습 5% 지점, stage2 = 30% 지점, stage3 = 최고 승률 체크포인트로 선정하고 `eval.json`에 `selectionRule: "quantile"`을 기록해 PPT에 그대로 적는다. 결과를 조작하지 않는다.
- 각 단계 메타(`episodes, winRate, avgSteps, trapHits, potionsUsed, kills`)를 정책 문서에 저장 → 진화 배너와 뱃지에 수치로 표시.

### 5.8 예상 학습 시간
스텝당(인코딩 포함) ~5~10µs(Dart JIT). 200k ep × 평균 40턴 = 800만 스텝 + adversarial 롤아웃(40k ep × 8후보 × 2회 × 40턴 ≈ 2,600만 스텝) ≈ 3~6분. 평가 100체크포인트 × 300배치 ≈ 120만 스텝 < 1분. **1사이클 10분 이내**, 재학습 3회 왕복 포함 40분 예산.

### 5.9 진화가 눈에 보이게 하는 방법
1. **경로 트레일**: 지나간 칸에 순번 숫자 + 반투명 색. 웨이브 종료 후에도 유지 → 스크린샷 1장에 경로가 보임.
2. **admin 단계 강제 토글**: 같은 배치에서 stage1/2/3을 차례로 돌려 경로 3장 나란히(PPT 슬라이드 10 핵심 자료). Compare 화면의 30분짜리 대체물.
3. **HUD 수치**: 이번 웨이브 턴 수 / 잃은 HP / 함정 횟수 / 물약 / 처치 → 단계가 오르면 숫자가 좋아지는 게 보임.
4. **진화 배너**: 웨이브 5/10 후 전체화면 "AI Stage 2 (평가 승률 12% → 48%, 학습 64,000회)".
5. **용사 두뇌 패널**: 현재 상태 특징(방향/인접 4칸/HP/물약/직전 이동)과 5행동 Q값 막대, 선택 행동 강조 → "왜 그쪽으로 갔나"를 실시간으로 설명(RL 발표 Q&A용).
6. **데모 레이아웃 버튼**: 함정 지름길 + 슬라임 밭 + 왕좌 앞 오크를 1초에 배치해 시연.
7. **PPT**: 학습곡선(승률 vs 에피소드, 단계 마커 3개) + 단계별 행동통계 표.

---

## 6. Firebase 설계

### 서비스
| 서비스 | 용도 | 이유 |
|---|---|---|
| Cloud Firestore | (1) 정책 배포 `policies/{stage}` + `chunks` (2) 리더보드 `runs` (3) nice: `curves/run1` | "PC에서 학습 → 서버 배포 → 앱이 내려받아 AI 교체"가 핵심 스토리. 재학습 후 재업로드만으로 앱 수정 없이 용사가 바뀜 |
| Authentication (익명) | `runs.uid` 소유 검증, 규칙에서 create 조건 | 회원가입 없이 평가자가 바로 시연 |
| 사용 안 함 | Storage(Blaze 필요), Hosting/Functions/Analytics, CLI | 시간·인증 비용 대비 평가 이득 없음 |

### 데이터 모델
```
policies/{stageId}                       stageId ∈ {stage1, stage2, stage3}
  stage: int, name: string("풋내기 용사"...), algorithm: "tabular_q_learning",
  featureSpecVersion: 1, episodes: int, winRate: double, avgSteps: double,
  trapHits: double, potionsUsed: double, kills: double,
  stateCount: int, chunkCount: int, version: string("2026-09-21T15:00"), createdAt: timestamp
policies/{stageId}/chunks/{000..NNN}
  data: string        # JSON {"stateIndex":[q_up,q_down,q_left,q_right,q_potion],...} 소수 2자리, 청크당 ≤ 6,000 상태(≈250KB, 1MiB 한도 안전)
runs/{autoId}
  uid: string, nickname: string(≤12, 기본 "마왕"), wavesCleared: int(0..15), stageReached: int(1..3),
  heroDeaths: int, durationSec: int, layoutSnapshot: string(JSON), appVersion: string, createdAt: serverTimestamp
curves/run1  (nice)
  data: string        # JSON [{ep,win,reward,steps}] ≤ 300점, stageMarkers: [int,int,int]
```
쿼리: `runs orderBy wavesCleared desc, createdAt desc limit 20` → 복합 색인 1개(첫 조회 시 콘솔 에러 링크 클릭 1회).

### 업로드 경로
`dungeon_core/bin/upload_policy.dart` — Firestore REST API 직접 호출. Admin SDK·서비스 계정·Firebase CLI·Flutter 빌드 전부 불필요.
```
PATCH https://firestore.googleapis.com/v1/projects/{projectId}/databases/(default)/documents/policies/stage1?key={apiKey}
body: {"fields":{"stage":{"integerValue":"1"},"winRate":{"doubleValue":0.12},...}}
PATCH .../policies/stage1/chunks/000?key={apiKey}
body: {"fields":{"data":{"stringValue":"{...}"}}}
```
실행: `dart run bin/upload_policy.dart --project <projectId> --api-key <apiKey> --out out/`. 청크 ≤ 900KB 검증, 실패 청크 3회 재시도, 멱등(덮어쓰기). **테스트 모드 규칙이 켜진 동안(18:15 이전)에만 업로드**하고, 최종 규칙은 마지막 업로드 후 1회만 게시(규칙 왕복 제거).
폴백: 앱 admin 시트에 "에셋 정책을 Firestore로 업로드" 버튼(cloud_firestore SDK, 동일 문서).

### 보안 규칙
개발 중(11:30~18:15): 콘솔 "테스트 모드" 기본 규칙(30일 만료, 전체 허용).
최종(18:15 이후 1회 게시, 규칙 탭 스크린샷을 PPT에):
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /policies/{stage} {
      allow read: if true;
      allow write: if false;
      match /chunks/{chunk} { allow read: if true; allow write: if false; }
    }
    match /curves/{doc} { allow read: if true; allow write: if false; }
    match /runs/{run} {
      allow read: if true;
      allow create: if request.auth != null
        && request.resource.data.uid == request.auth.uid
        && request.resource.data.wavesCleared is int
        && request.resource.data.wavesCleared >= 0 && request.resource.data.wavesCleared <= 15
        && request.resource.data.stageReached in [1, 2, 3]
        && request.resource.data.nickname is string && request.resource.data.nickname.size() <= 12;
      allow update, delete: if false;
    }
  }
}
```
스토리: 정책은 읽기 전용 배포물, 리더보드는 본인 uid로 생성만 허용.

### 학생이 콘솔에서 해야 할 단계 (번호 순)
1. [11:00, 10분] https://console.firebase.google.com 로그인 → "프로젝트 추가" → 이름 `namaiki-dungeon` → Google 애널리틱스 "사용 안 함" → 만들기 → 계속.
2. 프로젝트 개요 → 웹 아이콘 `</>` → 앱 닉네임 `web` → "Firebase Hosting 설정" 체크 해제 → 앱 등록 → 화면의 `firebaseConfig` 블록(apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId) 전체를 복사해 채팅에 붙여넣기 (Claude가 `firebase_options.dart` 작성; 웹 config는 공개 값) → 콘솔로 이동.
3. 왼쪽 "빌드" → Authentication → 시작하기 → "Sign-in method" 탭 → "익명" → 사용 설정 ON → 저장.
4. "빌드" → Firestore Database → 데이터베이스 만들기 → ID 기본(default) → 위치 `asia-northeast3 (Seoul)` → 다음 → "테스트 모드에서 시작" → 사용 설정.
5. Authentication → Settings → 승인된 도메인에 `localhost` 있는지 확인(기본 포함).
6. [16:00~17:00 사이] 앱에서 리더보드 첫 조회 시 Chrome 콘솔에 "The query requires an index" 링크가 뜨면 열어서 "색인 만들기" → 1~3분 대기.
7. [18:15] Firestore → 규칙 탭 → 위 최종 규칙 전체 붙여넣기 → 게시.
8. [18:15~18:30, PPT 스크린샷 3컷] Firestore 데이터 탭(policies 문서 펼침 + runs 목록), Authentication 사용자 탭(익명 uid), 규칙 탭.

---

## 7. Flutter 타깃 / 렌더링 결정

- **타깃: Flutter Web, Chrome 단일** (`flutter create namaiki_dungeon --platforms web`, `flutter run -d chrome`, 스크린샷은 1280x800 창). 근거: Flutter 3.47.5 설치 확인됨, Chrome 있음, 에뮬레이터 이미지/Android Studio 없음(첫 Gradle 빌드 1시간+ 리스크), Firebase 웹 앱은 config 6개 값 복사로 끝남(flutterfire CLI 불필요). 폴백: `flutter run -d web-server --web-port 8080` 후 Chrome 수동 접속.
- **렌더링: 위젯 그리드** (`GridView.builder` crossAxisCount 7, 셀 = `GestureDetector > Container(color) > Text(이모지)`), 트레일은 셀 배경 알파 + 순번 텍스트, HUD/패널은 Material 위젯, 두뇌 패널 막대는 `LinearProgressIndicator` 5개. 200ms `Timer.periodic`으로 step 후 `notifyListeners`. 근거: 49칸 리빌드는 성능 문제 없고 탭 처리·핫리로드가 공짜, CustomPainter 보간·Flame은 시간 대비 이득 없음. 표기: 슬라임 🟢, 고블린 👺, 오크 👹, 함정 🔺, 용사 🧝, 왕좌 👑, 기둥 진회색 블록.

---

## 8. 타임라인 (10:45 시작, 코드 동결 20:30, PPT 2시간, 버퍼 2회)

| 시각 | 작업 | 산출물 / 체크포인트 |
|---|---|---|
| **10:45–11:45** | 환경: PATH 등록, `flutter doctor`, `flutter config --enable-web`, `flutter create namaiki_dungeon --platforms web`, `flutter run -d chrome` 카운터 앱. 동시에 `dungeon_core` 패키지 생성 + `balance.dart`/`models.dart`/인터페이스 스텁(§11 시그니처) 커밋. 학생: 콘솔 1~5단계 → firebaseConfig 전달 | **[CP0] Chrome에 Flutter 앱 스크린샷**, 인터페이스 스텁 컴파일, config 확보 |
| **11:45–13:15** | 3갈래 병렬: (A) `GridMap/GameSim/FeatureEncoder/QTable/Policy` + 테스트 (B) `LayoutGenerator/Trainer/Evaluator` + `bin/train.dart`, 12:45 스모크 런 3k ep (C) 앱 셸: 라우팅, `GameController`, `BoardGrid`, `BuildPanel`, `HUD`, 결과 다이얼로그 — 용사는 `GreedyPolicy` 스텁 | `dart test` green, 스모크 승률 상승 확인, Chrome에서 배치→웨이브→용사 이동 |
| **13:15–14:00** | 본 학습 200k + 평가 → 단계 선정. 학생 점심. 결과 검토(격차·데모 레이아웃), 미달 시 보상/커리큘럼 1회 조정 후 2회차 | `policy_stage1~3.json`, `eval.json`, `curve.csv` |
| **14:00–15:30** | 앱 오프라인 완성: 에셋 정책 로드, 15웨이브 규칙, 단계 매핑, 진화 배너, 트레일, admin 단계 토글, 데모 배치 버튼. 첫 E2E 플레이 | **[CP A] Firebase 없이 15웨이브 완주 가능한 앱** + 플레이 스크린샷 4장. 여기서 멈춰도 "RL 용사 디펜스" PPT 가능 |
| **15:30–17:00** | Firebase: `firebase_options.dart` 수기, `flutter pub add firebase_core firebase_auth cloud_firestore`, 웹 빌드 확인(45분 넘게 깨지면 REST 전환), `PolicyRepository`(Firestore→에셋 폴백), `RunRepository`, 리더보드 화면. 병렬로 `upload_policy.dart` 작성·업로드 | **[CP B] Firestore에 policies 3문서·runs 문서 존재, 앱이 원격 정책으로 플레이** |
| **17:00–18:00** | 진화 UX 마감: 두뇌 패널, HUD 통계, 뱃지 수치. 필요 시 재학습 2회차 + 재업로드(18:15 전 완료) | 두뇌 패널 스크린샷, 최종 정책 업로드 완료 |
| **18:15–18:30** | 학생: 최종 규칙 게시(콘솔 7단계) + 콘솔 스크린샷 3컷. Claude: 규칙 게시 후 create 성공·update 거부 확인 | 규칙 스크린샷, 리더보드에 runs ≥ 3건 |
| **18:30–19:30** | **버퍼 1** / 저녁. 밀린 must 흡수. 여유 있으면 nice 1개(Compare 화면) | 안정 빌드 |
| **19:30–20:30** | 자료 수집: `python tool/plot_curves.py` → PNG 2장, 동일 배치 stage1/2/3 경로 스크린샷 3장, 메뉴/빌드/웨이브/사망/배너/리더보드/두뇌 패널, 아키텍처·RL 다이어그램(mermaid→PNG 또는 draw.io) | `docs/ppt/` 이미지 ≥ 15장, 슬라이드별 텍스트 초안 md |
| **20:30** | **코드 동결** (예외 없음) | — |
| **20:30–22:30** | PPT 제작(pptx 스킬) 13장 + 발표자 노트 + RL 설명 스크립트 | `namaiki_dungeon_rl.pptx` v1 |
| **22:30–23:15** | 학생 검토 → 수정 → PDF 백업 → 파일명/제출 형식 확인 → **제출** | 제출 완료 |
| **23:15–24:00** | **버퍼 2**. 여기까지 밀렸다면 nice 전부 포기, PPT만 마무리 | — |

체크포인트별 PPT 변형: CP0만 → 코어·학습 결과(그래프/표) + 설계도 중심, 앱은 CLI 텍스트 렌더 캡처. CP A만 → Firebase 슬라이드는 데이터 모델·규칙 원문·콘솔 스크린샷(프로젝트/Auth/빈 Firestore)으로 대체. CP B → 전체 목차.

---

## 9. 리스크 / 대응

| 리스크 | 대응 |
|---|---|
| Flutter web 디바이스 미인식/첫 빌드 실패 | 11:45까지 카운터 앱이 안 뜨면 (1) `flutter doctor -v`로 PATH/`CHROME_EXECUTABLE` 수정 (2) `-d web-server`로 서빙 후 수동 접속 (3) 13:15까지 실패 시 코어·학습기 먼저 완성해 진화 증거(그래프/표)를 확보하고 앱은 14:00 재시도. 코어는 Flutter 없이 동작하도록 설계됨 |
| cloud_firestore 웹 빌드 오류/버전 충돌 | `flutter pub add`로 최신 해석 조합 사용. 15:30부터 45분 안에 안 되면 `http` 패키지 + Firestore REST(+ Identity Toolkit REST `signUp` 익명 1회)로 `PolicyRepository/RunRepository` 교체. 데이터 모델·규칙·PPT 불변 |
| 학생 콘솔 작업 지연 | 앱은 에셋 폴백으로 항상 동작. Firebase는 15:30 이후에만 붙이고 콘솔 단계는 클릭 단위로 제공 |
| 학습이 안 됨(승률 평평/발산) | 12:45 스모크 런으로 조기 발견. 순서: (1) 마물 0개 맵에서 500ep 후 greedy 최단경로 도달(인코더·보상·업데이트 통합 검증) (2) 슬라임 1 → 오크 1 순으로 늘려 확인 (3) α 0.05, 스텝 벌점 조정(`balance.dart` 한 곳). 1사이클 10분이라 3회 왕복 30분 |
| 단계 간 차이가 안 보임 | 단계 = 승률 구간 선정으로 격차 확보, 미달 시 분위수 폴백을 자동 적용하고 PPT에 명시. 함정 −9.5 vs 우회 −2로 회피 유인 확보, `lastMove` 특징 + 되돌아가기 −1로 루프 억제. 정성적 증거는 admin 토글 경로 3장 + 두뇌 패널 |
| 용사가 왕복 루프 → 80턴 퇴각이 잦음 | `lastMove` 특징, ε 0.03, 되돌아가기 −1, 퇴각 −50. 그래도 잦으면 ε 0.05로 상향(플레이·평가 동일 적용) |
| Q-테이블 JSON 1MiB 초과 | sparse + 소수 2자리 + 6,000상태/청크 분할, 업로더가 900KB 검증. |Q| < 0.01 상태 제거 옵션 |
| 앱/학습기 인코딩 불일치 | 같은 `dungeon_core` 코드 사용으로 원천 차단 + `featureSpecVersion` 검사(불일치 시 에셋 폴백) + 앱에서 관찰한 경로를 `GameSim`으로 재현하는 테스트 1개 |
| 밸런스 붕괴(3단계가 너무 강함/마나 남아돎) | `balance.dart` 한 곳에서 마나 곡선/비용 조정. 게임오버는 정상 결말이고 리더보드가 "몇 웨이브 버텼나"라 완벽할 필요 없음. 17:00~18:00 3판 플레이로 튜닝 |
| 시간 초과로 PPT 침범 | 20:30 코드 동결 절대 준수. 18:30 이후 새 기능 금지(nice 1개 예외). 체크포인트별 PPT 변형 사용 |
| 서브에이전트 인터페이스 불일치 | 11:45 전에 §11 시그니처를 스텁으로 커밋, 모든 모듈은 import만. `dart test`/`flutter analyze`가 통합 게이트 |

---

## 10. PPT 목차 (13장)

| # | 제목 | 들어갈 자료 |
|---|---|---|
| 1 | 표지 — 마왕의 던전: 죽을수록 똑똑해지는 용사 | Flutter + Firebase + Q-learning, 이름·학번, 배경에 웨이브 진행 스크린샷 |
| 2 | 아이디어 | PSP '용사 주제에 건방지다' 오마주, 플레이어=마왕·용사=학습 AI, 핵심 루프 다이어그램(배치→침입→사망→학습→진화) |
| 3 | 게임 규칙 | 7x7 기둥 맵 그림, 마물 4종 표(HP/ATK/마나), 마나 경제, 용사 성장식, 승패, 5웨이브마다 단계 교체 흐름 |
| 4 | 플레이 흐름 4컷 | 빌드 → 웨이브 진행(트레일) → 용사 사망 → 진화 배너 스크린샷 |
| 5 | 시스템 아키텍처 | dungeon_core 공유 / 학습기 / Firestore / Flutter web 다이어그램, "학습은 PC 오프라인, 배포는 Firestore" 화살표 |
| 6 | RL 문제 정의 (MDP) | 상태 5특징 표(9×1296×4×2×5 = 466,560), 행동 5, 보상표(숫자), γ |
| 7 | 알고리즘 | Q-learning 갱신식, 하이퍼파라미터, 표 기반 선택 이유 3가지, 자기중심 특징이 임의 배치에 일반화되는 이유, `qtable.dart` 스니펫 |
| 8 | 학습 절차: 마왕 봇 vs 용사 봇 | 커리큘럼 3단 그림(랜덤→길목→적대적 선택), 고정 레이아웃, 20만 에피소드, 체크포인트, "단계 = 승률 10/45/75% 구간" 정의 |
| 9 | 학습 곡선 | `learning_curve.png`(승률·평균 리턴 vs 에피소드, 단계 마커 3개), 학습 시간 |
| 10 | 진화의 증거 | 같은 배치에서 stage1/2/3 경로 스크린샷 3장 + 두뇌 패널 스크린샷 + 단계별 행동통계 표(승률/턴/함정/물약/처치) |
| 11 | Firebase 활용 1: 정책 배포 | 데이터 모델 다이어그램(policies/chunks), REST 업로드 경로, 콘솔 데이터 탭 스크린샷, 앱 로딩 흐름(다운로드→캐시→폴백, featureSpecVersion) |
| 12 | Firebase 활용 2: 익명 인증 + 리더보드 + 보안 규칙 | runs 모델, 리더보드 화면, Authentication 사용자 탭, 규칙 코드 하이라이트(정책 읽기 전용, 본인 uid만 create) |
| 13 | 한계와 향후 과제 + 요약 | 국소 특징의 한계(장기 경로 계획 불가) → DQN, 마물도 학습(self-play), 유저 던전 공유; 게임/RL/Firebase 3축 요약, 발표자 노트에 30초 데모 스크립트 |

---

## 11. 멀티에이전트 구현 분해

### 공통 규칙 (모든 에이전트 프롬프트에 포함)
- 작업 루트 `C:\Users\gnfle\fly`. 절대 경로 사용. 규칙 상수는 `dungeon_core/lib/src/balance.dart`에서만 읽는다(숫자 하드코딩 금지).
- 아래 공개 인터페이스는 **변경 금지**. 필요하면 추가만 하고 변경은 오케스트레이터에 보고.
- 완료 = 명시된 명령이 통과 + 산출물 경로 존재. 학습 결과 수치(승률 등)는 목표이지 완료 기준이 아니다.
- 한국어 UI 문자열, 영어 식별자. 이모지는 UI 텍스트에만.

### 공개 인터페이스 (`dungeon_core`, 11:45 전에 스텁 커밋)
```dart
// lib/src/balance.dart
class Balance {
  static const int cols = 7, rows = 7;
  static const List<List<int>> pillars = [[1,1],[1,3],[1,5],[3,1],[3,3],[3,5],[5,1],[5,3],[5,5]];
  static const int entranceX = 0, entranceY = 0, throneX = 6, throneY = 6;
  static const int maxSteps = 80;
  static const int startMana = 12, manaPerWave = 5, totalWaves = 15, wavesPerStage = 5;
  static const int heroBaseHp = 50, heroHpPerWave = 6, heroBaseAtk = 8, heroAtkPerWave = 1;
  static const int potions = 2, potionHeal = 25;
  static const int trapDamage = 15;
  // 보상
  static const double rThrone = 100, rDeath = -100, rTimeout = -50, rStep = -1, rKill = 5,
      rHpLossPerPoint = -0.3, rTrapHit = -5, rWallBump = -2, rReverseMove = -1,
      rPotionWasteHigh = -3, rPotionNone = -2;
  // RL
  static const double gamma = 0.97, alpha = 0.1, alphaLate = 0.03, epsPlay = 0.03,
      epsStart = 1.0, epsEnd = 0.05, epsDecayFraction = 0.6, optimisticInit = 2.0;
  static const int featureSpecVersion = 1;
  static int heroHp(int wave) => heroBaseHp + heroHpPerWave * (wave - 1);
  static int heroAtk(int wave) => heroBaseAtk + heroAtkPerWave * (wave - 1);
  static int stageForWave(int wave) => 1 + (wave - 1) ~/ wavesPerStage;
}

// lib/src/models.dart
class Pos { final int x, y; const Pos(this.x, this.y); Pos move(HeroAction a); bool get inBounds; }
enum MonsterType { slime, goblin, orc, trap }
class MonsterSpec { final int hp, atk, cost; const MonsterSpec(this.hp, this.atk, this.cost); }
const Map<MonsterType, MonsterSpec> monsterSpecs = {
  MonsterType.slime: MonsterSpec(10, 2, 1), MonsterType.goblin: MonsterSpec(24, 5, 3),
  MonsterType.orc: MonsterSpec(40, 9, 6), MonsterType.trap: MonsterSpec(0, 15, 2),
};
class Monster { final MonsterType type; final Pos pos; int hp; Monster(this.type, this.pos, this.hp); Monster clone(); }
class HeroStats { final int maxHp, atk, potions; const HeroStats(this.maxHp, this.atk, this.potions); factory HeroStats.forWave(int wave); }
enum HeroAction { up, down, left, right, potion }
enum Outcome { running, heroDied, reachedThrone, gaveUp }
enum EventType { moved, bumpedWall, attacked, killed, trapHit, potionUsed, potionWasted, reversed }
class Event { final EventType type; final Pos? pos; final int? amount; final MonsterType? monster; }
class StepResult { final double reward; final Outcome outcome; final List<Event> events; bool get done => outcome != Outcome.running; }

// lib/src/grid_map.dart
class GridMap {
  GridMap();                                   // 기둥 포함 빈 맵
  final Map<Pos, Monster> monsters;            // 배치된 마물/함정 (pos → monster)
  bool isPillar(Pos p); bool isPlaceable(Pos p); bool isThrone(Pos p); bool isEntrance(Pos p);
  bool place(MonsterType t, Pos p);            // 배치 불가면 false
  bool remove(Pos p);
  int get totalCost;
  GridMap clone();
  Map<String, dynamic> toJson(); factory GridMap.fromJson(Map<String, dynamic> j);
  List<Pos> shortestPath();                    // 입구→왕좌 BFS(마물 무시, 기둥만)
  static List<Pos> placeableCells();
}

// lib/src/game_sim.dart
class GameSim {
  GameSim(GridMap map, HeroStats hero);        // map은 내부에서 clone. 결정론(난수 없음)
  StepResult step(HeroAction a);
  bool get done; Outcome get outcome;
  Pos get heroPos; int get hp, maxHp, atk, potions, steps; HeroAction? get lastMove;
  int get trapHits, kills, hpLost;
  List<Pos> get trail;                         // 방문 순서
  GridMap get map;                             // 현재 상태(죽은 마물 제거됨)
  GameSim clone();
}

// lib/src/feature_encoder.dart
enum AdjKind { wall, empty, weakMonster, strongMonster, trap, throne }
class StateFeatures { final int goalDx, goalDy; final List<AdjKind> adj; final int hpBucket; final bool hasPotion; final HeroAction? lastMove; }
class FeatureEncoder {
  static const int stateCount = 466560;        // 9*1296*4*2*5
  static StateFeatures features(GameSim s);
  static int encode(GameSim s);                // 0 <= idx < stateCount
  static int indexOf(StateFeatures f);
  static bool isWeak(Monster m, int heroAtk) => m.hp <= 2 * heroAtk;
}

// lib/src/qtable.dart
class QTable {
  QTable();                                    // dense Float32List(stateCount*5), 낙관 초기값은 Trainer가 넣음
  double get(int s, int a); void set(int s, int a, double v);
  List<double> row(int s);                     // 길이 5
  int argmax(int s, Random rng);               // 동점 랜덤
  int get visitedCount;                        // |q| > 0이거나 방문 플래그가 있는 상태 수
  String toSparseJson({int decimals = 2});     // {"v":1,"n":5,"q":{"idx":[...]}}
  factory QTable.fromSparseJson(String json);
  List<String> toChunks({int statesPerChunk = 6000}); factory QTable.fromChunks(List<String> chunks);
}

// lib/src/policy.dart
abstract class HeroPolicy { HeroAction act(GameSim sim, Random rng); String get name; }
class GreedyPolicy implements HeroPolicy { /* 왕좌 방향 직진, 막히면 다른 축 */ }
class QTablePolicy implements HeroPolicy {
  QTablePolicy(this.table, {this.epsilon = Balance.epsPlay});
  final QTable table; final double epsilon;
  List<double> qValues(GameSim sim);           // 두뇌 패널용
}

// lib/src/layout_generator.dart
enum Tier { easy, medium, hard, adversarial, fixed }
class LayoutGenerator {
  GridMap generate(Tier tier, Random rng, {HeroPolicy? adversary, HeroStats? hero});
  int sampleWave(Tier tier, Random rng);
  static List<GridMap> fixedLayouts();         // 6종
  static GridMap demoLayout();                 // 함정 지름길 + 슬라임 밭 + 왕좌 앞 오크
  static List<(GridMap, HeroStats)> evalSet({int seed = 42, int size = 300});
}

// lib/src/trainer.dart
class TrainConfig { final int episodes, seed, checkpointEvery; final String outDir; final Tier? onlyTier; final bool smoke; }
class CurvePoint { final int episode; final double winRate, avgReturn, avgSteps; final String tier; }
class Trainer {
  Trainer(this.config);
  Future<QTable> run({void Function(int episode, QTable q, CurvePoint p)? onCheckpoint});
}

// lib/src/evaluator.dart
class EvalStats { final double winRate, avgSteps, trapHits, potionsUsed, kills; final int episodes; Map<String, dynamic> toJson(); }
class Evaluator {
  static EvalStats evaluate(HeroPolicy p, List<(GridMap, HeroStats)> set, {int seed = 1});
  static bool runDemo(HeroPolicy p, {int wave = 6});                        // 데모 레이아웃 승패
  static Map<String, int> selectStages(List<(int episode, EvalStats)> ckpts); // {stage1: ep, stage2: ep, stage3: ep, rule}
}
```

### 앱 인터페이스 (`namaiki_dungeon`)
```dart
// lib/game/game_controller.dart
enum Phase { build, running, result, evolve, gameOver, victory }
class GameController extends ChangeNotifier {
  GameController(this.policies);               // Map<int, HeroPolicy> stage → policy
  Phase get phase; int get wave, mana, stage; GridMap get map; GameSim? get sim;
  MonsterType selected;                        // 팔레트 선택
  int? forcedStage;                            // admin 토글(null이면 웨이브 기준)
  bool placeAt(Pos p); bool removeAt(Pos p); void loadDemoLayout();
  void startWave(); void nextWave(); void restartSameLayout();
  List<double>? get currentQ; StateFeatures? get currentFeatures;
  RunRecord buildRun();
}
// lib/services/policy_repository.dart
class PolicySource { final HeroPolicy policy; final Map<String, dynamic> meta; final bool fromFirestore; }
class PolicyRepository { Future<Map<int, PolicySource>> loadAll({Duration timeout = const Duration(seconds: 5)}); }
// lib/services/run_repository.dart
class RunRecord { final String uid, nickname; final int wavesCleared, stageReached, heroDeaths, durationSec; final String layoutSnapshot; }
class RunRepository { Future<void> add(RunRecord r); Future<List<RunRecord>> top20(); }
```

### 모듈 표

| 모듈 | 책임 | 의존 | 완료 기준 |
|---|---|---|---|
| **M0 env_contracts** | Flutter PATH/doctor/web 활성화, `flutter create namaiki_dungeon --platforms web`, 카운터 앱 Chrome 실행, `dart create -t package dungeon_core`, 위 인터페이스 전부를 `UnimplementedError` 스텁으로 작성(`balance.dart`, `models.dart`는 완성본), 앱 pubspec에 path 의존 | — | `flutter run -d chrome` 스크린샷 존재, `dart analyze dungeon_core` 무경고, 앱이 `import 'package:dungeon_core/dungeon_core.dart'` 후 컴파일 |
| **M1 core_sim** | `GridMap`, `GameSim.step`(이동/공격/반격/함정/물약/되돌아가기/보상/종료/trail/events), `FeatureEncoder`, `QTable`(dense+sparse JSON+청크), `GreedyPolicy`, `QTablePolicy` | M0 | `dart test test/game_sim_test.dart test/encoder_test.dart test/qtable_test.dart` green: (1) 빈 맵에서 GreedyPolicy 12턴 왕좌 도달, 보상 합 = 100−12 (2) 함정 진입 HP−15, 보상 −1−4.5−5 (3) 슬라임(10) ATK 8로 2회 공격 후 사망, 반격 1회 2 피해, kill 보상 (4) encode 범위 0..466,559, 맵을 좌우 반전+용사/마물 반전 시 adj·goalDir가 대칭 매핑 (5) toSparseJson→toChunks→fromChunks 왕복 후 Q 동일 (6) 같은 맵·정책·시드로 두 GameSim 이벤트 시퀀스 동일 |
| **M2 core_layout** | `LayoutGenerator` 5 tier, `fixedLayouts` 6종, `demoLayout`, `evalSet(42,300)` | M0, M1 | `dart test test/layout_test.dart` green: 예산 초과 없음, 금지 칸(입구/왕좌/기둥/입구 인접) 위반 없음, hard는 오크≥1 왕좌 인접·함정≥3, evalSet 두 번 생성 시 동일, adversarial이 8후보 중 최저 리턴을 고름(GreedyPolicy로 검증) |
| **M3 trainer** | `Trainer`(ε/α 스케줄, 커리큘럼, 낙관 초기값, 2k 체크포인트, curve.csv), `Evaluator`, `bin/train.dart`, `bin/evaluate.dart`(단계 선정 + 분위수 폴백 + eval.json + stdout 표), `trainer_smoke_test`(마물 0개 맵 500ep 후 greedy 12턴 도달) | M1, M2 | (1) `dart run bin/train.dart --episodes 3000 --tier easy --smoke` 60초 이내 종료, 마지막 500ep 승률 > 첫 500ep (2) `--episodes 200000` 10분 이내에 체크포인트 100개 + curve.csv (3) `dart run bin/evaluate.dart` 가 policy_stage1~3.json(각 ≤ 3MB) + eval.json 생성, 표 출력. 승률 격차 ≥25%p와 데모 stage1 패/stage3 승은 **목표**(미달 시 폴백 규칙 기록만 확인) |
| **M4 uploader** | `bin/upload_policy.dart`: 메타 문서 + chunks(≤900KB 검증) + curves/run1 REST PATCH, 3회 재시도, 멱등. 인자 `--project --api-key --out` | M3 | 실행 후 콘솔에 policies/stage1~3 + chunks 서브컬렉션 존재(chunkCount 일치), 재실행 시 오류 없이 덮어쓰기 |
| **M5 app_shell** | 라우팅(메뉴/플레이/리더보드), `wave_rules.dart`, `GameController`(빌드/웨이브 Timer 200ms/결과/단계 매핑/heroDeaths/forcedStage/restartSameLayout), `BoardGrid`, `BuildPanel`(팔레트·마나·데모·시작), `HUD`, `ResultDialog`, 용사는 GreedyPolicy 스텁 | M0 (M1 인터페이스만) | Chrome에서 배치 탭 즉시 반응, 웨이브 중 배치 불가, GreedyPolicy로 웨이브 1~15 진행·마나 증감·단계 번호 전환이 화면과 로그에 맞음, `flutter analyze` 무경고 |
| **M6 app_offline** | 에셋 정책 로드(`PolicyRepository` 에셋 경로 먼저), `QTablePolicy` 연결, 진화 배너(`EvolveOverlay`, 메타 수치), 트레일(순번+알파), admin 시트(단계 강제 토글·같은 배치 재실행), `BrainPanel`, HUD 통계(턴/HP 손실/함정/물약/처치) | M1, M3, M5 | **[CP A]** Firebase 없이 15웨이브 완주, 배너 2회 노출, 두뇌 패널 막대 최댓값 = 선택 행동, admin 토글로 같은 배치 stage1/2/3 경로 스크린샷 3장, 플레이 스크린샷 4장, 콘솔 에러 0 |
| **M7 app_firebase** | `firebase_options.dart`(콘솔 값 수기), `FirebaseBootstrap`(실패해도 진행), `PolicyRepository` Firestore 우선(chunks 병합, featureSpecVersion 검사, 5초 타임아웃, 에셋 폴백, 로딩 UI), `RunRepository`, `LeaderboardScreen`, admin "에셋 정책 업로드" 폴백 버튼 | M5, M6, M4 | **[CP B]** 로그 `policy stage1..3 loaded from firestore (N states)`; 게임오버 후 runs 문서 생성·리더보드 표시; DevTools offline에서 에셋 폴백으로 플레이; 최종 규칙 게시 후 create 성공·update 거부 확인 |
| **M8 plots_assets** | `tool/plot_curves.py`(curve.csv → learning_curve.png 단계 마커, eval.json → stage_stats.png, Malgun Gothic), 스크린샷 체크리스트 15장 수집, 아키텍처·MDP·커리큘럼 다이어그램 PNG, 슬라이드별 텍스트 초안 md | M3, M6, M7 | `docs/ppt/`에 PNG ≥ 15장(1600px 폭, 한글 깨짐 없음), `docs/ppt/slides_draft.md` |
| **M9 ppt_deck** | pptx 스킬로 13장 제작, 발표자 노트(RL 4요소 설명 스크립트, 30초 데모), PDF 백업 | M8 | `docs/ppt/namaiki_dungeon_rl.pptx` 13장, 모든 장에 이미지/표/다이어그램 ≥1, RL 4요소·학습곡선·Firebase 2용도·보안규칙이 각각 별도 슬라이드, 22:30 v1·23:15 최종 |
| **N1 app_compare (nice)** | `compare_screen.dart`: 같은 GridMap·같은 시드로 GameSim 2개 stage1/stage3 lockstep, 경로 빨강/초록, 요약 배너 | M6 | 데모 배치에서 두 보드 결과가 화면에 나오고 "다시 실행" 시 동일 재현. 18:30 이후 시간 남을 때만 |

### 병렬 묶음 순서
1. **묶음 0 (10:45–11:45, 단일)**: M0
2. **묶음 1 (11:45–13:15, 3병렬)**: M1 ∥ M2+M3(스텁 위에서 시작, M1 완료 후 통합·스모크 런) ∥ M5
3. **묶음 2 (13:15–15:30, 2병렬)**: M3 본 학습·평가 → M4 ∥ M6
4. **묶음 3 (15:30–18:00, 2병렬)**: M7 ∥ (M6 진화 UX 마감, 필요 시 M3 재학습·M4 재업로드)
5. **묶음 4 (18:30–20:30, 2병렬)**: M8 ∥ N1(여유 시에만)
6. **묶음 5 (20:30–23:15, 단일)**: M9

통합 게이트: 묶음 1 종료 시 `dart test` 전체 green + `flutter analyze` 무경고 + 스모크 런 통과. 이 세 가지가 안 되면 묶음 2를 시작하지 않고 원인부터 잡는다.

---

## 12. 심사에서 기각한 대안과 이유

| 대안 | 기각 이유 |
|---|---|
| 단계 차이를 플레이 ε(0.20/0.05/0.00)로 보장 (계획 0) | "학습 결과가 단계"라는 컨셉을 부정하고 RL Q&A에서 무너짐. 모든 단계 ε=0.03, 차이는 학습량으로만 |
| 절대 좌표 + 고정 맵 상태 (계획 0) | 배치를 보고 통로를 고를 수 없어 플레이어 배치 변화에 적응하는 모습이 안 나옴. 자기중심 특징 채택 |
| 진입 즉시 결판 전투 (계획 0) | 싸울지/우회할지 판단이 정책에 표현되지 않음. 턴제 1회 공격 교환 채택 |
| 앱 내 admin 버튼만으로 정책 업로드 (계획 0) | Flutter 웹 빌드가 깨지면 배포·리더보드가 동시에 죽음. Dart REST 업로더를 must로, 앱 버튼은 폴백으로 |
| XP/레벨업, Compare lockstep, CustomPainter 보간을 must (계획 1) | 13시간 대비 범위 초과. XP는 cut, Compare는 nice(대체물 = admin 단계 토글), 렌더링은 위젯 그리드 |
| 학습 결과(격차 ≥25%p, 데모 승패)를 모듈 완료 기준 (계획 1) | 확률적 결과를 납기 기준으로 삼으면 재학습 루프가 시간을 먹음. 목표치로만 관리, 분위수 폴백 자동 기록 |
| 16:30 규칙 잠금 후 재업로드 시 규칙 왕복 (계획 1) | 학생 수작업 2회. 최종 규칙 게시를 마지막 업로드 후 18:15 1회로 |
| `safeDir` BFS 오라클 특징 + 절차 생성 맵 (계획 2) | 경로 문제를 특징이 대신 풀어 단계 차이가 안 갈리고, 막다른 골목에서 타임아웃 잦음. 기둥 맵 + 방향/인접/직전이동 특징 채택 |
| policies 쓰기를 10/1까지 API 키만으로 열어둠 (계획 2) | 웹 API 키는 공개 값. 업로드 후 read-only 잠금 |
| 마왕 목숨 3개 (계획 2) | 학생 컨셉(왕좌 도달 = 패배)과 다름 |
| ZoC(인접 마물 자동 공격) 규칙 (계획 2) | 의미는 있으나 공유 코어 디버깅 면적 증가. 반격 규칙으로 충분 |
| Python 학습기 | 규칙·인코딩 이중 구현 드리프트가 최대 리스크. 표 기반이라 numpy 이점 없음. matplotlib는 그래프에만 |
| Android/Windows 타깃, Flame | 에뮬레이터 이미지 없음·첫 빌드 1시간+, 학습 비용 대비 이득 없음 |
