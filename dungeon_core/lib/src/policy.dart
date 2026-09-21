import 'dart:math';

import 'balance.dart';
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

  @override
  HeroAction act(GameSim sim, Random rng) => throw UnimplementedError('M1');
}

/// ε-greedy Q-테이블 정책. 플레이/평가 ε = Balance.epsPlay (모든 단계 동일).
class QTablePolicy implements HeroPolicy {
  QTablePolicy(this.table, {this.epsilon = Balance.epsPlay, this.name = 'qtable'});

  final QTable table;
  final double epsilon;

  @override
  final String name;

  @override
  HeroAction act(GameSim sim, Random rng) => throw UnimplementedError('M1');

  /// 두뇌 패널용: 현재 상태의 5행동 Q값 (up, down, left, right, potion 순).
  List<double> qValues(GameSim sim) => throw UnimplementedError('M1');
}
