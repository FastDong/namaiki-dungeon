// 데모/비교용 배치 탐색: stage1 용사는 거의 항상 막히고 stage3 용사는 거의 항상 뚫는 배치를 찾는다.
// 사용: dart run bin/find_demo.dart [--out out] [--budget 30] [--wave 6] [--trials 3000] [--seeds 20]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';

void main(List<String> args) {
  String opt(String k, String d) {
    final i = args.indexOf('--$k');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : d;
  }

  final outDir = opt('out', 'out');
  final budget = int.parse(opt('budget', '30'));
  final wave = int.parse(opt('wave', '6'));
  final trials = int.parse(opt('trials', '3000'));
  final seeds = int.parse(opt('seeds', '20'));

  QTablePolicy load(int stage) {
    final j = jsonDecode(File('$outDir/policy_stage$stage.json').readAsStringSync()) as Map<String, dynamic>;
    return QTablePolicy(QTable.fromSparseJson(jsonEncode(j['q'])), epsilon: Balance.epsPlay);
  }

  final p1 = load(1), p2 = load(2), p3 = load(3);
  final hero = HeroStats.forWave(wave);
  final gen = LayoutGenerator();
  final rng = Random(2026);

  double winRate(HeroPolicy p, GridMap map) {
    var wins = 0;
    for (var s = 0; s < seeds; s++) {
      final sim = GameSim(map, hero);
      final r = Random(1000 + s);
      while (!sim.done) {
        sim.step(p.act(sim, r));
      }
      if (sim.outcome == Outcome.reachedThrone) wins++;
    }
    return wins / seeds;
  }

  double trapHits(HeroPolicy p, GridMap map) {
    var t = 0;
    for (var s = 0; s < seeds; s++) {
      final sim = GameSim(map, hero);
      final r = Random(1000 + s);
      while (!sim.done) {
        sim.step(p.act(sim, r));
      }
      t += sim.trapHits;
    }
    return t / seeds;
  }

  final tiers = [Tier.medium, Tier.hard, Tier.adversarial, Tier.fixed];
  final candidates = <(double score, GridMap map, double w1, double w2, double w3, double t1, double t3)>[];
  var tested = 0;
  for (var i = 0; i < trials; i++) {
    final tier = tiers[i % tiers.length];
    final map = gen.generate(tier, rng, adversary: p1, hero: hero);
    if (map.totalCost > budget) {
      // 예산 초과면 비싼 것부터 제거
      final ms = map.monsters.values.toList()..sort((a, b) => b.type.spec.cost.compareTo(a.type.spec.cost));
      for (final m in ms) {
        if (map.totalCost <= budget) break;
        map.remove(m.pos);
      }
    }
    tested++;
    final w1 = winRate(p1, map);
    if (w1 > 0.25) continue;
    final w3 = winRate(p3, map);
    if (w3 < 0.75) continue;
    final w2 = winRate(p2, map);
    final t1 = trapHits(p1, map), t3 = trapHits(p3, map);
    // 점수: 격차 + 함정 대비(1단계는 밟고 3단계는 피함) + 2단계가 중간
    final score = (w3 - w1) + 0.3 * (t1 - t3) + 0.2 * (1 - (w2 - 0.5).abs());
    candidates.add((score, map.clone(), w1, w2, w3, t1, t3));
  }
  candidates.sort((a, b) => b.$1.compareTo(a.$1));
  stdout.writeln('tested=$tested found=${candidates.length}');
  for (final c in candidates.take(5)) {
    final (score, map, w1, w2, w3, t1, t3) = c;
    stdout.writeln('score=${score.toStringAsFixed(2)} cost=${map.totalCost} '
        'win1=${(w1 * 100).round()}% win2=${(w2 * 100).round()}% win3=${(w3 * 100).round()}% '
        'trap1=${t1.toStringAsFixed(2)} trap3=${t3.toStringAsFixed(2)}');
    stdout.writeln('  ${jsonEncode(map.toJson())}');
    stdout.writeln('  ${map.monsters.values.map((m) => '${m.type.name}@(${m.pos.x},${m.pos.y})').join(' ')}');
  }
  if (candidates.isNotEmpty) {
    File('$outDir/demo_layout.json').writeAsStringSync(jsonEncode({
      'wave': wave,
      'budget': budget,
      'layout': candidates.first.$2.toJson(),
      'win1': candidates.first.$3,
      'win2': candidates.first.$4,
      'win3': candidates.first.$5,
    }));
    stdout.writeln('→ $outDir/demo_layout.json');
  }
}
