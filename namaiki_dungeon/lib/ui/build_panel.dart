import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import 'hud.dart';

/// 하단 빌드 패널: 팔레트 4종(이모지+이름+비용), 데모 배치, 웨이브 시작. running 중엔 비활성.
class BuildPanel extends StatelessWidget {
  const BuildPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final enabled = c.canBuild;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
    final cs = Theme.of(context).colorScheme;
    final dim = !enabled || !affordable;
    final fg = dim ? cs.onSurface.withValues(alpha: 0.45) : cs.onSurface;

    return Tooltip(
      message: '${type.korean} · ${type.statLabel} · 마나 ${type.spec.cost}',
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('palette_${type.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type.emoji, style: const TextStyle(fontSize: 22, height: 1)),
                const SizedBox(height: 2),
                Text(
                  type.korean,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.2),
                ),
                Text(
                  '🔮${type.spec.cost}',
                  style: TextStyle(fontSize: 11, color: affordable ? fg : cs.error, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
