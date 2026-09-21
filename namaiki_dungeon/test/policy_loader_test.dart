import 'dart:convert';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namaiki_dungeon/services/policy_loader.dart';

/// 작은 가짜 정책 JSON: 상태 7 에서 '아래'(index 1) 가 최댓값, 상태 42 에서 '물약'(index 4) 이 최댓값.
String fakePolicyJson(int stage, {bool withMeta = true}) {
  final q = QTable()
    ..set(7, 0, 1.0)
    ..set(7, 1, 9.5)
    ..set(7, 2, -2.0)
    ..set(42, 4, 3.25)
    ..markVisited(7)
    ..markVisited(42);
  final j = <String, dynamic>{
    if (withMeta)
      'meta': {
        'stage': stage,
        'name': 'fake_stage$stage',
        'episodes': 12000 * stage,
        'winRate': 0.2 * stage,
        'avgSteps': 30.5,
        'trapHits': 0.4,
        'potionsUsed': 1.1,
        'kills': 2.0,
      },
    'q': jsonDecode(q.toSparseJson()),
  };
  return jsonEncode(j);
}

void main() {
  test('정상 파일: QTablePolicy 복원 + 메타 파싱', () async {
    final r = await loadAssetPoliciesWithMeta(load: (path) async => fakePolicyJson(int.parse(path[path.length - 6])));
    expect(r.policies.length, 3);
    for (var s = 1; s <= 3; s++) {
      final p = r.policies[s];
      expect(p, isA<QTablePolicy>(), reason: 'stage $s');
      final t = (p as QTablePolicy).table;
      expect(t.get(7, 1), closeTo(9.5, 0.01));
      expect(t.get(42, 4), closeTo(3.25, 0.01));
      expect(t.get(7, 2), closeTo(-2.0, 0.01));
      final m = r.meta[s];
      expect(m, isNotNull);
      expect(m!.stage, s);
      expect(m.episodes, 12000 * s);
      expect(m.winRate, closeTo(0.2 * s, 1e-9));
      expect(m.name, 'fake_stage$s');
      expect(m.avgSteps, 30.5);
      expect(m.kills, 2.0);
    }
  });

  test('파일 없음(예외) → GreedyPolicy 폴백 + 메타 없음', () async {
    final r = await loadAssetPoliciesWithMeta(load: (path) async => throw Exception('missing $path'));
    expect(r.policies.length, 3);
    for (var s = 1; s <= 3; s++) {
      expect(r.policies[s], isA<GreedyPolicy>());
      expect(r.meta.containsKey(s), isFalse);
    }
  });

  test('일부만 깨짐: 깨진 단계만 Greedy, 나머지는 QTable', () async {
    final r = await loadAssetPoliciesWithMeta(load: (path) async {
      if (path.contains('stage2')) return '{not json';
      if (path.contains('stage3')) return jsonEncode({'meta': {'stage': 3}}); // q 없음
      return fakePolicyJson(1);
    });
    expect(r.policies[1], isA<QTablePolicy>());
    expect(r.policies[2], isA<GreedyPolicy>());
    expect(r.policies[3], isA<GreedyPolicy>());
    expect(r.meta.keys, [1]);
  });

  test('메타 없는 정상 파일: 정책은 QTable, 메타 키 없음, 이름은 기본값', () async {
    final r = await loadAssetPoliciesWithMeta(load: (_) async => fakePolicyJson(1, withMeta: false));
    expect(r.policies[2], isA<QTablePolicy>());
    expect((r.policies[2] as QTablePolicy).name, 'qtable_stage2');
    expect(r.meta, isEmpty);
  });

  test('parsePolicyJson: q 가 문자열(중첩 인코딩)이어도 복원', () {
    final q = QTable()
      ..set(3, 2, 4.0)
      ..markVisited(3);
    final text = jsonEncode({'q': q.toSparseJson()});
    final r = parsePolicyJson(text, stage: 1);
    expect(r, isNotNull);
    expect((r!.$1 as QTablePolicy).table.get(3, 2), closeTo(4.0, 0.01));
    expect(r.$2, isNull);
  });

  test('loadAssetPolicySources: PolicySource 어댑터 (학습/폴백 메타)', () async {
    final r = await loadAssetPolicySources(load: (path) async {
      if (path.contains('stage3')) throw Exception('missing');
      return fakePolicyJson(int.parse(path[path.length - 6]));
    });
    expect(r.length, 3);
    expect(r[1]!.isLearned, isTrue);
    expect(r[1]!.source, 'assets');
    expect(r[1]!.stage, 1);
    expect(r[1]!.episodes, 12000);
    expect(r[1]!.winRate, closeTo(0.2, 1e-9));
    expect(r[1]!.stateCount, 2);
    expect(r[3]!.isLearned, isFalse);
    expect(r[3]!.source, 'greedy');
    expect(r[3]!.stage, 3);
  });

  test('policyAssetPath 형식', () {
    expect(policyAssetPath(2), 'assets/policies/policy_stage2.json');
  });
}
