import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'board_grid.dart';
import 'theme.dart';

/// 상단 HUD: 웨이브, AI 단계 뱃지, 마나, 용사 HP바(피격 시 ember 점멸), 물약/턴/함정/처치/HP손실.
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
    final hitTick = (showSim && c.lastHeroDamage > 0) ? c.tick : null;

    final small = DungeonFonts.body(size: 11.5, color: DungeonColors.muted, weight: FontWeight.w500);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(
                text: '웨이브 ${c.wave}/${WaveRules.totalWaves}',
                color: DungeonColors.stone,
                fg: DungeonColors.parchment,
                border: DungeonColors.line,
              ),
              _Pill(
                text: '🔮 마나 ${c.mana}',
                color: DungeonColors.gold.withValues(alpha: 0.16),
                fg: DungeonColors.gold,
                border: DungeonColors.gold.withValues(alpha: 0.5),
              ),
              StageBadge(stage: c.stage, forced: c.forcedStage != null),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Sprite(SpriteKind.hero, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: _HpBar(ratio: ratio, hp: hp, maxHp: maxHp, hitTick: hitTick),
              ),
              const SizedBox(width: 8),
              Text('⚔ $atk', style: small.copyWith(color: DungeonColors.parchment)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              Text('🧪 물약 $potions', style: small.copyWith(color: DungeonColors.potion)),
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

class _HpBar extends StatelessWidget {
  const _HpBar({required this.ratio, required this.hp, required this.maxHp, required this.hitTick});

  final double ratio;
  final int hp;
  final int maxHp;
  final int? hitTick;

  @override
  Widget build(BuildContext context) {
    final barColor = ratio > 0.5 ? DungeonColors.potion : (ratio > 0.25 ? DungeonColors.gold : DungeonColors.ember);
    Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const ColoredBox(color: DungeonColors.floor, child: SizedBox(height: 16, width: double.infinity)),
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              widthFactor: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [barColor.withValues(alpha: 0.85), barColor]),
                ),
                child: const SizedBox(height: 16),
              ),
            ),
          ),
          Text(
            'HP $hp / $maxHp',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
              shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
          if (hitTick != null)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('hp_flash_$hitTick'),
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 200),
                builder: (_, t, _) => ColoredBox(
                  color: DungeonColors.ember.withValues(alpha: 0.6 * sin(t * pi).clamp(0.0, 1.0)),
                ),
              ),
            ),
        ],
      ),
    );
    return bar;
  }
}

/// AI 단계 뱃지. 단계별 색상, admin 강제 시 표시.
class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage, this.forced = false});

  final int stage;
  final bool forced;

  static Color colorFor(int stage) => DungeonColors.stage(stage);

  @override
  Widget build(BuildContext context) {
    final color = colorFor(stage);
    return _Pill(
      text: 'AI Stage $stage · ${WaveRules.stageName(stage)}${forced ? ' (강제)' : ''}',
      color: color.withValues(alpha: 0.18),
      fg: color,
      border: color.withValues(alpha: 0.6),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.fg, required this.border});

  final String text;
  final Color color;
  final Color fg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: DungeonFonts.body(size: 12, weight: FontWeight.w700, color: fg, height: 1.2),
      ),
    );
  }
}

/// 마물 종류 → 표시용 짧은 설명 (팔레트/결과에서 공용).
extension MonsterTypeUi on MonsterType {
  String get statLabel => isTrap ? '진입 시 ${spec.atk}' : 'HP ${spec.hp} · ATK ${spec.atk}';
}
