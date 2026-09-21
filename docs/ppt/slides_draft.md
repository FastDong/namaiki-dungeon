# 마왕의 던전: 죽을수록 똑똑해지는 용사 — 슬라이드 초안 (13장)

> 표기: `{{...}}` 는 학습/앱 결과가 나오면 채우는 값. 이미지 경로는 docs/ppt/ 기준.

---

## 1. 표지
- 제목: **마왕의 던전** — 죽을수록 똑똑해지는 용사
- 부제: Flutter + Firebase + Q-learning 으로 만든 마물 배치 디펜스
- 이름/학번: {{이름}} / {{학번}}
- 배경 이미지: shots/wave_trail.png (웨이브 진행 중 트레일이 보이는 화면)
- 발표자 노트: "플레이어는 마왕입니다. 마물을 배치해서 던전에 쳐들어오는 용사를 막는데, 이 용사는 강화학습으로 미리 훈련된 AI이고 5웨이브를 막을 때마다 더 많이 학습한 상위 단계 용사가 등장합니다."

## 2. 아이디어
- 오마주: PSP 『용사 주제에 건방지다』 — 마왕 시점, 용사를 막는 던전 게임
- 뒤집힌 구도: **플레이어 = 환경 설계자(마왕)**, **AI = 학습하는 주인공(용사)**
- 핵심 루프 다이어그램: 배치 → 침입 → 용사 사망 → (오프라인) 학습 → 진화한 용사 등장
- 왜 재밌나: 내가 짠 함정에 걸리던 용사가 어느 순간 피해 돌아가기 시작한다
- 이미지: diagrams/core_loop.png

## 3. 게임 규칙
- 맵: 7×7, 기둥 9개, 입구(0,0) → 왕좌(6,6)
- 마물 표 | 종류 | HP | ATK | 마나 |
  | 슬라임 | 10 | 2 | 1 |
  | 고블린 | 24 | 5 | 3 |
  | 오크 | 40 | 9 | 6 |
  | 가시함정 | – | 진입 시 15 | 2 |
- 자원: 시작 마나 12, 웨이브마다 +5 (이월)
- 용사: HP 50 + 6(w−1), ATK 8 + (w−1), 물약 2개(+25)
- 승패: 용사 사망/80턴 퇴각 = 방어 성공, 왕좌 도달 = 게임오버, 15웨이브 방어 = 승리
- **5웨이브마다 AI 단계 교체** (1~5: Stage 1, 6~10: Stage 2, 11~15: Stage 3)
- 이미지: shots/build_phase.png

## 4. 플레이 흐름 4컷
- ① 빌드 페이즈(팔레트·마나) ② 웨이브 진행(경로 트레일·데미지 팝) ③ 용사 사망 → 결과 카드 ④ 진화 배너
- 이미지: shots/build_phase.png, shots/wave_trail.png, shots/result.png, shots/evolve.png

## 5. 시스템 아키텍처
- 순수 Dart 패키지 `dungeon_core`: 규칙·시뮬레이터·상태 인코더·Q-테이블·배치 봇·학습기 → **앱과 학습기가 같은 코드 공유** (규칙 이중 구현 없음)
- 학습기 `bin/train.dart`(PC 오프라인) → `policy_stage1~3.json` → `bin/upload_policy.dart` → **Firestore `policies/`**
- Flutter 앱: 시작 시 Firestore에서 정책 3개 다운로드(실패 시 에셋 폴백) → 웨이브마다 단계에 맞는 정책으로 용사 행동
- 리더보드: 게임 종료 시 `runs/` 문서 생성, 상위 20 조회
- 이미지: diagrams/architecture.png

## 6. 강화학습 문제 정의 (MDP)
- **상태 (466,560개, 자기중심·절대좌표 없음)**: 왕좌 방향(9) × 인접 4칸 종류(6⁴=1,296) × HP 구간(4) × 물약(2) × 직전 이동(5)
  - 인접 칸 종류: 벽 / 빈칸 / 약한 마물 / 강한 마물 / 함정 / 왕좌 ("약함" = 2턴 안에 잡을 수 있음 → 용사가 성장해도 같은 Q-테이블 유효)
- **행동 (5)**: 상/하/좌/우 이동(마물 칸이면 공격), 물약
- **보상**: 왕좌 +100 · 사망 −100 · 퇴각 −50 · 턴 −1 · 처치 +5 · HP 손실 −0.3/pt · 함정 −5 · 벽 충돌 −2 · 되돌아가기 −1 · 물약 낭비 −3
- γ = 0.97
- 왜 자기중심 상태인가: 플레이어가 어떤 배치를 해도 "주변을 보고 판단"하는 정책이라 일반화됨
- 이미지: diagrams/mdp.png

