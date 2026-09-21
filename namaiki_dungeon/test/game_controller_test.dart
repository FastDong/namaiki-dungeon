import 'dart:convert';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namaiki_dungeon/game/game_controller.dart';
import 'package:namaiki_dungeon/game/wave_rules.dart';

import 'fakes.dart';

/// GameSim은 M1 스텁이라 startWave는 다루지 않는다. 컨트롤러의 순수 로직만 검증한다.
void main() {
  final policies = <int, HeroPolicy>{
    1: const FixedPolicy('s1', HeroAction.right),
    2: const FixedPolicy('s2', HeroAction.down),
    3: const FixedPolicy('s3', HeroAction.potion),
  };

  GameController make() => GameController(policies, initialMap: FakeGridMap());

  group('초기 상태', () {
    test('mana 12, wave 1, stage 1, build 페이즈, 슬라임 선택', () {
      final c = make();
      expect(c.mana, Balance.startMana);
      expect(c.mana, 12);
      expect(c.wave, 1);
      expect(c.stage, 1);
      expect(c.phase, Phase.build);
      expect(c.selected, MonsterType.slime);
      expect(c.heroDeaths, 0);
      expect(c.wavesCleared, 0);
      expect(c.sim, isNull);
      expect(c.trail, isEmpty);
      expect(c.showHero, isFalse);
      c.dispose();
    });

    test('빈 정책 맵은 거부', () {
      expect(() => GameController(const {}), throwsA(isA<AssertionError>()));
    });
  });

  group('단계 매핑', () {
    test('WaveRules.stageForWave 1→1, 5→1, 6→2, 10→2, 11→3, 15→3', () {
      expect(WaveRules.stageForWave(1), 1);
      expect(WaveRules.stageForWave(5), 1);
      expect(WaveRules.stageForWave(6), 2);
      expect(WaveRules.stageForWave(10), 2);
      expect(WaveRules.stageForWave(11), 3);
      expect(WaveRules.stageForWave(15), 3);
      expect(WaveRules.stageCount, 3);
      expect(WaveRules.isStageTransition(5, 6), isTrue);
      expect(WaveRules.isStageTransition(10, 11), isTrue);
      expect(WaveRules.isStageTransition(4, 5), isFalse);
      expect(WaveRules.isFinalWave(15), isTrue);
      expect(WaveRules.isFinalWave(14), isFalse);
    });

    test('controller.stage는 웨이브를 따르고 forcedStage가 우선', () {
      final c = make();
      for (final (w, s) in [(1, 1), (5, 1), (6, 2), (11, 3)]) {
        c.debugSetWave(w);
        expect(c.stage, s, reason: 'wave $w');
        expect(c.waveStage, s);
        expect(c.policyForStage(c.stage).name, 's$s');
      }
      c.forcedStage = 3;
      c.debugSetWave(1);
      expect(c.stage, 3);
      expect(c.waveStage, 1);
      expect(c.activePolicy.name, 's3');
      c.forcedStage = null;
      expect(c.stage, 1);
      c.dispose();
    });

    test('마나 곡선 래퍼는 Balance와 일치', () {
      expect(WaveRules.cumulativeMana(1), Balance.startMana);
      expect(WaveRules.cumulativeMana(15), Balance.startMana + Balance.manaPerWave * 14);
      expect(WaveRules.heroFor(1).maxHp, Balance.heroHp(1));
      expect(WaveRules.heroFor(15).atk, Balance.heroAtk(15));
      expect(WaveRules.heroFor(3).potions, Balance.potions);
    });
  });

  group('빌드 페이즈 배치', () {
    test('placeAt 비용 차감, removeAt 전액 환불', () {
      final c = make();
      var notified = 0;
      c.addListener(() => notified++);

      c.selected = MonsterType.goblin;
      final cost = MonsterType.goblin.spec.cost;
      expect(c.placeAt(const Pos(2, 2)), isTrue);
      expect(c.mana, Balance.startMana - cost);
      expect(c.map.monsters[const Pos(2, 2)]?.type, MonsterType.goblin);
      expect(c.placedCost, cost);

      expect(c.removeAt(const Pos(2, 2)), isTrue);
      expect(c.mana, Balance.startMana);
      expect(c.map.monsters, isEmpty);

      expect(c.removeAt(const Pos(2, 2)), isFalse, reason: '빈 칸 제거는 false');
      expect(c.mana, Balance.startMana);
      expect(notified, 3, reason: '선택 변경 1 + 배치 1 + 제거 1');
      c.dispose();
    });

    test('마나 부족이면 배치 거부, 맵 변화 없음', () {
      final c = make();
      c.selected = MonsterType.orc;
      final orc = MonsterType.orc.spec.cost;
      final n = Balance.startMana ~/ orc; // 12 / 6 = 2
      for (var i = 0; i < n; i++) {
        expect(c.placeAt(Pos(2 + i, 4)), isTrue);
      }
      expect(c.mana, Balance.startMana - orc * n);
      expect(c.placeAt(const Pos(4, 4)), isFalse);
      expect(c.map.monsters.length, n);
      expect(c.mana, Balance.startMana - orc * n);
      c.dispose();
    });

    test('배치 불가 칸(기둥/입구/왕좌/점유)은 false, 마나 유지', () {
      final c = make();
      c.selected = MonsterType.slime;
      expect(c.placeAt(const Pos(1, 1)), isFalse, reason: '기둥');
      expect(c.placeAt(Pos.entrance), isFalse, reason: '입구');
      expect(c.placeAt(Pos.throne), isFalse, reason: '왕좌');
      expect(c.placeAt(const Pos(1, 0)), isFalse, reason: '입구 인접');
      expect(c.mana, Balance.startMana);
      expect(c.placeAt(const Pos(2, 0)), isTrue);
      expect(c.placeAt(const Pos(2, 0)), isFalse, reason: '점유 칸');
      expect(c.mana, Balance.startMana - MonsterType.slime.spec.cost);
      c.dispose();
    });

    test('running 중에는 placeAt/removeAt 무시', () {
      final c = make();
      c.selected = MonsterType.trap;
      expect(c.placeAt(const Pos(3, 0)), isTrue);
      final manaBefore = c.mana;

      c.debugSetPhase(Phase.running);
      expect(c.canBuild, isFalse);
      expect(c.isRunning, isTrue);
      expect(c.placeAt(const Pos(4, 0)), isFalse);
      expect(c.removeAt(const Pos(3, 0)), isFalse);
      expect(c.mana, manaBefore);
      expect(c.map.monsters.length, 1);

      c.debugSetPhase(Phase.result);
      expect(c.placeAt(const Pos(4, 0)), isFalse);

      c.debugSetPhase(Phase.build);
      expect(c.placeAt(const Pos(4, 0)), isTrue);
      c.dispose();
    });

    test('running 중 startWave/loadDemoLayout는 무시(페이즈 유지)', () {
      final c = make();
      c.debugSetPhase(Phase.running);
      c.startWave();
      c.loadDemoLayout();
      expect(c.phase, Phase.running);
      expect(c.takeError(), isNull);
      c.dispose();
    });
  });

  group('웨이브 전이', () {
    test('nextWave: wave+1, mana +5, build 페이즈 (5의 배수 아닐 때)', () {
      final c = make();
      c.selected = MonsterType.slime;
      c.placeAt(const Pos(2, 2));
      final mana = c.mana;

      c.debugSetPhase(Phase.result);
      c.nextWave();
      expect(c.wave, 2);
      expect(c.mana, mana + Balance.manaPerWave);
      expect(c.phase, Phase.build);
      expect(c.map.monsters[const Pos(2, 2)]?.type, MonsterType.slime, reason: '배치 유지');
      c.dispose();
    });

    test('nextWave는 result 페이즈에서만 동작', () {
      final c = make();
      c.nextWave();
      expect(c.wave, 1);
      expect(c.mana, Balance.startMana);
      c.dispose();
    });

    test('웨이브 5→6, 10→11은 evolve를 거쳐 build', () {
      final c = make();
      for (final w in [5, 10]) {
        c.debugSetWave(w);
        c.debugSetPhase(Phase.result);
        c.nextWave();
        expect(c.wave, w + 1);
        expect(c.phase, Phase.evolve);
        expect(c.waveStage, WaveRules.stageForWave(w + 1));
        c.placeAt(const Pos(2, 2));
        expect(c.map.monsters, isEmpty, reason: 'evolve 중 배치 불가');
        c.dismissEvolve();
        expect(c.phase, Phase.build);
      }
      c.dismissEvolve();
      expect(c.phase, Phase.build, reason: 'build에서 dismissEvolve는 무해');
      c.dispose();
    });

    test('nextWave 시 살아남은 마물 HP 전회복', () {
      final c = make();
      c.selected = MonsterType.orc;
      c.placeAt(const Pos(5, 6));
      c.map.monsters[const Pos(5, 6)]!.hp = 3; // 웨이브 중 피해를 흉내
      c.debugSetPhase(Phase.result);
      c.nextWave();
      expect(c.map.monsters[const Pos(5, 6)]!.hp, MonsterType.orc.spec.hp);
      c.dispose();
    });

    test('누적 마나는 Balance.cumulativeMana와 일치(미사용 시)', () {
      final c = make();
      for (var w = 1; w < Balance.totalWaves; w++) {
        expect(c.mana, Balance.cumulativeMana(w), reason: 'wave $w');
        c.debugSetPhase(Phase.result);
        c.nextWave();
        if (c.phase == Phase.evolve) c.dismissEvolve();
      }
      expect(c.wave, Balance.totalWaves);
      expect(c.mana, Balance.cumulativeMana(Balance.totalWaves));
      c.dispose();
    });
  });

  group('기록', () {
    test('buildRun: uid 빈 문자열, 닉네임 마왕, 레이아웃 스냅샷 JSON', () {
      final c = make();
      c.selected = MonsterType.trap;
      c.placeAt(const Pos(3, 0));
      final r = c.buildRun();
      expect(r.uid, '');
      expect(r.nickname, '마왕');
      expect(r.wavesCleared, 0);
      expect(r.stageReached, 1);
      expect(r.heroDeaths, 0);
      expect(r.durationSec, greaterThanOrEqualTo(0));
      final j = jsonDecode(r.layoutSnapshot) as Map<String, dynamic>;
      expect((j['m'] as List).length, 1);
      expect(r.toMap()['nickname'], '마왕');
      c.dispose();
    });

    test('currentQ/currentFeatures는 QTablePolicy가 아니면 null', () {
      final c = make();
      expect(c.currentQ, isNull);
      expect(c.currentFeatures, isNull);
      c.dispose();
    });
  });
}
