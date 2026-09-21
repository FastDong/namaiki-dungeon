import 'dart:math';
import 'dart:typed_data';

import 'balance.dart';
import 'feature_encoder.dart';
import 'game_sim.dart';
import 'grid_map.dart';
import 'layout_generator.dart';
import 'models.dart';
import 'policy.dart';
import 'qtable.dart';
import 'trainer_fs_stub.dart' if (dart.library.io) 'trainer_fs_io.dart';

/// 학습 설정. CLI 인자(bin/train.dart)에서 채운다.
class TrainConfig {
  final int episodes;
  final int seed;
  final int checkpointEvery;

  /// 체크포인트 JSON과 curve.csv를 쓰는 폴더 (예: out/). checkpoints/ep_N.json 형식.
  final String outDir;

  /// 지정하면 커리큘럼 대신 이 tier만 사용 (스모크 런용).
  final Tier? onlyTier;

  /// 스모크 모드: 체크포인트 파일을 쓰지 않고 진행 로그만 출력.
  final bool smoke;

  /// 체크포인트마다 stdout 한 줄 로그 출력 여부.
  final bool verbose;

  /// ε-탐색의 무작위 행동에 "HP가 가득 찬 상태의 물약"을 포함할지.
  ///
  /// 기본 false: HP가 가득 차 있으면 무작위 행동을 이동 4개 중에서만 고른다(탐색 행동 정책만 바뀌고
  /// MDP·보상·Q 갱신은 그대로. Q-learning은 off-policy라 최적 Q는 동일). true면 5개 균등(순수 ε-greedy).
  ///
  /// 이유: 5개 균등이면 무작위 탐색 단계에서 물약 2개가 ~10턴 안에 소진돼 hasPotion=1 상태로 왕좌에
  /// 도달하는 경험이 거의 없다 → hasPotion=1 영역이 비관적으로 남고, 그리디 정책이 "먼저 물약을 다
  /// 마셔서(−4×2) 잘 학습된 hasPotion=0 영역으로 들어가는" 자기강화 인공물이 20만 에피소드 후에도
  /// 남는다(평가셋 300판 중 118판이 2턴째에 HP 100%로 물약 2개 소모).
  final bool explorePotionAtFullHp;

  const TrainConfig({
    required this.episodes,
    this.seed = 7,
    this.checkpointEvery = 2000,
    this.outDir = 'out',
    this.onlyTier,
    this.smoke = false,
    this.verbose = true,
    this.explorePotionAtFullHp = false,
  });
}

/// 학습 곡선 한 점 (최근 checkpointEvery 에피소드 집계).
class CurvePoint {
  final int episode;
  final double winRate, avgReturn, avgSteps;
  final String tier;
  const CurvePoint(this.episode, this.winRate, this.avgReturn, this.avgSteps, this.tier);

  String toCsvRow() => '$episode,${winRate.toStringAsFixed(4)},${avgReturn.toStringAsFixed(2)},${avgSteps.toStringAsFixed(2)},$tier';
  static const String csvHeader = 'episode,winRate,avgReturn,avgSteps,tier';
}

/// 에피소드마다 학습 상대 맵을 공급하는 훅 (테스트·실험용). 기본은 LayoutGenerator.generate.
typedef MapProvider = GridMap Function(Tier tier, Random rng);

/// 에피소드마다 용사 스탯을 공급하는 훅 (테스트용). 기본은 HeroStats.forWave(LayoutGenerator.sampleWave).
typedef HeroProvider = HeroStats Function(Tier tier, Random rng);

/// 에피소드 1개 결과 콜백 (스모크 통계용). [episode]는 1부터.
typedef EpisodeCallback = void Function(int episode, bool won, double ret, int steps);

