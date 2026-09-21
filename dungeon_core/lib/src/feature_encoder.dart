import 'game_sim.dart';
import 'grid_map.dart';
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

  @override
  String toString() =>
      'StateFeatures(goal=($goalDx,$goalDy) adj=${adj.map((k) => k.name).join('/')} '
      'hp=$hpBucket potion=$hasPotion last=${lastMove?.name ?? 'none'})';
}

/// 상태 인덱스 = ((((goalDir*1296 + adj)*4 + hp)*2 + potion)*5 + lastMove)
/// - goalDir = (goalDx+1)*3 + (goalDy+1)           ∈ 0..8
/// - adj     = up*216 + down*36 + left*6 + right    ∈ 0..1295 (AdjKind.index)
/// - lastMove: none=0, up=1, down=2, left=3, right=4
class FeatureEncoder {
  FeatureEncoder._();

  /// AdjKind 가짓수 (= AdjKind.values.length, 상수식이 필요해 리터럴로 둔다).
  static const int adjKindCount = 6;
  static const int goalDirCount = 9,
      adjCount = adjKindCount * adjKindCount * adjKindCount * adjKindCount, // 1296
      hpBucketCount = 4,
      potionCount = 2,
      lastMoveCount = 5;
  static const int stateCount = goalDirCount * adjCount * hpBucketCount * potionCount * lastMoveCount; // 466560
  static const int actionCount = 5;

  /// hpBucket 경계 (hp/maxHp 비율, 이하). 넘으면 마지막 버킷(3).
  static const List<double> hpBucketBounds = [0.25, 0.5, 0.75];

  // 인접 칸 혼합 진법 자리수: up*216 + down*36 + left*6 + right
  static const int _adjRadixUp = adjKindCount * adjKindCount * adjKindCount; // 216
  static const int _adjRadixDown = adjKindCount * adjKindCount; // 36
  static const int _adjRadixLeft = adjKindCount; // 6
  static const int _goalAxisCount = 3;

  /// 시뮬레이터 상태 → 특징. GameSim의 공개 getter만 사용한다.
  static StateFeatures features(GameSim s) {
    final hero = s.heroPos;
    final map = s.map;
    final atk = s.atk;
    final adj = List<AdjKind>.filled(moveActions.length, AdjKind.wall, growable: false);
    for (var i = 0; i < moveActions.length; i++) {
      adj[i] = AdjKind.values[adjKindIndexAt(map, hero.move(moveActions[i]), atk)];
    }
    return StateFeatures(
      goalDx: (Pos.throne.x - hero.x).sign,
      goalDy: (Pos.throne.y - hero.y).sign,
      adj: adj,
      hpBucket: hpBucketOf(s.hp, s.maxHp),
      hasPotion: s.potions > 0,
      lastMove: _normalizeLastMove(s.lastMove),
    );
  }

  /// 0 <= idx < stateCount. features()를 거치지 않는 빠른 경로 (학습 루프에서 매 스텝 호출).
  static int encode(GameSim s) {
    final hero = s.heroPos;
    final map = s.map;
    final atk = s.atk;
    final goalDir = _goalDirIndex((Pos.throne.x - hero.x).sign, (Pos.throne.y - hero.y).sign);
    final adj = adjKindIndexAt(map, hero.move(HeroAction.up), atk) * _adjRadixUp +
        adjKindIndexAt(map, hero.move(HeroAction.down), atk) * _adjRadixDown +
        adjKindIndexAt(map, hero.move(HeroAction.left), atk) * _adjRadixLeft +
        adjKindIndexAt(map, hero.move(HeroAction.right), atk);
    return _compose(
      goalDir,
      adj,
      hpBucketOf(s.hp, s.maxHp),
      s.potions > 0 ? 1 : 0,
      _lastMoveIndex(_normalizeLastMove(s.lastMove)),
    );
  }

  /// 특징 → 인덱스. 범위를 벗어난 특징은 [ArgumentError].
  static int indexOf(StateFeatures f) {
    if (f.goalDx < -1 || f.goalDx > 1) {
      throw ArgumentError.value(f.goalDx, 'goalDx', '-1..1 이어야 함');
    }
    if (f.goalDy < -1 || f.goalDy > 1) {
      throw ArgumentError.value(f.goalDy, 'goalDy', '-1..1 이어야 함');
    }
    if (f.adj.length != moveActions.length) {
      throw ArgumentError.value(f.adj.length, 'adj.length', '상/하/좌/우 4개여야 함');
    }
    if (f.hpBucket < 0 || f.hpBucket >= hpBucketCount) {
      throw ArgumentError.value(f.hpBucket, 'hpBucket', '0..${hpBucketCount - 1} 이어야 함');
    }
    if (f.lastMove == HeroAction.potion) {
      throw ArgumentError.value(f.lastMove, 'lastMove', '이동 행동 또는 null 이어야 함');
    }
    final adj = f.adj[0].index * _adjRadixUp +
        f.adj[1].index * _adjRadixDown +
        f.adj[2].index * _adjRadixLeft +
        f.adj[3].index;
    return _compose(
      _goalDirIndex(f.goalDx, f.goalDy),
      adj,
      f.hpBucket,
      f.hasPotion ? 1 : 0,
      _lastMoveIndex(f.lastMove),
    );
  }

