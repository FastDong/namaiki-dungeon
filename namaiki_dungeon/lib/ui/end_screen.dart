import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'board_grid.dart';
import 'theme.dart';

/// 게임 오버 / 승리 전체화면. "다시 시작"은 메뉴로 돌아간다.
/// 왕좌 도달(게임오버)은 보드 ember 물들임 뒤 페이드인, 승리는 gold.
class EndScreen extends StatelessWidget {
  const EndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final victory = c.phase == Phase.victory;
    final run = _safeRun(c);
    final accent = victory ? DungeonColors.gold : DungeonColors.ember;

    final minutes = c.durationSec ~/ 60;
    final seconds = c.durationSec % 60;

    return TweenAnimationBuilder<double>(
      key: ValueKey('end_anim_${c.phase}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
      builder: (context, t, child) => ColoredBox(
        color: DungeonColors.void_.withValues(alpha: 0.94 * t),
        child: Opacity(opacity: t, child: child),
      ),
      child: ColoredBox(
        key: ValueKey(victory ? 'victory_screen' : 'game_over_screen'),
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
                      boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 26)],
                    ),
                    child: Sprite(victory ? SpriteKind.throne : SpriteKind.hero, size: 56),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    victory ? '승리!' : '왕좌가 함락됐다',
                    style: DungeonFonts.title(size: 32, color: accent),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    victory
                        ? '${WaveRules.totalWaves}웨이브를 모두 막아냈다. 용사는 끝내 마왕을 넘지 못했다.'
                        : '웨이브 ${c.wave}의 용사가 왕좌에 도달했다.',
                    style: DungeonFonts.body(size: 14, color: DungeonColors.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: DungeonColors.stone,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DungeonColors.line),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Row('막아낸 웨이브', '${c.wavesCleared} / ${WaveRules.totalWaves}'),
                        _Row('도달 단계', 'AI Stage ${run.stageReached} (${WaveRules.stageName(run.stageReached)})',
                            color: DungeonColors.stage(run.stageReached)),
                        _Row('용사 처치', '${c.heroDeaths}회', color: DungeonColors.violet),
                        _Row('플레이 시간', '$minutes분 $seconds초'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const ValueKey('back_to_menu_button'),
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: DungeonColors.void_,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    ),
                    icon: const Icon(Icons.replay),
                    label: const Text('다시 시작 (메뉴로)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// buildRun은 맵 직렬화를 포함하므로 (코어 미구현 시) 실패해도 화면은 떠야 한다.
  static ({int stageReached}) _safeRun(GameController c) {
    try {
      return (stageReached: c.buildRun().stageReached);
    } catch (_) {
      return (stageReached: WaveRules.stageForWave(c.wave));
    }
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color = DungeonColors.parchment});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: DungeonFonts.body(size: 13, color: DungeonColors.muted)),
            TextSpan(text: value, style: DungeonFonts.body(size: 14, color: color, weight: FontWeight.w800)),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
