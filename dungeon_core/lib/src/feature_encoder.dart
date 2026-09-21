import 'game_sim.dart';
import 'models.dart';

/// 인접 칸 분류. 인덱스가 곧 인코딩 값이다 (0..5). 순서 변경 금지.
enum AdjKind { wall, empty, weakMonster, strongMonster, trap, throne }

/// 자기중심 상태 특징 (PLAN.md §5.1). 절대 좌표 없음.
class StateFeatures {
  /// sign(왕좌.x − 용사.x), sign(왕좌.y − 용사.y) ∈ {-1, 0, 1}
  final int goalDx, goalDy;

  /// 상/하/좌/우 순서 (HeroAction.up, down, left, right 인덱스와 동일).
  final List<AdjKind> adj;

  /// 0: ≤25%, 1: ≤50%, 2: ≤75%, 3: >75%
  final int hpBucket;
  final bool hasPotion;

  /// 직전 "실제 이동" 방향. 없으면 null. (공격/물약/벽 충돌은 갱신하지 않음)
  final HeroAction? lastMove;

  const StateFeatures({
    required this.goalDx,
    required this.goalDy,
    required this.adj,
    required this.hpBucket,
    required this.hasPotion,
    required this.lastMove,
  });
}

/// 상태 인덱스 = ((((goalDir*1296 + adj)*4 + hp)*2 + potion)*5 + lastMove)
/// - goalDir = (goalDx+1)*3 + (goalDy+1)           ∈ 0..8
/// - adj     = up*216 + down*36 + left*6 + right    ∈ 0..1295 (AdjKind.index)
/// - lastMove: none=0, up=1, down=2, left=3, right=4
class FeatureEncoder {
  FeatureEncoder._();

  static const int goalDirCount = 9, adjCount = 1296, hpBucketCount = 4, potionCount = 2, lastMoveCount = 5;
  static const int stateCount = goalDirCount * adjCount * hpBucketCount * potionCount * lastMoveCount; // 466560
  static const int actionCount = 5;

  static StateFeatures features(GameSim s) => throw UnimplementedError('M1');

  /// 0 <= idx < stateCount
  static int encode(GameSim s) => indexOf(features(s));

  static int indexOf(StateFeatures f) => throw UnimplementedError('M1');

  /// 두뇌 패널·디버그용 역변환.
  static StateFeatures decode(int index) => throw UnimplementedError('M1');

  /// 2턴 안에 죽일 수 있으면 약함. 용사가 성장해도 같은 Q-테이블이 유효하도록 상대 강도로 정의.
  static bool isWeak(Monster m, int heroAtk) => m.hp <= 2 * heroAtk;
}
