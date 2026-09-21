import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';

/// 상단 HUD: 웨이브, AI 단계 뱃지, 마나, 용사 HP바, 물약/턴/함정/처치/HP손실.
class Hud extends StatelessWidget {
  const Hud({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final sim = c.sim;
    final stats = c.heroStats;
    final showSim = sim != null && c.phase != Phase.build && c.phase != Phase.evolve;

    final hp = showSim ? sim.hp : stats.maxHp;
    final maxHp = showSim ? sim.maxHp : stats.maxHp;
    final atk = showSim ? sim.atk : stats.atk;
    final potions = showSim ? sim.potions : stats.potions;
    final steps = showSim ? sim.steps : 0;
    final trapHits = showSim ? sim.trapHits : 0;
    final kills = showSim ? sim.kills : 0;
    final hpLost = showSim ? sim.hpLost : 0;
    final ratio = maxHp == 0 ? 0.0 : (hp / maxHp).clamp(0.0, 1.0);

    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 좁은 폭(360px)에서도 넘치지 않도록 Wrap.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(
                text: '웨이브 ${c.wave}/${WaveRules.totalWaves}',
                color: cs.secondaryContainer,
                fg: cs.onSecondaryContainer,
              ),
              _Pill(
                text: '🔮 마나 ${c.mana}',
                color: cs.tertiaryContainer,
                fg: cs.onTertiaryContainer,
              ),
              StageBadge(stage: c.stage, forced: c.forcedStage != null),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('🧝', style: TextStyle(fontSize: 16, height: 1, color: cs.onSurface)),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      LinearProgressIndicator(
                        value: ratio,
                        minHeight: 16,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: ratio > 0.5
                            ? Colors.green.shade400
                            : (ratio > 0.25 ? Colors.orange.shade400 : Colors.red.shade400),
                      ),
                      Text(
                        'HP $hp / $maxHp',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, height: 1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('⚔ $atk', style: small),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              Text('🧪 물약 $potions', style: small),
              Text('턴 $steps/${WaveRules.maxSteps}', style: small),
              Text('함정 $trapHits', style: small),
              Text('처치 $kills', style: small),
              Text('HP손실 $hpLost', style: small),
            ],
          ),
        ],
      ),
    );
  }
}

/// AI 단계 뱃지. 단계별 색상, admin 강제 시 표시.
class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage, this.forced = false});

  final int stage;
  final bool forced;

  static Color colorFor(int stage) => switch (stage) {
        1 => const Color(0xFF3F8F4F),
        2 => const Color(0xFFB8741A),
        3 => const Color(0xFFB0304A),
        _ => const Color(0xFF555555),
      };

  @override
  Widget build(BuildContext context) {
    return _Pill(
      text: 'AI Stage $stage · ${WaveRules.stageName(stage)}${forced ? ' (강제)' : ''}',
      color: colorFor(stage),
      fg: Colors.white,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.fg});

  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.2),
      ),
    );
  }
}

/// 마물 종류 → 표시용 짧은 설명 (팔레트/결과에서 공용).
extension MonsterTypeUi on MonsterType {
  String get statLabel => isTrap ? '진입 시 ${spec.atk}' : 'HP ${spec.hp} · ATK ${spec.atk}';
}
