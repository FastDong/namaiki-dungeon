import 'dart:convert';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

/// 배치 봇(M2) 검증. PLAN.md §5.5·§11 M2 완료 기준.
void main() {
  final gen = LayoutGenerator();
  const budgetTiers = [Tier.easy, Tier.medium, Tier.hard];
  const trials = 200;

  bool isPillar(Pos p) => Balance.pillars.any((c) => c[0] == p.x && c[1] == p.y);
  bool isNearEntrance(Pos p) =>
      Balance.forbiddenNearEntrance.any((c) => c[0] == p.x && c[1] == p.y);
  bool isForbidden(Pos p) =>
      !p.inBounds || p == Pos.entrance || p == Pos.throne || isPillar(p) || isNearEntrance(p);

  int count(GridMap m, MonsterType t) => m.monsters.values.where((x) => x.type == t).length;
  Iterable<Pos> cellsOf(GridMap m, MonsterType t) =>
      m.monsters.values.where((x) => x.type == t).map((x) => x.pos);
  String js(GridMap m) => jsonEncode(m.toJson());

  /// 금지 칸 위반 없음 + 키/좌표 일치 + 배치 가능 36칸 안 + totalCost가 스펙 합과 일치.
  void expectValid(GridMap map, String label) {
    final placeable = GridMap.placeableCells().toSet();
    var sum = 0;
    for (final e in map.monsters.entries) {
      expect(e.key, equals(e.value.pos), reason: '$label: 키와 pos 불일치 ${e.key}');
      expect(isForbidden(e.key), isFalse, reason: '$label: 금지 칸 위반 ${e.key}');
      expect(placeable.contains(e.key), isTrue, reason: '$label: 배치 가능 칸 밖 ${e.key}');
      sum += e.value.type.spec.cost;
    }
    expect(map.totalCost, equals(sum), reason: '$label: totalCost 불일치');
  }

  group('예산', () {
    for (final tier in budgetTiers) {
      test('${tier.name}: $trials회 생성 시 샘플된 예산을 절대 초과하지 않고 전부 소진한다', () {
        final (lo, hi) = LayoutGenerator.budgetRange(tier)!;
        for (var seed = 0; seed < trials; seed++) {
          // generate()가 rng에서 맨 처음 뽑는 값이 예산이므로 같은 시드로 미리 알 수 있다.
          final budget = LayoutGenerator.sampleBudget(tier, Random(seed));
          expect(budget, inInclusiveRange(lo, hi));
          final map = gen.generate(tier, Random(seed));
          expect(map.totalCost, lessThanOrEqualTo(budget), reason: '${tier.name} seed=$seed 예산 초과');
          // 슬라임(1)이 항상 살 수 있고 칸(36)이 예산(≤35)보다 많으므로 예산을 정확히 다 쓴다.
          expect(map.totalCost, equals(budget), reason: '${tier.name} seed=$seed 예산 미소진');
        }
      });
    }

    test('adversarial: hard 예산 범위 안', () {
      final (lo, hi) = LayoutGenerator.budgetRange(Tier.adversarial)!;
      for (var seed = 0; seed < 40; seed++) {
        final map = gen.generate(Tier.adversarial, Random(seed));
        expect(map.totalCost, inInclusiveRange(lo, hi), reason: 'seed=$seed');
      }
    });

    test('fixed: 비용 > 0, budgetRange는 null', () {
      expect(LayoutGenerator.budgetRange(Tier.fixed), isNull);
      expect(LayoutGenerator.sampleBudget(Tier.fixed, Random(1)), 0);
      for (var seed = 0; seed < 30; seed++) {
        expect(gen.generate(Tier.fixed, Random(seed)).totalCost, greaterThan(0));
      }
    });
  });

  group('금지 칸', () {
    for (final tier in Tier.values) {
      test('${tier.name}: 입구/왕좌/기둥/입구 인접 위반 없음', () {
        final n = tier == Tier.adversarial ? 40 : trials;
        for (var seed = 0; seed < n; seed++) {
          expectValid(gen.generate(tier, Random(seed)), '${tier.name} seed=$seed');
        }
      });
    }
  });

  group('tier 규칙', () {
    test('easy: 슬라임/함정만', () {
      for (var seed = 0; seed < trials; seed++) {
        final map = gen.generate(Tier.easy, Random(seed));
        expect(map.monsters, isNotEmpty);
        for (final m in map.monsters.values) {
          expect(m.type, anyOf(MonsterType.slime, MonsterType.trap), reason: 'seed=$seed');
        }
      }
    });

    test('easy: 왕좌 인접 칸이 우선 배치 대상으로 실제로 쓰인다 (전체 집계)', () {
      var near = 0, total = 0;
      for (var seed = 0; seed < trials; seed++) {
        final map = gen.generate(Tier.easy, Random(seed));
        for (final p in map.monsters.keys) {
          total++;
          if (p.manhattan(Pos.throne) <= LayoutRules.nearThroneMaxDistance) near++;
        }
      }
      // 균등 배치라면 4/36 ≈ 11%인데, 확률 0.5로 인접 칸을 우선하면 훨씬 높아야 한다.
      expect(near / total, greaterThan(0.2));
    });

    test('medium: 4종 모두 등장하고 함정이 최단경로 위에 자주 놓인다', () {
      final pathSet = GridMap().shortestPath().toSet();
      final seen = <MonsterType>{};
      var trapsOnPath = 0, traps = 0;
      for (var seed = 0; seed < trials; seed++) {
        final map = gen.generate(Tier.medium, Random(seed));
        for (final m in map.monsters.values) {
          seen.add(m.type);
          if (m.isTrap) {
            traps++;
            if (pathSet.contains(m.pos)) trapsOnPath++;
          }
        }
      }
      expect(seen, containsAll(MonsterType.values));
      expect(traps, greaterThan(0));
      expect(trapsOnPath / traps, greaterThan(0.5));
    });

    for (final tier in [Tier.hard, Tier.adversarial]) {
      test('${tier.name}: 오크 ≥1이 왕좌 인접, 함정 ≥3', () {
        final n = tier == Tier.adversarial ? 40 : trials;
        for (var seed = 0; seed < n; seed++) {
          final map = gen.generate(tier, Random(seed));
          final orcs = cellsOf(map, MonsterType.orc).toList();
          expect(orcs.length, greaterThanOrEqualTo(LayoutRules.hardForcedOrcs), reason: 'seed=$seed');
          expect(
            orcs.any((p) => p.manhattan(Pos.throne) <= LayoutRules.nearThroneMaxDistance),
            isTrue,
            reason: '${tier.name} seed=$seed: 왕좌 인접 오크 없음 $orcs',
          );
          expect(count(map, MonsterType.trap), greaterThanOrEqualTo(LayoutRules.hardForcedTraps),
              reason: 'seed=$seed');
        }
      });
    }

    test('hard: 첫 오크는 왕좌 바로 옆 문(거리 1)에 선다', () {
      for (var seed = 0; seed < trials; seed++) {
        final map = gen.generate(Tier.hard, Random(seed));
        expect(cellsOf(map, MonsterType.orc).any((p) => p.manhattan(Pos.throne) == 1), isTrue,
            reason: 'seed=$seed');
      }
    });

    test('hard: 고블린이 가장 많이 쓰인다 (전체 집계)', () {
      final tally = <MonsterType, int>{for (final t in MonsterType.values) t: 0};
      for (var seed = 0; seed < trials; seed++) {
        for (final m in gen.generate(Tier.hard, Random(seed)).monsters.values) {
          tally[m.type] = tally[m.type]! + 1;
        }
      }
      expect(tally[MonsterType.goblin], greaterThan(tally[MonsterType.slime]!));
      expect(tally[MonsterType.goblin], greaterThan(tally[MonsterType.orc]!));
    });
  });

  group('결정론', () {
    for (final tier in Tier.values) {
      test('${tier.name}: 같은 시드 → 같은 배치', () {
        for (var seed = 0; seed < 10; seed++) {
          expect(js(gen.generate(tier, Random(seed))), equals(js(gen.generate(tier, Random(seed)))));
        }
      });
    }
  });

  group('sampleWave', () {
    for (final tier in Tier.values) {
      test('${tier.name}: 범위 안 균등, 양끝 모두 등장', () {
        final (lo, hi) = LayoutGenerator.waveRange(tier);
        final rng = Random(7);
        final seen = <int>{};
        for (var i = 0; i < 2000; i++) {
          final w = gen.sampleWave(tier, rng);
          expect(w, inInclusiveRange(lo, hi));
          seen.add(w);
        }
        expect(seen, containsAll(List.generate(hi - lo + 1, (i) => lo + i)));
      });
    }

    test('범위 값: easy 1..6, medium 3..11, 나머지 6..15', () {
      expect(LayoutGenerator.waveRange(Tier.easy), (1, 6));
      expect(LayoutGenerator.waveRange(Tier.medium), (3, 11));
      expect(LayoutGenerator.waveRange(Tier.hard), (6, Balance.totalWaves));
      expect(LayoutGenerator.waveRange(Tier.adversarial), (6, Balance.totalWaves));
      expect(LayoutGenerator.waveRange(Tier.fixed), (6, Balance.totalWaves));
    });
  });

  group('fixedLayouts', () {
    test('6종 모두 비용 > 0, 유효, 서로 다름, 이름 수 일치', () {
      final all = LayoutGenerator.fixedLayouts();
      expect(all, hasLength(6));
      expect(LayoutGenerator.fixedLayoutNames, hasLength(6));
      final jsons = <String>{};
      for (var i = 0; i < all.length; i++) {
        expect(all[i].totalCost, greaterThan(0), reason: LayoutGenerator.fixedLayoutNames[i]);
        expectValid(all[i], LayoutGenerator.fixedLayoutNames[i]);
        jsons.add(js(all[i]));
      }
      expect(jsons, hasLength(6), reason: '중복 배치');
    });

    test('입구 앞 벽: 입구 근처 통로가 고블린으로 막힌다', () {
      final m = LayoutGenerator.fixedLayouts()[0];
      expect(count(m, MonsterType.goblin), greaterThanOrEqualTo(3));
      // 입구에서 나오는 두 통로의 첫 배치 가능 칸이 모두 막혀 있어야 한다.
      expect(m.monsters[const Pos(2, 0)]?.type, MonsterType.goblin);
      expect(m.monsters[const Pos(0, 2)]?.type, MonsterType.goblin);
      for (final p in m.monsters.keys) {
        expect(p.manhattan(Pos.entrance), lessThanOrEqualTo(4), reason: '$p 는 입구 근처가 아님');
      }
    });

    test('왕좌 포위: 왕좌 두 문에 오크, 인접 칸에 오크/고블린만', () {
      final m = LayoutGenerator.fixedLayouts()[1];
      expect(m.monsters[const Pos(5, 6)]?.type, MonsterType.orc);
      expect(m.monsters[const Pos(6, 5)]?.type, MonsterType.orc);
      expect(m.monsters.length, greaterThanOrEqualTo(3));
      for (final e in m.monsters.entries) {
        expect(e.key.manhattan(Pos.throne), lessThanOrEqualTo(LayoutRules.nearThroneMaxDistance));
        expect(e.value.type, anyOf(MonsterType.orc, MonsterType.goblin));
      }
    });

    test('함정 복도: 최단경로 위에 함정 5개, 함정만', () {
      final m = LayoutGenerator.fixedLayouts()[2];
      final pathSet = GridMap().shortestPath().toSet();
      expect(count(m, MonsterType.trap), LayoutRules.corridorTraps);
      expect(m.monsters.length, LayoutRules.corridorTraps);
      for (final p in m.monsters.keys) {
        expect(pathSet.contains(p), isTrue, reason: '$p 는 최단경로 밖');
      }
    });

    test('슬라임 밭: 슬라임 12개 산개, 슬라임만', () {
      final m = LayoutGenerator.fixedLayouts()[3];
      expect(count(m, MonsterType.slime), 12);
      expect(m.monsters.length, 12);
      // 산개: 상반부(y<3)와 하반부(y>3)에 모두 있고, 왼쪽(x<3)·오른쪽(x>3)에도 모두 있다.
      final ps = m.monsters.keys;
      expect(ps.any((p) => p.y < 3) && ps.any((p) => p.y > 3), isTrue);
      expect(ps.any((p) => p.x < 3) && ps.any((p) => p.x > 3), isTrue);
    });

    test('좌우 분기 함정: 한 갈래는 함정, 다른 갈래는 고블린', () {
      final m = LayoutGenerator.fixedLayouts()[4];
      final right = m.monsters[const Pos(2, 0)]?.type;
      final down = m.monsters[const Pos(0, 2)]?.type;
      expect({right, down}, equals({MonsterType.trap, MonsterType.goblin}));
      expect(count(m, MonsterType.trap), greaterThanOrEqualTo(2));
      expect(count(m, MonsterType.goblin), greaterThanOrEqualTo(2));
    });

    test('오크 2연속: 왕좌 앞 일직선에 오크 2', () {
      final m = LayoutGenerator.fixedLayouts()[5];
      final orcs = cellsOf(m, MonsterType.orc).toList();
      expect(orcs, hasLength(2));
      expect(m.monsters.length, 2);
      expect(orcs[0].manhattan(orcs[1]), 1, reason: '서로 붙어 있어야 함');
      expect(orcs.any((p) => p.manhattan(Pos.throne) == 1), isTrue, reason: '하나는 왕좌 바로 앞');
      expect(orcs[0].x == orcs[1].x || orcs[0].y == orcs[1].y, isTrue, reason: '일직선');
    });

    test('generate(fixed)는 6종 중 하나의 독립 복사본을 준다', () {
      final originals = LayoutGenerator.fixedLayouts().map(js).toSet();
      final seen = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        final m = gen.generate(Tier.fixed, Random(seed));
        final j = js(m);
        expect(originals.contains(j), isTrue, reason: 'seed=$seed: 고정 배치가 아님');
        seen.add(j);
        // 반환된 맵을 바꿔도 다음 호출에 영향이 없어야 한다.
        m.monsters.clear();
      }
      expect(seen, hasLength(6), reason: '60회 안에 6종이 모두 나와야 한다');
      expect(LayoutGenerator.fixedLayouts().map(js).toSet(), equals(originals));
    });
  });

  group('demoLayout', () {
    test('비용 ≤ 30, 함정 ≥2(최단경로 위), 오크 ≥1(왕좌 앞), 슬라임 ≥5', () {
      final m = LayoutGenerator.demoLayout();
      expectValid(m, 'demo');
      expect(m.totalCost, lessThanOrEqualTo(30));
      final pathSet = GridMap().shortestPath().toSet();
      final traps = cellsOf(m, MonsterType.trap).toList();
      expect(traps.length, greaterThanOrEqualTo(2));
      for (final p in traps) {
        expect(pathSet.contains(p), isTrue, reason: '함정 $p 는 최단경로 밖');
      }
      final orcs = cellsOf(m, MonsterType.orc).toList();
      expect(orcs.length, greaterThanOrEqualTo(1));
      expect(orcs.any((p) => p.manhattan(Pos.throne) == 1), isTrue);
      final slimes = cellsOf(m, MonsterType.slime).toList();
      expect(slimes.length, greaterThanOrEqualTo(5));
      for (final p in slimes) {
        expect(pathSet.contains(p), isFalse, reason: '슬라임 $p 는 우회로(최단경로 밖)에 있어야 함');
      }
    });

    test('두 번 호출해도 동일', () {
      expect(js(LayoutGenerator.demoLayout()), equals(js(LayoutGenerator.demoLayout())));
    });
  });

  group('evalSet', () {
    test('seed 42, size 300: 두 번 생성 시 toJson·스탯 전부 동일', () {
      final a = LayoutGenerator.evalSet();
      final b = LayoutGenerator.evalSet();
      expect(a, hasLength(300));
      expect(b, hasLength(300));
      for (var i = 0; i < a.length; i++) {
        expect(js(a[i].$1), equals(js(b[i].$1)), reason: 'index $i 배치 다름');
        expect(jsonEncode(a[i].$2.toJson()), equals(jsonEncode(b[i].$2.toJson())),
            reason: 'index $i 스탯 다름');
      }
    });

    test('구성: easy/medium/hard 각 100, 웨이브 1·6·11 순환, 모두 유효', () {
      final set = LayoutGenerator.evalSet();
      final waves = LayoutRules.evalWaves();
      expect(waves, [1, 6, 11]);
      for (var i = 0; i < set.length; i++) {
        final (map, hero) = set[i];
        final tier = i < 100
            ? Tier.easy
            : i < 200
                ? Tier.medium
                : Tier.hard;
        final (lo, hi) = LayoutGenerator.budgetRange(tier)!;
        expect(map.totalCost, inInclusiveRange(lo, hi), reason: 'index $i (${tier.name})');
        expectValid(map, 'eval $i');
        final w = waves[i % waves.length];
        expect(hero.maxHp, Balance.heroHp(w), reason: 'index $i 웨이브 $w');
        expect(hero.atk, Balance.heroAtk(w), reason: 'index $i 웨이브 $w');
        expect(hero.potions, Balance.potions);
      }
      // hard 구간은 hard 규칙(왕좌 인접 오크)을 만족해야 한다.
      for (var i = 200; i < 300; i++) {
        expect(
          cellsOf(set[i].$1, MonsterType.orc)
              .any((p) => p.manhattan(Pos.throne) <= LayoutRules.nearThroneMaxDistance),
          isTrue,
          reason: 'index $i',
        );
      }
    });

    test('다른 seed면 다른 셋', () {
      final a = LayoutGenerator.evalSet(seed: 1, size: 30);
      final b = LayoutGenerator.evalSet(seed: 2, size: 30);
      expect(a.map((e) => js(e.$1)).join(), isNot(equals(b.map((e) => js(e.$1)).join())));
    });
  });

  group('adversarial', () {
    /// 테스트 측 독립 롤아웃 (GreedyPolicy, 결정론적 시뮬).
    double rollout(GridMap map, HeroStats hero) {
      final sim = GameSim(map, hero);
      const policy = GreedyPolicy();
      final rng = Random(0);
      var total = 0.0;
      var guard = 0;
      while (!sim.done) {
        total += sim.step(policy.act(sim, rng)).reward;
        if (++guard > Balance.maxSteps + 1) fail('시뮬이 maxSteps 안에 끝나지 않음');
      }
      return total;
    }

    test('8후보 중 평균 리턴이 가장 낮은 후보를 고른다 (GreedyPolicy로 검증)', () {
      final hero = HeroStats.forWave(LayoutRules.adversarialHeroWave);
      for (var seed = 0; seed < 30; seed++) {
        final s = gen.searchAdversarial(Random(seed));
        expect(s.candidates, hasLength(Balance.adversarialCandidates));
        expect(s.avgReturns, hasLength(Balance.adversarialCandidates));
        // 1) 내부 일관성: bestIndex = argmin (동점이면 앞선 것).
        var argmin = 0;
        for (var i = 1; i < s.avgReturns.length; i++) {
          if (s.avgReturns[i] < s.avgReturns[argmin]) argmin = i;
        }
        expect(s.bestIndex, argmin, reason: 'seed=$seed ${s.avgReturns}');
        expect(identical(s.best, s.candidates[s.bestIndex]), isTrue);
        for (final r in s.avgReturns) {
          expect(r, greaterThanOrEqualTo(s.avgReturns[s.bestIndex]));
        }
        // 2) 외부 재계산: GreedyPolicy + 결정론 시뮬이므로 리턴이 정확히 재현된다.
        for (var i = 0; i < s.candidates.length; i++) {
          expect(s.avgReturns[i], closeTo(rollout(s.candidates[i], hero), 1e-9),
              reason: 'seed=$seed 후보 $i 리턴 불일치');
        }
        // 3) 후보는 모두 hard 규칙을 만족하고, 롤아웃 후에도 변형되지 않았다(비용 범위 안).
        final (lo, hi) = LayoutGenerator.budgetRange(Tier.hard)!;
        for (final c in s.candidates) {
          expect(c.totalCost, inInclusiveRange(lo, hi));
          expect(count(c, MonsterType.trap), greaterThanOrEqualTo(LayoutRules.hardForcedTraps));
        }
      }
    });

    test('generate(adversarial)는 searchAdversarial의 best와 같다 (같은 시드)', () {
      for (var seed = 0; seed < 20; seed++) {
        final viaGenerate = gen.generate(Tier.adversarial, Random(seed));
        final viaSearch = gen.searchAdversarial(Random(seed)).best;
        expect(js(viaGenerate), equals(js(viaSearch)), reason: 'seed=$seed');
      }
    });

    test('adversary/hero를 넘기면 그 정책·스탯으로 평가한다', () {
      // 항상 물약만 쓰는 정책: 이동하지 않으므로 80턴 후 퇴각. 모든 후보 리턴이 같아 첫 후보가 뽑힌다.
      final s = gen.searchAdversarial(
        Random(3),
        adversary: _PotionOnlyPolicy(),
        hero: HeroStats.forWave(1),
      );
      expect(s.avgReturns.toSet(), hasLength(1), reason: '이동 없는 정책은 배치와 무관하게 같은 리턴');
      expect(s.bestIndex, 0);
      // 리턴 자체는 음수 (턴 벌점 + 물약 벌점 + 퇴각).
      expect(s.avgReturns.first, lessThan(0));
    });

    test('rolloutReturn: 빈 맵에서 GreedyPolicy는 12턴 만에 왕좌 도달 → 100 − 12', () {
      final ret = LayoutGenerator.rolloutReturn(
          GridMap(), HeroStats.forWave(1), const GreedyPolicy(), Random(0));
      expect(ret, closeTo(Balance.rThrone + Balance.rStep * 12, 1e-9));
    });
  });
}

/// 테스트용: 항상 물약만 쓰는 정책 (이동 없음).
class _PotionOnlyPolicy implements HeroPolicy {
  @override
  String get name => 'potion-only';

  @override
  HeroAction act(GameSim sim, Random rng) => HeroAction.potion;
}
