import 'dart:math';

import 'package:dungeon_core/src/balance.dart';
import 'package:dungeon_core/src/game_sim.dart';
import 'package:dungeon_core/src/grid_map.dart';
import 'package:dungeon_core/src/models.dart';
import 'package:dungeon_core/src/policy.dart';
import 'package:test/test.dart';

/// 웨이브 1 용사 (HP 50, ATK 8, 물약 2).
final wave1 = HeroStats.forWave(1);

GameSim emptySim() => GameSim(GridMap(), wave1);

/// 정책으로 끝까지 진행. (보상 합, 스텝 결과 목록) 반환.
(double, List<StepResult>) runToEnd(GameSim sim, HeroPolicy policy, Random rng) {
  var total = 0.0;
  final results = <StepResult>[];
  while (!sim.done) {
    final r = sim.step(policy.act(sim, rng));
    total += r.reward;
    results.add(r);
  }
  return (total, results);
}

void main() {
  test('초기 상태: 입구, 풀 HP, trail=[입구], steps 0', () {
    final sim = emptySim();
    expect(sim.heroPos, Pos.entrance);
    expect(sim.hp, wave1.maxHp);
    expect(sim.maxHp, wave1.maxHp);
    expect(sim.atk, wave1.atk);
    expect(sim.potions, wave1.potions);
    expect(sim.steps, 0);
    expect(sim.lastMove, isNull);
    expect(sim.trail, [Pos.entrance]);
    expect(sim.done, isFalse);
    expect(sim.outcome, Outcome.running);
    expect(sim.trapHits, 0);
    expect(sim.kills, 0);
    expect(sim.hpLost, 0);
    expect(sim.potionsUsed, 0);
  });

  test('1. 빈 맵 GreedyPolicy: 12턴 왕좌 도달, 보상 합 = rThrone + 12*rStep, trail 13', () {
    final sim = emptySim();
    final (total, results) = runToEnd(sim, const GreedyPolicy(), Random(0));
    expect(sim.outcome, Outcome.reachedThrone);
    expect(sim.steps, 12);
    expect(results.length, 12);
    expect(total, closeTo(Balance.rThrone + 12 * Balance.rStep, 1e-9));
    expect(total, closeTo(88, 1e-9));
    expect(sim.trail.length, 13);
    expect(sim.trail.first, Pos.entrance);
    expect(sim.trail.last, Pos.throne);
    expect(sim.heroPos, Pos.throne);
    expect(sim.hp, wave1.maxHp);
    // 마지막 스텝만 종료, 나머지는 running
    for (final r in results.take(11)) {
      expect(r.done, isFalse);
      expect(r.reward, closeTo(Balance.rStep, 1e-9));
    }
    expect(results.last.done, isTrue);
    expect(results.last.reward, closeTo(Balance.rStep + Balance.rThrone, 1e-9));
    // 종료 후 step은 StateError
    expect(() => sim.step(HeroAction.up), throwsStateError);
  });

  test('2. 함정 (2,0): right,right → HP 50→35, 보상 = rStep + 15*rHpLossPerPoint + rTrapHit, 함정 유지', () {
    final map = GridMap();
    expect(map.place(MonsterType.trap, const Pos(2, 0)), isTrue);
    final sim = GameSim(map, wave1);

    final r1 = sim.step(HeroAction.right);
    expect(sim.heroPos, const Pos(1, 0));
    expect(r1.reward, closeTo(Balance.rStep, 1e-9));
    expect(r1.events.map((e) => e.type), [EventType.moved]);

    final r2 = sim.step(HeroAction.right);
    expect(sim.heroPos, const Pos(2, 0));
    expect(sim.hp, wave1.maxHp - Balance.trapDamage);
    expect(sim.hp, 35);
    expect(sim.hpLost, Balance.trapDamage);
    expect(sim.trapHits, 1);
    final expected = Balance.rStep + Balance.trapDamage * Balance.rHpLossPerPoint + Balance.rTrapHit;
    expect(r2.reward, closeTo(expected, 1e-9));
    expect(r2.reward, closeTo(-10.5, 1e-9));
    expect(r2.done, isFalse);
    expect(r2.events.map((e) => e.type), [EventType.moved, EventType.trapHit]);
    final trapEv = r2.events.last;
    expect(trapEv.pos, const Pos(2, 0));
    expect(trapEv.amount, Balance.trapDamage);
    expect(trapEv.monster, MonsterType.trap);
    // 함정은 남아 있고 trail에 기록됨
    expect(sim.map.monsters[const Pos(2, 0)]?.type, MonsterType.trap);
    expect(sim.trail, [Pos.entrance, const Pos(1, 0), const Pos(2, 0)]);
    expect(sim.lastMove, HeroAction.right);
    // 원본 맵은 영향 없음 (clone)
    expect(map.monsters.length, 1);
  });

  test('3. 슬라임 (2,0): 이동→공격(반격 2)→공격(처치, 반격 없음, 제자리)→진입', () {
    final map = GridMap();
    expect(map.place(MonsterType.slime, const Pos(2, 0)), isTrue);
    final sim = GameSim(map, wave1);
    final slimeSpec = MonsterType.slime.spec;

    sim.step(HeroAction.right); // (1,0) 빈칸 이동
    expect(sim.heroPos, const Pos(1, 0));

    // 첫 공격: 슬라임 hp 10-8=2, 반격 2 → 용사 48
    final r2 = sim.step(HeroAction.right);
    expect(sim.heroPos, const Pos(1, 0));
    expect(sim.map.monsters[const Pos(2, 0)]!.hp, slimeSpec.hp - wave1.atk);
    expect(sim.map.monsters[const Pos(2, 0)]!.hp, 2);
    expect(sim.hp, wave1.maxHp - slimeSpec.atk);
    expect(sim.hp, 48);
    expect(sim.hpLost, slimeSpec.atk);
    expect(r2.reward, closeTo(Balance.rStep + slimeSpec.atk * Balance.rHpLossPerPoint, 1e-9));
    expect(r2.events.map((e) => e.type), [EventType.attacked]);
    expect(r2.events.first.pos, const Pos(2, 0));
    expect(r2.events.first.amount, wave1.atk);
    expect(r2.events.first.monster, MonsterType.slime);
    expect(sim.kills, 0);
    expect(sim.lastMove, HeroAction.right); // 공격은 lastMove 불변
    expect(sim.trail.length, 2); // 공격 턴은 trail에 추가 안 됨

    // 두 번째 공격: 처치, kills=1, rKill, 반격 없음, 제자리
    final r3 = sim.step(HeroAction.right);
    expect(sim.heroPos, const Pos(1, 0));
    expect(sim.map.monsters.containsKey(const Pos(2, 0)), isFalse);
    expect(sim.kills, 1);
    expect(sim.hp, 48);
    expect(r3.reward, closeTo(Balance.rStep + Balance.rKill, 1e-9));
    expect(r3.events.map((e) => e.type), [EventType.attacked, EventType.killed]);
    expect(r3.events.last.pos, const Pos(2, 0));
    expect(r3.events.last.monster, MonsterType.slime);
    expect(sim.steps, 3);

    // 이제 (2,0)으로 이동 가능
    final r4 = sim.step(HeroAction.right);
    expect(sim.heroPos, const Pos(2, 0));
    expect(r4.events.map((e) => e.type), [EventType.moved]);
    expect(r4.reward, closeTo(Balance.rStep, 1e-9));
    expect(sim.trail, [Pos.entrance, const Pos(1, 0), const Pos(2, 0)]);

    // 원본 맵의 슬라임은 그대로 (clone)
    expect(map.monsters[const Pos(2, 0)]!.hp, slimeSpec.hp);
  });

  test('4. 기둥 (1,1) 충돌: 제자리, rWallBump, steps 증가, lastMove 불변', () {
    final sim = emptySim();
    sim.step(HeroAction.down); // (0,1)
    expect(sim.heroPos, const Pos(0, 1));
    expect(sim.lastMove, HeroAction.down);

    final r = sim.step(HeroAction.right); // (1,1) 기둥
    expect(sim.heroPos, const Pos(0, 1));
    expect(r.reward, closeTo(Balance.rStep + Balance.rWallBump, 1e-9));
    expect(r.events.map((e) => e.type), [EventType.bumpedWall]);
    expect(r.events.first.pos, const Pos(1, 1));
    expect(sim.steps, 2);
    expect(sim.lastMove, HeroAction.down);
    expect(sim.trail.length, 2);
    expect(sim.hp, wave1.maxHp);

    // 맵 밖도 동일
    final sim2 = emptySim();
    final r2 = sim2.step(HeroAction.up);
    expect(sim2.heroPos, Pos.entrance);
    expect(r2.reward, closeTo(Balance.rStep + Balance.rWallBump, 1e-9));
    expect(r2.events.first.type, EventType.bumpedWall);
    expect(sim2.lastMove, isNull);
  });

  test('5. 물약: 풀 HP 사용 → rPotionWasteHigh, HP 불변, potions 1 / 0개면 rPotionNone', () {
    final sim = emptySim();
    final r1 = sim.step(HeroAction.potion);
    expect(sim.hp, wave1.maxHp);
    expect(sim.potions, wave1.potions - 1);
    expect(sim.potions, 1);
    expect(sim.potionsUsed, 1);
    expect(r1.reward, closeTo(Balance.rStep + Balance.rPotionWasteHigh, 1e-9));
    expect(r1.events.map((e) => e.type), [EventType.potionUsed, EventType.potionWasted]);
    expect(r1.events.first.amount, 0);
    expect(sim.lastMove, isNull);
    expect(sim.trail.length, 1);

    final r2 = sim.step(HeroAction.potion);
    expect(sim.potions, 0);
    expect(sim.potionsUsed, 2);
    expect(r2.reward, closeTo(Balance.rStep + Balance.rPotionWasteHigh, 1e-9));

    final r3 = sim.step(HeroAction.potion);
    expect(sim.potions, 0);
    expect(sim.potionsUsed, 2);
    expect(sim.hp, wave1.maxHp);
    expect(r3.reward, closeTo(Balance.rStep + Balance.rPotionNone, 1e-9));
    expect(r3.events.map((e) => e.type), [EventType.potionWasted]);
    expect(sim.steps, 3);
  });

  test('5b. 물약: 낮은 HP에서 사용하면 벌점 없이 회복(최대치 캡)', () {
    // 함정 2개로 HP 50 → 20 만든 뒤 물약
    final map = GridMap();
    map.place(MonsterType.trap, const Pos(2, 0));
    map.place(MonsterType.trap, const Pos(3, 0));
    final sim = GameSim(map, wave1);
    sim.step(HeroAction.right);
    sim.step(HeroAction.right);
    sim.step(HeroAction.right);
    expect(sim.hp, wave1.maxHp - 2 * Balance.trapDamage);
    expect(sim.trapHits, 2);
    final hpBefore = sim.hp;

    final r = sim.step(HeroAction.potion);
    final healed = min(Balance.potionHeal, wave1.maxHp - hpBefore);
    expect(sim.hp, hpBefore + healed);
    expect(r.reward, closeTo(Balance.rStep, 1e-9)); // 회복은 벌점/보상 없음
    expect(r.events.map((e) => e.type), [EventType.potionUsed]);
    expect(r.events.first.amount, healed);
    expect(sim.hpLost, 2 * Balance.trapDamage); // 회복해도 누적 손실은 유지
  });

  test('6. 벽 충돌 반복 80턴 → gaveUp, 마지막 보상에 rTimeout', () {
    final sim = emptySim();
    StepResult? last;
    for (var i = 0; i < Balance.maxSteps; i++) {
      expect(sim.done, isFalse);
      last = sim.step(HeroAction.up); // (0,-1) 맵 밖
    }
    expect(sim.done, isTrue);
    expect(sim.outcome, Outcome.gaveUp);
    expect(sim.steps, Balance.maxSteps);
    expect(sim.heroPos, Pos.entrance);
    expect(last!.reward, closeTo(Balance.rStep + Balance.rWallBump + Balance.rTimeout, 1e-9));
    expect(last.outcome, Outcome.gaveUp);
    expect(sim.trail, [Pos.entrance]);
  });

  test('6b. 사망: 오크 반격 누적 → heroDied, rDeath, 사망 턴에 종료', () {
    final map = GridMap();
    map.place(MonsterType.orc, const Pos(2, 0));
    final sim = GameSim(map, wave1);
    sim.step(HeroAction.right); // (1,0)
    final orcAtk = MonsterType.orc.spec.atk;
    var total = 0.0;
    StepResult? last;
    // 오크 40HP, 용사 ATK 8 → 5회 공격에 사망. 반격 4회 = 36 < 50 이라 오크가 먼저 죽는다.
    for (var i = 0; i < 5; i++) {
      last = sim.step(HeroAction.right);
      total += last.reward;
    }
    expect(sim.kills, 1);
    expect(sim.hp, wave1.maxHp - 4 * orcAtk);
    expect(sim.done, isFalse);
    expect(total, closeTo(5 * Balance.rStep + 4 * orcAtk * Balance.rHpLossPerPoint + Balance.rKill, 1e-9));

    // 두 번째 오크: HP 14 → 반격 1회(9) → 5, 반격 2회 → 사망
    final map2 = GridMap();
    map2.place(MonsterType.orc, const Pos(2, 0));
    map2.place(MonsterType.orc, const Pos(3, 0));
    final sim2 = GameSim(map2, wave1);
    sim2.step(HeroAction.right);
    for (var i = 0; i < 5; i++) {
      sim2.step(HeroAction.right);
    }
    sim2.step(HeroAction.right); // (2,0) 진입
    expect(sim2.heroPos, const Pos(2, 0));
    sim2.step(HeroAction.right); // 오크2 공격, 반격 → 5
    expect(sim2.hp, wave1.maxHp - 5 * orcAtk);
    expect(sim2.done, isFalse);
    final death = sim2.step(HeroAction.right); // 반격 → 사망
    expect(sim2.done, isTrue);
    expect(sim2.outcome, Outcome.heroDied);
    expect(death.outcome, Outcome.heroDied);
    expect(sim2.hp, 0); // 0 밑으로 내려가지 않음
    final lostThisTurn = wave1.maxHp - 5 * orcAtk; // 실제 잃은 HP(클램프)
    expect(death.reward, closeTo(Balance.rStep + lostThisTurn * Balance.rHpLossPerPoint + Balance.rDeath, 1e-9));
    expect(sim2.hpLost, wave1.maxHp);
  });

  test('되돌아가기: 직전 이동의 반대 방향 실제 이동 → rReverseMove + reversed 이벤트', () {
    final sim = emptySim();
    sim.step(HeroAction.right); // (1,0)
    final r = sim.step(HeroAction.left); // (0,0)
    expect(sim.heroPos, Pos.entrance);
    expect(r.reward, closeTo(Balance.rStep + Balance.rReverseMove, 1e-9));
    expect(r.events.map((e) => e.type), [EventType.moved, EventType.reversed]);
    expect(sim.lastMove, HeroAction.left);

    // 벽 충돌은 lastMove를 바꾸지 않으므로, 그 뒤 반대 이동도 되돌아가기
    sim.step(HeroAction.up); // 맵 밖 → 제자리
    expect(sim.lastMove, HeroAction.left);
    final r2 = sim.step(HeroAction.right); // (1,0) — left의 반대
    expect(r2.events.map((e) => e.type), [EventType.moved, EventType.reversed]);

    // 공격 후 후퇴는 되돌아가기가 아님 (공격은 lastMove 미갱신)
    final map = GridMap();
    map.place(MonsterType.orc, const Pos(2, 0));
    final s2 = GameSim(map, wave1);
    s2.step(HeroAction.right); // (1,0), lastMove=right
    s2.step(HeroAction.right); // 공격
    final back = s2.step(HeroAction.left); // (0,0): right의 반대 → 되돌아가기 맞음
    expect(back.events.map((e) => e.type), [EventType.moved, EventType.reversed]);
    // 반면 down 후 공격 후 up 은 반대
    final s3 = GameSim(map, wave1);
    s3.step(HeroAction.right); // (1,0)
    s3.step(HeroAction.down); // (1,1)은 기둥 → 충돌, lastMove=right 유지
    expect(s3.lastMove, HeroAction.right);
  });

  test('7. 결정론: 같은 맵·같은 행동열 → 이벤트/상태 동일, clone은 원본과 독립', () {
    final map = GridMap();
    map.place(MonsterType.slime, const Pos(2, 0));
    map.place(MonsterType.trap, const Pos(2, 1));
    map.place(MonsterType.goblin, const Pos(4, 2));
    map.place(MonsterType.orc, const Pos(6, 5));
    final hero = HeroStats.forWave(6);

    final a = GameSim(map, hero);
    final b = GameSim(map, hero);
    final rngA = Random(7);
    final rngB = Random(7);
    const policy = GreedyPolicy();
    final evA = <String>[];
    final evB = <String>[];
    var totalA = 0.0, totalB = 0.0;
    while (!a.done) {
      final actA = policy.act(a, rngA);
      final actB = policy.act(b, rngB);
      expect(actB, actA);
      final ra = a.step(actA);
      final rb = b.step(actB);
      evA.addAll(ra.events.map((e) => e.toString()));
      evB.addAll(rb.events.map((e) => e.toString()));
      totalA += ra.reward;
      totalB += rb.reward;
    }
    expect(b.done, isTrue);
    expect(evA, evB);
    expect(evA, isNotEmpty);
    expect(totalA, totalB);
    expect(a.outcome, b.outcome);
    expect(a.heroPos, b.heroPos);
    expect(a.hp, b.hp);
    expect(a.steps, b.steps);
    expect(a.trail, b.trail);
    expect(a.kills, b.kills);
    expect(a.trapHits, b.trapHits);
    expect(a.potionsUsed, b.potionsUsed);
    expect(a.map.toJson(), b.map.toJson());

    // clone 독립성 (웨이브 1 용사: ATK 8 → 슬라임은 2회 공격)
    final base = GameSim(map, wave1);
    base.step(HeroAction.right);
    base.step(HeroAction.right); // 슬라임 공격 (hp 2 남음)
    final c = base.clone();
    expect(c.heroPos, base.heroPos);
    expect(c.hp, base.hp);
    expect(c.steps, base.steps);
    expect(c.lastMove, base.lastMove);
    expect(c.trail, base.trail);
    expect(c.map.toJson(), base.map.toJson());
    expect(identical(c.map, base.map), isFalse);

    final snapshotHp = c.hp;
    final snapshotSteps = c.steps;
    final snapshotTrail = List<Pos>.of(c.trail);
    final snapshotMap = c.map.toJson();
    // 원본만 진행
    base.step(HeroAction.right); // 슬라임 처치
    base.step(HeroAction.right); // (2,0)
    base.step(HeroAction.down); // (2,1) 함정
    expect(base.trapHits, 1);
    expect(base.kills, 1);
    // clone 불변
    expect(c.hp, snapshotHp);
    expect(c.steps, snapshotSteps);
    expect(c.trail, snapshotTrail);
    expect(c.map.toJson(), snapshotMap);
    expect(c.kills, 0);
    expect(c.trapHits, 0);
    expect(c.map.monsters[const Pos(2, 0)]!.hp, MonsterType.slime.spec.hp - wave1.atk);
    // clone을 진행해도 원본 불변
    final baseSteps = base.steps;
    c.step(HeroAction.right);
    expect(base.steps, baseSteps);
  });

  group('GreedyPolicy', () {
    test('큰 축 우선, 같으면 x 우선, 막히면 다른 축', () {
      const p = GreedyPolicy();
      final rng = Random(1);
      final sim = emptySim();
      // (0,0): dx=dy=6 → x 우선 → right
      expect(p.act(sim, rng), HeroAction.right);
      sim.step(HeroAction.right);
      // (1,0): dx=5, dy=6 → down 이지만 (1,1) 기둥 → right
      expect(p.act(sim, rng), HeroAction.right);
      sim.step(HeroAction.right);
      // (2,0): dx=4, dy=6 → down
      expect(p.act(sim, rng), HeroAction.down);
    });

    test('HP ≤ 25%이고 물약 있으면 물약, 없으면 이동', () {
      const p = GreedyPolicy();
      final rng = Random(1);
      // 함정 3개: 50 → 5 (10%)
      final map = GridMap();
      map.place(MonsterType.trap, const Pos(2, 0));
      map.place(MonsterType.trap, const Pos(3, 0));
      map.place(MonsterType.trap, const Pos(4, 0));
      final sim = GameSim(map, wave1);
      for (final a in [HeroAction.right, HeroAction.right, HeroAction.right, HeroAction.right]) {
        sim.step(a);
      }
      expect(sim.hp, wave1.maxHp - 3 * Balance.trapDamage);
      expect(sim.hp <= sim.maxHp * GreedyPolicy.potionHpRatio, isTrue);
      expect(p.act(sim, rng), HeroAction.potion);
      sim.step(HeroAction.potion); // 5 → 30 (60%)
      expect(p.act(sim, rng), isNot(HeroAction.potion));

      // 물약 0개면 낮아도 이동
      final sim2 = GameSim(map, const HeroStats(50, 8, 0));
      for (final a in [HeroAction.right, HeroAction.right, HeroAction.right, HeroAction.right]) {
        sim2.step(a);
      }
      expect(sim2.potions, 0);
      expect(p.act(sim2, rng).isMove, isTrue);
    });

    test('마물은 그냥 공격 (그 방향으로 이동 시도)', () {
      const p = GreedyPolicy();
      final rng = Random(1);
      final map = GridMap();
      map.place(MonsterType.orc, const Pos(2, 0));
      final sim = GameSim(map, wave1);
      sim.step(HeroAction.right); // (1,0)
      // (1,0)에서 down 은 기둥이라 right = 오크 공격
      expect(p.act(sim, rng), HeroAction.right);
      final r = sim.step(HeroAction.right);
      expect(r.events.first.type, EventType.attacked);
    });

    test('결정론: rng 시드가 달라도 빈 맵에서는 같은 경로', () {
      const p = GreedyPolicy();
      final s1 = emptySim();
      final s2 = emptySim();
      runToEnd(s1, p, Random(1));
      runToEnd(s2, p, Random(999));
      expect(s1.trail, s2.trail);
      expect(s1.trail.length, 13);
    });
  });
}
