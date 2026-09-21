import 'dart:convert';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

const int _n = FeatureEncoder.actionCount;

/// GameSim/GridMap이 아직 스텁이면 시뮬 기반 테스트는 건너뛴다 (구현 후 자동 활성화).
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

/// 소수 [decimals]자리로 반올림한 값과 float32 오차 안에서 같은가.
Matcher _roundedTo(double v, int decimals) {
  final scale = pow(10, decimals).toDouble();
  final expected = (v * scale).round() / scale;
  return closeTo(expected, 1e-4);
}

/// 서로 다른 상태 [count]개를 랜덤으로 뽑아 랜덤 Q값을 넣고 방문 표시.
Map<int, List<double>> _fillRandom(QTable t, int count, Random rng, {double range = 150}) {
  final truth = <int, List<double>>{};
  while (truth.length < count) {
    final s = rng.nextInt(FeatureEncoder.stateCount);
    if (truth.containsKey(s)) continue;
    final row = List<double>.generate(_n, (_) => (rng.nextDouble() * 2 - 1) * range);
    for (var a = 0; a < _n; a++) {
      t.set(s, a, row[a]);
    }
    t.markVisited(s);
    truth[s] = row;
  }
  return truth;
}

void main() {
  final simSkip = _simSkipReason();

  group('기본', () {
    test('초기값 0, 방문 0, get/set/row', () {
      final t = QTable();
      expect(t.raw.length, FeatureEncoder.stateCount * _n);
      expect(t.visitedCount, 0);
      expect(t.get(0, 0), 0);
      expect(t.get(FeatureEncoder.stateCount - 1, _n - 1), 0);
      expect(t.row(123), List<double>.filled(_n, 0));

      t.set(123, 2, 1.5);
      t.set(FeatureEncoder.stateCount - 1, _n - 1, -7.25);
      expect(t.get(123, 2), 1.5);
      expect(t.row(123), [0, 0, 1.5, 0, 0]);
      expect(t.row(123).length, _n);
      expect(t.get(FeatureEncoder.stateCount - 1, _n - 1), -7.25);
      // row는 복사본
      t.row(123)[2] = 99;
      expect(t.get(123, 2), 1.5);
      // set은 방문 플래그를 건드리지 않는다
      expect(t.visitedCount, 0);
      expect(t.isVisited(123), isFalse);
    });

    test('markVisited / isVisited / visitedCount (중복 표시는 1회만 집계)', () {
      final t = QTable();
      t.markVisited(10);
      t.markVisited(10);
      t.markVisited(FeatureEncoder.stateCount - 1);
      expect(t.visitedCount, 2);
      expect(t.isVisited(10), isTrue);
      expect(t.isVisited(11), isFalse);
      expect(t.isVisited(FeatureEncoder.stateCount - 1), isTrue);
    });

    test('maxValue', () {
      final t = QTable();
      t.set(5, 0, -3);
      t.set(5, 1, 2.5);
      t.set(5, 2, 2.5);
      t.set(5, 3, -10);
      t.set(5, 4, 0);
      expect(t.maxValue(5), 2.5);
      expect(t.maxValue(6), 0);
    });

    test('clone은 독립 복사본 (값·방문 플래그)', () {
      final t = QTable();
      t.set(7, 1, 4);
      t.markVisited(7);
      final c = t.clone();
      expect(c.get(7, 1), 4);
      expect(c.isVisited(7), isTrue);
      expect(c.visitedCount, 1);
      c.set(7, 1, -1);
      c.markVisited(8);
      expect(t.get(7, 1), 4);
      expect(t.isVisited(8), isFalse);
      expect(t.visitedCount, 1);
      expect(c.visitedCount, 2);
    });
  });

  group('argmax', () {
    test('단독 최대는 항상 그 인덱스 (rng 무관)', () {
      final t = QTable();
      final rng = Random(1);
      for (var a = 0; a < _n; a++) {
        final s = 1000 + a;
        for (var b = 0; b < _n; b++) {
          t.set(s, b, -5);
        }
        t.set(s, a, 3);
        for (var k = 0; k < 50; k++) {
          expect(t.argmax(s, rng), a);
        }
      }
      // 음수뿐인 행
      t.set(2000, 0, -1);
      t.set(2000, 1, -9);
      t.set(2000, 2, -0.5);
      t.set(2000, 3, -2);
      t.set(2000, 4, -3);
      expect(t.argmax(2000, rng), 2);
    });

    test('동점이면 rng에 따라 여러 값이 나오고, 동점 후보 밖은 절대 안 나온다', () {
      final t = QTable();
      const s = 42;
      t.set(s, 0, 1);
      t.set(s, 1, 7);
      t.set(s, 2, 7);
      t.set(s, 3, 7);
      t.set(s, 4, -1);
      final rng = Random(3);
      final seen = <int>{};
      for (var k = 0; k < 300; k++) {
        final a = t.argmax(s, rng);
        expect(a, anyOf(1, 2, 3));
        seen.add(a);
      }
      expect(seen, {1, 2, 3});

      // 전부 0 (초기 상태) 이면 5개 모두 나온다
      final seen0 = <int>{};
      for (var k = 0; k < 300; k++) {
        seen0.add(t.argmax(99, rng));
      }
      expect(seen0, {0, 1, 2, 3, 4});
    });

    test('같은 시드면 같은 동점 선택 (결정론)', () {
      final t = QTable();
      final a1 = List.generate(100, (_) => t.argmax(0, Random(11)));
      final a2 = List.generate(100, (_) => t.argmax(0, Random(11)));
      expect(a1, a2);
    });
  });

  group('sparse JSON', () {
    test('형식: v/n/q, 방문 상태만, 인덱스 오름차순', () {
      final t = QTable();
      t.set(5, 0, 2);
      t.set(5, 1, -0.3);
      t.set(5, 2, 12.345);
      t.set(5, 3, 0.006); // float32 저장 후에도 0.01로 반올림 (0.005는 float32에서 0.00499…가 됨)
      t.set(5, 4, -0.004); // "-0.00" → "0"
      t.markVisited(5);
      t.markVisited(3);
      t.set(999, 0, 55); // 미방문 → 제외
      final json = t.toSparseJson();
      expect(json, '{"v":${Balance.featureSpecVersion},"n":5,"q":{"3":[0,0,0,0,0],"5":[2,-0.3,12.35,0.01,0]}}');
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['v'], Balance.featureSpecVersion);
      expect(decoded['n'], _n);
      expect((decoded['q'] as Map).keys, ['3', '5']);
    });

    test('decimals 파라미터', () {
      final t = QTable();
      t.set(1, 0, 2.678);
      t.set(1, 1, -1.5);
      t.markVisited(1);
      expect(t.toSparseJson(decimals: 0), contains('"1":[3,-2,0,0,0]'));
      expect(t.toSparseJson(decimals: 1), contains('"1":[2.7,-1.5,0,0,0]'));
      expect(t.toSparseJson(decimals: 3), contains('"1":[2.678,-1.5,0,0,0]'));
    });

    test('왕복: 방문 상태 값 동일(소수 2자리), 미방문 0, 방문 플래그 복원', () {
      final t = QTable();
      final rng = Random(5);
      final truth = _fillRandom(t, 300, rng);
      // 미방문이지만 값이 있는 상태 (낙관 초기값 흉내) → 저장되지 않아야 함
      final unvisited = <int>[];
      while (unvisited.length < 50) {
        final s = rng.nextInt(FeatureEncoder.stateCount);
        if (truth.containsKey(s) || unvisited.contains(s)) continue;
        unvisited.add(s);
        t.set(s, 0, Balance.optimisticInit);
      }
      expect(t.visitedCount, 300);

      final json = t.toSparseJson();
      final back = QTable.fromSparseJson(json);
      expect(back.visitedCount, 300);
      truth.forEach((s, row) {
        expect(back.isVisited(s), isTrue);
        for (var a = 0; a < _n; a++) {
          // 테이블은 float32 저장이므로 기준값도 저장된 값(t.get)으로 잡는다.
          expect(back.get(s, a), _roundedTo(t.get(s, a), 2), reason: 's=$s a=$a');
          expect((back.get(s, a) - row[a]).abs(), lessThan(0.005 + 1e-4));
        }
      });
      for (final s in unvisited) {
        expect(back.isVisited(s), isFalse);
        expect(back.row(s), List<double>.filled(_n, 0));
      }
      // 두 번 왕복해도 동일 (반올림 고정점)
      expect(QTable.fromSparseJson(back.toSparseJson()).toSparseJson(), back.toSparseJson());
    });

    test('빈 테이블 왕복', () {
      final t = QTable();
      final json = t.toSparseJson();
      expect(json, '{"v":${Balance.featureSpecVersion},"n":5,"q":{}}');
      expect(QTable.fromSparseJson(json).visitedCount, 0);
      expect(t.toChunks(), isEmpty);
      expect(QTable.fromChunks(const []).visitedCount, 0);
    });

    test('fromSparseJson: "v" 불일치 → FormatException', () {
      final bad = '{"v":${Balance.featureSpecVersion + 1},"n":5,"q":{"1":[0,0,0,0,0]}}';
      expect(() => QTable.fromSparseJson(bad), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"n":5,"q":{}}'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":"1","n":5,"q":{}}'), throwsFormatException);
    });

    test('fromSparseJson: 깨진 형식 → FormatException', () {
      final v = Balance.featureSpecVersion;
      expect(() => QTable.fromSparseJson('not json'), throwsFormatException);
      expect(() => QTable.fromSparseJson('[1,2,3]'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":$v,"n":4,"q":{}}'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":$v,"n":5}'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":$v,"n":5,"q":{"x":[0,0,0,0,0]}}'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":$v,"n":5,"q":{"-1":[0,0,0,0,0]}}'), throwsFormatException);
      expect(
        () => QTable.fromSparseJson('{"v":$v,"n":5,"q":{"${FeatureEncoder.stateCount}":[0,0,0,0,0]}}'),
        throwsFormatException,
      );
      expect(() => QTable.fromSparseJson('{"v":$v,"n":5,"q":{"1":[0,0,0]}}'), throwsFormatException);
      expect(() => QTable.fromSparseJson('{"v":$v,"n":5,"q":{"1":[0,0,"a",0,0]}}'), throwsFormatException);
      // 정상 (정수/실수 혼용, n 생략 허용)
      final ok = QTable.fromSparseJson('{"v":$v,"q":{"1":[1,-2.5,0,3,0.25]}}');
      expect(ok.row(1), [1, -2.5, 0, 3, 0.25]);
      expect(ok.isVisited(1), isTrue);
    });
  });

  group('청크', () {
    test('15,000 방문 상태 → 3청크(6000/6000/3000), 각 < 900KB, 순서 무관 왕복', () {
      final t = QTable();
      final rng = Random(9);
      final truth = _fillRandom(t, 15000, rng);
      expect(Balance.statesPerChunk, 6000);

      final chunks = t.toChunks();
      expect(chunks.length, 3);
      final sizes = <int>[];
      var prevMax = -1;
      for (final c in chunks) {
        expect(c.length, lessThan(900 * 1024));
        final d = jsonDecode(c) as Map<String, dynamic>;
        expect(d['v'], Balance.featureSpecVersion);
        expect(d['n'], _n);
        final q = d['q'] as Map<String, dynamic>;
        sizes.add(q.length);
        // 청크 내부 오름차순 + 청크 간 오름차순
        final keys = q.keys.map(int.parse).toList();
        for (var i = 0; i < keys.length; i++) {
          expect(keys[i], greaterThan(i == 0 ? prevMax : keys[i - 1]));
        }
        prevMax = keys.last;
      }
      expect(sizes, [6000, 6000, 3000]);

      final shuffled = List<String>.from(chunks)..shuffle(Random(2));
      final back = QTable.fromChunks(shuffled);
      expect(back.visitedCount, 15000);
      truth.forEach((s, row) {
        expect(back.isVisited(s), isTrue);
        for (var a = 0; a < _n; a++) {
          expect(back.get(s, a), _roundedTo(t.get(s, a), 2), reason: 's=$s a=$a');
          expect((back.get(s, a) - row[a]).abs(), lessThan(0.005 + 1e-4));
        }
      });
      // 단일 JSON 경로와 청크 경로의 결과가 같다
      expect(back.toSparseJson(), QTable.fromSparseJson(t.toSparseJson()).toSparseJson());
      expect(back.toChunks(), chunks);
    });

    test('statesPerChunk 경계: 정확히 나누어떨어지는 경우와 1개짜리 청크', () {
      final t = QTable();
      final rng = Random(4);
      _fillRandom(t, 12, rng);
      expect(t.toChunks(statesPerChunk: 4).length, 3);
      expect(t.toChunks(statesPerChunk: 12).length, 1);
      expect(t.toChunks(statesPerChunk: 100).length, 1);
      expect(t.toChunks(statesPerChunk: 1).length, 12);
      expect(t.toChunks(statesPerChunk: 5).length, 3);
      expect(() => t.toChunks(statesPerChunk: 0), throwsArgumentError);
      final back = QTable.fromChunks(t.toChunks(statesPerChunk: 5));
      expect(back.toSparseJson(), QTable.fromSparseJson(t.toSparseJson()).toSparseJson());
    });

    test('fromChunks: 잘못된 v가 섞이면 FormatException', () {
      final t = QTable();
      _fillRandom(t, 10, Random(1));
      final chunks = t.toChunks(statesPerChunk: 5);
      final bad = [chunks[0], '{"v":${Balance.featureSpecVersion + 1},"n":5,"q":{}}'];
      expect(() => QTable.fromChunks(bad), throwsFormatException);
    });
  });

  group('QTablePolicy', () {
    test('ε=0: 정책 선택 = table.argmax (GameSim 없이 테이블 직접 검증)', () {
      final t = QTable();
      final rng = Random(8);
      final truth = _fillRandom(t, 500, rng);
      final policy = QTablePolicy(t, epsilon: 0);
      expect(policy.epsilon, 0);
      expect(policy.name, 'qtable');
      expect(policy.table, same(t));
      // 채워진 상태는 랜덤 실수 Q값이라 동점이 없으므로 argmax = 최댓값 행동 (rng 무관)
      for (final s in truth.keys) {
        final row = t.row(s);
        final best = row.reduce(max);
        final a = t.argmax(s, rng);
        expect(row[a], best);
        expect(HeroAction.values[a], HeroAction.values[row.indexOf(best)]);
        expect(t.argmax(s, Random(0)), a);
      }
    });

    test('기본 ε = Balance.epsPlay', () {
      final t = QTable();
      expect(QTablePolicy(t).epsilon, Balance.epsPlay);
      expect(QTablePolicy(t, name: 'stage1').name, 'stage1');
    });

    test('ε=0 act == argmax(encode(sim)), qValues == row (실제 GameSim)', () {
      final t = QTable();
      final sim = GameSim(GridMap(), HeroStats.forWave(1));
      final s = FeatureEncoder.encode(sim);
      // 단독 최대를 left(2)에 둔다
      for (var a = 0; a < _n; a++) {
        t.set(s, a, -1);
      }
      t.set(s, HeroAction.left.index, 5);
      final policy = QTablePolicy(t, epsilon: 0);
      expect(policy.act(sim, Random(1)), HeroAction.left);
      expect(policy.qValues(sim), [-1, -1, 5, -1, -1]);

      // 동점: 같은 시드로 argmax와 act가 같은 순서로 선택
      for (var a = 0; a < _n; a++) {
        t.set(s, a, 2);
      }
      final r1 = Random(77);
      final r2 = Random(77);
      for (var k = 0; k < 50; k++) {
        expect(policy.act(sim, r1), HeroAction.values[t.argmax(s, r2)]);
      }

      // ε=1: 5행동 전부 등장
      final randomPolicy = QTablePolicy(t, epsilon: 1);
      final seen = <HeroAction>{};
      final r3 = Random(5);
      for (var k = 0; k < 200; k++) {
        seen.add(randomPolicy.act(sim, r3));
      }
      expect(seen, HeroAction.values.toSet());
    }, skip: simSkip);
  });
}
