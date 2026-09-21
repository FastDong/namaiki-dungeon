import 'dart:math';

import 'balance.dart';
import 'game_sim.dart';
import 'grid_map.dart';
import 'models.dart';
import 'policy.dart';

/// 배치 봇(마왕 봇) 난이도. 학습하지 않는 규칙 기반 (PLAN.md §5.5).
enum Tier { easy, medium, hard, adversarial, fixed }

extension TierX on Tier {
  String get korean => switch (this) {
        Tier.easy => '쉬움',
        Tier.medium => '보통',
        Tier.hard => '어려움',
        Tier.adversarial => '적대적',
        Tier.fixed => '고정',
      };
}

/// 배치 봇 규칙 수치 (PLAN.md §5.5).
///
/// 게임 규칙(Balance)·마물 스펙(monsterSpecs)이 아니라 "학습 상대를 어떻게 만들 것인가"에 대한
/// 파라미터라서 이 파일에 모아 둔다. 다른 곳에서 숫자를 직접 쓰지 않는다.
class LayoutRules {
  LayoutRules._();

  // ── 예산 (양끝 포함 균등) ───────────────────────────
  static const int easyBudgetMin = 6, easyBudgetMax = 12;
  static const int mediumBudgetMin = 12, mediumBudgetMax = 22;
  static const int hardBudgetMin = 20, hardBudgetMax = 35;

  // ── 용사 웨이브 (양끝 포함 균등) ────────────────────
  static const int easyWaveMin = 1, easyWaveMax = 6;
  static const int mediumWaveMin = 3, mediumWaveMax = 11;
  static const int hardWaveMin = 6, hardWaveMax = Balance.totalWaves;

  /// adversarial 롤아웃에 [hero]가 안 넘어왔을 때 쓰는 용사 웨이브.
  static const int adversarialHeroWave = 6;

  /// "왕좌 인접"으로 보는 최대 맨해튼 거리. (5,5)가 기둥이라 거리 1은 (5,6)·(6,5) 2칸뿐이므로
  /// 거리 2의 (4,6)·(6,4)까지 포함한다.
  static const int nearThroneMaxDistance = 2;

  /// easy: 배치마다 왕좌 인접 칸을 우선할 확률.
  static const double easyNearThroneProb = 0.5;

  /// medium: 배치마다 최단경로 위 칸에 함정을 놓을 확률.
  static const double mediumPathTrapProb = 0.6;

  /// hard: 왕좌 인접 오크 강제 수, 최단경로 위/근처 함정 강제 수, 이후 종류 가중치.
  static const int hardForcedOrcs = 1, hardForcedTraps = 3;
  static const Map<MonsterType, double> hardWeights = {
    MonsterType.goblin: 0.5,
    MonsterType.slime: 0.2,
    MonsterType.trap: 0.2,
    MonsterType.orc: 0.1,
  };

  /// fixed "함정 복도"의 함정 수.
  static const int corridorTraps = 5;

  /// demo: 지름길 함정 수, 슬라임 밭 크기.
  static const int demoTraps = 3, demoSlimes = 6;

  /// 고정 평가셋이 순환하는 웨이브 = 각 단계의 첫 웨이브 (1, 6, 11).
  static List<int> evalWaves() => List<int>.generate(
        Balance.totalWaves ~/ Balance.wavesPerStage,
        (s) => 1 + s * Balance.wavesPerStage,
      );
}

/// adversarial 생성 과정의 중간 결과 (테스트·디버그 UI용).
class AdversarialSearch {
  /// hard 규칙으로 만든 후보 (Balance.adversarialCandidates개).
  final List<GridMap> candidates;

  /// 후보별 용사 평균 리턴 (Balance.adversarialRollouts회 평균).
  final List<double> avgReturns;

  /// 평균 리턴이 가장 낮은 후보의 인덱스 (동점이면 앞선 것).
  final int bestIndex;

  const AdversarialSearch(this.candidates, this.avgReturns, this.bestIndex);

  GridMap get best => candidates[bestIndex];
}

