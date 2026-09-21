import 'grid_map.dart';
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

  /// 각 (맵, 용사) 조합을 정책으로 1회 플레이 (ε은 정책 내부값, rng seed 고정). "승"은 용사가 왕좌 도달.
  static EvalStats evaluate(HeroPolicy p, List<(GridMap, HeroStats)> set, {int seed = 1}) =>
      throw UnimplementedError('M3');

  /// 데모 레이아웃(LayoutGenerator.demoLayout)에서 용사가 왕좌에 도달하면 true.
  static bool runDemo(HeroPolicy p, {int wave = 6, int seed = 1}) => throw UnimplementedError('M3');

  /// 단계 선정. 반환: {'stage1': ep, 'stage2': ep, 'stage3': ep, 'rule': 0(threshold) | 1(quantile)}
  /// - stage1: 승률 ≥ stage1WinRate 첫 체크포인트, stage2: ≥ stage2WinRate 첫 체크포인트, stage3: 최고 승률.
  /// - 문턱 미달이면 분위수 폴백(stage1Quantile/stage2Quantile 지점, stage3 최고)과 rule=1.
  /// - 항상 stage1.ep < stage2.ep < stage3.ep 가 되도록 보정(불가능하면 가장 가까운 순서 유지 조합).
  static Map<String, int> selectStages(List<(int, EvalStats)> ckpts) => throw UnimplementedError('M3');
}
