import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/foundation.dart';

import '../services/run_repository.dart';
import 'wave_rules.dart';

/// 게임 진행 단계.
/// build → running → result → (evolve) → build … → victory / gameOver
enum Phase { build, running, result, evolve, gameOver, victory }

extension PhaseX on Phase {
  String get korean => switch (this) {
        Phase.build => '배치',
        Phase.running => '웨이브 진행',
        Phase.result => '결과',
        Phase.evolve => '진화',
        Phase.gameOver => '게임 오버',
        Phase.victory => '승리',
      };
}

/// 앱 상태 컨트롤러 (PLAN.md §11 "앱 인터페이스").
///
/// - 빌드 페이즈: 팔레트 선택 → 셀 탭으로 배치/제거, 마나 차감/환불.
/// - 웨이브: [GameSim]을 만들고 200ms마다 정책 행동을 한 스텝씩 실행.
/// - 종료: 방어 성공이면 result(웨이브 5/10 뒤엔 evolve 배너), 15웨이브 방어면 victory, 왕좌 도달이면 gameOver.
/// - 규칙 숫자는 전부 `Balance`/`monsterSpecs`에서 읽는다.
class GameController extends ChangeNotifier {
  /// [policies]: 단계(1..3) → 용사 정책. 비어 있으면 안 된다.
  /// [initialMap]/[rng]/[tickInterval]은 테스트·admin용 주입 지점.
  GameController(
    this.policies, {
    GridMap? initialMap,
    Random? rng,
    this.tickInterval = const Duration(milliseconds: 200),
  })  : assert(policies.isNotEmpty, '정책이 하나 이상 필요합니다'),
        _map = initialMap ?? GridMap(),
        _rng = rng ?? Random(),
        _startedAt = DateTime.now();

  /// 단계 → 정책. 정책 주입 지점 (M6에서 QTablePolicy로 교체).
  final Map<int, HeroPolicy> policies;

  /// 웨이브 진행 틱 간격 (기본 200ms).
  final Duration tickInterval;

  final Random _rng;
  final DateTime _startedAt;

  Phase _phase = Phase.build;
  int _wave = 1;
  int _mana = Balance.startMana;
  GridMap _map;
  GameSim? _sim;
  HeroPolicy? _policy;
  Timer? _timer;

  MonsterType _selected = MonsterType.slime;
  int? _forcedStage;

  int _heroDeaths = 0;
  int _wavesCleared = 0;
  Outcome? _lastOutcome;
  HeroAction? _lastAction;
  StepResult? _lastStep;
  String? _lastError;
  int _tick = 0;
  int _lastHeroDamage = 0;

  // ── 읽기 ──────────────────────────────────────────

  Phase get phase => _phase;
  int get wave => _wave;
  int get mana => _mana;

  /// 현재 적용 단계: admin 강제값이 있으면 그것, 없으면 웨이브 기준.
  int get stage => _forcedStage ?? WaveRules.stageForWave(_wave);

  /// 웨이브 기준 단계 (강제값 무시). 뱃지·진화 배너 표시용.
  int get waveStage => WaveRules.stageForWave(_wave);

  /// 빌드 레이아웃 (웨이브 시작 전 배치). 웨이브 중 실제 상태는 [sim]의 map을 본다.
  GridMap get map => _map;

  /// 화면에 그릴 맵: 웨이브 진행/결과 중엔 시뮬레이터의 현재 맵, 그 외엔 빌드 레이아웃.
  GridMap get boardMap {
    final s = _sim;
    if (s != null && (_phase == Phase.running || _phase == Phase.result || _phase == Phase.gameOver || _phase == Phase.victory)) {
      return s.map;
    }
    return _map;
  }

  GameSim? get sim => _sim;

  /// 이번 웨이브에 쓰인 정책 (웨이브 시작 전엔 현재 단계 정책).
  HeroPolicy get activePolicy => _policy ?? policyForStage(stage);

  /// 팔레트 선택.
  MonsterType get selected => _selected;
  set selected(MonsterType t) {
    if (_selected == t) return;
    _selected = t;
    notifyListeners();
  }

  /// admin 단계 강제 (null이면 웨이브 기준). 다음 startWave부터 적용.
  int? get forcedStage => _forcedStage;
  set forcedStage(int? s) {
    if (_forcedStage == s) return;
    _forcedStage = s;
    notifyListeners();
  }