/// 학습 상대 배치 생성기.
///
/// | tier | 예산 | 규칙 |
/// | easy | U[6,12] | 슬라임/함정만, 왕좌 인접 3칸 우선 확률 0.5 |
/// | medium | U[12,22] | 4종 전부, 입구→왕좌 최단경로 위 칸에 확률 0.6으로 함정 |
/// | hard | U[20,35] | 오크 ≥1 왕좌 인접 강제, 함정 ≥3, 고블린으로 병목 |
/// | adversarial | hard 동일 | hard 후보 8개 → adversary 정책으로 각 2회 롤아웃 → 용사 평균 리턴 최저 배치 채택 |
/// | fixed | — | fixedLayouts() 6종 중 랜덤 |
/// 예산은 절대 초과하지 않는다. 금지 칸(입구/왕좌/기둥/입구 인접) 위반 없음.
class LayoutGenerator {
  LayoutGenerator();

  /// 고정 배치 6종의 이름 (fixedLayouts()와 같은 순서).
  static const List<String> fixedLayoutNames = [
    '입구 앞 벽',
    '왕좌 포위',
    '함정 복도',
    '슬라임 밭',
    '좌우 분기 함정',
    '오크 2연속',
  ];

  /// [adversary]/[hero]는 Tier.adversarial에서만 사용 (없으면 GreedyPolicy / HeroStats.forWave(6)).
  GridMap generate(Tier tier, Random rng, {HeroPolicy? adversary, HeroStats? hero}) {
    switch (tier) {
      case Tier.easy:
        return _generateEasy(rng);
      case Tier.medium:
        return _generateMedium(rng);
      case Tier.hard:
        return _generateHard(rng);
      case Tier.adversarial:
        return searchAdversarial(rng, adversary: adversary, hero: hero).best;
      case Tier.fixed:
        final all = fixedLayouts();
        return all[rng.nextInt(all.length)].clone();
    }
  }

  /// 용사 웨이브 샘플: easy 1..6, medium 3..11, hard/adversarial/fixed 6..15 (균등).
  int sampleWave(Tier tier, Random rng) {
    final (lo, hi) = waveRange(tier);
    return lo + rng.nextInt(hi - lo + 1);
  }

  /// tier별 예산 범위 (양끝 포함). fixed는 예산 개념이 없어 null.
  static (int min, int max)? budgetRange(Tier tier) => switch (tier) {
        Tier.easy => (LayoutRules.easyBudgetMin, LayoutRules.easyBudgetMax),
        Tier.medium => (LayoutRules.mediumBudgetMin, LayoutRules.mediumBudgetMax),
        Tier.hard || Tier.adversarial => (LayoutRules.hardBudgetMin, LayoutRules.hardBudgetMax),
        Tier.fixed => null,
      };

  /// tier별 용사 웨이브 범위 (양끝 포함).
  static (int min, int max) waveRange(Tier tier) => switch (tier) {
        Tier.easy => (LayoutRules.easyWaveMin, LayoutRules.easyWaveMax),
        Tier.medium => (LayoutRules.mediumWaveMin, LayoutRules.mediumWaveMax),
        Tier.hard || Tier.adversarial || Tier.fixed => (LayoutRules.hardWaveMin, LayoutRules.hardWaveMax),
      };

  /// 예산 B ~ U[min,max] 정수 샘플. generate()가 맨 처음 rng에서 뽑는 값이라 같은 시드로
  /// 먼저 호출하면 그 배치의 예산을 알 수 있다 (테스트용). fixed는 0.
  static int sampleBudget(Tier tier, Random rng) {
    final range = budgetRange(tier);
    if (range == null) return 0;
    final (lo, hi) = range;
    return lo + rng.nextInt(hi - lo + 1);
  }

  // ── easy ────────────────────────────────────────────

  GridMap _generateEasy(Random rng) {
    final map = GridMap();
    var remaining = sampleBudget(Tier.easy, rng);
    const kinds = [MonsterType.slime, MonsterType.trap];
    while (true) {
      final affordable = _affordable(kinds, remaining);
      if (affordable.isEmpty) break;
      final free = _freeCells(map);
      if (free.isEmpty) break;
      final type = affordable[rng.nextInt(affordable.length)];
      var pool = free;
      if (rng.nextDouble() < LayoutRules.easyNearThroneProb) {
        final near = _nearThrone(free);
        if (near.isNotEmpty) pool = near;
      }
      remaining -= _placeChecked(map, type, pool[rng.nextInt(pool.length)]);
    }
    return map;
  }

  // ── medium ──────────────────────────────────────────