## 7. 알고리즘: 표 기반 Q-learning
- 갱신식: Q(s,a) ← Q(s,a) + α[r + γ·max Q(s′,·) − Q(s,a)]
- 하이퍼파라미터: α 0.1→0.03, ε 1.0→0.05(60% 지점까지 선형), 낙관 초기값 +2(왕좌 방향 이동)
- 선택 이유 ① 라이브러리 없이 Dart로 구현·검증 가능 ② Q값을 앱에서 그대로 막대로 보여줄 수 있는 **설명 가능한 RL** ③ JSON 그대로 Firestore에 배포 ④ 결정론적 유한 MDP라 수렴 안정
- 코드 스니펫: qtable.dart / trainer.dart 갱신 부분 10줄
- 이미지: shots/code_qlearning.png

## 8. 학습 절차: 마왕 봇 vs 용사 봇
- 마왕 봇(규칙 기반, 학습 안 함)이 상대 배치를 생성 — **커리큘럼**
  - easy(0~20%): 슬라임/함정, 왕좌 근처
  - medium(20~60%): 4종, 최단경로에 함정
  - hard/적대적/고정(60~100%): 왕좌 앞 오크, 함정 3+, **적대적 = 후보 8개 중 현재 용사가 가장 못 뚫는 배치 채택**
- {{총 에피소드}} 에피소드, 2,000마다 체크포인트 → 고정 평가셋 300배치로 전부 평가
- **단계 정의**: 승률 ≥10% 첫 체크포인트 = Stage 1, ≥45% = Stage 2, 최고 = Stage 3 (선정 규칙: {{threshold|quantile}})
- 이미지: diagrams/curriculum.png

## 9. 학습 곡선
- 이미지: learning_curve.png (승률·평균 리턴, 단계 마커 3개), eval_curve.png
- 학습 시간: {{학습 시간}} (Dart, 노트북 CPU)
- 관찰: {{승률 추이 한 줄}}

## 10. 진화의 증거
- 같은 배치(데모 레이아웃)에서 Stage 1/2/3 용사의 경로 3장 나란히: shots/compare_stage1.png, compare_stage2.png, compare_stage3.png
- 단계별 행동 통계 표: stage_stats.png (승률 / 평균 턴 / 함정 밟음 / 물약 / 처치)
- 두뇌 패널: shots/brain_panel.png — "왜 그쪽으로 갔나"를 Q값으로 설명
- 발표자 노트: Stage 1은 함정을 밟고 직진, Stage 3은 {{관찰}}

## 11. Firebase 활용 ① 정책 배포
- Firestore 데이터 모델: `policies/{stage}` (메타: episodes, winRate, …) + `chunks/{i}` (Q-테이블 sparse JSON 조각, 문서 1MiB 한도 대응)
- 업로드: Dart REST 스크립트 `upload_policy.dart` — 재학습 후 재업로드만 하면 **앱 수정 없이 용사가 바뀜**
- 앱 로딩 흐름: Firestore → 버전 검사(featureSpecVersion) → 실패 시 에셋 폴백
- 이미지: shots/firestore_policies.png (콘솔 데이터 탭), diagrams/policy_flow.png

## 12. Firebase 활용 ② 익명 인증 + 리더보드 + 보안 규칙
- 익명 Auth: 회원가입 없이 즉시 플레이, uid로 기록 소유 검증
- `runs/` 모델과 리더보드 화면: shots/leaderboard.png, shots/auth_users.png
- 보안 규칙: 정책은 **읽기 전용**, runs는 **본인 uid로 생성만**, 값 범위 검증(wavesCleared 0~15 등)
- 이미지: shots/rules.png (규칙 탭)

## 13. 한계와 향후 과제 + 요약
- 한계: 국소 관측(인접 4칸)이라 장기 경로 계획 불가 → 막다른 길 없는 맵으로 설계
- 향후: DQN/PPO로 확장, 마물도 학습(self-play), 다른 유저의 던전에 내 용사 보내기
- 요약: 게임(마물 배치 디펜스) / RL(표 기반 Q-learning, 자기중심 상태, 커리큘럼) / Firebase(정책 배포 + 익명 인증 + 리더보드 + 규칙)
- 저장소: https://github.com/FastDong/namaiki-dungeon
- 발표자 노트(30초 데모 스크립트): 데모 배치 버튼 → 웨이브 시작 → Stage 1 용사가 함정 밟고 사망 → admin에서 Stage 3 강제 → 같은 배치 재실행 → 함정 우회

---

## 스크린샷 체크리스트 (docs/ppt/shots/)
- [ ] menu.png
- [ ] build_phase.png
- [ ] wave_trail.png
- [ ] hit_effect.png (데미지 팝 순간)
- [ ] result.png
- [ ] evolve.png
- [ ] compare_stage1.png / compare_stage2.png / compare_stage3.png (데모 배치, admin 단계 강제)
- [ ] brain_panel.png
- [ ] leaderboard.png
- [ ] gameover.png
- [ ] firestore_policies.png / auth_users.png / rules.png (콘솔)
- [ ] phone_photo.jpg (실기기 실행, 있으면)
- [ ] code_qlearning.png