  int get heroDeaths => _heroDeaths;
  int get wavesCleared => _wavesCleared;
  Outcome? get lastOutcome => _lastOutcome;
  HeroAction? get lastAction => _lastAction;
  StepResult? get lastStep => _lastStep;

  /// 스텝 카운터. 스텝마다 1씩 증가하며 이펙트 위젯이 "한 번 재생" 트리거로 쓴다 (웨이브 시작 시에도 증가).
  int get tick => _tick;

  /// 마지막 스텝의 이벤트 (없으면 빈 리스트). lastStep.events 와 동일.
  List<Event> get lastEvents => _lastStep?.events ?? const [];

  /// 마지막 스텝에서 용사가 잃은 HP (반격/함정). 0이면 피격 없음.
  int get lastHeroDamage => _lastHeroDamage;

  /// 마지막 오류 메시지 (읽으면 지워짐). 코어 예외를 화면 스낵바로 보여주기 위함.
  String? takeError() {
    final e = _lastError;
    _lastError = null;
    return e;
  }

  /// 경로 트레일 (웨이브 종료 후에도 다음 웨이브 시작 전까지 유지).
  List<Pos> get trail => _sim?.trail ?? const [];

  /// 용사를 보드에 그려야 하는가 (웨이브 진행 중 또는 종료 직후).
  bool get showHero => _sim != null && _phase != Phase.build && _phase != Phase.evolve;

  /// 이번 웨이브 용사 스탯 (웨이브 시작 전엔 예정 스탯).
  HeroStats get heroStats => WaveRules.heroFor(_wave);

  /// 현재 배치된 마나 총합.
  int get placedCost => _map.monsters.values.fold(0, (s, m) => s + m.type.spec.cost);

  /// 플레이 경과 시간(초).
  int get durationSec => DateTime.now().difference(_startedAt).inSeconds;

  bool get isRunning => _phase == Phase.running;
  bool get canBuild => _phase == Phase.build;

  /// 단계에 해당하는 정책. 없으면 웨이브 기준 → 아무거나.
  HeroPolicy policyForStage(int s) =>
      policies[s] ?? policies[WaveRules.stageForWave(_wave)] ?? policies.values.first;

  /// 두뇌 패널용: 정책이 QTablePolicy일 때 현재 상태의 5행동 Q값. 아니면 null.
  List<double>? get currentQ {
    final s = _sim;
    final p = activePolicy;
    if (s == null || p is! QTablePolicy) return null;
    return p.qValues(s);
  }

  /// 두뇌 패널용: 정책이 QTablePolicy일 때 현재 상태 특징. 아니면 null.
  StateFeatures? get currentFeatures {
    final s = _sim;
    if (s == null || activePolicy is! QTablePolicy) return null;
    return FeatureEncoder.features(s);
  }

  // ── 빌드 페이즈 ───────────────────────────────────

  /// 선택한 종류를 [p]에 배치. 비용 ≤ 마나이고 배치 가능할 때만 true.
  bool placeAt(Pos p) {
    if (_phase != Phase.build) return false;
    final cost = _selected.spec.cost;
    if (cost > _mana) return false;
    if (!_map.place(_selected, p)) return false;
    _mana -= cost;
    notifyListeners();
    return true;
  }

  /// [p]의 마물/함정 제거, 전액 환불.
  bool removeAt(Pos p) {
    if (_phase != Phase.build) return false;
    final m = _map.monsters[p];
    if (m == null) return false;
    if (!_map.remove(p)) return false;
    _mana += m.type.spec.cost;
    notifyListeners();
    return true;
  }

  /// 데모 레이아웃(함정 지름길 + 슬라임 밭 + 왕좌 앞 오크)을 현재 마나 안에서 적용.
  /// 기존 배치는 전액 환불한 뒤 비싼 것부터 채우고, 예산을 넘는 항목은 덜어낸다.
  void loadDemoLayout() {
    if (_phase != Phase.build) return;
    try {
      final demo = LayoutGenerator.demoLayout();
      final items = demo.monsters.values.toList()
        ..sort((a, b) => b.type.spec.cost.compareTo(a.type.spec.cost));
      var budget = _mana + placedCost;
      final fresh = GridMap();
      for (final m in items) {
        final c = m.type.spec.cost;
        if (c > budget) continue;
        if (fresh.place(m.type, m.pos)) budget -= c;
      }
      _map = fresh;
      _mana = budget;
    } catch (e) {
      _lastError = '데모 배치 실패: $e';
    }
    notifyListeners();
  }

