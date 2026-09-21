import 'dart:math';

import 'balance.dart';
import 'feature_encoder.dart';
import 'game_sim.dart';
import 'models.dart';
import 'qtable.dart';

/// 용사 정책. 앱과 학습기가 같은 인터페이스를 쓴다.
abstract class HeroPolicy {
  HeroAction act(GameSim sim, Random rng);
  String get name;
}

/// 왕좌 방향 직진 스텁. 막히면(벽/맵 밖) 다른 축으로. 마물은 그냥 공격(직진 돌격형).
/// M5 앱 셸이 M1/M3 완료 전에 쓰는 대역이자, 인코더/시뮬 테스트의 기준 정책.
class GreedyPolicy implements HeroPolicy {
  const GreedyPolicy();

  @override
  String get name => 'greedy';

  /// 물약을 마시는 HP 비율 문턱 (정책 휴리스틱, 게임 규칙 아님). 인코더의 최저 hpBucket(≤25%)과 일치.
  static const double potionHpRatio = 0.25;

  /// 왕좌 방향(|dx|,|dy| 중 큰 축 우선, 같으면 x 우선)으로 이동. 그 축이 벽/맵 밖이면 다른 축.
  /// 둘 다 막히면 [rng]로 통과 가능한 아무 방향. 마물 칸은 그냥 진입 시도(=공격).
  /// HP ≤ [potionHpRatio]이고 물약이 있으면 물약. rng는 막힌 경우에만 쓰므로 그 외엔 결정론.
  @override
  HeroAction act(GameSim sim, Random rng) {
    if (sim.potions > 0 && sim.hp <= sim.maxHp * potionHpRatio) {
      return HeroAction.potion;
    }
    final pos = sim.heroPos;
    final dx = Pos.throne.x - pos.x;
    final dy = Pos.throne.y - pos.y;
    final HeroAction? xAct = dx > 0
        ? HeroAction.right
        : dx < 0
            ? HeroAction.left
            : null;
    final HeroAction? yAct = dy > 0
        ? HeroAction.down
        : dy < 0
            ? HeroAction.up
            : null;
    final order = <HeroAction>[];
    if (dx.abs() >= dy.abs()) {
      if (xAct != null) order.add(xAct);
      if (yAct != null) order.add(yAct);
    } else {
      if (yAct != null) order.add(yAct);
      if (xAct != null) order.add(xAct);
    }
    for (final a in order) {
      if (_passable(sim, pos.move(a))) return a;
    }
    // 둘 다 막힘: 통과 가능한 방향 중 무작위 (기둥 맵엔 항상 하나 이상 존재).
    final open = [for (final a in moveActions) if (_passable(sim, pos.move(a))) a];
    if (open.isEmpty) return moveActions[rng.nextInt(moveActions.length)];
    return open[rng.nextInt(open.length)];
  }

  static bool _passable(GameSim sim, Pos p) => p.inBounds && !sim.map.isPillar(p);
}

/// ε-greedy Q-테이블 정책. 플레이/평가 ε = Balance.epsPlay (모든 단계 동일).
class QTablePolicy implements HeroPolicy {
  QTablePolicy(this.table, {this.epsilon = Balance.epsPlay, this.name = 'qtable'});

  final QTable table;
  final double epsilon;

  @override
  final String name;

  /// ε 확률로 5행동 중 균등 랜덤, 아니면 현재 상태의 argmax(동점은 rng).
  /// ε ≤ 0 이면 rng.nextDouble()을 소비하지 않아 `table.argmax(encode(sim), rng)`와 정확히 같다.
  @override
  HeroAction act(GameSim sim, Random rng) {
    if (epsilon > 0 && rng.nextDouble() < epsilon) {
      return HeroAction.values[rng.nextInt(HeroAction.values.length)];
    }
    return HeroAction.values[table.argmax(FeatureEncoder.encode(sim), rng)];
  }

  /// 두뇌 패널용: 현재 상태의 5행동 Q값 (up, down, left, right, potion 순).
  List<double> qValues(GameSim sim) => table.row(FeatureEncoder.encode(sim));
}