  GridMap _generateMedium(Random rng) {
    final map = GridMap();
    var remaining = sampleBudget(Tier.medium, rng);
    final pathSet = map.shortestPath().toSet();
    while (true) {
      final affordable = _affordable(MonsterType.values, remaining);
      if (affordable.isEmpty) break;
      final free = _freeCells(map);
      if (free.isEmpty) break;
      if (affordable.contains(MonsterType.trap) &&
          rng.nextDouble() < LayoutRules.mediumPathTrapProb) {
        final onPath = _onPath(free, pathSet);
        if (onPath.isNotEmpty) {
          remaining -= _placeChecked(map, MonsterType.trap, onPath[rng.nextInt(onPath.length)]);
          continue;
        }
      }
      final type = affordable[rng.nextInt(affordable.length)];
      remaining -= _placeChecked(map, type, free[rng.nextInt(free.length)]);
    }
    return map;
  }

  // ── hard ────────────────────────────────────────────

  GridMap _generateHard(Random rng) {
    final map = GridMap();
    var remaining = sampleBudget(Tier.hard, rng);
    final pathSet = map.shortestPath().toSet();

    // 1. 왕좌 인접 오크 강제 (예산 ≥ 20 > 오크 6 이므로 항상 가능). 거리 1 칸이 비어 있으면 그쪽 우선.
    for (var i = 0; i < LayoutRules.hardForcedOrcs; i++) {
      if (MonsterType.orc.spec.cost > remaining) break;
      final near = _nearThrone(_freeCells(map));
      if (near.isEmpty) break;
      final gate = near.where((p) => p.manhattan(Pos.throne) == 1).toList();
      final pool = gate.isNotEmpty ? gate : near;
      remaining -= _placeChecked(map, MonsterType.orc, pool[rng.nextInt(pool.length)]);
    }

    // 2. 최단경로 위(없으면 근처, 그것도 없으면 아무 칸) 함정 강제.
    for (var i = 0; i < LayoutRules.hardForcedTraps; i++) {
      if (MonsterType.trap.spec.cost > remaining) break;
      final free = _freeCells(map);
      if (free.isEmpty) break;
      var pool = _onPath(free, pathSet);
      if (pool.isEmpty) pool = _nearPath(free, pathSet);
      if (pool.isEmpty) pool = free;
      remaining -= _placeChecked(map, MonsterType.trap, pool[rng.nextInt(pool.length)]);
    }

    // 3. 남은 예산: 고블린 위주 가중 랜덤 종류, 랜덤 칸.
    while (true) {
      final affordable = _affordable(MonsterType.values, remaining);
      if (affordable.isEmpty) break;
      final free = _freeCells(map);
      if (free.isEmpty) break;
      final type = _weightedPick(rng, LayoutRules.hardWeights, affordable);
      remaining -= _placeChecked(map, type, free[rng.nextInt(free.length)]);
    }
    return map;
  }

  // ── adversarial ─────────────────────────────────────

  /// adversarial 절차를 중간 결과까지 노출한다 (generate(Tier.adversarial)와 rng 소비가 동일).
  ///
  /// hard 후보 Balance.adversarialCandidates개를 만들고, 각 후보를 [adversary](없으면 GreedyPolicy)와
  /// [hero](없으면 HeroStats.forWave(6))로 Balance.adversarialRollouts회 롤아웃해 용사 평균 리턴이
  /// 가장 낮은 후보를 고른다.
  AdversarialSearch searchAdversarial(Random rng, {HeroPolicy? adversary, HeroStats? hero}) {
    final policy = adversary ?? const GreedyPolicy();
    final stats = hero ?? HeroStats.forWave(LayoutRules.adversarialHeroWave);
    final candidates = List<GridMap>.generate(
      Balance.adversarialCandidates,
      (_) => _generateHard(rng),
    );
    final avgReturns = <double>[];
    var bestIndex = 0;
    for (var i = 0; i < candidates.length; i++) {
      var total = 0.0;
      for (var r = 0; r < Balance.adversarialRollouts; r++) {
        total += rolloutReturn(candidates[i], stats, policy, rng);
      }
      final avg = total / Balance.adversarialRollouts;
      avgReturns.add(avg);
      if (avg < avgReturns[bestIndex]) bestIndex = i;
    }
    return AdversarialSearch(candidates, avgReturns, bestIndex);
  }

