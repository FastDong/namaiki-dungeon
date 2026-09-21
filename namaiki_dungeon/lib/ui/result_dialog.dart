import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';

/// 웨이브 결과 카드. 보드 위에 겹쳐 그려 트레일이 보이는 채로 결과를 확인한다.
/// (Phase.result일 때 PlayScreen이 Stack에 올린다.)
class ResultDialog extends StatelessWidget {
  const ResultDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final sim = c.sim;
    final outcome = c.lastOutcome;
    final defended = outcome?.defended ?? false;
    final cs = Theme.of(context).colorScheme;

    final title = switch (outcome) {
      Outcome.heroDied => '용사를 쓰러뜨렸다!',
      Outcome.gaveUp => '용사가 퇴각했다!',
      Outcome.reachedThrone => '왕좌가 함락됐다…',
      _ => '웨이브 종료',
    };
    final subtitle = defended
        ? '웨이브 ${c.wave} 방어 성공 · 마나 +${WaveRules.manaPerWave}'
        : '웨이브 ${c.wave} 방어 실패';

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              key: const ValueKey('result_dialog'),
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      defended ? '🛡️ $title' : '💀 $title',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    if (sim != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Stat(label: '턴', value: '${sim.steps}'),
                          _Stat(label: 'HP 손실', value: '${sim.hpLost}'),
                          _Stat(label: '함정', value: '${sim.trapHits}'),
                          _Stat(label: '처치', value: '${sim.kills}'),
                          _Stat(label: '물약', value: '${sim.potionsUsed}'),
                        ],
                      ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('next_wave_button'),
                      onPressed: c.nextWave,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        WaveRules.isStageTransition(c.wave, c.wave + 1)
                            ? '다음 웨이브 (용사가 진화한다…)'
                            : '다음 웨이브',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.1)),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.2)),
        ],
      ),
    );
  }
}
