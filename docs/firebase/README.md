# Firebase 연동 (M7) + 정책 업로더 (M4)

프로젝트: `namaiki-dungeon-61bba` · Firestore `asia-northeast3` · 익명 Auth · 웹 앱.
설정값은 `namaiki_dungeon/lib/firebase_options.dart` (gitignore, 콘솔 웹 config 수기 입력). API 키를 다른 파일에 복사하지 않는다.

## 1. 앱 흐름

```
main() → NamaikiBoot (스플래시 "용사의 기억을 불러오는 중…")
  ├ FirebaseBootstrap.init()          initializeApp + signInAnonymously, 각각 try/catch, 전체 5초 타임아웃. 실패해도 계속.
  ├ PolicyRepository.loadAll()        Firestore policies/stageN + chunks → QTable.fromChunks → QTablePolicy(ε=Balance.epsPlay)
  │                                    featureSpecVersion 불일치/타임아웃/청크 수 불일치/파싱 실패 → 에셋(policy_loader.loadAssetPoliciesWithMeta)
  │                                    에셋도 없으면 GreedyPolicy. 로그: "policy stageN loaded from firestore (M states)" / "from assets" / "greedy fallback"
  └ NamaikiApp(policies, metaStore, runRepository)
       Provider<PolicyMetaStore>  → evolve_overlay 등이 PolicyMetaStore.maybeOf(context)로 승률/학습 횟수 읽음
       Provider<RunRepository>    → LeaderboardScreen
       navigatorObservers: [RunRecorderObserver] → PlayScreen 라우트의 GameController phase가 gameOver/victory로 바뀌면 RunRepository.add(buildRun())
```

파일: `lib/services/firebase_bootstrap.dart`, `lib/services/policy_repository.dart`(PolicySource, PolicyRepository, PolicyMetaStore),
`lib/services/run_repository.dart`(RunRecord, RunRepository), `lib/ui/leaderboard_screen.dart`, `lib/main.dart`.

## 2. 데이터 모델 (PLAN.md §6)

```
policies/{stageId}                         stageId ∈ {stage1, stage2, stage3}
  stage: int, name: string, algorithm: "tabular_q_learning", featureSpecVersion: int(=Balance.featureSpecVersion),
  episodes: int, winRate: double, avgSteps: double, trapHits: double, potionsUsed: double, kills: double,
  stateCount: int, chunkCount: int, statesPerChunk: int, version: string("2026-09-21T15:00"), createdAt: timestamp,
  (선택) selectionRule: string, demoWin: bool
policies/{stageId}/chunks/{000..NNN}
  data: string     QTable.toChunks 각 항목 = {"v":1,"n":5,"q":{"stateIndex":[q_up,q_down,q_left,q_right,q_potion],...}}, ≤ 900KB 검증
  index: int
runs/{autoId}
  uid: string(익명 uid), nickname: string(≤12, 기본 "마왕"), wavesCleared: int(0..15), stageReached: int(1..3),
  heroDeaths: int, durationSec: int, layoutSnapshot: string(GridMap.toJson), appVersion: string, createdAt: serverTimestamp
curves/run1 (옵션, out/curve.csv 있을 때)
  data: string(JSON [{ep,win,reward,steps}] ≤ 300점), points: int, stageMarkers: [int,int,int], updatedAt: timestamp
```

리더보드 쿼리: `runs orderBy wavesCleared desc, createdAt desc limit 20` → **복합 색인 1개 필요**.
색인이 없으면 앱은 `failed-precondition`을 잡아 `wavesCleared desc` 단일 정렬로 폴백하고(화면에 "단순 정렬" 표시), 콘솔에 링크를 남긴다.

### 색인 생성 링크 (학생이 1회 클릭 → "색인 만들기" → 1~3분 대기)

https://console.firebase.google.com/v1/r/project/namaiki-dungeon-61bba/firestore/indexes?create_composite=ClJwcm9qZWN0cy9uYW1haWtpLWR1bmdlb24tNjFiYmEvZGF0YWJhc2VzLyhkZWZhdWx0KS9jb2xsZWN0aW9uR3JvdXBzL3J1bnMvaW5kZXhlcy9fEAEaEAoMd2F2ZXNDbGVhcmVkEAIaDQoJY3JlYXRlZEF0EAIaDAoIX19uYW1lX18QAg