  /// 두뇌 패널·디버그용 역변환. 범위를 벗어나면 [RangeError].
  static StateFeatures decode(int index) {
    if (index < 0 || index >= stateCount) {
      throw RangeError.range(index, 0, stateCount - 1, 'index');
    }
    var r = index;
    final lastMove = r % lastMoveCount;
    r ~/= lastMoveCount;
    final potion = r % potionCount;
    r ~/= potionCount;
    final hpBucket = r % hpBucketCount;
    r ~/= hpBucketCount;
    final adj = r % adjCount;
    r ~/= adjCount;
    final goalDir = r; // 0..8
    return StateFeatures(
      goalDx: goalDir ~/ _goalAxisCount - 1,
      goalDy: goalDir % _goalAxisCount - 1,
      adj: List<AdjKind>.unmodifiable([
        AdjKind.values[adj ~/ _adjRadixUp],
        AdjKind.values[(adj ~/ _adjRadixDown) % adjKindCount],
        AdjKind.values[(adj ~/ _adjRadixLeft) % adjKindCount],
        AdjKind.values[adj % adjKindCount],
      ]),
      hpBucket: hpBucket,
      hasPotion: potion == 1,
      lastMove: lastMove == 0 ? null : moveActions[lastMove - 1],
    );
  }

  /// 2턴 안에 죽일 수 있으면 약함. 용사가 성장해도 같은 Q-테이블이 유효하도록 상대 강도로 정의.
  static bool isWeak(Monster m, int heroAtk) => m.hp <= 2 * heroAtk;

  /// 인접 칸 [p]의 분류 인덱스(AdjKind.index).
  /// 맵 밖·기둥 → wall, 왕좌 → throne, 함정 → trap, 마물 → weak/strong, 그 외 empty.
  static int adjKindIndexAt(GridMap map, Pos p, int heroAtk) {
    if (!p.inBounds || map.isPillar(p)) return AdjKind.wall.index;
    if (map.isThrone(p)) return AdjKind.throne.index;
    final m = map.monsters[p];
    if (m == null) return AdjKind.empty.index;
    if (m.isTrap) return AdjKind.trap.index;
    return isWeak(m, heroAtk) ? AdjKind.weakMonster.index : AdjKind.strongMonster.index;
  }

  /// 인접 칸 [p]의 분류.
  static AdjKind adjKindAt(GridMap map, Pos p, int heroAtk) => AdjKind.values[adjKindIndexAt(map, p, heroAtk)];

  /// HP 비율 버킷. hp/maxHp ≤ 0.25 → 0, ≤ 0.5 → 1, ≤ 0.75 → 2, 그 외 3 ([hpBucketBounds]).
  /// 부동소수 오차 없이 정수 곱셈으로 같은 경계를 판정한다. maxHp ≤ 0 이면 0.
  static int hpBucketOf(int hp, int maxHp) {
    if (maxHp <= 0) return 0;
    if (hp * 4 <= maxHp) return 0; // ≤ 25%
    if (hp * 2 <= maxHp) return 1; // ≤ 50%
    if (hp * 4 <= maxHp * 3) return 2; // ≤ 75%
    return hpBucketCount - 1;
  }

  static int _goalDirIndex(int dx, int dy) => (dx + 1) * _goalAxisCount + (dy + 1);

  /// none=0, up=1, down=2, left=3, right=4
  static int _lastMoveIndex(HeroAction? a) => a == null ? 0 : a.index + 1;

  /// GameSim 계약상 lastMove는 이동 행동만 오지만, 방어적으로 potion은 none으로 본다.
  static HeroAction? _normalizeLastMove(HeroAction? a) => a == HeroAction.potion ? null : a;

  static int _compose(int goalDir, int adj, int hpBucket, int potion, int lastMove) =>
      (((goalDir * adjCount + adj) * hpBucketCount + hpBucket) * potionCount + potion) * lastMoveCount + lastMove;
}
