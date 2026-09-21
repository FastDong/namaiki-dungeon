import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import 'admin_sheet.dart';
import 'board_grid.dart';
import 'build_panel.dart';
import 'end_screen.dart';
import 'evolve_overlay.dart';
import 'hud.dart';
import 'result_dialog.dart';

/// 플레이 화면: HUD + 보드 + 빌드 패널, 페이즈별 오버레이(결과/진화/종료).
/// 상위에서 `ChangeNotifierProvider<GameController>`로 감싸서 띄운다.
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
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: Duration(milliseconds: isError ? 3500 : 1200),
        backgroundColor: isError ? cs.errorContainer : null,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('마왕의 던전'),
        actions: [
          IconButton(
            key: const ValueKey('admin_button'),
            tooltip: '관리자',
            icon: const Icon(Icons.settings),
            onPressed: () => AdminSheet.show(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Column(
              children: [
                const Hud(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Center(
                      child: BoardGrid(
                        map: c.boardMap,
                        trail: c.trail,
                        heroPos: c.showHero ? c.sim?.heroPos : null,
                        buildMode: c.canBuild,
                        onCellTap: (p) => _onCellTap(c, p),
                      ),
                    ),
                  ),
                ),
                const BuildPanel(),
              ],
            ),
          ),
          if (phase == Phase.result) const ResultDialog(),
          if (phase == Phase.evolve) const EvolveOverlay(),
          if (phase == Phase.gameOver || phase == Phase.victory) const EndScreen(),
        ],
      ),
    );
  }
}
