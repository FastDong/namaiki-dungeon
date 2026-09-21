import 'dart:math';

import 'balance.dart';
import 'game_sim.dart';
import 'grid_map.dart';
import 'layout_generator.dart';
import 'models.dart';
import 'policy.dart';

/// 고정 평가셋 결과.
class EvalStats {
  final double winRate, avgSteps, trapHits, potionsUsed, kills;
  final int episodes;
  const EvalStats({
    required this.winRate,
    required this.avgSteps,
    required this.trapHits,
    required this.potionsUsed,
    required this.kills,
    required this.episodes,
  });

  Map<String, dynamic> toJson() => {
        'winRate': winRate,
        'avgSteps': avgSteps,
        'trapHits': trapHits,
        'potionsUsed': potionsUsed,
        'kills': kills,
        'episodes': episodes,
      };
  factory EvalStats.fromJson(Map<String, dynamic> j) => EvalStats(
        winRate: (j['winRate'] as num).toDouble(),
        avgSteps: (j['avgSteps'] as num).toDouble(),
        trapHits: (j['trapHits'] as num).toDouble(),
        potionsUsed: (j['potionsUsed'] as num).toDouble(),
        kills: (j['kills'] as num).toDouble(),
        episodes: j['episodes'] as int,
      );
}

/// 체크포인트 평가와 단계 선정 (PLAN.md §5.7).
class Evaluator {
  Evaluator._();

  /// selectStages 반환 맵의 'rule' 값.
  static const int ruleThreshold = 0, ruleQuantile = 1;

  /// 단계 이름 (stage 1..3).
  static const List<String> stageNames = ['풋내기 용사', '노련한 용사', '각성한 용사'];

  /// 각 (맵, 용사) 조합을 정책으로 1회 플레이 (ε은 정책 내부값, rng seed 고정). "승"은 용사가 왕좌 도달.
  static EvalStats evaluate(HeroPolicy p, List<(GridMap, HeroStats)> set, {int seed = 1}) {
    if (set.isEmpty) {
      return const EvalStats(winRate: 0, avgSteps: 0, trapHits: 0, potionsUsed: 0, kills: 0, episodes: 0);
    }
    final rng = Random(seed);
    var wins = 0, steps = 0, traps = 0, potions = 0, kills = 0;
    for (final (map, hero) in set) {
      final sim = GameSim(map, hero);
      _playOut(sim, p, rng);
      if (sim.outcome == Outcome.reachedThrone) wins++;
      steps += sim.steps;
      traps += sim.trapHits;
      potions += sim.potionsUsed;
      kills += sim.kills;
    }
    final n = set.length;
    return EvalStats(
      winRate: wins / n,
      avgSteps: steps / n,
      trapHits: traps / n,
      potionsUsed: potions / n,
      kills: kills / n,
      episodes: n,
    );
  }

  /// 데모 레이아웃(LayoutGenerator.demoLayout)에서 용사가 왕좌에 도달하면 true.
  static bool runDemo(HeroPolicy p, {int wave = 6, int seed = 1}) {
    final sim = GameSim(LayoutGenerator.demoLayout(), HeroStats.forWave(wave));
    _playOut(sim, p, Random(seed));
    return sim.outcome == Outcome.reachedThrone;
  }

  /// 단계 선정. 반환: {'stage1': ep, 'stage2': ep, 'stage3': ep, 'rule': 0(threshold) | 1(quantile)}
  /// - stage1: 승률 ≥ stage1WinRate 첫 체크포인트, stage2: ≥ stage2WinRate 첫 체크포인트, stage3: 최고 승률.
  /// - 문턱 미달이면 분위수 폴백(stage1Quantile/stage2Quantile 지점, stage3 최고)과 rule=1.
  /// - 항상 stage1.ep < stage2.ep < stage3.ep 가 되도록 보정(불가능하면 가장 가까운 순서 유지 조합).
  ///
  /// 보정 절차: stage3 = 최고 승률(동점이면 더 늦은 체크포인트; 체크포인트가 3개 이상이면 앞에 2개가 남도록
  /// 인덱스 ≥ 2 범위에서 최고), stage2 = stage3 이전 구간에서 문턱을 처음 넘는 것(없으면 분위수, rule=1),
  /// stage1 = stage2 이전 구간에서 문턱을 처음 넘는 것(없으면 분위수, rule=1).
  static Map<String, int> selectStages(List<(int, EvalStats)> ckpts) {
    if (ckpts.isEmpty) throw ArgumentError.value(ckpts, 'ckpts', '체크포인트가 없음');
    final sorted = List<(int, EvalStats)>.of(ckpts)..sort((a, b) => a.$1.compareTo(b.$1));
    final n = sorted.length;
    final lastEp = sorted.last.$1;

    // stage3: 최고 승률 (동점이면 더 늦은 것). n ≥ 3이면 앞에 두 자리를 남기기 위해 인덱스 ≥ 2에서 고른다.
    final minI3 = n >= 3 ? 2 : n - 1;
    var i3 = minI3;
    for (var i = minI3; i < n; i++) {
      if (sorted[i].$2.winRate >= sorted[i3].$2.winRate) i3 = i;
    }

    var fallback = false;

    // stage2: [1, i3-1] 구간에서 문턱을 처음 넘는 것.
    final hi2 = i3 - 1;
    final lo2 = n >= 2 ? 1 : 0;
    var i2 = _firstAtLeast(sorted, Balance.stage2WinRate, lo2, hi2);
    if (i2 < 0) {
      fallback = true;
      i2 = _clamp(_quantileIndex(sorted, Balance.stage2Quantile * lastEp), lo2, max(lo2, hi2));
    }

    // stage1: [0, i2-1] 구간에서 문턱을 처음 넘는 것.
    final hi1 = i2 - 1;
    var i1 = _firstAtLeast(sorted, Balance.stage1WinRate, 0, hi1);
    if (i1 < 0) {
      fallback = true;
      i1 = _clamp(_quantileIndex(sorted, Balance.stage1Quantile * lastEp), 0, max(0, hi1));
    }

    return {
      'stage1': sorted[i1].$1,
      'stage2': sorted[i2].$1,
      'stage3': sorted[i3].$1,
      'rule': fallback ? ruleQuantile : ruleThreshold,
    };
  }

  // ── 내부 ────────────────────────────────────────────

  static void _playOut(GameSim sim, HeroPolicy p, Random rng) {
    while (!sim.done) {
      sim.step(p.act(sim, rng));
    }
  }

  /// [lo, hi] 구간(양끝 포함)에서 승률 ≥ [threshold]인 첫 인덱스. 없으면 -1.
  static int _firstAtLeast(List<(int, EvalStats)> sorted, double threshold, int lo, int hi) {
    for (var i = max(lo, 0); i <= hi && i < sorted.length; i++) {
      if (sorted[i].$2.winRate >= threshold) return i;
    }
    return -1;
  }

  /// 에피소드 수가 [targetEpisode] 이상인 첫 체크포인트 인덱스 (없으면 마지막).
  static int _quantileIndex(List<(int, EvalStats)> sorted, double targetEpisode) {
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].$1 >= targetEpisode) return i;
    }
    return sorted.length - 1;
  }

  static int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
}