  // ── 웨이브 ────────────────────────────────────────

  /// 현재 빌드 레이아웃으로 웨이브 시작.
  void startWave() {
    if (_phase != Phase.build) return;
    _beginWave();
  }

  /// admin: 현재 레이아웃을 유지한 채 같은 웨이브를 다시 실행 (단계 강제 토글과 함께 사용).
  void restartSameLayout() {
    _beginWave();
  }

  void _beginWave() {
    _stopTimer();
    try {
      _policy = policyForStage(stage);
      _sim = GameSim(_map, WaveRules.heroFor(_wave));
    } catch (e) {
      _sim = null;
      _lastError = '웨이브 시작 실패: $e';
      _phase = Phase.build;
      notifyListeners();
      return;
    }
    _lastAction = null;
    _lastStep = null;
    _lastOutcome = null;
    _lastHeroDamage = 0;
    _tick++;
    _phase = Phase.running;
    notifyListeners();
    _timer = Timer.periodic(tickInterval, (_) => _step());
  }

  void _step() {
    final s = _sim;
    final p = _policy;
    if (s == null || p == null) {
      _stopTimer();
      return;
    }
    if (s.done) {
      _stopTimer();
      _finishWave(s.outcome);
      notifyListeners();
      return;
    }
    try {
      final a = p.act(s, _rng);
      _lastAction = a;
      final hpBefore = s.hp;
      final r = s.step(a);
      _lastStep = r;
      _lastHeroDamage = max(0, hpBefore - s.hp);
      _tick++;
      if (r.done) {
        _stopTimer();
        _finishWave(r.outcome);
      }
    } catch (e) {
      _stopTimer();
      _lastError = '웨이브 진행 오류: $e';
      _phase = Phase.build;
    }
    notifyListeners();
  }

  void _finishWave(Outcome o) {
    _lastOutcome = o;
    if (o == Outcome.reachedThrone) {
      _phase = Phase.gameOver;
      return;
    }
    // 방어 성공 (사망 또는 턴 초과 퇴각)
    if (o == Outcome.heroDied) _heroDeaths++;
    _wavesCleared = max(_wavesCleared, _wave);
    if (WaveRules.isFinalWave(_wave)) {
      _phase = Phase.victory;
      return;
    }
    _phase = Phase.result;
  }

  /// 결과 확인 후 다음 웨이브 준비: 살아남은 마물 HP 회복, 마나 +5, wave+1.
  /// 단계가 바뀌는 웨이브(5→6, 10→11)면 build 대신 evolve 배너를 먼저 보여준다.
  void nextWave() {
    if (_phase != Phase.result) return;
    _map = _survivorsWithFullHp();
    final from = _wave;
    _wave++;
    _mana += Balance.manaPerWave;
    _phase = WaveRules.isStageTransition(from, _wave) ? Phase.evolve : Phase.build;
    notifyListeners();
  }

  /// 진화 배너 닫기 → 빌드 페이즈.
  void dismissEvolve() {
    if (_phase != Phase.evolve) return;
    _phase = Phase.build;
    notifyListeners();
  }

  /// 시뮬레이터의 현재 맵(죽은 마물 제거됨)을 복제하고 살아남은 마물 HP를 전회복.
  GridMap _survivorsWithFullHp() {
    final src = _sim?.map ?? _map;
    final next = src.clone();
    for (final m in next.monsters.values) {
      m.hp = m.maxHp;
    }
    return next;
  }

  // ── 기록 ──────────────────────────────────────────

  /// 리더보드 기록 생성 (uid는 저장 계층이 채운다).
  RunRecord buildRun() => RunRecord(
        uid: '',
        nickname: '마왕',
        wavesCleared: _wavesCleared,
        stageReached: WaveRules.stageForWave(_wave).clamp(1, WaveRules.stageCount),
        heroDeaths: _heroDeaths,
        durationSec: durationSec,
        layoutSnapshot: jsonEncode(_map.toJson()),
      );

  // ── 테스트 훅 ─────────────────────────────────────

  /// 테스트 전용: 페이즈 직접 설정 (startWave 없이 running 상태 등을 만들기 위함).
  @visibleForTesting
  void debugSetPhase(Phase p) {
    _stopTimer();
    _phase = p;
    notifyListeners();
  }

  /// 테스트 전용: 웨이브 직접 설정.
  @visibleForTesting
  void debugSetWave(int w) {
    _wave = w;
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
