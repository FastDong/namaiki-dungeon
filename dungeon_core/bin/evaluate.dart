import 'dart:convert';
import 'dart:io';

import 'package:dungeon_core/dungeon_core.dart';

/// 체크포인트 평가 + 단계 선정 CLI.
///
/// ```
/// dart run bin/evaluate.dart [--out out] [--eval-size 300] [--eval-seed 42]
/// ```
/// out/checkpoints/ep_*.json 전부를 고정 평가셋(LayoutGenerator.evalSet)에서 ε=Balance.epsPlay로 평가하고
/// 표를 출력한 뒤 Evaluator.selectStages로 3단계를 골라 out/policy_stage{1,2,3}.json + out/eval.json을 쓴다.
Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts.containsKey('help') || opts.containsKey('h')) {
    print(_usage);
    return;
  }
  final out = opts['out'] ?? 'out';
  final evalSize = _intOpt(opts, 'eval-size', 300);
  final evalSeed = _intOpt(opts, 'eval-seed', 42);

  final ckDir = Directory('$out${Platform.pathSeparator}checkpoints');
  if (!ckDir.existsSync()) {
    stderr.writeln('체크포인트 폴더가 없음: ${ckDir.path}');
    exitCode = 66;
    return;
  }
  final files = <(int, File)>[];
  final re = RegExp(r'^ep_(\d+)\.json$');
  for (final e in ckDir.listSync()) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last;
    final m = re.firstMatch(name);
    if (m == null) continue;
    files.add((int.parse(m.group(1)!), e));
  }
  if (files.isEmpty) {
    stderr.writeln('ep_*.json 체크포인트가 없음: ${ckDir.path}');
    exitCode = 66;
    return;
  }
  files.sort((a, b) => a.$1.compareTo(b.$1));

  final set = LayoutGenerator.evalSet(seed: evalSeed, size: evalSize);
  print('evaluate: out=$out checkpoints=${files.length} evalSet=${set.length} (seed $evalSeed) '
      'eps=${Balance.epsPlay}');

  final sw = Stopwatch()..start();
  final ckpts = <(int, EvalStats)>[];
  final demoByEp = <int, bool>{};
  final statesByEp = <int, int>{};

  print(_header);
  for (final (ep, file) in files) {
    final q = QTable.fromSparseJson(file.readAsStringSync());
    final policy = QTablePolicy(q, epsilon: Balance.epsPlay);
    final stats = Evaluator.evaluate(policy, set);
    final demo = Evaluator.runDemo(policy);
    ckpts.add((ep, stats));
    demoByEp[ep] = demo;
    statesByEp[ep] = q.visitedCount;
    print(_row(ep, stats, demo, q.visitedCount));
  }
  print('평가 소요: ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

  final sel = Evaluator.selectStages(ckpts);
  final rule = sel['rule'] == Evaluator.ruleQuantile ? 'quantile' : 'threshold';
  final stageEps = [sel['stage1']!, sel['stage2']!, sel['stage3']!];
  final statsByEp = {for (final (ep, s) in ckpts) ep: s};

  print('');
  print('단계 선정 (rule=$rule):');
  final demoResults = <String, bool>{};
  for (var i = 0; i < 3; i++) {
    final stage = i + 1;
    final ep = stageEps[i];
    final stats = statsByEp[ep]!;
    final demo = demoByEp[ep]!;
    demoResults['stage$stage'] = demo;
    print('  stage$stage ${Evaluator.stageNames[i]}: ep=$ep winRate=${_pct(stats.winRate)} '
        'avgSteps=${stats.avgSteps.toStringAsFixed(1)} demo=${demo ? '승' : '패'} states=${statesByEp[ep]}');

    final meta = <String, dynamic>{
      'stage': stage,
      'name': Evaluator.stageNames[i],
      'algorithm': 'tabular_q_learning',
      'featureSpecVersion': Balance.featureSpecVersion,
      'episodes': ep,
      'winRate': stats.winRate,
      'avgSteps': stats.avgSteps,
      'trapHits': stats.trapHits,
      'potionsUsed': stats.potionsUsed,
      'kills': stats.kills,
      'stateCount': statesByEp[ep],
      'selectionRule': rule,
    };
    // 체크포인트 파일이 곧 toSparseJson 출력이므로 파싱 없이 그대로 "q" 값으로 끼워 넣는다.
    final sparse = files.firstWhere((f) => f.$1 == ep).$2.readAsStringSync();
    final path = '$out${Platform.pathSeparator}policy_stage$stage.json';
    File(path).writeAsStringSync('{"meta":${jsonEncode(meta)},"q":$sparse}');
    final mb = File(path).lengthSync() / (1024 * 1024);
    print('    → $path (${mb.toStringAsFixed(2)} MB)');
  }

  final evalJson = <String, dynamic>{
    'evalSize': set.length,
    'evalSeed': evalSeed,
    'epsPlay': Balance.epsPlay,
    'checkpoints': [
      for (final (ep, s) in ckpts)
        {'episode': ep, 'stats': s.toJson(), 'demo': demoByEp[ep], 'stateCount': statesByEp[ep]},
    ],
    'stages': {'stage1': stageEps[0], 'stage2': stageEps[1], 'stage3': stageEps[2]},
    'demo': demoResults,
    'selectionRule': rule,
  };
  final evalPath = '$out${Platform.pathSeparator}eval.json';
  File(evalPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evalJson));
  print('  → $evalPath');
}

const String _usage = '''
dart run bin/evaluate.dart [options]
  --out DIR        학습 산출물 폴더 (기본 out; out/checkpoints/ep_*.json 을 읽음)
  --eval-size N    고정 평가셋 크기 (기본 300)
  --eval-seed N    고정 평가셋 시드 (기본 42)
''';

const String _header = '  episode | winRate | avgSteps | trapHits | potions | kills | demo | states';

String _row(int ep, EvalStats s, bool demo, int states) =>
    '${ep.toString().padLeft(9)} | ${_pct(s.winRate).padLeft(7)} | ${s.avgSteps.toStringAsFixed(1).padLeft(8)} | '
    '${s.trapHits.toStringAsFixed(2).padLeft(8)} | ${s.potionsUsed.toStringAsFixed(2).padLeft(7)} | '
    '${s.kills.toStringAsFixed(2).padLeft(5)} | ${(demo ? '승' : '패').padLeft(3)} | $states';

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

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
