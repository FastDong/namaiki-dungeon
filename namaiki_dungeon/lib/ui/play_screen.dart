import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import 'admin_sheet.dart';
import 'board_grid.dart';
import 'brain_panel.dart';
import 'build_panel.dart';
import 'end_screen.dart';
import 'evolve_overlay.dart';
import 'hud.dart';
import 'result_dialog.dart';
import 'theme.dart';

/// 플레이 화면: HUD + 2.5D 보드 + 두뇌 패널 + 빌드 패널, 페이즈별 오버레이(결과/진화/종료).
/// 상위에서 `ChangeNotifierProvider<GameController>`로 감싸서 띄운다.
///
/// 이펙트는 [GameController.tick] 이 바뀔 때마다 [GameController.lastEvents] 를 한 번씩 재생한다
/// (BoardGrid 안에서 key 교체 방식). 사망/왕좌 도달은 outcome 으로 보드 물들임 → 결과 카드 슬라이드업.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  GameController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<GameController>();
    if (!identical(c, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = c;
      c.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// 코어 예외 등 오류 메시지를 스낵바로 표시.
  void _onControllerChanged() {
    final err = _controller?.takeError();
    if (err == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _snack(err, isError: true);
    });
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: DungeonFonts.body(size: 13)),
        duration: Duration(milliseconds: isError ? 3500 : 1200),
        backgroundColor: isError ? const Color(0xFF4A1F22) : DungeonColors.stone,
      ));
  }

  void _onCellTap(GameController c, Pos p) {
    if (!c.canBuild) return;
    if (c.map.monsters.containsKey(p)) {
      c.removeAt(p);
      return;
    }
    if (c.selected.spec.cost > c.mana) {
      _snack('마나가 부족합니다 (${c.selected.korean} ${c.selected.spec.cost}, 보유 ${c.mana})');
      return;
    }
    if (!c.placeAt(p)) {
      _snack('여기엔 배치할 수 없습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final phase = c.phase;
    final ended = phase == Phase.result || phase == Phase.gameOver || phase == Phase.victory;

    return Theme(
      data: DungeonTheme.of(context),
      child: Scaffold(
        backgroundColor: DungeonColors.void_,
        appBar: AppBar(
          title: Text('마왕의 던전', style: DungeonFonts.title(size: 20)),
          actions: [
            IconButton(
              key: const ValueKey('admin_button'),
              tooltip: '관리자',
              icon: const Icon(Icons.settings, color: DungeonColors.muted),
              onPressed: () => AdminSheet.show(context),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 배경: 아주 은은한 violet 비네트
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [Color(0xFF1B1626), DungeonColors.void_],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Hud(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          // 세로가 모자라면 보드를 줄인다 (기울인 높이 = side * footprintRatio).
                          final byHeight = box.maxHeight.isFinite
                              ? box.maxHeight / BoardGrid.footprintRatio
                              : double.infinity;
                          final side = [360.0, box.maxWidth, byHeight].reduce((a, b) => a < b ? a : b);
                          return Center(
                            child: BoardGrid(
                              map: c.boardMap,
                              trail: c.trail,
                              heroPos: c.showHero ? c.sim?.heroPos : null,
                              buildMode: c.canBuild,
                              onCellTap: (p) => _onCellTap(c, p),
                              events: c.lastEvents,
                              tick: c.tick,
                              heroDamage: c.lastHeroDamage,
                              outcome: ended ? c.lastOutcome : null,
                              maxSide: side.clamp(120.0, 360.0),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const BrainPanel(),
                  const BuildPanel(),
                ],
              ),
            ),
            if (phase == Phase.result) const ResultDialog(),
            if (phase == Phase.evolve) const EvolveOverlay(),
            if (phase == Phase.gameOver || phase == Phase.victory) const EndScreen(),
          ],
        ),
      ),
    );
  }
}
