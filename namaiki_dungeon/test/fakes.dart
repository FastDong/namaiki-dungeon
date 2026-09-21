import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';

/// 테스트 더블. M1의 GridMap 구현이 스텁인 동안 컨트롤러 로직을 검증하기 위한 최소 맵.
/// 규칙 판정은 Balance 상수만 사용한다 (테스트 코드 안에서만 쓰인다).
class FakeGridMap extends GridMap {
  FakeGridMap();

  static final Set<Pos> _pillars = {
    for (final p in Balance.pillars) Pos(p[0], p[1]),
  };
  static final Set<Pos> _forbidden = {
    for (final p in Balance.forbiddenNearEntrance) Pos(p[0], p[1]),
  };

  @override
  bool isPillar(Pos p) => _pillars.contains(p);

  @override
  bool isPlaceable(Pos p) =>
      p.inBounds &&
      !isPillar(p) &&
      !isThrone(p) &&
      !isEntrance(p) &&
      !_forbidden.contains(p) &&
      !monsters.containsKey(p);

  @override
  bool place(MonsterType t, Pos p) {
    if (!isPlaceable(p)) return false;
    monsters[p] = Monster.fresh(t, p);
    return true;
  }

  @override
  bool remove(Pos p) => monsters.remove(p) != null;

  @override
  int get totalCost => monsters.values.fold(0, (s, m) => s + m.type.spec.cost);

  @override
  GridMap clone() {
    final c = FakeGridMap();
    for (final e in monsters.entries) {
      c.monsters[e.key] = e.value.clone();
    }
    return c;
  }

  @override
  Map<String, dynamic> toJson() => {
        'm': [for (final m in monsters.values) m.toJson()],
      };
}

/// 항상 같은 행동을 내는 정책 (정책 조회 검증용).
class FixedPolicy implements HeroPolicy {
  const FixedPolicy(this.name, this.action);

  @override
  final String name;
  final HeroAction action;

  @override
  HeroAction act(GameSim sim, Random rng) => action;
}
