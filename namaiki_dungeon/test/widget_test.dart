import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:namaiki_dungeon/game/game_controller.dart';
import 'package:namaiki_dungeon/main.dart';
import 'package:namaiki_dungeon/ui/leaderboard_screen.dart';
import 'package:namaiki_dungeon/ui/play_screen.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  setUpAll(() {
    // 위젯 테스트에선 네트워크 폰트 페치 금지 → 기본 폰트 폴백
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final policies = <int, HeroPolicy>{
    for (var s = 1; s <= 3; s++) s: const GreedyPolicy(),
  };

  /// 모바일 세로 화면 (360x740 논리 픽셀) 크기로 고정.
  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('메뉴: 제목·게임 시작·리더보드(Firebase 없으면 오류 상태)', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(NamaikiApp(policies: policies));

    expect(find.text('마왕의 던전'), findsOneWidget);
    expect(find.text('게임 시작'), findsOneWidget);
    expect(find.text('리더보드'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('leaderboard_button')));
    // 라우트 전환 + Firestore 미초기화 예외 → 오류 상태 (로딩 인디케이터는 무한 애니메이션이라 pumpAndSettle 금지)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(LeaderboardScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('leaderboard_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Widget playApp(GameController c) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: ChangeNotifierProvider<GameController>.value(
          value: c,
          child: const PlayScreen(),
        ),
      );

  testWidgets('플레이 화면: HUD·팔레트·보드가 360px 폭에서 오버플로 없이 그려진다', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    expect(find.text('웨이브 1/${Balance.totalWaves}'), findsOneWidget);
    expect(find.textContaining('AI Stage 1'), findsOneWidget);
    expect(find.text('🔮 마나 ${Balance.startMana}'), findsOneWidget);
    expect(find.text('웨이브 시작'), findsOneWidget);
    expect(find.text('데모 배치'), findsOneWidget);
    for (final t in MonsterType.values) {
      expect(find.byKey(ValueKey('palette_${t.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('cell_0_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('cell_6_6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('셀 탭: 배치 → 마나 차감, 다시 탭 → 제거·환불', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    // 고블린 선택 후 (2,2) 배치
    await tester.tap(find.byKey(const ValueKey('palette_goblin')));
    await tester.pump();
    expect(c.selected, MonsterType.goblin);

    await tester.tap(find.byKey(const ValueKey('cell_2_2')));
    await tester.pump();
    final cost = MonsterType.goblin.spec.cost;
    expect(c.mana, Balance.startMana - cost);
    expect(find.text('🔮 마나 ${Balance.startMana - cost}'), findsOneWidget);
    expect(find.byKey(const ValueKey('sprite_goblin')), findsWidgets);

    // 같은 칸 다시 탭 → 제거
    await tester.tap(find.byKey(const ValueKey('cell_2_2')));
    await tester.pump();
    expect(c.mana, Balance.startMana);
    expect(c.map.monsters, isEmpty);

    // 기둥 탭 → 배치 불가 스낵바
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    expect(find.text('여기엔 배치할 수 없습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('running 중엔 팔레트·시작 버튼 비활성, 셀 탭 무시', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    c.debugSetPhase(Phase.running);
    await tester.pump();

    expect(find.text('용사 침입 중…'), findsOneWidget);
    final start = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '용사 침입 중…'));
    expect(start.onPressed, isNull);
    final demo = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '데모 배치'));
    expect(demo.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('cell_2_2')));
    await tester.pump();
    expect(c.mana, Balance.startMana);
    expect(tester.takeException(), isNull);
  });

  testWidgets('result → 결과 카드 → 다음 웨이브, 5웨이브 뒤엔 진화 배너', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    c.debugSetWave(5);
    c.debugSetPhase(Phase.result);
    await tester.pump();
    expect(find.byKey(const ValueKey('result_dialog')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900)); // 슬라이드업 종료 대기

    await tester.tap(find.byKey(const ValueKey('next_wave_button')));
    await tester.pump();
    expect(c.wave, 6);
    expect(c.phase, Phase.evolve);
    expect(find.byKey(const ValueKey('evolve_overlay')), findsOneWidget);
    expect(find.textContaining('AI Stage 2'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1000)); // 링/오버슈트 애니메이션 종료

    await tester.tap(find.byKey(const ValueKey('evolve_continue_button')));
    await tester.pump();
    expect(c.phase, Phase.build);
    expect(find.text('웨이브 6/${Balance.totalWaves}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('게임 오버/승리 화면 → 메뉴로 복귀', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    // 메뉴 대역: 버튼 하나로 PlayScreen을 push (실제 MenuScreen은 스텁 GridMap을 쓰므로 여기선 대역 사용)
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider<GameController>.value(
                    value: c,
                    child: const PlayScreen(),
                  ),
                ),
              ),
              child: const Text('게임 시작'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsOneWidget);

    c.debugSetPhase(Phase.gameOver);
    await tester.pump();
    expect(find.byKey(const ValueKey('game_over_screen')), findsOneWidget);
    expect(find.text('왕좌가 함락됐다'), findsOneWidget);

    c.debugSetPhase(Phase.victory);
    await tester.pump();
    expect(find.byKey(const ValueKey('victory_screen')), findsOneWidget);
    expect(find.text('승리!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('back_to_menu_button')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayScreen), findsNothing);
    expect(find.text('게임 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin 시트: 단계 강제 토글이 뱃지에 반영', (tester) async {
    await setPhone(tester);
    final c = GameController(policies, initialMap: FakeGridMap());
    addTearDown(c.dispose);
    await tester.pumpWidget(playApp(c));

    await tester.tap(find.byKey(const ValueKey('admin_button')));
    await tester.pumpAndSettle();
    expect(find.text('관리자'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('force_stage_3')));
    await tester.pumpAndSettle();
    expect(c.forcedStage, 3);
    expect(c.stage, 3);

    // 시트 닫기
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI Stage 3'), findsOneWidget);
    expect(find.textContaining('(강제)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