/// 표 기반 Q-learning 학습 루프 (PLAN.md §5.4~5.6).
///
/// - Q 초기값: 왕좌에 가까워지는 이동 행동 +optimisticInit, 나머지 0 (상태 최초 방문 시 적용).
/// - ε: epsStart → epsEnd, 전체의 epsDecayFraction 지점까지 선형 감소 후 고정.
/// - α: alpha, 전체의 alphaLateFraction 지점부터 alphaLate.
/// - 커리큘럼: Balance.curriculum* 상수 참조. onlyTier가 있으면 그 tier만.
/// - 에피소드마다 tier에 맞는 웨이브를 샘플해 HeroStats.forWave(w).
/// - checkpointEvery마다 onCheckpoint 호출 + (smoke가 아니면) outDir/checkpoints/ep_N.json 저장 + curve.csv 한 줄 추가.
class Trainer {
  /// [mapProvider]/[heroProvider]를 주면 LayoutGenerator 대신 그 훅으로 상대·용사를 만든다 (테스트용).
  Trainer(this.config, {MapProvider? mapProvider, HeroProvider? heroProvider})
      : _mapProvider = mapProvider,
        _heroProvider = heroProvider;

  final TrainConfig config;
  final MapProvider? _mapProvider;
  final HeroProvider? _heroProvider;

  static const int _n = FeatureEncoder.actionCount;

  /// 이동 행동 수 (potion은 HeroAction의 마지막 값이므로 앞 4개가 이동).
  static final int _moveCount = HeroAction.potion.index;

  /// 학습 실행. 반환된 QTable은 방문 상태가 모두 markVisited 되어 있다.
  ///
  /// [onCheckpoint]는 checkpointEvery마다(그리고 episodes가 배수가 아니면 마지막에 한 번 더) 호출된다.
  /// [onEpisode]는 매 에피소드 종료 시 호출된다 (bin/train.dart --smoke 통계용).
  Future<QTable> run({
    void Function(int episode, QTable q, CurvePoint p)? onCheckpoint,
    EpisodeCallback? onEpisode,
  }) async {
    final cfg = config;
    if (cfg.episodes <= 0) throw ArgumentError.value(cfg.episodes, 'episodes', '양수여야 함');
    if (cfg.checkpointEvery <= 0) throw ArgumentError.value(cfg.checkpointEvery, 'checkpointEvery', '양수여야 함');

    final rng = Random(cfg.seed);
    final gen = LayoutGenerator();
    final q = QTable();
    final raw = q.raw;
    // adversarial 배치 봇이 "현재 용사"를 상대로 롤아웃할 때 쓰는 ε=0 정책 (q를 참조하므로 1회 생성).
    final adversary = QTablePolicy(q, epsilon: 0, name: 'trainee');

    final fs = cfg.smoke ? null : TrainerFs(cfg.outDir);
    fs?.prepare(CurvePoint.csvHeader);

    final sw = Stopwatch()..start();
    final episodes = cfg.episodes;
    final double gamma = Balance.gamma;
    final explorePotion = cfg.explorePotionAtFullHp;

    // 체크포인트 창 통계
    var winWins = 0;
    var winReturn = 0.0;
    var winSteps = 0;
    var winCount = 0;
    final tierCounts = List<int>.filled(Tier.values.length, 0);

    for (var i = 0; i < episodes; i++) {
      final f = i / episodes;

      // ── 스케줄 ──
      final eps = f < Balance.epsDecayFraction
          ? Balance.epsStart + (Balance.epsEnd - Balance.epsStart) * (f / Balance.epsDecayFraction)
          : Balance.epsEnd;
      final alpha = f < Balance.alphaLateFraction ? Balance.alpha : Balance.alphaLate;

      // ── 커리큘럼 ──
      final tier = cfg.onlyTier ?? _curriculumTier(f, rng);
      tierCounts[tier.index]++;

      // ── 상대·용사 ──
      final hero = _heroProvider != null ? _heroProvider(tier, rng) : HeroStats.forWave(gen.sampleWave(tier, rng));
      final map = _mapProvider != null
          ? _mapProvider(tier, rng)
          : gen.generate(tier, rng, adversary: adversary, hero: hero);

      // ── 에피소드 ──
      final sim = GameSim(map, hero);
      var ret = 0.0;
      var s = FeatureEncoder.encode(sim);
      _ensureInit(q, raw, s);
      while (true) {
        final int a;
        if (eps > 0 && rng.nextDouble() < eps) {
          // 무작위 탐색. HP가 가득 차면(옵션) 물약(마지막 행동)을 빼고 이동 4개 중에서 고른다.
          a = (explorePotion || sim.hp < sim.maxHp) ? rng.nextInt(_n) : rng.nextInt(_moveCount);
        } else {
          a = q.argmax(s, rng);
        }
        final res = sim.step(HeroAction.values[a]);
        final r = res.reward;
        ret += r;

        var s2 = -1;
        double target;
        if (res.done) {
          target = r;
        } else {
          s2 = FeatureEncoder.encode(sim);
          _ensureInit(q, raw, s2);
          target = r + gamma * q.maxValue(s2);
        }
        final idx = s * _n + a;
        raw[idx] += alpha * (target - raw[idx]);
        q.markVisited(s);

        if (res.done) break;
        s = s2;
      }

      final won = sim.outcome == Outcome.reachedThrone;
      final steps = sim.steps;
      onEpisode?.call(i + 1, won, ret, steps);

      if (won) winWins++;
      winReturn += ret;
      winSteps += steps;
      winCount++;

      // ── 체크포인트 ──
      final ep = i + 1;
      if (ep % cfg.checkpointEvery == 0 || ep == episodes) {
        final point = CurvePoint(
          ep,
          winWins / winCount,
          winReturn / winCount,
          winSteps / winCount,
          _dominantTier(tierCounts),
        );
        if (fs != null) {
          fs.writeCheckpoint(ep, q.toSparseJson());
          fs.appendCurveRow(point.toCsvRow());
        }
        onCheckpoint?.call(ep, q, point);
        if (cfg.verbose) {
          final secs = sw.elapsedMilliseconds / 1000;
          print('ep $ep/$episodes tier=${point.tier} win=${point.winRate.toStringAsFixed(3)} '
              'ret=${point.avgReturn.toStringAsFixed(1)} steps=${point.avgSteps.toStringAsFixed(1)} '
              'eps=${eps.toStringAsFixed(3)} alpha=${alpha.toStringAsFixed(3)} '
              'states=${q.visitedCount} elapsed=${secs.toStringAsFixed(1)}s');
        }
        winWins = 0;
        winReturn = 0;
        winSteps = 0;
        winCount = 0;
        tierCounts.fillRange(0, tierCounts.length, 0);
      }
    }
    return q;
  }

