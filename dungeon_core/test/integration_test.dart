import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

/// M1(GridMap/GameSim/FeatureEncoder/QTable/정책) + M2(LayoutGenerator) 통합 검증.
///
/// 개별 모듈 테스트(game_sim_test, encoder_test, qtable_test, layout_test)가 각 단위를 다루고,
/// 여기서는 "실제 GameSim 위에서 인코더·정책·배치 봇이 함께 돌아가는가"를 본다.
/// 규칙 근거는 PLAN.md §3(게임 규칙), §5.1(상태 벡터), §5.3(보상).

/// 행동을 대각선 전치((x,y)→(y,x))한 것: up↔left, down↔right. potion 불변.
HeroAction _transpose(HeroAction a) => switch (a) {
      HeroAction.up => HeroAction.left,
      HeroAction.left => HeroAction.up,
      HeroAction.down => HeroAction.right,
      HeroAction.right => HeroAction.down,
      HeroAction.potion => HeroAction.potion,
    };

/// 좌표 전치.
Pos _transposePos(Pos p) => Pos(p.y, p.x);

/// [sim]을 [policy]로 끝까지(최대 Balance.maxSteps) 진행. 매 스텝 encode()도 호출한다(학습 루프와 동일 부하).
/// 반환: 보상 합.
double _playOut(GameSim sim, HeroPolicy policy, Random rng) {
  var total = 0.0;
  while (!sim.done) {
    FeatureEncoder.encode(sim);
    total += sim.step(policy.act(sim, rng)).reward;
  }
  return total;
}

/// [actions]를 순서대로 밟으며 (스텝 전 특징, 보상) 목록을 돌려준다. 종료되면 멈춘다.
(List<StateFeatures>, List<double>) _trace(GameSim sim, List<HeroAction> actions) {
  final feats = <StateFeatures>[];
  final rewards = <double>[];
  for (final a in actions) {
    if (sim.done) break;
    feats.add(FeatureEncoder.features(sim));
    rewards.add(sim.step(a).reward);
  }
  return (feats, rewards);
}

