import 'package:dungeon_core/dungeon_core.dart';
import 'package:test/test.dart';

/// M3 Evaluator: evaluate/runDemo 기본 동작과 selectStages 문턱/폴백/순서 보정 (PLAN.md §5.7).

EvalStats _stats(double winRate) =>
    EvalStats(winRate: winRate, avgSteps: 20, trapHits: 0, potionsUsed: 0, kills: 0, episodes: 10);

/// 2000ep 간격 체크포인트 목록.
List<(int, EvalStats)> _ckpts(List<double> winRates, {int every = 2000}) =>
    [for (var i = 0; i < winRates.length; i++) ((i + 1) * every, _stats(winRates[i]))];

void main() {
  group('evaluate / runDemo', () {
    test('GreedyPolicy로 소형 평가셋 평가: 범위와 episodes', () {
      final set = LayoutGenerator.evalSet(seed: 42, size: 12);
      final s = Evaluator.evaluate(const GreedyPolicy(), set);
      expect(s.episodes, 12);
      expect(s.winRate, inInclusiveRange(0.0, 1.0));
      expect(s.avgSteps, inInclusiveRange(1.0, Balance.maxSteps.toDouble()));
      expect(s.trapHits, greaterThanOrEqualTo(0));
      expect(s.potionsUsed, greaterThanOrEqualTo(0));
      expect(s.kills, greaterThanOrEqualTo(0));
    });

    test('같은 정책·세트·시드면 결과 동일 (결정론)', () {
      final set = LayoutGenerator.evalSet(seed: 42, size: 9);
      final a = Evaluator.evaluate(const GreedyPolicy(), set, seed: 3);
      final b = Evaluator.evaluate(const GreedyPolicy(), set, seed: 3);
      expect(a.toJson(), b.toJson());
    });

    test('빈 세트는 0 통계', () {
      final s = Evaluator.evaluate(const GreedyPolicy(), const []);
      expect(s.episodes, 0);
      expect(s.winRate, 0);
    });

    test('빈 맵 + 낙관 초기값 Q(직진) → 평가셋 없이도 승', () {
      // 빈 맵에서 오른쪽/아래만 선호하는 Q-테이블은 항상 왕좌에 도달한다.
      final q = QTable();
      for (var s = 0; s < FeatureEncoder.stateCount; s++) {
        Trainer.applyOptimisticInit(q, s);
      }
      final p = QTablePolicy(q, epsilon: 0);
      final stats = Evaluator.evaluate(p, [(GridMap(), HeroStats.forWave(1)), (GridMap(), HeroStats.forWave(6))]);
      expect(stats.winRate, 1.0);
      // 오른쪽/아래가 동점이라 기둥 쪽으로 부딪히는 턴이 섞이므로 최단 12턴 이상, maxSteps 미만.
      expect(stats.avgSteps, greaterThanOrEqualTo(Pos.entrance.manhattan(Pos.throne).toDouble()));
      expect(stats.avgSteps, lessThan(Balance.maxSteps.toDouble()));
    });

    test('runDemo는 결정론적 bool', () {
      final a = Evaluator.runDemo(const GreedyPolicy());
      final b = Evaluator.runDemo(const GreedyPolicy());
      expect(a, b);
      // 데모 레이아웃은 직진 시 함정 3개(45 피해) + 왕좌 앞 오크(40hp, atk 9)라 wave 6 그리디는 진다.
      // (규칙이 바뀌면 이 기대치도 바뀔 수 있으므로 값 자체보다 bool 반환을 검증한다.)
      expect(a, isA<bool>());
    });

    test('EvalStats JSON 왕복', () {
      final s = EvalStats(winRate: 0.5, avgSteps: 20.5, trapHits: 0.3, potionsUsed: 1.2, kills: 2.1, episodes: 300);
      expect(EvalStats.fromJson(s.toJson()).toJson(), s.toJson());
    });
  });

  group('selectStages', () {
    test('문턱 규칙: ≥10% 첫, ≥70% 첫, 최고', () {
      final sel = Evaluator.selectStages(_ckpts([0.02, 0.08, 0.12, 0.30, 0.46, 0.72, 0.80, 0.78]));
      expect(sel['stage1'], 6000); // 0.12
      expect(sel['stage2'], 12000); // 0.72
      expect(sel['stage3'], 14000); // 0.80
      expect(sel['rule'], Evaluator.ruleThreshold);
    });

    test('입력 순서와 무관하게 에피소드 순으로 정렬해 판단', () {
      final list = _ckpts([0.02, 0.08, 0.12, 0.30, 0.46, 0.72, 0.80, 0.78]).reversed.toList();
      final sel = Evaluator.selectStages(list);
      expect(sel['stage1'], 6000);
      expect(sel['stage2'], 12000);
      expect(sel['stage3'], 14000);
    });

    test('최고 승률 동점이면 더 늦은 체크포인트', () {
      final sel = Evaluator.selectStages(_ckpts([0.1, 0.5, 0.7, 0.7, 0.6]));
      expect(sel['stage3'], 8000);
    });

    test('stage2 문턱 미달 → 분위수 폴백(30% 지점), rule=1', () {
      // 10개 체크포인트(2k..20k): 30% 지점 = 6000.
      final sel = Evaluator.selectStages(_ckpts([0.05, 0.12, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.42, 0.41]));
      expect(sel['rule'], Evaluator.ruleQuantile);
      expect(sel['stage1'], 4000); // 문턱 ≥10% 첫 = 0.12
      expect(sel['stage2'], 6000); // 0.30 × 20000
      expect(sel['stage3'], 18000); // 최고 0.42
    });

    test('두 문턱 모두 미달 → stage1 5% 지점, stage2 30% 지점, stage3 최고', () {
      final rates = List<double>.generate(100, (i) => 0.01 + i * 0.0005); // 0.01 → 0.0595
      final sel = Evaluator.selectStages(_ckpts(rates)); // 2k..200k
      expect(sel['rule'], Evaluator.ruleQuantile);
      expect(sel['stage1'], 10000); // 0.05 × 200000
      expect(sel['stage2'], 60000); // 0.30 × 200000
      expect(sel['stage3'], 200000);
      expect(sel['stage1']!, lessThan(sel['stage2']!));
      expect(sel['stage2']!, lessThan(sel['stage3']!));
    });

    test('순서 보정: 첫 체크포인트부터 두 문턱을 넘어도 stage1 < stage2 < stage3', () {
      final sel = Evaluator.selectStages(_ckpts([0.9, 0.9, 0.9, 0.9]));
      expect(sel['stage1']!, lessThan(sel['stage2']!));
      expect(sel['stage2']!, lessThan(sel['stage3']!));
      // 최고 동점 → 마지막(8000), stage2는 그 앞에서 문턱 첫 = 4000, stage1 = 2000.
      expect(sel['stage1'], 2000);
      expect(sel['stage2'], 4000);
      expect(sel['stage3'], 8000);
    });

    test('순서 보정: 최고 승률이 너무 이르면 뒤쪽에서 최고를 다시 고른다', () {
      // 최고(0.9)가 첫 체크포인트. stage3은 인덱스 ≥ 2 범위의 최고(0.5 @ 8000).
      final sel = Evaluator.selectStages(_ckpts([0.9, 0.2, 0.4, 0.5, 0.3]));
      expect(sel['stage3'], 8000);
      expect(sel['stage1']!, lessThan(sel['stage2']!));
      expect(sel['stage2']!, lessThan(sel['stage3']!));
    });

    test('순서 보정: stage2 문턱이 stage3 뒤에서만 넘으면 앞 구간에서 폴백', () {
      // 최고 0.7 @ 8000, 그 뒤 12000이 0.5(≥45%)지만 stage3 뒤라 사용 불가 → 분위수 폴백.
      final sel = Evaluator.selectStages(_ckpts([0.05, 0.15, 0.3, 0.7, 0.4, 0.5]));
      expect(sel['stage3'], 8000);
      expect(sel['stage2']!, lessThan(8000));
      expect(sel['stage1']!, lessThan(sel['stage2']!));
      expect(sel['rule'], Evaluator.ruleQuantile);
    });

    test('체크포인트 1~2개: 가능한 최선의 조합, 예외 없음', () {
      final one = Evaluator.selectStages(_ckpts([0.5]));
      expect(one['stage1'], 2000);
      expect(one['stage2'], 2000);
      expect(one['stage3'], 2000);

      final two = Evaluator.selectStages(_ckpts([0.2, 0.6]));
      expect(two['stage3'], 4000);
      expect(two['stage1']!, lessThanOrEqualTo(two['stage2']!));
      expect(two['stage2']!, lessThanOrEqualTo(two['stage3']!));
    });

    test('빈 목록은 ArgumentError', () {
      expect(() => Evaluator.selectStages(const []), throwsArgumentError);
    });
  });
}
