import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import 'board_grid.dart';
import 'hud.dart';
import 'theme.dart';

/// 하단 빌드 패널: 팔레트 4종(벡터 스프라이트+이름+비용), 데모 배치, 웨이브 시작. running 중엔 비활성.
class BuildPanel extends StatelessWidget {
  const BuildPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final enabled = c.canBuild;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: DungeonColors.stone,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: DungeonColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final t in MonsterType.values) ...[
                Expanded(
                  child: _PaletteButton(
                    type: t,
                    selected: c.selected == t,
                    affordable: t.spec.cost <= c.mana,
                    enabled: enabled,
                    onTap: () => c.selected = t,
                  ),
                ),
                if (t != MonsterType.values.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? c.loadDemoLayout : null,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('데모 배치'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: enabled ? c.startWave : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: DungeonColors.ember,
                    foregroundColor: DungeonColors.void_,
                    disabledBackgroundColor: DungeonColors.floor,
                    disabledForegroundColor: DungeonColors.muted,
                  ),
                  icon: Icon(c.isRunning ? Icons.hourglass_top : Icons.play_arrow),
                  label: Text(c.isRunning ? '용사 침입 중…' : '웨이브 시작'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.type,
    required this.selected,
    required this.affordable,
    required this.enabled,
    required this.onTap,
  });

  final MonsterType type;
  final bool selected;
  final bool affordable;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = !enabled || !affordable;
    final fg = dim ? DungeonColors.parchment.withValues(alpha: 0.45) : DungeonColors.parchment;
    final accent = type.isTrap ? DungeonColors.muted : DungeonColors.violet;

    return Tooltip(
      message: '${type.korean} · ${type.statLabel} · 마나 ${type.spec.cost}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? DungeonColors.monsterCell : DungeonColors.floor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? accent : DungeonColors.line, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 10)] : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('palette_${type.name}'),
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(opacity: dim ? 0.45 : 1, child: Sprite(type.sprite, size: 26)),
                  const SizedBox(height: 3),
                  Text(
                    type.korean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DungeonFonts.body(size: 11, weight: FontWeight.w700, color: fg, height: 1.2),
                  ),
                  Text(
                    '◆ ${type.spec.cost}',
                    style: DungeonFonts.body(
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: affordable ? DungeonColors.gold.withValues(alpha: dim ? 0.5 : 1) : DungeonColors.danger,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
