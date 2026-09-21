import 'dart:math';

import 'grid_map.dart';
import 'models.dart';
import 'policy.dart';

/// 배치 봇(마왕 봇) 난이도. 학습하지 않는 규칙 기반 (PLAN.md §5.5).
enum Tier { easy, medium, hard, adversarial, fixed }

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

  /// [adversary]/[hero]는 Tier.adversarial에서만 사용 (없으면 GreedyPolicy / HeroStats.forWave(6)).
  GridMap generate(Tier tier, Random rng, {HeroPolicy? adversary, HeroStats? hero}) =>
      throw UnimplementedError('M2');

  /// 용사 웨이브 샘플: easy 1..6, medium 3..11, hard/adversarial/fixed 6..15 (균등).
  int sampleWave(Tier tier, Random rng) => throw UnimplementedError('M2');

  /// 사람이 만든 6종: 입구 앞 벽, 왕좌 포위, 함정 복도, 슬라임 밭, 좌우 분기 함정, 오크 2연속.
  static List<GridMap> fixedLayouts() => throw UnimplementedError('M2');

  /// 데모: 함정 지름길 + 슬라임 밭 + 왕좌 앞 오크. 앱의 "데모 배치" 버튼과 PPT 시연용.
  static GridMap demoLayout() => throw UnimplementedError('M2');

  /// 고정 평가셋: easy/medium/hard 각 size/3, 웨이브 스탯 1·6·11 순환. 같은 seed면 항상 동일.
  static List<(GridMap, HeroStats)> evalSet({int seed = 42, int size = 300}) =>
      throw UnimplementedError('M2');
}
