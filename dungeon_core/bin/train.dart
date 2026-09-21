import 'dart:io';

import 'package:dungeon_core/dungeon_core.dart';

/// 학습 CLI.
///
/// ```
/// dart run bin/train.dart [--episodes 200000] [--seed 7] [--out out] [--tier easy|medium|hard|adversarial|fixed]
///                         [--smoke] [--checkpoint-every 2000] [--explore-potion]
/// ```
/// --smoke: 체크포인트 파일을 쓰지 않고, 첫 500ep vs 마지막 500ep 승률을 출력. 상승이면 exit 0, 아니면 exit 2.
/// --explore-potion: ε-탐색 무작위 행동에 HP 100%의 물약도 포함(순수 5행동 균등). 기본은 제외(TrainConfig 참조).
Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts.containsKey('help') || opts.containsKey('h')) {
    print(_usage);
    return;
  }

  final episodes = _intOpt(opts, 'episodes', 200000);
  final seed = _intOpt(opts, 'seed', 7);
  final out = opts['out'] ?? 'out';
  final checkpointEvery = _intOpt(opts, 'checkpoint-every', Balance.checkpointEvery);
  final smoke = opts.containsKey('smoke');
  final explorePotion = opts.containsKey('explore-potion');
  Tier? tier;
  final tierName = opts['tier'];
  if (tierName != null) {
    tier = Tier.values.where((t) => t.name == tierName).firstOrNull;
    if (tier == null) {
      stderr.writeln('알 수 없는 tier: $tierName (easy|medium|hard|adversarial|fixed)');
      exitCode = 64;
      return;
    }
  }

  const smokeWindow = 500;
  final config = TrainConfig(
    episodes: episodes,
    seed: seed,
    checkpointEvery: checkpointEvery,
    outDir: out,
    onlyTier: tier,
    smoke: smoke,
    explorePotionAtFullHp: explorePotion,
  );
  print('train: episodes=$episodes seed=$seed out=$out tier=${tier?.name ?? 'curriculum'} '
      'smoke=$smoke checkpointEvery=$checkpointEvery explorePotionAtFullHp=$explorePotion');

  // 스모크 통계: 첫 500 / 마지막 500 에피소드 승수.
  var firstWins = 0;
  var lastWins = 0;
  var lastCount = 0;
  final lastStart = episodes - smokeWindow + 1;

  final sw = Stopwatch()..start();
  var checkpoints = 0;
  final q = await Trainer(config).run(
    onCheckpoint: (ep, q, p) => checkpoints++,
    onEpisode: (ep, won, ret, steps) {
      if (ep <= smokeWindow && won) firstWins++;
      if (ep >= lastStart) {
        lastCount++;
        if (won) lastWins++;
      }
    },
  );
  sw.stop();

  final secs = sw.elapsedMilliseconds / 1000;
  print('done: $episodes episodes in ${secs.toStringAsFixed(1)}s '
      '(${(episodes / (secs == 0 ? 1 : secs)).toStringAsFixed(0)} ep/s), '
      'states=${q.visitedCount}, checkpoints=$checkpoints');

  if (smoke) {
    final firstN = episodes < smokeWindow ? episodes : smokeWindow;
    final firstRate = firstWins / firstN;
    final lastRate = lastCount == 0 ? 0.0 : lastWins / lastCount;
    print('smoke: first$firstN winRate=${firstRate.toStringAsFixed(3)} '
        'last$lastCount winRate=${lastRate.toStringAsFixed(3)}');
    if (lastRate > firstRate) {
      print('smoke: PASS (승률 상승)');
      exitCode = 0;
    } else {
      print('smoke: FAIL (승률 상승 없음)');
      exitCode = 2;
    }
  } else {
    print('outputs: $out/checkpoints/ep_N.json, $out/curve.csv');
  }
}

const String _usage = '''
dart run bin/train.dart [options]
  --episodes N          총 에피소드 (기본 200000)
  --seed N              난수 시드 (기본 7)
  --out DIR             산출물 폴더 (기본 out)
  --tier NAME           easy|medium|hard|adversarial|fixed (기본: 커리큘럼)
  --smoke               파일 미출력 + 첫/마지막 500ep 승률 비교 (상승 exit 0, 아니면 2)
  --checkpoint-every N  체크포인트 간격 (기본 2000)
  --explore-potion      ε-탐색 무작위 행동에 HP 100% 물약 포함 (기본: 제외)
''';

/// `--key value`, `--key=value`, `--flag` 를 수동 파싱. 플래그는 값 ''.
Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    var a = args[i];
    if (!a.startsWith('--')) continue;
    a = a.substring(2);
    final eq = a.indexOf('=');
    if (eq >= 0) {
      out[a.substring(0, eq)] = a.substring(eq + 1);
    } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[a] = args[++i];
    } else {
      out[a] = '';
    }
  }
  return out;
}

int _intOpt(Map<String, String> opts, String key, int def) {
  final v = opts[key];
  if (v == null || v.isEmpty) return def;
  final n = int.tryParse(v);
  if (n == null) {
    stderr.writeln('--$key 값이 정수가 아님: $v');
    exit(64);
  }
  return n;
}