void main() {
  const up = HeroAction.up, down = HeroAction.down, left = HeroAction.left, right = HeroAction.right;
  const potion = HeroAction.potion;

  group('(a) 실제 GameSim 위 FeatureEncoder.features/encode', () {
    test('빈 맵 입구: goal=(1,1), adj 상/좌=wall, 하/우=empty, hpBucket 3, 물약 있음, lastMove 없음', () {
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final f = FeatureEncoder.features(sim);
      expect(f.goalDx, 1);
      expect(f.goalDy, 1);
      expect(f.adj[up.index], AdjKind.wall, reason: '(0,-1) 맵 밖');
      expect(f.adj[left.index], AdjKind.wall, reason: '(-1,0) 맵 밖');
      expect(f.adj[down.index], AdjKind.empty, reason: '(0,1) 빈칸');
      expect(f.adj[right.index], AdjKind.empty, reason: '(1,0) 빈칸');
      expect(f.hpBucket, FeatureEncoder.hpBucketCount - 1, reason: '풀 HP → 마지막 버킷');
      expect(f.hasPotion, isTrue);
      expect(f.lastMove, isNull);
      final idx = FeatureEncoder.encode(sim);
      expect(idx, inInclusiveRange(0, FeatureEncoder.stateCount - 1));
      expect(idx, FeatureEncoder.indexOf(f));
      expect(FeatureEncoder.decode(idx).toString(), f.toString());
    });

    test('기둥 (1,1) 위 (1,0)에서 adj[down]=wall, lastMove=right', () {
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      expect(sim.step(right).outcome, Outcome.running);
      expect(sim.heroPos, const Pos(1, 0));
      expect(sim.map.isPillar(const Pos(1, 1)), isTrue, reason: 'Balance.pillars에 (1,1)');
      final f = FeatureEncoder.features(sim);
      expect(f.adj[down.index], AdjKind.wall);
      expect(f.adj[up.index], AdjKind.wall, reason: '맵 밖');
      expect(f.adj[left.index], AdjKind.empty, reason: '입구 (0,0)은 빈칸으로 본다');
      expect(f.adj[right.index], AdjKind.empty);
      expect(f.lastMove, right);
      expect(f.goalDx, 1);
      expect(f.goalDy, 1);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
    });

    test('왕좌 인접 (5,6)에서 adj[right]=throne, adj[up]=wall(기둥 5,5), adj[down]=wall(맵 밖), goal=(1,0)', () {
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      // 열 0을 따라 아래로 6칸 → 행 6을 따라 오른쪽 5칸 = (5,6). 열 0·행 6에는 기둥이 없다.
      for (var i = 0; i < Balance.rows - 1; i++) {
        expect(sim.step(down).outcome, Outcome.running);
      }
      for (var i = 0; i < Balance.cols - 2; i++) {
        expect(sim.step(right).outcome, Outcome.running);
      }
      expect(sim.heroPos, Pos(Balance.throneX - 1, Balance.throneY));
      final f = FeatureEncoder.features(sim);
      expect(f.adj[right.index], AdjKind.throne);
      expect(f.adj[up.index], AdjKind.wall);
      expect(f.adj[down.index], AdjKind.wall);
      expect(f.adj[left.index], AdjKind.empty);
      expect(f.goalDx, 1);
      expect(f.goalDy, 0);
      expect(f.lastMove, right);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
      // 한 칸 더 가면 왕좌 도달 종료 (+100 −1)
      final r = sim.step(right);
      expect(r.outcome, Outcome.reachedThrone);
      expect(r.reward, closeTo(Balance.rStep + Balance.rThrone, 1e-9));
      expect(sim.steps, Pos.entrance.manhattan(Pos.throne), reason: '최단 12턴');
    });
  });

  group('(b) 대각선 전치 대칭', () {
    test('스크립트 행동열: 공격·처치·함정·물약·벽·되돌아가기 전부에서 adj/goal 축 교환 + 보상 시퀀스 동일', () {
      // 원본: 슬라임 (2,0), 함정 (3,0), 오크 (4,0)  /  전치: 슬라임 (0,2), 함정 (0,3), 오크 (0,4)
      final map = GridMap();
      final mapT = GridMap();
      const items = [
        (MonsterType.slime, Pos(2, 0)),
        (MonsterType.trap, Pos(3, 0)),
        (MonsterType.orc, Pos(4, 0)),
      ];
      for (final (t, p) in items) {
        expect(map.place(t, p), isTrue);
        expect(mapT.place(t, _transposePos(p)), isTrue);
      }
      final hero = HeroStats.forWave(1);
      final actions = [
        right, // (1,0) 이동
        right, // 슬라임 공격 (10→2), 반격 2
        right, // 슬라임 처치 (+5)
        right, // (2,0) 진입
        right, // (3,0) 함정 (−15, −5 −4.5)
        potion, // HP 33/50 → 50 (낭비 아님)
        up, // 맵 밖 → 벽 충돌 (−2)
        right, // 오크 공격 (40→32), 반격 9
        potion, // HP 41/50 = 82% > 75% → 낭비 벌점 (−3), 회복 9
        left, // (2,0) 되돌아가기 (−1)
        potion, // 물약 없음 (−2)
        down, // (2,1) 이동
        down, // (2,2) 이동
      ];
      final sim = GameSim(map, hero);
      final simT = GameSim(mapT, hero);
      final (feats, rewards) = _trace(sim, actions);
      final (featsT, rewardsT) = _trace(simT, actions.map(_transpose).toList());

      expect(rewards.length, actions.length, reason: '중간에 종료되면 안 되는 시나리오');
      expect(rewardsT, rewards);
      // 사건이 실제로 일어났는지(시나리오 검증): 처치, 함정, 벽, 물약, 되돌아가기
      expect(sim.kills, 1);
      expect(sim.trapHits, 1);
      expect(sim.potionsUsed, 2);
      expect(sim.potions, 0);
      expect(rewards[2], closeTo(Balance.rStep + Balance.rKill, 1e-9));
      expect(rewards[4], closeTo(Balance.rStep + Balance.rTrapHit + Balance.rHpLossPerPoint * Balance.trapDamage, 1e-9));
      expect(rewards[6], closeTo(Balance.rStep + Balance.rWallBump, 1e-9));
      expect(rewards[8], closeTo(Balance.rStep + Balance.rPotionWasteHigh, 1e-9));
      expect(rewards[9], closeTo(Balance.rStep + Balance.rReverseMove, 1e-9));
      expect(rewards[10], closeTo(Balance.rStep + Balance.rPotionNone, 1e-9));

      for (var i = 0; i < feats.length; i++) {
        final f = feats[i], g = featsT[i];
        expect(g.goalDx, f.goalDy, reason: 'step $i');
        expect(g.goalDy, f.goalDx, reason: 'step $i');
        expect(g.adj[up.index], f.adj[left.index], reason: 'step $i');
        expect(g.adj[left.index], f.adj[up.index], reason: 'step $i');
        expect(g.adj[down.index], f.adj[right.index], reason: 'step $i');
        expect(g.adj[right.index], f.adj[down.index], reason: 'step $i');
        expect(g.hpBucket, f.hpBucket, reason: 'step $i');
        expect(g.hasPotion, f.hasPotion, reason: 'step $i');
        expect(g.lastMove, f.lastMove == null ? isNull : _transpose(f.lastMove!), reason: 'step $i');
      }
      // 상태 종류가 실제로 다양했는지: 약한 마물·강한 마물·함정·벽이 인접 특징에 한 번씩은 등장
      final seen = feats.expand((f) => f.adj).toSet();
      expect(seen, containsAll([AdjKind.wall, AdjKind.empty, AdjKind.weakMonster, AdjKind.strongMonster, AdjKind.trap]));
      // 최종 상태도 전치 관계
      expect(simT.heroPos, _transposePos(sim.heroPos));
      expect(simT.hp, sim.hp);
      expect(simT.map.monsters.length, sim.map.monsters.length);
      for (final m in sim.map.monsters.values) {
        final mT = simT.map.monsters[_transposePos(m.pos)];
        expect(mT, isNotNull);
        expect(mT!.type, m.type);
        expect(mT.hp, m.hp);
      }
    });

    test('랜덤 배치 × 랜덤 워크 30회: 전 구간 특징 축 교환 + 보상 시퀀스·결과 동일', () {
      final rng = Random(2024);
      var episodes = 0;
      var totalSteps = 0;
      for (var trial = 0; trial < 30; trial++) {
        final map = GridMap();
        final mapT = GridMap();
        final cells = GridMap.placeableCells()..shuffle(rng);
        final n = 4 + rng.nextInt(12);
        for (final p in cells.take(n)) {
          final t = MonsterType.values[rng.nextInt(MonsterType.values.length)];
          expect(map.place(t, p), isTrue);
          expect(mapT.place(t, _transposePos(p)), isTrue);
        }
        final hero = HeroStats.forWave(1 + rng.nextInt(Balance.totalWaves));
        // 행동열을 먼저 뽑아 두 시뮬에 동일하게 적용 (rng 소비 순서 무관하게 검증)
        final actions = List<HeroAction>.generate(
          Balance.maxSteps,
          (_) => rng.nextInt(3) == 0
              ? HeroAction.values[rng.nextInt(HeroAction.values.length)]
              : (rng.nextBool() ? right : down),
        );
        final sim = GameSim(map, hero);
        final simT = GameSim(mapT, hero);
        final (feats, rewards) = _trace(sim, actions);
        final (featsT, rewardsT) = _trace(simT, actions.map(_transpose).toList());
        expect(rewardsT, rewards, reason: 'trial $trial');
        expect(feats.length, featsT.length, reason: 'trial $trial');
        for (var i = 0; i < feats.length; i++) {
          final f = feats[i], g = featsT[i];
          expect(g.goalDx, f.goalDy, reason: 'trial $trial step $i');
          expect(g.goalDy, f.goalDx, reason: 'trial $trial step $i');
          expect(g.adj[up.index], f.adj[left.index], reason: 'trial $trial step $i');
          expect(g.adj[left.index], f.adj[up.index], reason: 'trial $trial step $i');
          expect(g.adj[down.index], f.adj[right.index], reason: 'trial $trial step $i');
          expect(g.adj[right.index], f.adj[down.index], reason: 'trial $trial step $i');
          expect(g.hpBucket, f.hpBucket, reason: 'trial $trial step $i');
          expect(g.hasPotion, f.hasPotion, reason: 'trial $trial step $i');
          expect(g.lastMove, f.lastMove == null ? isNull : _transpose(f.lastMove!), reason: 'trial $trial step $i');
        }
        expect(sim.done, isTrue, reason: '80턴이면 반드시 종료');
        expect(simT.outcome, sim.outcome, reason: 'trial $trial');
        expect(simT.steps, sim.steps);
        expect(simT.kills, sim.kills);
        expect(simT.trapHits, sim.trapHits);
        expect(simT.hpLost, sim.hpLost);
        expect(simT.trail.map(_transposePos).toList(), sim.trail);
        episodes++;
        totalSteps += sim.steps;
      }
      expect(episodes, 30);
      expect(totalSteps, greaterThan(300));
    });
  });

  group('(c) 약함/강함 판정 (hp ≤ 2 × ATK)', () {
    /// 마물을 (2,0)에 두고 용사를 (1,0)까지 보낸 뒤 adj[right] 분류를 돌려준다.
    AdjKind adjRightOf(MonsterType t, HeroStats hero) {
      final map = GridMap();
      expect(map.place(t, const Pos(2, 0)), isTrue);
      final sim = GameSim(map, hero);
      expect(sim.step(right).outcome, Outcome.running);
      expect(sim.heroPos, const Pos(1, 0));
      final f = FeatureEncoder.features(sim);
      expect(FeatureEncoder.encode(sim), FeatureEncoder.indexOf(f));
      return f.adj[right.index];
    }

    test('슬라임(10) vs ATK 8 → weakMonster', () {
      final hero = HeroStats.forWave(1);
      expect(hero.atk, 8);
      expect(monsterSpecs[MonsterType.slime]!.hp, 10);
      expect(adjRightOf(MonsterType.slime, hero), AdjKind.weakMonster);
    });

    test('오크(40) vs ATK 8 → strongMonster', () {
      final hero = HeroStats.forWave(1);
      expect(hero.atk, 8);
      expect(monsterSpecs[MonsterType.orc]!.hp, 40);
      expect(adjRightOf(MonsterType.orc, hero), AdjKind.strongMonster);
    });

    test('오크(40) vs ATK 20(웨이브 13) → weakMonster (경계 40 ≤ 2×20)', () {
      final hero = HeroStats.forWave(13);
      expect(hero.atk, 20, reason: 'PLAN §3: 웨이브 13부터 오크가 약함');
      expect(adjRightOf(MonsterType.orc, hero), AdjKind.weakMonster);
      // 바로 아래 웨이브 12(ATK 19)는 아직 강함
      expect(HeroStats.forWave(12).atk, 19);
      expect(adjRightOf(MonsterType.orc, HeroStats.forWave(12)), AdjKind.strongMonster);
    });

    test('고블린(24): 웨이브 5(ATK 12)부터 약함, 웨이브 4(ATK 11)는 강함', () {
      expect(HeroStats.forWave(5).atk, 12);
      expect(adjRightOf(MonsterType.goblin, HeroStats.forWave(5)), AdjKind.weakMonster);
      expect(adjRightOf(MonsterType.goblin, HeroStats.forWave(4)), AdjKind.strongMonster);
    });

    test('다친 오크: 한 대 맞아 HP 32면 ATK 16(웨이브 9)에서 약함으로 바뀐다', () {
      final map = GridMap();
      expect(map.place(MonsterType.orc, const Pos(2, 0)), isTrue);
      final hero = HeroStats.forWave(9);
      expect(hero.atk, 16);
      final sim = GameSim(map, hero);
      sim.step(right);
      expect(FeatureEncoder.features(sim).adj[right.index], AdjKind.strongMonster, reason: '40 > 32');
      sim.step(right); // 공격 → 오크 24
      expect(sim.map.monsters[const Pos(2, 0)]!.hp, 24);
      expect(FeatureEncoder.features(sim).adj[right.index], AdjKind.weakMonster, reason: '24 ≤ 32');
    });
  });

  group('(d) QTablePolicy ε=0 은 세팅한 Q값의 argmax 행동을 고른다', () {
    test('입구 상태에서 각 행동에 최댓값을 주면 그 행동이 나온다 (물약 포함)', () {
      final table = QTable();
      final policy = QTablePolicy(table, epsilon: 0);
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final s = FeatureEncoder.encode(sim);
      final rng = Random(1);
      for (final a in HeroAction.values) {
        for (final b in HeroAction.values) {
          table.set(s, b.index, b == a ? 3.5 : -1.0);
        }
        expect(policy.act(sim, rng), a, reason: '${a.name}에 최댓값');
        expect(policy.qValues(sim), table.row(s));
        expect(policy.qValues(sim)[a.index], 3.5);
      }
      // rng를 바꿔도 단독 최대는 결정론
      for (var seed = 0; seed < 20; seed++) {
        expect(policy.act(sim, Random(seed)), potion);
      }
    });

    test('상태가 바뀌면 그 상태의 Q값을 따른다 (다른 상태의 값은 영향 없음)', () {
      final table = QTable();
      final policy = QTablePolicy(table, epsilon: 0);
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final rng = Random(3);
      final s0 = FeatureEncoder.encode(sim);
      table.set(s0, down.index, 1.0);
      expect(policy.act(sim, rng), down);
      sim.step(down); // (0,1)
      final s1 = FeatureEncoder.encode(sim);
      expect(s1, isNot(s0), reason: 'lastMove가 바뀌어 다른 상태');
      table.set(s1, right.index, 9.0);
      table.set(s1, down.index, 8.9);
      expect(policy.act(sim, rng), right);
      // s0 값은 그대로
      expect(table.get(s0, down.index), 1.0);
      expect(policy.qValues(sim), [0.0, 8.9, 0.0, 9.0, 0.0].map((v) => closeTo(v, 1e-6)).toList());
    });

    test('세팅한 Q-테이블로 12턴 왕좌 도달: 빈 맵 모든 상태에 "아래→오른쪽" 경로를 가르친다', () {
      final table = QTable();
      final policy = QTablePolicy(table, epsilon: 0);
      // 학습 대신 직접 기록: 열 0에서는 down, 행 6에서는 right. 상태는 실제 시뮬을 밟아가며 인코딩한다.
      final teacher = GameSim(GridMap(), HeroStats.forWave(1));
      while (!teacher.done) {
        final s = FeatureEncoder.encode(teacher);
        final a = teacher.heroPos.y < Balance.throneY ? down : right;
        table.set(s, a.index, 1.0);
        table.markVisited(s);
        teacher.step(a);
      }
      expect(teacher.outcome, Outcome.reachedThrone);
      // 같은 테이블을 sparse JSON → 청크 왕복한 뒤 정책으로 재생
      final restored = QTable.fromChunks(table.toChunks(statesPerChunk: 4));
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final total = _playOut(sim, QTablePolicy(restored, epsilon: 0), Random(0));
      expect(sim.outcome, Outcome.reachedThrone);
      expect(sim.steps, 12);
      expect(total, closeTo(Balance.rThrone + Balance.rStep * 12, 1e-9));
      expect(sim.trail, teacher.trail);
      expect(policy.name, 'qtable');
    });
  });

  group('(e) evalSet(42, 300) × GreedyPolicy 완주', () {
    test('300개 전부 예외 없이 종료, 결과 분포 출력', () {
      final set = LayoutGenerator.evalSet(seed: 42, size: 300);
      expect(set.length, 300);
      const policy = GreedyPolicy();
      final counts = <Outcome, int>{for (final o in Outcome.values) o: 0};
      var totalSteps = 0;
      var totalTrapHits = 0;
      var totalKills = 0;
      var totalPotions = 0;
      var totalReturn = 0.0;
      for (var i = 0; i < set.length; i++) {
        final (map, hero) = set[i];
        final before = map.toJson().toString();
        final sim = GameSim(map, hero);
        final ret = _playOut(sim, policy, Random(i));
        expect(sim.done, isTrue, reason: 'evalSet[$i]');
        expect(sim.outcome, isNot(Outcome.running), reason: 'evalSet[$i]');
        expect(sim.steps, inInclusiveRange(1, Balance.maxSteps), reason: 'evalSet[$i]');
        expect(sim.hp, inInclusiveRange(0, hero.maxHp), reason: 'evalSet[$i]');
        expect(map.toJson().toString(), before, reason: 'GameSim은 원본 맵을 바꾸지 않는다 (evalSet[$i])');
        counts[sim.outcome] = counts[sim.outcome]! + 1;
        totalSteps += sim.steps;
        totalTrapHits += sim.trapHits;
        totalKills += sim.kills;
        totalPotions += sim.potionsUsed;
        totalReturn += ret;
      }
      final wins = counts[Outcome.reachedThrone]!;
      final deaths = counts[Outcome.heroDied]!;
      final retreats = counts[Outcome.gaveUp]!;
      expect(wins + deaths + retreats, 300);
      expect(counts[Outcome.running], 0);
      // ignore: avoid_print
      print('[integration (e)] evalSet(42,300) GreedyPolicy: 승(왕좌) $wins / 사망 $deaths / 퇴각(80턴) $retreats | '
          '평균 턴 ${(totalSteps / 300).toStringAsFixed(1)}, 함정 ${(totalTrapHits / 300).toStringAsFixed(2)}, '
          '처치 ${(totalKills / 300).toStringAsFixed(2)}, 물약 ${(totalPotions / 300).toStringAsFixed(2)}, '
          '평균 리턴 ${(totalReturn / 300).toStringAsFixed(1)}');
      // 단순 확인: 직진 돌격형은 빈 곳이 많은 easy에서 대부분 이기고, 어딘가에서는 죽어야 정상(마물이 실제로 작동)
      expect(wins, greaterThan(0));
      expect(deaths + retreats, greaterThan(0));
    });

    test('같은 evalSet 항목을 같은 시드로 두 번 돌리면 트레일·결과 동일 (결정론)', () {
      final set = LayoutGenerator.evalSet(seed: 42, size: 300);
      for (final i in [0, 99, 100, 199, 200, 299]) {
        final (map, hero) = set[i];
        final a = GameSim(map, hero);
        final b = GameSim(map, hero);
        _playOut(a, const GreedyPolicy(), Random(7));
        _playOut(b, const GreedyPolicy(), Random(7));
        expect(b.outcome, a.outcome, reason: 'evalSet[$i]');
        expect(b.trail, a.trail, reason: 'evalSet[$i]');
        expect(b.hp, a.hp, reason: 'evalSet[$i]');
      }
    });
  });

  group('(f) 성능', () {
    test('빈 맵 + medium 배치 1,000 에피소드 (GreedyPolicy, 매 스텝 encode) 총 시간 출력 — 목표 ≤ 1ms/에피소드', () {
      final empty = GridMap();
      final medium = LayoutGenerator().generate(Tier.medium, Random(42));
      expect(medium.monsters, isNotEmpty);
      final maps = [empty, medium];
      const policy = GreedyPolicy();
      final hero = HeroStats.forWave(6);

      // JIT 워밍업 (측정 제외)
      for (var i = 0; i < 200; i++) {
        _playOut(GameSim(maps[i % 2], hero), policy, Random(i));
      }

      const episodes = 1000;
      var steps = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < episodes; i++) {
        final sim = GameSim(maps[i % 2], hero);
        _playOut(sim, policy, Random(i));
        steps += sim.steps;
      }
      sw.stop();
      final perEpisodeUs = sw.elapsedMicroseconds / episodes;
      final perStepUs = sw.elapsedMicroseconds / steps;
      // ignore: avoid_print
      print('[integration (f)] $episodes 에피소드(빈 맵/medium 교대, 총 $steps 스텝): '
          '${sw.elapsedMilliseconds} ms 총, 에피소드당 ${perEpisodeUs.toStringAsFixed(1)} µs, '
          '스텝당 ${perStepUs.toStringAsFixed(2)} µs'
          '${perEpisodeUs > 1000 ? '  ← 목표(1ms/에피소드) 초과, 보고 필요' : '  (목표 1ms/에피소드 이내)'}');
      expect(steps, greaterThan(episodes * 5), reason: '에피소드가 실제로 진행됐는지');
      // 목표 초과는 실패로 만들지 않는다(환경 편차). 단 터무니없는 회귀(100배)는 잡는다.
      expect(perEpisodeUs, lessThan(100 * 1000));
    });
  });
}
