// 통합 위젯 테스트: 실제 GameController + 실제 dungeon_core(GridMap/GameSim) + GreedyPolicy로
// PlayScreen을 띄워 "배치 → 웨이브 시작 → 타이머 진행 → 결과/게임오버 화면"이 예외 없이 끝나는지 확인한다.
//
// 검증 포인트는 승패가 아니라 "예외 없이 종료 + 화면 전환 + 마나/턴 표시가 컨트롤러와 일치"이다.
import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namaiki_dungeon/game/game_controller.dart';
import 'package:namaiki_dungeon/main.dart';
import 'package:namaiki_dungeon/ui/play_screen.dart';
import 'package:provider/provider.dart';

void main() {
  final policies = <int, HeroPolicy>{
    for (var s = 1; s <= Balance.totalWaves ~/ Balance.wavesPerStage; s++) s: const GreedyPolicy(),
  };

  /// 모바일 세로 화면 (360x740 논리 픽셀) 크기로 고정.
  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  Widget playApp(GameController c) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: ChangeNotifierProvider<GameController>.value(
          value: c,
          child: const PlayScreen(),
        ),
      );

  /// 웨이브 종료 페이즈인가.
  bool isEnded(Phase p) => p == Phase.result || p == Phase.gameOver || p == Phase.victory;

  /// 200ms 틱을 최대 [maxTicks]회 진행하며 웨이브가 끝날 때까지 기다린다. 실제 소요 틱 수를 돌려준다.
  Future<int> runWave(WidgetTester tester, GameController c, {int maxTicks = 100}) async {
    var ticks = 0;
    while (!isEnded(c.phase) && ticks < maxTicks) {
      await tester.pump(c.tickInterval);
      ticks++;
      // 매 틱마다 렌더 예외가 없어야 한다.
      expect(tester.takeException(), isNull, reason: '틱 $ticks 에서 예외');
    }
    return ticks;
  }

  testWidgets('슬라임 1개 배치 → 마나 11 → 웨이브 시작 → 타이머 진행 → 결과 또는 게임오버 화면', (tester) async {
    await setPhone(tester);
    final c = GameController(policies);
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    // 초기 상태: 마나 12, 빌드 페이즈
    expect(c.phase, Phase.build);
    expect(find.text('🔮 마나 ${Balance.startMana}'), findsOneWidget);

    // 팔레트에서 슬라임 선택
    await tester.tap(find.byKey(const ValueKey('palette_slime')));
    await tester.pump();
    expect(c.selected, MonsterType.slime);

    // 최단경로 위 배치 가능 칸 (0,2)에 배치 → 마나 11
    const cell = Pos(0, 2);
    expect(GridMap.isPlaceableCell(cell), isTrue);
    await tester.tap(find.byKey(ValueKey('cell_${cell.x}_${cell.y}')));
    await tester.pump();
    final expectedMana = Balance.startMana - MonsterType.slime.spec.cost;
    expect(expectedMana, 11);
    expect(c.mana, expectedMana);
    expect(find.text('🔮 마나 $expectedMana'), findsOneWidget);
    expect(c.map.monsters[cell]?.type, MonsterType.slime);
    expect(find.text(MonsterType.slime.emoji), findsWidgets);

    // 웨이브 시작
    await tester.tap(find.text('웨이브 시작'));
    await tester.pump();
    expect(c.phase, Phase.running);
    expect(c.sim, isNotNull);
    expect(find.text('용사 침입 중…'), findsOneWidget);

    // 진행 중엔 배치가 무시된다 (셀 탭 → 마나/맵 불변)
    await tester.tap(find.byKey(const ValueKey('cell_2_2')), warnIfMissed: false);
    await tester.pump();
    expect(c.mana, expectedMana);
    expect(c.map.monsters.length, 1);

    // 200ms 틱 최대 100회
    final ticks = await runWave(tester, c);
    expect(isEnded(c.phase), isTrue, reason: '$ticks 틱 안에 웨이브가 끝나야 한다 (phase=${c.phase})');
    expect(c.sim!.done, isTrue);
    expect(c.lastOutcome, isNot(Outcome.running));
    expect(c.sim!.steps, lessThanOrEqualTo(Balance.maxSteps));
    // 슬라임 하나는 GreedyPolicy가 뚫고 지나가므로 왕좌 도달(게임오버)이 기대되지만, 검증 포인트는 예외 없는 종료.
    await tester.pump();
    if (c.phase == Phase.gameOver) {
      expect(find.byKey(const ValueKey('game_over_screen')), findsOneWidget);
      expect(find.text('왕좌가 함락됐다'), findsOneWidget);
      expect(c.lastOutcome, Outcome.reachedThrone);
    } else {
      expect(find.byKey(const ValueKey('result_dialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('next_wave_button')), findsOneWidget);
      expect(c.lastOutcome?.defended, isTrue);
    }
    // HUD 턴 표시가 시뮬레이터와 일치
    expect(find.text('턴 ${c.sim!.steps}/${Balance.maxSteps}'), findsOneWidget);
    // 트레일: 입구에서 시작, 시뮬레이터 트레일과 동일 (공격/벽충돌 턴은 이동이 아니라 steps+1 이하)
    expect(c.trail.first, Pos.entrance);
    expect(c.trail, c.sim!.trail);
    expect(c.trail.length, lessThanOrEqualTo(c.sim!.steps + 1));

    // 종료 후 타이머가 멈춰 있어야 한다: 더 pump해도 상태 불변
    final stepsAtEnd = c.sim!.steps;
    await tester.pump(c.tickInterval * 5);
    expect(c.sim!.steps, stepsAtEnd);
    expect(tester.takeException(), isNull);
  });

  testWidgets('빈 맵: GreedyPolicy가 12턴에 왕좌 도달 → 게임오버 화면', (tester) async {
    await setPhone(tester);
    final c = GameController(policies);
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    await tester.tap(find.text('웨이브 시작'));
    await tester.pump();
    expect(c.phase, Phase.running);

    final ticks = await runWave(tester, c);
    final expectedSteps = (Pos.throne.x - Pos.entrance.x) + (Pos.throne.y - Pos.entrance.y); // 맨해튼 12
    expect(ticks, expectedSteps);
    expect(c.phase, Phase.gameOver);
    expect(c.lastOutcome, Outcome.reachedThrone);
    expect(c.sim!.steps, expectedSteps);
    expect(c.sim!.heroPos, Pos.throne);
    expect(c.trail.length, expectedSteps + 1);
    expect(c.trail.first, Pos.entrance);
    expect(c.trail.last, Pos.throne);

    await tester.pump();
    expect(find.byKey(const ValueKey('game_over_screen')), findsOneWidget);
    expect(find.text('웨이브 1의 용사가 왕좌에 도달했다.'), findsOneWidget);
    expect(find.textContaining('막아낸 웨이브'), findsOneWidget);
    expect(find.byKey(const ValueKey('back_to_menu_button')), findsOneWidget);
    expect(c.wavesCleared, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('슬라임 12개로 입구 통로를 막아도 예외 없이 종료 (결과 또는 게임오버)', (tester) async {
    await setPhone(tester);
    final c = GameController(policies);
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    await tester.tap(find.byKey(const ValueKey('palette_slime')));
    await tester.pump();

    // 입구 근처부터 배치 가능 칸을 행 우선으로 채운다 (마나 12 → 슬라임 12개).
    final budget = Balance.startMana ~/ MonsterType.slime.spec.cost;
    final cells = GridMap.placeableCells();
    // 입구와 가까운 순 (맨해튼 거리)으로 정렬해 통로를 막는다.
    cells.sort((a, b) {
      final da = (a.x - Pos.entrance.x).abs() + (a.y - Pos.entrance.y).abs();
      final db = (b.x - Pos.entrance.x).abs() + (b.y - Pos.entrance.y).abs();
      return da != db ? da.compareTo(db) : a.index.compareTo(b.index);
    });
    var placed = 0;
    for (final p in cells) {
      if (placed >= budget) break;
      await tester.tap(find.byKey(ValueKey('cell_${p.x}_${p.y}')));
      await tester.pump();
      placed++;
      expect(c.mana, Balance.startMana - placed * MonsterType.slime.spec.cost);
    }
    expect(placed, budget);
    expect(c.mana, 0);
    expect(c.map.monsters.length, budget);
    expect(find.text('🔮 마나 0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 마나 0이면 추가 배치는 거부되고 스낵바 안내 (예외 없음)
    final freeCell = cells.firstWhere((p) => !c.map.monsters.containsKey(p));
    await tester.tap(find.byKey(ValueKey('cell_${freeCell.x}_${freeCell.y}')));
    await tester.pump();
    expect(c.map.monsters.length, budget);
    expect(find.textContaining('마나가 부족합니다'), findsOneWidget);

    await tester.tap(find.text('웨이브 시작'));
    await tester.pump();
    expect(c.phase, Phase.running);

    final ticks = await runWave(tester, c);
    expect(isEnded(c.phase), isTrue, reason: '$ticks 틱 안에 종료 (phase=${c.phase})');
    expect(c.phase, isNot(Phase.victory)); // 웨이브 1에서 승리는 불가
    expect(c.sim!.done, isTrue);
    expect(c.sim!.steps, lessThanOrEqualTo(Balance.maxSteps));
    // GreedyPolicy는 슬라임을 공격해 뚫으므로 최소 1마리는 처치했어야 한다.
    expect(c.sim!.kills, greaterThanOrEqualTo(1));

    await tester.pump();
    if (c.phase == Phase.result) {
      expect(find.byKey(const ValueKey('result_dialog')), findsOneWidget);
      // 다음 웨이브: 마나 +5, 웨이브 2, 빌드 페이즈, 죽은 슬라임은 사라짐
      await tester.tap(find.byKey(const ValueKey('next_wave_button')));
      await tester.pump();
      expect(c.phase, Phase.build);
      expect(c.wave, 2);
      expect(c.mana, Balance.manaPerWave);
      expect(find.text('🔮 마나 ${Balance.manaPerWave}'), findsOneWidget);
      expect(find.text('웨이브 2/${Balance.totalWaves}'), findsOneWidget);
      expect(c.map.monsters.length, budget - c.sim!.kills);
      for (final m in c.map.monsters.values) {
        expect(m.hp, m.maxHp, reason: '생존 마물 HP 전회복');
      }
    } else {
      expect(c.phase, Phase.gameOver);
      expect(find.byKey(const ValueKey('game_over_screen')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('전체 앱 흐름: 메뉴 → 게임 시작 → 웨이브 → 게임오버 → 메뉴 복귀 (타이머 잔존 없음)', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(NamaikiApp(policies: policies));
    expect(find.byKey(const ValueKey('start_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);

    // 라우트 안의 실제 컨트롤러를 꺼내 본다.
    final c = tester.element(find.byType(PlayScreen)).read<GameController>();
    expect(c.phase, Phase.build);
    expect(c.mana, Balance.startMana);

    // 빈 맵으로 바로 시작 → 12턴 게임오버
    await tester.tap(find.text('웨이브 시작'));
    await tester.pump();
    expect(c.phase, Phase.running);
    await runWave(tester, c);
    expect(c.phase, Phase.gameOver);
    await tester.pump();
    expect(find.byKey(const ValueKey('game_over_screen')), findsOneWidget);

    // 기록 생성이 예외 없이 된다 (레이아웃 스냅샷 JSON 포함)
    final run = c.buildRun();
    expect(run.wavesCleared, 0);
    expect(run.stageReached, 1);
    expect(run.layoutSnapshot, isNotEmpty);

    // 메뉴 복귀 → 컨트롤러 dispose. 이후 pending 타이머가 남아 있으면 테스트 프레임워크가 실패시킨다.
    await tester.tap(find.byKey(const ValueKey('back_to_menu_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('start_button')), findsOneWidget);
    expect(find.byType(PlayScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('웨이브 진행 중 화면을 닫아도(dispose) 타이머가 남지 않는다', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(NamaikiApp(policies: policies));
    await tester.tap(find.byKey(const ValueKey('start_button')));
    await tester.pumpAndSettle();
    final c = tester.element(find.byType(PlayScreen)).read<GameController>();

    await tester.tap(find.text('웨이브 시작'));
    await tester.pump();
    await tester.pump(c.tickInterval * 3);
    expect(c.phase, Phase.running);
    expect(c.sim!.steps, 3);

    // 뒤로가기 → 라우트 pop → provider가 컨트롤러 dispose
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
    // 남은 타이머가 있으면 여기서 프레임워크가 'A Timer is still pending' 으로 실패시킨다.
    expect(tester.takeException(), isNull);
  });
}