  /// [map] 위에서 [policy]로 한 에피소드를 끝까지(최대 Balance.maxSteps) 돌린 용사 보상 합.
  /// GameSim이 map을 clone하므로 [map]은 변하지 않는다.
  static double rolloutReturn(GridMap map, HeroStats hero, HeroPolicy policy, Random rng) {
    final sim = GameSim(map, hero);
    var total = 0.0;
    for (var i = 0; i < Balance.maxSteps && !sim.done; i++) {
      total += sim.step(policy.act(sim, rng)).reward;
    }
    return total;
  }

  // ── fixed / demo / eval ─────────────────────────────

  /// 사람이 만든 6종: 입구 앞 벽, 왕좌 포위, 함정 복도, 슬라임 밭, 좌우 분기 함정, 오크 2연속.
  /// 매 호출마다 새 인스턴스를 만든다 (호출자가 자유롭게 변형 가능).
  static List<GridMap> fixedLayouts() => [
        _entranceWall(),
        _throneSiege(),
        _trapCorridor(),
        _slimeField(),
        _forkTraps(),
        _doubleOrc(),
      ];

  /// 입구 앞 벽: 입구에서 나오는 두 통로((1,0)→(2,0), (0,1)→(0,2))를 고블린 줄로 막는다.
  static GridMap _entranceWall() => _build([
        (MonsterType.goblin, const Pos(2, 0)),
        (MonsterType.goblin, const Pos(2, 1)),
        (MonsterType.goblin, const Pos(2, 2)),
        (MonsterType.goblin, const Pos(1, 2)),
        (MonsterType.goblin, const Pos(0, 2)),
      ]);

  /// 왕좌 포위: 왕좌로 들어가는 두 문(5,6)·(6,5)에 오크, 그 바깥 (4,6)·(6,4)에 고블린.
  static GridMap _throneSiege() => _build([
        (MonsterType.orc, const Pos(5, 6)),
        (MonsterType.orc, const Pos(6, 5)),
        (MonsterType.goblin, const Pos(4, 6)),
        (MonsterType.goblin, const Pos(6, 4)),
      ]);

  /// 함정 복도: 입구→왕좌 최단경로 한가운데 연속 5칸에 함정.
  static GridMap _trapCorridor() {
    final map = GridMap();
    final onPath = _placeablePath(map);
    for (final p in _middle(onPath, LayoutRules.corridorTraps)) {
      _placeChecked(map, MonsterType.trap, p);
    }
    return map;
  }

  /// 슬라임 밭: 맵 전역에 슬라임 12개 산개 (값싼 시간 끌기).
  static GridMap _slimeField() => _build([
        for (final p in const [
          Pos(3, 0), Pos(5, 0),
          Pos(6, 1),
          Pos(0, 2), Pos(2, 2), Pos(4, 2), Pos(6, 2),
          Pos(1, 4), Pos(3, 4), Pos(5, 4),
          Pos(2, 6), Pos(4, 6),
        ])
          (MonsterType.slime, p),
      ]);

  /// 좌우 분기 함정: 입구의 오른쪽 갈래((2,0) 쪽)는 함정, 아래 갈래((0,2) 쪽)는 고블린.
  static GridMap _forkTraps() => _build([
        (MonsterType.trap, const Pos(2, 0)),
        (MonsterType.trap, const Pos(3, 0)),
        (MonsterType.trap, const Pos(2, 1)),
        (MonsterType.goblin, const Pos(0, 2)),
        (MonsterType.goblin, const Pos(0, 3)),
        (MonsterType.goblin, const Pos(1, 2)),
      ]);

  /// 오크 2연속: 왕좌 앞 일직선 (6,4)→(6,5)에 오크 2.
  static GridMap _doubleOrc() => _build([
        (MonsterType.orc, const Pos(6, 4)),
        (MonsterType.orc, const Pos(6, 5)),
      ]);

