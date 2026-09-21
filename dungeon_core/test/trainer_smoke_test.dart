import 'dart:io';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

/// M3 Trainer 스모크 (PLAN.md §11 M3): 마물 0개 고정 맵에서 500ep 학습 후 ε=0 정책이 12턴에 왕좌 도달.
///
/// 12턴 판정은 물약 0개 용사로 한다. 물약 2개 용사는 500ep에서 "물약을 먼저 써서(−4×2) 잘 학습된
/// hasPotion=0 영역으로 들어가는" 탐색 부족 인공물이 생겨 14턴이 되기 때문(승리 자체는 유지).
/// 무작위 탐색 단계에서는 물약이 ~10턴 안에 소진돼 왕좌 근처의 hasPotion=1 상태가 거의 방문되지 않는다.

/// [sim]을 [policy]로 끝까지 진행.
void _playOut(GameSim sim, HeroPolicy policy, Random rng) {
  while (!sim.done) {
    sim.step(policy.act(sim, rng));
  }
}

/// 물약 없는 1웨이브 용사.
final HeroStats _noPotionHero = HeroStats(Balance.heroHp(1), Balance.heroAtk(1), 0);

void main() {
  group('Trainer 스모크', () {
    late QTable q;

    setUpAll(() async {
      final trainer = Trainer(
        const TrainConfig(episodes: 500, seed: 1, onlyTier: Tier.easy, smoke: true, verbose: false),
        mapProvider: (tier, rng) => GridMap(),
        heroProvider: (tier, rng) => _noPotionHero,
      );
      q = await trainer.run();
    });

    test('마물 0 고정 맵 500ep → ε=0 정책이 12턴에 왕좌 도달', () {
      final policy = QTablePolicy(q, epsilon: 0);
      for (final seed in [1, 2, 3]) {
        final sim = GameSim(GridMap(), _noPotionHero);
        _playOut(sim, policy, Random(seed));
        expect(sim.outcome, Outcome.reachedThrone, reason: 'seed $seed');
        expect(sim.steps, Pos.entrance.manhattan(Pos.throne), reason: 'seed $seed: 최단 12턴');
      }
    });

    test('물약 2개 용사(forWave 1)로 500ep 학습해도 ε=0 정책이 왕좌에 도달한다', () async {
      final q2 = await Trainer(
        const TrainConfig(episodes: 500, seed: 1, onlyTier: Tier.easy, smoke: true, verbose: false),
        mapProvider: (tier, rng) => GridMap(),
        heroProvider: (tier, rng) => HeroStats.forWave(1),
      ).run();
      final policy = QTablePolicy(q2, epsilon: 0);
      for (final seed in [1, 2, 3]) {
        final sim = GameSim(GridMap(), HeroStats.forWave(1));
        _playOut(sim, policy, Random(seed));
        expect(sim.outcome, Outcome.reachedThrone, reason: 'seed $seed');
        // 물약 낭비 인공물(위 주석)로 최단 12턴보다 몇 턴 더 걸릴 수 있다.
        expect(sim.steps, lessThanOrEqualTo(Pos.entrance.manhattan(Pos.throne) + Balance.potions), reason: 'seed $seed');
      }
    });

    test('방문 상태가 기록되고 sparse JSON 왕복이 가능하다', () {
      expect(q.visitedCount, greaterThan(0));
      final back = QTable.fromSparseJson(q.toSparseJson());
      expect(back.visitedCount, q.visitedCount);
    });

    test('낙관 초기값: 최초 방문 상태의 왕좌 방향 이동 행동만 +optimisticInit', () {
      final fresh = QTable();
      // goalDx=+1, goalDy=+1, 사방 empty, hp 3, potion, lastMove none.
      final s = FeatureEncoder.indexOf(const StateFeatures(
        goalDx: 1,
        goalDy: 1,
        adj: [AdjKind.empty, AdjKind.empty, AdjKind.empty, AdjKind.empty],
        hpBucket: 3,
        hasPotion: true,
        lastMove: null,
      ));
      Trainer.applyOptimisticInit(fresh, s);
      expect(fresh.row(s), [0, Balance.optimisticInit, 0, Balance.optimisticInit, 0]);
      expect(fresh.isVisited(s), isTrue);
      // 두 번째 호출은 아무 것도 하지 않는다.
      Trainer.applyOptimisticInit(fresh, s);
      expect(fresh.row(s), [0, Balance.optimisticInit, 0, Balance.optimisticInit, 0]);

      final s2 = FeatureEncoder.indexOf(const StateFeatures(
        goalDx: -1,
        goalDy: 0,
        adj: [AdjKind.wall, AdjKind.empty, AdjKind.empty, AdjKind.empty],
        hpBucket: 0,
        hasPotion: false,
        lastMove: HeroAction.down,
      ));
      Trainer.applyOptimisticInit(fresh, s2);
      expect(fresh.row(s2), [0, 0, Balance.optimisticInit, 0, 0]);
    });
  });

  group('Trainer 체크포인트', () {
    test('onCheckpoint/onEpisode 호출 횟수와 CurvePoint 내용', () async {
      final points = <CurvePoint>[];
      var episodesSeen = 0;
      final q = await Trainer(
        const TrainConfig(episodes: 50, seed: 3, checkpointEvery: 20, onlyTier: Tier.easy, smoke: true, verbose: false),
      ).run(
        onCheckpoint: (ep, q, p) {
          expect(ep, p.episode);
          points.add(p);
        },
        onEpisode: (ep, won, ret, steps) {
          episodesSeen++;
          expect(ep, episodesSeen);
          expect(steps, inInclusiveRange(1, Balance.maxSteps));
        },
      );
      expect(episodesSeen, 50);
      // 20, 40, 그리고 마지막 50 (배수가 아니어도 마지막에 한 번).
      expect(points.map((p) => p.episode).toList(), [20, 40, 50]);
      for (final p in points) {
        expect(p.winRate, inInclusiveRange(0.0, 1.0));
        expect(p.avgSteps, inInclusiveRange(1.0, Balance.maxSteps.toDouble()));
        expect(p.tier, 'easy');
      }
      expect(q.visitedCount, greaterThan(0));
    });

    test('smoke가 아니면 outDir/checkpoints/ep_N.json + curve.csv(헤더 1회)를 쓴다', () async {
      final dir = Directory.systemTemp.createTempSync('trainer_test_');
      try {
        await Trainer(
          TrainConfig(
            episodes: 40,
            seed: 5,
            checkpointEvery: 20,
            onlyTier: Tier.easy,
            outDir: dir.path,
            verbose: false,
          ),
        ).run();
        final ck20 = File('${dir.path}${Platform.pathSeparator}checkpoints${Platform.pathSeparator}ep_20.json');
        final ck40 = File('${dir.path}${Platform.pathSeparator}checkpoints${Platform.pathSeparator}ep_40.json');
        expect(ck20.existsSync(), isTrue);
        expect(ck40.existsSync(), isTrue);
        final loaded = QTable.fromSparseJson(ck40.readAsStringSync());
        expect(loaded.visitedCount, greaterThan(0));

        final csv = File('${dir.path}${Platform.pathSeparator}curve.csv').readAsLinesSync();
        expect(csv.first, CurvePoint.csvHeader);
        expect(csv.length, 3);
        expect(csv.where((l) => l == CurvePoint.csvHeader).length, 1);
        expect(csv[1].startsWith('20,'), isTrue);
        expect(csv[2].startsWith('40,'), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('같은 시드면 결과가 동일하다 (결정론)', () async {
      Future<String> once() async {
        final q = await Trainer(
          const TrainConfig(episodes: 30, seed: 11, checkpointEvery: 30, smoke: true, verbose: false),
        ).run();
        return q.toSparseJson();
      }

      expect(await once(), await once());
    });
  });
}
