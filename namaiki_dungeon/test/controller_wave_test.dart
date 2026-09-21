import 'dart:async';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namaiki_dungeon/game/game_controller.dart';

/// 실제 dungeon_core(GridMap/GameSim/GreedyPolicy)로 웨이브 루프를 돌리는 통합 테스트.
/// 코어가 아직 스텁이면(UnimplementedError) 통째로 건너뛴다.
void main() {
  final String? skipReason = _coreReady() ? null : 'dungeon_core 미구현(M1 진행 중)';

  final policies = <int, HeroPolicy>{
    for (var s = 1; s <= 3; s++) s: const GreedyPolicy(),
  };

  GameController make({GridMap? map}) => GameController(
        policies,
        initialMap: map,
        tickInterval: const Duration(milliseconds: 1),
      );

  /// running이 끝날 때까지 대기 (최대 10초).
  Future<void> waitWave(GameController c) {
    if (c.phase != Phase.running) return Future.value();
    final done = Completer<void>();
    void listener() {
      if (c.phase != Phase.running && !done.isCompleted) done.complete();
    }

    c.addListener(listener);
    return done.future.timeout(const Duration(seconds: 10)).whenComplete(() => c.removeListener(listener));
  }

  test('빈 맵: 용사가 왕좌 도달 → gameOver, 트레일 입구→왕좌', () async {
    final c = make();
    c.startWave();
    expect(c.phase, Phase.running);
    expect(c.showHero, isTrue);
    await waitWave(c);

    expect(c.phase, Phase.gameOver);
    expect(c.lastOutcome, Outcome.reachedThrone);
    expect(c.trail.first, Pos.entrance);
    expect(c.trail.last, Pos.throne);
    expect(c.sim!.steps, Pos.entrance.manhattan(Pos.throne), reason: '기둥 맵은 우회 없이 최단 12턴');
    expect(c.buildRun().wavesCleared, 0);
    expect(c.buildRun().stageReached, 1);
    c.dispose();
  }, skip: skipReason);

  test('왕좌 포위(오크 벽): 방어 성공 → result → nextWave로 마나+5·생존 마물 HP 회복', () async {
    // 어느 경로로 와도 오크 3마리(반격 36×3 > HP 50 + 물약 50)를 뚫어야 하는 배치. 마나 무시(주입 맵).
    final wall = GridMap();
    for (final p in const [
      Pos(6, 5), Pos(6, 4), Pos(5, 4), Pos(6, 3),
      Pos(5, 6), Pos(4, 6), Pos(3, 6), Pos(4, 5),
    ]) {
      expect(wall.place(MonsterType.orc, p), isTrue, reason: '$p');
    }
    final c = make(map: wall);
    final manaBefore = c.mana;

    c.startWave();
    await waitWave(c);

    expect(c.phase, Phase.result);
    expect(c.lastOutcome!.defended, isTrue);
    if (c.lastOutcome == Outcome.heroDied) expect(c.heroDeaths, 1);
    expect(c.wavesCleared, 1);
    expect(c.mana, manaBefore, reason: '마나는 nextWave에서 지급');
    expect(c.placeAt(const Pos(2, 2)), isFalse, reason: 'result 중 배치 불가');

    // 웨이브 중 피해를 입은 오크가 있어야 회복 검증이 의미 있다.
    final damaged = c.sim!.map.monsters.values.where((m) => m.hp < m.maxHp).length;
    final survivors = c.sim!.map.monsters.length;
    expect(survivors, lessThanOrEqualTo(8));

    c.nextWave();
    expect(c.phase, Phase.build);
    expect(c.wave, 2);
    expect(c.mana, manaBefore + Balance.manaPerWave);
    expect(c.map.monsters.length, survivors, reason: '죽은 마물은 사라지고 생존 마물만 유지');
    expect(c.map.monsters.values.every((m) => m.hp == m.maxHp), isTrue, reason: 'HP 전회복 (피해 입었던 수: $damaged)');
    expect(c.trail, isNotEmpty, reason: '트레일은 다음 웨이브 시작 전까지 유지');
    expect(c.showHero, isFalse);

    // 빌드 페이즈에서 다시 배치 가능
    c.selected = MonsterType.slime;
    expect(c.placeAt(const Pos(2, 2)), isTrue);
    expect(c.mana, manaBefore + Balance.manaPerWave - MonsterType.slime.spec.cost);

    // 웨이브 2 시작도 정상 동작
    c.startWave();
    expect(c.phase, Phase.running);
    expect(c.trail.length, 1, reason: '새 웨이브는 트레일 초기화');
    await waitWave(c);
    expect(c.phase, isNot(Phase.running));
    c.dispose();
  }, skip: skipReason);

  test('restartSameLayout: 같은 웨이브·같은 레이아웃으로 재실행, 단계 강제 반영', () async {
    final c = make();
    c.selected = MonsterType.trap;
    c.placeAt(const Pos(2, 0));
    final layoutBefore = c.map.toJson().toString();

    c.forcedStage = 3;
    c.startWave();
    await waitWave(c);
    expect(c.phase, Phase.gameOver);
    expect(c.activePolicy.name, 'greedy');
    expect(c.stage, 3);

    c.restartSameLayout();
    expect(c.phase, Phase.running);
    expect(c.wave, 1);
    expect(c.map.toJson().toString(), layoutBefore, reason: '레이아웃 유지');
    await waitWave(c);
    expect(c.phase, Phase.gameOver);
    expect(c.sim!.trapHits, 1, reason: 'GreedyPolicy는 함정을 밟는다');
    c.dispose();
  }, skip: skipReason);

  test('loadDemoLayout: 현재 마나 안에서 적용, 마나+배치비용 보존', () {
    final c = make();
    c.loadDemoLayout();
    expect(c.takeError(), isNull);
    expect(c.map.monsters, isNotEmpty);
    expect(c.placedCost, lessThanOrEqualTo(Balance.startMana));
    expect(c.placedCost + c.mana, Balance.startMana);

    // 두 번 눌러도 마나 총량 보존 (기존 배치 환불 후 재적용)
    c.loadDemoLayout();
    expect(c.placedCost + c.mana, Balance.startMana);
    c.dispose();
  }, skip: skipReason);

  test('dispose 후 타이머가 남지 않는다 (running 중 dispose)', () async {
    final c = make();
    c.startWave();
    expect(c.phase, Phase.running);
    c.dispose();
    // 타이머가 살아 있다면 여기서 notifyListeners → dispose된 ChangeNotifier assert가 터진다.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }, skip: skipReason);
}

bool _coreReady() {
  try {
    final g = GridMap();
    g.isPillar(const Pos(1, 1));
    g.place(MonsterType.slime, const Pos(2, 2));
    g.clone();
    g.toJson();
    final sim = GameSim(GridMap(), HeroStats.forWave(1));
    sim.step(const GreedyPolicy().act(sim, _FixedRandom()));
    LayoutGenerator.demoLayout();
    return true;
  } on UnimplementedError {
    return false;
  }
}

/// 결정론 확인용 고정 난수 (GreedyPolicy는 막힌 경우에만 rng를 쓴다).
class _FixedRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
