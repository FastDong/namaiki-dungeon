import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

/// GameSim/GridMap이 아직 스텁(UnimplementedError)이면 시뮬 기반 테스트는 건너뛴다.
/// 구현이 들어오면 자동으로 활성화된다.
String? _simSkipReason() {
  try {
    final map = GridMap();
    map.isPillar(Pos.entrance);
    GameSim(map, HeroStats.forWave(1)).heroPos;
    return null;
  } on UnimplementedError catch (e) {
    return 'GameSim/GridMap 미구현: $e';
  }
}

void main() {
  final simSkip = _simSkipReason();

  group('상수·순서', () {
    test('stateCount = 9*1296*4*2*5 = 466,560', () {
      expect(FeatureEncoder.stateCount, 466560);
      expect(
        FeatureEncoder.goalDirCount *
            FeatureEncoder.adjCount *
            FeatureEncoder.hpBucketCount *
            FeatureEncoder.potionCount *
            FeatureEncoder.lastMoveCount,
        FeatureEncoder.stateCount,
      );
      expect(FeatureEncoder.actionCount, HeroAction.values.length);
    });

    test('AdjKind 순서 고정: wall, empty, weakMonster, strongMonster, trap, throne', () {
      expect(AdjKind.values, [
        AdjKind.wall,
        AdjKind.empty,
        AdjKind.weakMonster,
        AdjKind.strongMonster,
        AdjKind.trap,
        AdjKind.throne,
      ]);
      expect(AdjKind.values.length, FeatureEncoder.adjKindCount);
      expect(AdjKind.wall.index, 0);
      expect(AdjKind.throne.index, 5);
    });

    test('moveActions 순서 = up, down, left, right (adj 슬롯 순서)', () {
      expect(moveActions, [HeroAction.up, HeroAction.down, HeroAction.left, HeroAction.right]);
    });
  });

  group('indexOf / decode 왕복', () {
    test('0 과 stateCount-1', () {
      expect(FeatureEncoder.indexOf(FeatureEncoder.decode(0)), 0);
      final last = FeatureEncoder.stateCount - 1;
      expect(FeatureEncoder.indexOf(FeatureEncoder.decode(last)), last);

      final f0 = FeatureEncoder.decode(0);
      expect(f0.goalDx, -1);
      expect(f0.goalDy, -1);
      expect(f0.adj, everyElement(AdjKind.wall));
      expect(f0.hpBucket, 0);
      expect(f0.hasPotion, isFalse);
      expect(f0.lastMove, isNull);

      final fl = FeatureEncoder.decode(last);
      expect(fl.goalDx, 1);
      expect(fl.goalDy, 1);
      expect(fl.adj, everyElement(AdjKind.throne));
      expect(fl.hpBucket, 3);
      expect(fl.hasPotion, isTrue);
      expect(fl.lastMove, HeroAction.right);
    });

    test('랜덤 5,000개 indexOf(decode(i)) == i', () {
      final rng = Random(7);
      for (var k = 0; k < 5000; k++) {
        final i = rng.nextInt(FeatureEncoder.stateCount);
        final f = FeatureEncoder.decode(i);
        expect(FeatureEncoder.indexOf(f), i, reason: 'i=$i f=$f');
      }
    });

    test('손으로 만든 특징 → 공식과 일치 → decode 로 복원', () {
      // goalDir = (1+1)*3 + (0+1) = 7, adj = 1*216 + 2*36 + 0*6 + 4 = 292, hp=2, potion=1, last=down(2)
      const f = StateFeatures(
        goalDx: 1,
        goalDy: 0,
        adj: [AdjKind.empty, AdjKind.weakMonster, AdjKind.wall, AdjKind.trap],
        hpBucket: 2,
        hasPotion: true,
        lastMove: HeroAction.down,
      );
      const expected = ((((7 * 1296) + 292) * 4 + 2) * 2 + 1) * 5 + 2;
      final idx = FeatureEncoder.indexOf(f);
      expect(idx, expected);
      final back = FeatureEncoder.decode(idx);
      expect(back.goalDx, f.goalDx);
      expect(back.goalDy, f.goalDy);
      expect(back.adj, f.adj);
      expect(back.hpBucket, f.hpBucket);
      expect(back.hasPotion, f.hasPotion);
      expect(back.lastMove, f.lastMove);
    });

    test('lastMove 인코딩: none=0, up=1, down=2, left=3, right=4', () {
      StateFeatures withLast(HeroAction? a) => StateFeatures(
            goalDx: -1,
            goalDy: -1,
            adj: const [AdjKind.wall, AdjKind.wall, AdjKind.wall, AdjKind.wall],
            hpBucket: 0,
            hasPotion: false,
            lastMove: a,
          );
      expect(FeatureEncoder.indexOf(withLast(null)), 0);
      expect(FeatureEncoder.indexOf(withLast(HeroAction.up)), 1);
      expect(FeatureEncoder.indexOf(withLast(HeroAction.down)), 2);
      expect(FeatureEncoder.indexOf(withLast(HeroAction.left)), 3);
      expect(FeatureEncoder.indexOf(withLast(HeroAction.right)), 4);
    });

    test('모든 인덱스가 서로 다른 특징으로 복원된다 (전수 466,560)', () {
      // decode가 단사인지: 복원한 특징을 다시 indexOf 하면 같은 값이어야 한다.
      for (var i = 0; i < FeatureEncoder.stateCount; i++) {
        if (FeatureEncoder.indexOf(FeatureEncoder.decode(i)) != i) {
          fail('왕복 실패 i=$i');
        }
      }
    });
  });

  group('잘못된 범위 방어', () {
    test('decode 범위 밖', () {
      expect(() => FeatureEncoder.decode(-1), throwsRangeError);
      expect(() => FeatureEncoder.decode(FeatureEncoder.stateCount), throwsRangeError);
    });

    StateFeatures make({
      int goalDx = 0,
      int goalDy = 0,
      List<AdjKind> adj = const [AdjKind.empty, AdjKind.empty, AdjKind.empty, AdjKind.empty],
      int hpBucket = 3,
      HeroAction? lastMove,
    }) =>
        StateFeatures(
          goalDx: goalDx,
          goalDy: goalDy,
          adj: adj,
          hpBucket: hpBucket,
          hasPotion: true,
          lastMove: lastMove,
        );

    test('indexOf 잘못된 goalDir / adj 길이 / hpBucket / lastMove=potion', () {
      expect(() => FeatureEncoder.indexOf(make(goalDx: 2)), throwsArgumentError);
      expect(() => FeatureEncoder.indexOf(make(goalDy: -2)), throwsArgumentError);
      expect(() => FeatureEncoder.indexOf(make(adj: const [AdjKind.empty])), throwsArgumentError);
      expect(() => FeatureEncoder.indexOf(make(hpBucket: 4)), throwsArgumentError);
      expect(() => FeatureEncoder.indexOf(make(hpBucket: -1)), throwsArgumentError);
      expect(() => FeatureEncoder.indexOf(make(lastMove: HeroAction.potion)), throwsArgumentError);
      // 정상 값은 통과
      final ok = FeatureEncoder.indexOf(make(lastMove: HeroAction.left));
      expect(ok, inInclusiveRange(0, FeatureEncoder.stateCount - 1));
    });
  });

  group('hpBucket / isWeak', () {
    test('hpBucket 경계 (≤25%→0, ≤50%→1, ≤75%→2, >75%→3)', () {
      final max = Balance.heroHp(1); // 50
      expect(FeatureEncoder.hpBucketOf(max, max), 3);
      // 경계 "이하"는 floor, 바로 위는 floor+1 (50 기준: 37→2, 38→3 / 25→1, 26→2 / 12→0, 13→1)
      expect(FeatureEncoder.hpBucketOf((max * 0.75).floor() + 1, max), 3);
      expect(FeatureEncoder.hpBucketOf((max * 0.75).floor(), max), 2);
      expect(FeatureEncoder.hpBucketOf((max * 0.5).floor() + 1, max), 2);
      expect(FeatureEncoder.hpBucketOf((max * 0.5).floor(), max), 1);
      expect(FeatureEncoder.hpBucketOf((max * 0.25).floor() + 1, max), 1);
      expect(FeatureEncoder.hpBucketOf((max * 0.25).floor(), max), 0);
      // 정확히 경계에 떨어지는 maxHp (예: 100 → 25/50/75 는 "이하"라 낮은 버킷)
      expect(FeatureEncoder.hpBucketOf(25, 100), 0);
      expect(FeatureEncoder.hpBucketOf(50, 100), 1);
      expect(FeatureEncoder.hpBucketOf(75, 100), 2);
      expect(FeatureEncoder.hpBucketOf(76, 100), 3);
      expect(FeatureEncoder.hpBucketOf(1, max), 0);
      expect(FeatureEncoder.hpBucketOf(0, max), 0);
      expect(FeatureEncoder.hpBucketOf(-5, max), 0);
      expect(FeatureEncoder.hpBucketOf(10, 0), 0);
      // 비율 정의와 정수 판정이 모든 (hp, maxHp) 조합에서 일치
      for (var m = 1; m <= Balance.heroHp(Balance.totalWaves); m++) {
        for (var hp = 0; hp <= m; hp++) {
          final r = hp / m;
          var expected = FeatureEncoder.hpBucketBounds.length;
          for (var b = 0; b < FeatureEncoder.hpBucketBounds.length; b++) {
            if (r <= FeatureEncoder.hpBucketBounds[b]) {
              expected = b;
              break;
            }
          }
          expect(FeatureEncoder.hpBucketOf(hp, m), expected, reason: 'hp=$hp max=$m');
        }
      }
    });

    test('isWeak: hp <= 2*atk', () {
      final slime = Monster.fresh(MonsterType.slime, const Pos(2, 2));
      final goblin = Monster.fresh(MonsterType.goblin, const Pos(2, 2));
      final orc = Monster.fresh(MonsterType.orc, const Pos(2, 2));
      // 웨이브 1 용사(ATK 8): 슬라임만 약함
      expect(FeatureEncoder.isWeak(slime, Balance.heroAtk(1)), isTrue);
      expect(FeatureEncoder.isWeak(goblin, Balance.heroAtk(1)), isFalse);
      expect(FeatureEncoder.isWeak(orc, Balance.heroAtk(1)), isFalse);
      // 고블린은 웨이브 5(ATK 12)부터, 오크는 웨이브 13(ATK 20)부터 약함 (PLAN §3)
      expect(FeatureEncoder.isWeak(goblin, Balance.heroAtk(4)), isFalse);
      expect(FeatureEncoder.isWeak(goblin, Balance.heroAtk(5)), isTrue);
      expect(FeatureEncoder.isWeak(orc, Balance.heroAtk(12)), isFalse);
      expect(FeatureEncoder.isWeak(orc, Balance.heroAtk(13)), isTrue);
      // 현재 HP 기준 (다친 마물은 약해진다)
      final hurtOrc = Monster(MonsterType.orc, const Pos(2, 2), 2 * Balance.heroAtk(1));
      expect(FeatureEncoder.isWeak(hurtOrc, Balance.heroAtk(1)), isTrue);
    });
  });

  group('GameSim 스모크 (구현 후 자동 활성화)', () {
    test('빈 맵: 입구에서 goalDir=(1,1), 상/좌=wall, 하/우=empty, 11턴 뒤 왕좌 인접', () {
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final f = FeatureEncoder.features(sim);
      expect(f.goalDx, 1);
      expect(f.goalDy, 1);
      expect(f.adj, [AdjKind.wall, AdjKind.empty, AdjKind.wall, AdjKind.empty]);
      expect(f.hpBucket, 3);
      expect(f.hasPotion, Balance.potions > 0);
      expect(f.lastMove, isNull);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
      expect(FeatureEncoder.encode(sim), inInclusiveRange(0, FeatureEncoder.stateCount - 1));

      // 0행은 기둥이 없으므로 오른쪽 6칸, 6열도 기둥이 없으므로 아래 5칸 → (6,5)
      for (var i = 0; i < Balance.cols - 1; i++) {
        sim.step(HeroAction.right);
      }
      for (var i = 0; i < Balance.rows - 2; i++) {
        sim.step(HeroAction.down);
      }
      expect(sim.heroPos, Pos(Balance.throneX, Balance.throneY - 1));
      final g = FeatureEncoder.features(sim);
      expect(g.goalDx, 0);
      expect(g.goalDy, 1);
      expect(g.adj[HeroAction.down.index], AdjKind.throne);
      expect(g.adj[HeroAction.right.index], AdjKind.wall); // 맵 밖
      expect(g.adj[HeroAction.left.index], AdjKind.wall); // 기둥 (5,5)
      expect(g.adj[HeroAction.up.index], AdjKind.empty);
      expect(g.lastMove, HeroAction.down);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(g));
    }, skip: simSkip);

    test('마물 배치: trap / weak / strong / 기둥 wall / lastMove 갱신 규칙', () {
      final map = GridMap();
      expect(map.place(MonsterType.trap, const Pos(2, 0)), isTrue);
      expect(map.place(MonsterType.slime, const Pos(0, 2)), isTrue);
      expect(map.place(MonsterType.goblin, const Pos(0, 4)), isTrue);
      final sim = GameSim(map, HeroStats.forWave(1)); // ATK 8: 슬라임 약함, 고블린 강함

      sim.step(HeroAction.right); // (1,0)
      var f = FeatureEncoder.features(sim);
      expect(f.adj[HeroAction.up.index], AdjKind.wall); // 맵 밖
      expect(f.adj[HeroAction.down.index], AdjKind.wall); // 기둥 (1,1)
      expect(f.adj[HeroAction.left.index], AdjKind.empty); // 입구
      expect(f.adj[HeroAction.right.index], AdjKind.trap);
      expect(f.lastMove, HeroAction.right);

      sim.step(HeroAction.down); // 기둥 → 제자리, lastMove 유지
      expect(sim.heroPos, const Pos(1, 0));
      expect(FeatureEncoder.features(sim).lastMove, HeroAction.right);

      sim.step(HeroAction.left); // (0,0) 되돌아가기
      sim.step(HeroAction.down); // (0,1)
      f = FeatureEncoder.features(sim);
      expect(f.adj[HeroAction.down.index], AdjKind.weakMonster); // 슬라임 (0,2)
      expect(f.adj[HeroAction.right.index], AdjKind.wall); // 기둥 (1,1)
      expect(f.adj[HeroAction.left.index], AdjKind.wall); // 맵 밖
      expect(f.adj[HeroAction.up.index], AdjKind.empty);
      expect(f.lastMove, HeroAction.down);

      sim.step(HeroAction.down); // 슬라임 공격(제자리), lastMove 유지
      expect(sim.heroPos, const Pos(0, 1));
      expect(FeatureEncoder.features(sim).lastMove, HeroAction.down);
      final hitsToKill = (monsterSpecs[MonsterType.slime]!.hp + sim.atk - 1) ~/ sim.atk;
      for (var i = 1; i < hitsToKill; i++) {
        sim.step(HeroAction.down);
      }
      expect(FeatureEncoder.features(sim).adj[HeroAction.down.index], AdjKind.empty); // 처치됨

      sim.step(HeroAction.down); // (0,2)
      sim.step(HeroAction.down); // (0,3)
      f = FeatureEncoder.features(sim);
      expect(f.adj[HeroAction.down.index], AdjKind.strongMonster); // 고블린 (0,4)
      expect(f.adj[HeroAction.right.index], AdjKind.wall); // 기둥 (1,3)
      expect(f.goalDx, 1);
      expect(f.goalDy, 1);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
    }, skip: simSkip);

    test('전치 대칭: 맵·행동을 (x,y)→(y,x)로 바꾸면 goalDx↔goalDy, adj up↔left, down↔right', () {
      // 기둥·입구·왕좌·입구 인접 금지칸이 모두 전치에 불변이므로, 전치한 맵에서 전치한 행동열을 밟으면
      // 매 스텝 특징이 정확히 축 교환된 형태여야 한다 (절대 좌표가 새어 들어가지 않았다는 검증).
      HeroAction tr(HeroAction a) => switch (a) {
            HeroAction.up => HeroAction.left,
            HeroAction.left => HeroAction.up,
            HeroAction.down => HeroAction.right,
            HeroAction.right => HeroAction.down,
            HeroAction.potion => HeroAction.potion,
          };
      final rng = Random(21);
      var steps = 0;
      for (var trial = 0; trial < 40; trial++) {
        final map = GridMap();
        final mapT = GridMap();
        final cells = GridMap.placeableCells()..shuffle(rng);
        for (final p in cells.take(10)) {
          final t = MonsterType.values[rng.nextInt(MonsterType.values.length)];
          expect(map.place(t, p), isTrue);
          expect(mapT.place(t, Pos(p.y, p.x)), isTrue);
        }
        final hero = HeroStats.forWave(1 + rng.nextInt(Balance.totalWaves));
        final sim = GameSim(map, hero);
        final simT = GameSim(mapT, hero);
        while (!sim.done) {
          final f = FeatureEncoder.features(sim);
          final g = FeatureEncoder.features(simT);
          expect(g.goalDx, f.goalDy);
          expect(g.goalDy, f.goalDx);
          expect(g.adj[HeroAction.up.index], f.adj[HeroAction.left.index]);
          expect(g.adj[HeroAction.left.index], f.adj[HeroAction.up.index]);
          expect(g.adj[HeroAction.down.index], f.adj[HeroAction.right.index]);
          expect(g.adj[HeroAction.right.index], f.adj[HeroAction.down.index]);
          expect(g.hpBucket, f.hpBucket);
          expect(g.hasPotion, f.hasPotion);
          expect(g.lastMove, f.lastMove == null ? isNull : tr(f.lastMove!));
          expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
          expect(FeatureEncoder.encode(simT), FeatureEncoder.indexOf(g));

          // 왕좌 쪽으로 치우친 랜덤 워크 (종료 상태도 몇 번은 밟도록)
          final a = rng.nextInt(3) == 0
              ? HeroAction.values[rng.nextInt(HeroAction.values.length)]
              : (rng.nextBool() ? HeroAction.right : HeroAction.down);
          final r = sim.step(a);
          final rT = simT.step(tr(a));
          expect(rT.reward, r.reward);
          expect(rT.outcome, r.outcome);
          steps++;
        }
        expect(simT.done, isTrue);
      }
      expect(steps, greaterThan(200));
    }, skip: simSkip);
  });
}