(REST `runQuery`로 미리 뽑아 둔 링크. 수동 생성 시: 컬렉션 `runs`, 필드 `wavesCleared` 내림차순 + `createdAt` 내림차순, 쿼리 범위 "컬렉션".)

## 3. 정책 업로드 (dungeon_core/bin/upload_policy.dart)

Firestore REST PATCH 직접 호출. Admin SDK·서비스 계정·Firebase CLI 불필요. **테스트 모드 규칙이 켜진 동안에만** 업로드한다.

```bash
cd C:\Users\gnfle\fly\dungeon_core
dart run bin/upload_policy.dart --project namaiki-dungeon-61bba --api-key <firebase_options.dart의 apiKey> --out out/
```

- 입력: `out/policy_stage{1,2,3}.json` (`bin/evaluate.dart` 산출물 `{"meta":{...},"q":<sparse>}`; 루트가 sparse JSON인 파일도 허용),
  `out/eval.json`(stageMarkers), `out/curve.csv`(curves/run1).
- 동작: 청크 먼저 PATCH → 메타 문서 PATCH → 옛 청크(index ≥ chunkCount) 삭제 → GET으로 chunkCount·청크 수 검증.
  청크 ≤ 900KB 검증(초과 시 statesPerChunk 절반으로 재분할), 요청당 3회 재시도(1s/2s/4s), 멱등(재실행 = 덮어쓰기).
- 옵션: `--stages 1,2,3`, `--collection policies`, `--version STR`, `--no-curves`, `--dry-run`, `--delete`, `--make-smoke DIR`.
- 로그에 API 키는 찍히지 않는다(오류 본문에서도 마스킹).

스모크 절차(실행 완료, 2026-09-21 17:44):
```bash
dart run bin/upload_policy.dart --make-smoke out_tmp                       # 방문 상태 50개 가짜 정책
dart run bin/upload_policy.dart --project ... --api-key ... --out out_tmp --collection policies_smoke --stages 1 --no-curves
#   → chunk 000 업로드(1.9KB), 메타 업로드(chunkCount=1), 검증 OK. 재실행 시 덮어쓰기 OK.
curl ".../documents/policies_smoke/stage1?key=..."                          # HTTP 200
dart run bin/upload_policy.dart --project ... --api-key ... --collection policies_smoke --stages 1 --delete
#   → 삭제 검증: 문서 없음(OK), chunks 0개. 이후 GET → 404
```

에셋 폴백: 같은 파일을 `namaiki_dungeon/assets/policies/policy_stage{1,2,3}.json`으로 복사한다.

## 4. 최종 보안 규칙 (마지막 업로드 후 1회 게시, PLAN.md §6 원문)

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

앱의 `RunRepository.add`는 이 규칙에 맞춰 uid=현재 익명 uid, wavesCleared 0..15 클램프, stageReached 1..3 클램프, nickname 12자 절단으로 저장한다.
규칙 게시 후엔 업로더(API 키만, 인증 없음)는 `policies` 쓰기가 거부되므로 재업로드가 필요하면 테스트 모드로 잠시 되돌린다.

## 5. 콘솔 체크리스트

1. Firestore → 색인 탭: 위 링크로 `runs (wavesCleared desc, createdAt desc)` 복합 색인 생성.
2. `dart run bin/upload_policy.dart ...` 로 policies/stage1~3 업로드 → 데이터 탭에서 chunks 서브컬렉션 확인.
3. 앱 실행 → Chrome 콘솔에 `policy stage1..3 loaded from firestore (N states)`.
4. 게임오버/승리 → Firestore `runs`에 문서 생성 → 메뉴 → 리더보드 표시.
5. 규칙 탭에 최종 규칙 게시 → 게임오버 후 create 성공, 콘솔에서 update 시도 시 거부 확인.

## 6. 읽기 스모크 (curl)

```bash
curl -s -w "\nHTTP %{http_code}\n" "https://firestore.googleapis.com/v1/projects/namaiki-dungeon-61bba/databases/(default)/documents/policies?mask.fieldPaths=stage&key=<apiKey>"
```
2026-09-21 17:45 결과: `HTTP 200` (아직 실제 정책 미업로드 → `{}`).