  /// 커리큘럼 tier: [0, easyEnd) easy, [easyEnd, mediumEnd) medium,
  /// 이후 hard lateHardShare / adversarial lateAdversarialShare / 나머지 fixed (rng 1회 소비).
  static Tier _curriculumTier(double f, Random rng) {
    if (f < Balance.curriculumEasyEnd) return Tier.easy;
    if (f < Balance.curriculumMediumEnd) return Tier.medium;
    final u = rng.nextDouble();
    if (u < Balance.lateHardShare) return Tier.hard;
    if (u < Balance.lateHardShare + Balance.lateAdversarialShare) return Tier.adversarial;
    return Tier.fixed;
  }

  /// 창 안에서 가장 많이 쓰인 tier 이름 (동점이면 enum 순서 앞).
  static String _dominantTier(List<int> counts) {
    var best = 0;
    for (var t = 1; t < counts.length; t++) {
      if (counts[t] > counts[best]) best = t;
    }
    return Tier.values[best].name;
  }

  /// 상태 [s] 최초 방문 시 낙관 초기값: 왕좌에 가까워지는 이동 행동에 +optimisticInit, 그리고 방문 표시.
  /// 이미 방문한 상태면 아무 것도 하지 않는다.
  static void _ensureInit(QTable q, Float32List raw, int s) {
    if (q.isVisited(s)) return;
    final f = FeatureEncoder.decode(s);
    final base = s * _n;
    if (f.goalDx > 0) {
      raw[base + HeroAction.right.index] += Balance.optimisticInit;
    } else if (f.goalDx < 0) {
      raw[base + HeroAction.left.index] += Balance.optimisticInit;
    }
    if (f.goalDy > 0) {
      raw[base + HeroAction.down.index] += Balance.optimisticInit;
    } else if (f.goalDy < 0) {
      raw[base + HeroAction.up.index] += Balance.optimisticInit;
    }
    q.markVisited(s);
  }

  /// 테스트·디버그용: 낙관 초기값 적용 (공개 래퍼).
  static void applyOptimisticInit(QTable q, int s) => _ensureInit(q, q.raw, s);
}