  /// 데모: 함정 지름길 + 슬라임 밭 + 왕좌 앞 오크. 앱의 "데모 배치" 버튼과 PPT 시연용.
  ///
  /// - 지름길: 최단경로 한가운데 3칸 함정 (직진하면 45 피해).
  /// - 왕좌 앞 오크: 최단경로가 왕좌로 들어가는 마지막 칸.
  /// - 슬라임 밭: 최단경로 밖 중앙 열린 칸 6개 (우회로를 택하면 슬라임과 싸운다).
  /// 총 비용 3·2 + 6 + 6·1 = 18.
  static GridMap demoLayout() {
    final map = GridMap();
    final onPath = _placeablePath(map);
    for (final p in _middle(onPath, LayoutRules.demoTraps)) {
      _placeChecked(map, MonsterType.trap, p);
    }
    _placeChecked(map, MonsterType.orc, onPath.last);

    const fieldPool = [
      Pos(2, 2), Pos(3, 2), Pos(4, 2),
      Pos(2, 4), Pos(3, 4), Pos(4, 4),
      Pos(2, 3), Pos(4, 3),
      Pos(1, 2), Pos(5, 2), Pos(1, 4), Pos(5, 4),
      Pos(2, 1), Pos(4, 1), Pos(2, 5), Pos(4, 5),
    ];
    final pathSet = onPath.toSet();
    var slimes = 0;
    for (final p in fieldPool) {
      if (slimes >= LayoutRules.demoSlimes) break;
      if (pathSet.contains(p) || map.monsters.containsKey(p)) continue;
      _placeChecked(map, MonsterType.slime, p);
      slimes++;
    }
    return map;
  }

  /// 고정 평가셋: easy/medium/hard 각 size/3, 웨이브 스탯 1·6·11 순환. 같은 seed면 항상 동일.
  static List<(GridMap, HeroStats)> evalSet({int seed = 42, int size = 300}) {
    final rng = Random(seed);
    final gen = LayoutGenerator();
    final waves = LayoutRules.evalWaves();
    const tiers = [Tier.easy, Tier.medium, Tier.hard];
    final perTier = size ~/ tiers.length;
    final out = <(GridMap, HeroStats)>[];
    for (final tier in tiers) {
      for (var i = 0; i < perTier; i++) {
        final map = gen.generate(tier, rng);
        out.add((map, HeroStats.forWave(waves[out.length % waves.length])));
      }
    }
    return out;
  }

  // ── 내부 도우미 ─────────────────────────────────────

  /// place()가 실패하면 예외. 성공 시 비용 반환.
  static int _placeChecked(GridMap map, MonsterType t, Pos p) {
    if (!map.place(t, p)) {
      throw StateError('배치 실패: ${t.korean} @ $p');
    }
    return t.spec.cost;
  }

  static GridMap _build(List<(MonsterType, Pos)> items) {
    final map = GridMap();
    for (final (t, p) in items) {
      _placeChecked(map, t, p);
    }
    return map;
  }

  static List<MonsterType> _affordable(Iterable<MonsterType> kinds, int remaining) =>
      kinds.where((t) => t.spec.cost <= remaining).toList();

  /// 배치 가능하고 비어 있는 칸 (행 우선).
  static List<Pos> _freeCells(GridMap map) =>
      GridMap.placeableCells().where((p) => !map.monsters.containsKey(p)).toList();

  static List<Pos> _nearThrone(List<Pos> cells) => cells.where((p) {
        final d = p.manhattan(Pos.throne);
        return d >= 1 && d <= LayoutRules.nearThroneMaxDistance;
      }).toList();

  static List<Pos> _onPath(List<Pos> cells, Set<Pos> pathSet) =>
      cells.where(pathSet.contains).toList();

  static List<Pos> _nearPath(List<Pos> cells, Set<Pos> pathSet) =>
      cells.where((p) => pathSet.any((q) => q.manhattan(p) == 1)).toList();

  /// 최단경로 중 배치 가능한 칸 (경로 순서 유지).
  static List<Pos> _placeablePath(GridMap map) {
    final placeable = GridMap.placeableCells().toSet();
    return map.shortestPath().where(placeable.contains).toList();
  }

  /// 리스트 한가운데 [n]개 (리스트가 짧으면 전부).
  static List<Pos> _middle(List<Pos> cells, int n) {
    if (cells.length <= n) return List<Pos>.of(cells);
    final start = (cells.length - n) ~/ 2;
    return cells.sublist(start, start + n);
  }

  static MonsterType _weightedPick(
    Random rng,
    Map<MonsterType, double> weights,
    List<MonsterType> allowed,
  ) {
    var total = 0.0;
    for (final t in allowed) {
      total += weights[t] ?? 0;
    }
    if (total <= 0) return allowed[rng.nextInt(allowed.length)];
    var r = rng.nextDouble() * total;
    for (final t in allowed) {
      r -= weights[t] ?? 0;
      if (r < 0) return t;
    }
    return allowed.last;
  }
}
