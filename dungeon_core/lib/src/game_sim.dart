import 'grid_map.dart';
import 'models.dart';

/// 턴제 시뮬레이터. 난수 없음(결정론). 같은 맵 + 같은 행동열 = 같은 결과.
///
/// 규칙 (PLAN.md §3, §5.3):
/// - 이동 행동: 목적지가 빈칸/왕좌면 이동(trail 기록, lastMove 갱신). 마물 칸이면 그 마물을 1회 공격(용사 ATK),
///   마물이 살아있으면 즉시 반격(마물 ATK). 용사는 제자리. 마물 사망 시 칸이 비고 kills++, 보상 rKill.
///   벽/맵 밖이면 제자리(bumpedWall, rWallBump). 함정 칸 진입 시 이동은 성공하고 trapDamage 피해 + rTrapHit(+HP 손실 벌점).
/// - potion: 물약 있으면 HP +potionHeal(최대 maxHp), HP 비율 > potionWasteHpRatio였으면 rPotionWasteHigh 추가.
///   물약 없으면 무효(턴 소모) + rPotionNone.
/// - 직전 이동의 정반대 방향으로 "실제 이동"하면 rReverseMove (공격/물약은 lastMove를 갱신하지 않음).
/// - 매 턴 rStep. HP 손실 1당 rHpLossPerPoint. 종료: 왕좌 도달 rThrone, 사망 rDeath, steps >= maxSteps 이면 gaveUp rTimeout.
/// - 함정은 hp 0이며 공격 대상이 아니고 영구.
class GameSim {
  /// [map]은 내부에서 clone한다. 웨이브가 끝나면 살아남은 마물은 호출자가 [map]에서 HP 회복시켜 재사용.
  GameSim(GridMap map, HeroStats hero) {
    throw UnimplementedError('M1');
  }

  StepResult step(HeroAction a) => throw UnimplementedError('M1');

  bool get done => throw UnimplementedError('M1');
  Outcome get outcome => throw UnimplementedError('M1');

  Pos get heroPos => throw UnimplementedError('M1');
  int get hp => throw UnimplementedError('M1');
  int get maxHp => throw UnimplementedError('M1');
  int get atk => throw UnimplementedError('M1');
  int get potions => throw UnimplementedError('M1');
  int get steps => throw UnimplementedError('M1');
  HeroAction? get lastMove => throw UnimplementedError('M1');

  int get trapHits => throw UnimplementedError('M1');
  int get kills => throw UnimplementedError('M1');
  int get hpLost => throw UnimplementedError('M1');
  int get potionsUsed => throw UnimplementedError('M1');

  /// 방문 순서 (입구 포함, 공격으로 제자리인 턴은 추가하지 않음).
  List<Pos> get trail => throw UnimplementedError('M1');

  /// 현재 상태의 맵 (죽은 마물은 제거됨, 살아있는 마물은 현재 HP).
  GridMap get map => throw UnimplementedError('M1');

  GameSim clone() => throw UnimplementedError('M1');
}
