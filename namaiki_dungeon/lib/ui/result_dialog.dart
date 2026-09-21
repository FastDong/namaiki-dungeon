import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'board_grid.dart';
import 'theme.dart';

/// 웨이브 결과 카드. 보드 위에 겹쳐 그려 트레일이 보이는 채로 결과를 확인한다.
/// (Phase.result일 때 PlayScreen이 Stack에 올린다.) 사망 연출(420ms) 뒤 아래에서 슬라이드업.
class ResultDialog extends StatelessWidget {
  const ResultDialog({super.key, this.delay = const Duration(milliseconds: 380)});

  /// 보드 연출이 끝난 뒤 카드가 올라오기까지 대기.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final sim = c.sim;
    final outcome = c.lastOutcome;
    final defended = outcome?.defended ?? false;
    final accent = defended ? DungeonColors.violet : DungeonColors.ember;

    final title = switch (outcome) {
      Outcome.heroDied => '용사를 쓰러뜨렸다!',
      Outcome.gaveUp => '용사가 퇴각했다!',
      Outcome.reachedThrone => '왕좌가 함락됐다…',
      _ => '웨이브 종료',
    };
    final subtitle = defended
        ? '웨이브 ${c.wave} 방어 성공 · 마나 +${WaveRules.manaPerWave}'
        : '웨이브 ${c.wave} 방어 실패';

    return TweenAnimationBuilder<double>(
      key: ValueKey('result_anim_${c.wave}_${c.tick}'),
      tween: Tween(begin: 0, end: 1),
      duration: delay + const Duration(milliseconds: 320),
      curve: Interval(delay.inMilliseconds / (delay.inMilliseconds + 320), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.45 * t),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionalTranslation(
            translation: Offset(0, 1 - t),
            child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            key: const ValueKey('result_dialog'),
            decoration: BoxDecoration(
              color: DungeonColors.stone,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 8)),
                BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 30),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Sprite(defended ? SpriteKind.throne : SpriteKind.hero, size: 26),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: DungeonFonts.title(size: 20, color: accent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, textAlign: TextAlign.center, style: DungeonFonts.body(size: 13, color: DungeonColors.muted)),
                const SizedBox(height: 12),
                if (sim != null)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Stat(label: '턴', value: '${sim.steps}', color: DungeonColors.parchment),
                      _Stat(label: 'HP 손실', value: '${sim.hpLost}', color: DungeonColors.ember),
                      _Stat(label: '함정', value: '${sim.trapHits}', color: DungeonColors.danger),
                      _Stat(label: '처치', value: '${sim.kills}', color: DungeonColors.violet),
                      _Stat(label: '물약', value: '${sim.potionsUsed}', color: DungeonColors.potion),
                    ],
                  ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('next_wave_button'),
                  onPressed: c.nextWave,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    WaveRules.isStageTransition(c.wave, c.wave + 1) ? '다음 웨이브 (용사가 진화한다…)' : '다음 웨이브',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: DungeonColors.floor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DungeonColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: DungeonFonts.title(size: 18, color: color, height: 1.1)),
          Text(label, style: DungeonFonts.body(size: 11, color: DungeonColors.muted, height: 1.2)),
        ],
      ),
    );
  }
}
