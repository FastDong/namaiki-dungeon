import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:namaiki_dungeon/game/game_controller.dart';
import 'package:namaiki_dungeon/ui/board_grid.dart';
import 'package:namaiki_dungeon/ui/evolve_overlay.dart';
import 'package:namaiki_dungeon/ui/play_screen.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  Widget playApp(GameController c) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: ChangeNotifierProvider<GameController>.value(value: c, child: const PlayScreen()),
      );

  group('2.5D 투영', () {
    test('project ↔ unproject 왕복', () {
      for (final p in const [Offset(-120, -300), Offset(0, -10), Offset(150, -200), Offset(60, -350)]) {
        final s = BoardProjection.project(p);
        final back = BoardProjection.unproject(s);
        expect(back.dx, closeTo(p.dx, 1e-6));
        expect(back.dy, closeTo(p.dy, 1e-6));
      }
    });

    test('hitTest: 모든 셀 중심을 투영한 화면 좌표가 같은 셀로 판정된다', () {
      const side = 328.0;
      final h = side * BoardGrid.footprintRatio;
      final cs = BoardGrid.cellSizeFor(side);
      for (var y = 0; y < Balance.rows; y++) {
        for (var x = 0; x < Balance.cols; x++) {
          final cx = BoardGrid.boardPadding + x * (cs + BoardGrid.cellGap) + cs / 2;
          final cy = BoardGrid.boardPadding + y * (cs + BoardGrid.cellGap) + cs / 2;
          // 축(bottomCenter) 기준 로컬 → 화면 → 레이아웃 박스 좌표
          final scr = BoardProjection.project(Offset(cx - side / 2, cy - side));
          final local = Offset(scr.dx + side / 2, scr.dy + h);
          expect(BoardGrid.hitTest(local, side), Pos(x, y), reason: 'cell $x,$y');
        }
      }
      // 보드 밖
      expect(BoardGrid.hitTest(const Offset(-40, 10), side), isNull);
      expect(BoardGrid.hitTest(Offset(side / 2, h + 30), side), isNull);
    });

    test('투영 높이는 한 변보다 작고 footprintRatio 안에 들어온다', () {
      const side = 360.0;
      final ph = BoardProjection.projectedHeight(side);
      expect(ph, lessThan(side));
      expect(ph, lessThan(side * BoardGrid.footprintRatio));
      expect(ph, greaterThan(side * 0.5));
    });
  });

  group('보드 위젯', () {
    testWidgets('기울인 보드에서 탭 → 해당 셀 배치 (히트테스트 역변환)', (tester) async {
      await setPhone(tester);
      final c = GameController({1: const GreedyPolicy()}, initialMap: FakeGridMap());
      addTearDown(c.dispose);
      await tester.pumpWidget(playApp(c));

      // 화면상 셀 위젯의 중심을 직접 탭 (Transform 히트테스트 경로가 아니라 BoardGrid.hitTest 경로)
      final area = find.byKey(const ValueKey('board_tap_area'));
      expect(area, findsOneWidget);
      final box = tester.getRect(area);
      final side = box.width;
      final h = box.height;
      final cs = BoardGrid.cellSizeFor(side);
      Offset screenOf(Pos p) {
        final cx = BoardGrid.boardPadding + p.x * (cs + BoardGrid.cellGap) + cs / 2;
        final cy = BoardGrid.boardPadding + p.y * (cs + BoardGrid.cellGap) + cs / 2;
        final scr = BoardProjection.project(Offset(cx - side / 2, cy - side));
        return box.topLeft + Offset(scr.dx + side / 2, scr.dy + h);
      }

      await tester.tapAt(screenOf(const Pos(2, 2)));
      await tester.pump();
      expect(c.map.monsters.containsKey(const Pos(2, 2)), isTrue, reason: '(2,2) 배치');
      expect(c.mana, Balance.startMana - MonsterType.slime.spec.cost);

      await tester.tapAt(screenOf(const Pos(4, 0)));
      await tester.pump();
      expect(c.map.monsters.containsKey(const Pos(4, 0)), isTrue, reason: '(4,0) 배치 — 먼 줄');

      await tester.tapAt(screenOf(const Pos(2, 2)));
      await tester.pump();
      expect(c.map.monsters.containsKey(const Pos(2, 2)), isFalse, reason: '다시 탭 → 제거');
      expect(tester.takeException(), isNull);
    });

    testWidgets('스프라이트: 마물/왕좌/입구/기둥, 웨이브 중 용사 레이어·트레일', (tester) async {
      await setPhone(tester);
      final map = FakeGridMap()..place(MonsterType.orc, const Pos(4, 4));
      final c = GameController({1: const GreedyPolicy()}, initialMap: map, tickInterval: const Duration(days: 1));
      addTearDown(c.dispose);
      await tester.pumpWidget(playApp(c));

      expect(find.byKey(const ValueKey('sprite_orc')), findsWidgets);
      expect(find.byKey(const ValueKey('sprite_throne')), findsWidgets);
      expect(find.byKey(const ValueKey('sprite_entrance')), findsOneWidget);
      expect(find.byKey(const ValueKey('hero_layer')), findsNothing);

      c.startWave();
      await tester.pump();
      expect(find.byKey(const ValueKey('hero_layer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      c.debugSetPhase(Phase.build); // 타이머 정지 (pending timer 검사)
      await tester.pump();
    });
  });

  group('두뇌 패널', () {
    testWidgets('Greedy 정책 → "규칙 기반 용사(학습 전)"', (tester) async {
      await setPhone(tester);
      final c = GameController({1: const GreedyPolicy()}, initialMap: FakeGridMap());
      addTearDown(c.dispose);
      await tester.pumpWidget(playApp(c));
      expect(find.byKey(const ValueKey('brain_panel')), findsOneWidget);
      expect(find.text('규칙 기반 용사(학습 전)'), findsOneWidget);
    });

    testWidgets('QTable 정책 → 5행동 막대, 최댓값 = 선택 행동', (tester) async {
      await setPhone(tester);
      final table = QTable();
      final policy = QTablePolicy(table, epsilon: 0, name: 'test_q');
      final c = GameController(
        {1: policy, 2: policy, 3: policy},
        initialMap: FakeGridMap(),
        tickInterval: const Duration(days: 1),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(playApp(c));
      expect(find.textContaining('Q-table'), findsOneWidget);

      c.startWave();
      await tester.pump();
      // 현재 상태에서 '아래' 를 압도적으로 높게
      final s = FeatureEncoder.encode(c.sim!);
      table.set(s, HeroAction.down.index, 50);
      // 한 스텝 진행시켜 lastAction 이 채워지게 (running 이라 타이머는 하루 뒤 → 수동 트리거 불가하므로 재시작)
      c.restartSameLayout();
      await tester.pump();
      for (final a in HeroAction.values) {
        expect(find.byKey(ValueKey('qbar_${a.name}')), findsOneWidget);
      }
      expect(c.currentQ, isNotNull);
      final q = c.currentQ!;
      final best = q.indexOf(q.reduce((a, b) => a > b ? a : b));
      expect(HeroAction.values[best], HeroAction.down);
      expect(tester.takeException(), isNull);
      c.debugSetPhase(Phase.build); // 타이머 정지 (pending timer 검사)
      await tester.pump();
    });
  });

  group('진화 배너', () {
    testWidgets('메타 주입 시 승률/학습 문구, 없으면 생략', (tester) async {
      await setPhone(tester);
      final c = GameController({1: const GreedyPolicy()}, initialMap: FakeGridMap());
      addTearDown(c.dispose);
      c.debugSetWave(6);
      c.debugSetPhase(Phase.evolve);

      Widget app(EvolveOverlay o) => MaterialApp(
            home: ChangeNotifierProvider<GameController>.value(value: c, child: Scaffold(body: o)),
          );

      await tester.pumpWidget(app(const EvolveOverlay()));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byKey(const ValueKey('evolve_meta')), findsNothing);
      expect(find.textContaining('AI Stage 2'), findsWidgets);

      await tester.pumpWidget(app(const EvolveOverlay(episodes: 30000, prevWinRate: 0.12, winRate: 0.41)));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('평가 승률 12% → 41% · 학습 30,000회'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
