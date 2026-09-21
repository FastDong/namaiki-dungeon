import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';

/// 7x7 보드. 셀 = 색 Container + 이모지 텍스트 + 트레일(순번 + 반투명 배경).
///
/// 규칙 판정(기둥/배치 가능)은 전부 [GridMap]에 묻는다. 앱은 규칙을 재구현하지 않는다.
class BoardGrid extends StatelessWidget {
  const BoardGrid({
    super.key,
    required this.map,
    required this.trail,
    this.heroPos,
    this.buildMode = false,
    this.onCellTap,
  });

  /// 그릴 맵 (빌드 중엔 레이아웃, 웨이브 중엔 시뮬레이터 맵).
  final GridMap map;

  /// 방문 순서. 비어 있으면 트레일 없음.
  final List<Pos> trail;

  /// 용사 위치 (null이면 그리지 않음).
  final Pos? heroPos;

  /// 빌드 페이즈면 배치 가능 칸을 살짝 강조.
  final bool buildMode;

  final void Function(Pos p)? onCellTap;

  static const String heroEmoji = '🧝';
  static const String throneEmoji = '👑';
  static const String entranceEmoji = '🚪';

  @override
  Widget build(BuildContext context) {
    // 첫 방문 순번만 표시 (같은 칸 재방문은 첫 번호 유지).
    final firstVisit = <Pos, int>{};
    for (var i = 0; i < trail.length; i++) {
      firstVisit.putIfAbsent(trail[i], () => i);
    }
    final cs = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: GridView.builder(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Balance.cols,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: Balance.cols * Balance.rows,
            itemBuilder: (context, i) {
              final p = Pos.fromIndex(i);
              return _Cell(
                key: ValueKey('cell_${p.x}_${p.y}'),
                pos: p,
                map: map,
                visitIndex: firstVisit[p],
                hasHero: heroPos == p,
                buildMode: buildMode,
                onTap: onCellTap == null ? null : () => onCellTap!(p),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.pos,
    required this.map,
    required this.visitIndex,
    required this.hasHero,
    required this.buildMode,
    required this.onTap,
  });

  final Pos pos;
  final GridMap map;
  final int? visitIndex;
  final bool hasHero;
  final bool buildMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPillar = map.isPillar(pos);
    final isThrone = map.isThrone(pos);
    final isEntrance = map.isEntrance(pos);
    final monster = map.monsters[pos];

    Color bg;
    if (isPillar) {
      bg = const Color(0xFF3A3A44); // 기둥: 진회색
    } else if (isThrone) {
      bg = const Color(0xFF5A3E1B);
    } else if (isEntrance) {
      bg = const Color(0xFF1E3A4A);
    } else if (monster != null) {
      bg = monster.isTrap ? const Color(0xFF4A2A2A) : const Color(0xFF2E2A4A);
    } else {
      bg = cs.surfaceContainerHigh;
    }

    // 배치 가능 칸 강조 (빌드 페이즈, 빈 칸일 때만 규칙에 묻는다)
    final placeable = buildMode && !isPillar && monster == null && !isThrone && !isEntrance && map.isPlaceable(pos);

    final trailColor = Colors.amber.withValues(alpha: 0.28);

    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth;
        final emojiSize = (side * 0.5).clamp(12.0, 30.0);
        final tinySize = (side * 0.22).clamp(8.0, 12.0);
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: placeable
                  ? Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1)
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (visitIndex != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: trailColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                if (visitIndex != null)
                  Positioned(
                    left: 2,
                    top: 1,
                    child: Text(
                      '${visitIndex! + 1}',
                      style: TextStyle(
                        fontSize: tinySize,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade200,
                        height: 1,
                      ),
                    ),
                  ),
                Center(child: _content(emojiSize, tinySize, monster, isPillar, isThrone, isEntrance)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content(double emojiSize, double tinySize, Monster? monster, bool isPillar, bool isThrone, bool isEntrance) {
    if (hasHero) {
      return Text(BoardGrid.heroEmoji, style: TextStyle(fontSize: emojiSize, height: 1));
    }
    if (isPillar) return const SizedBox.shrink();
    if (isThrone) {
      return Text(BoardGrid.throneEmoji, style: TextStyle(fontSize: emojiSize, height: 1));
    }
    if (isEntrance) {
      return Text(BoardGrid.entranceEmoji, style: TextStyle(fontSize: emojiSize * 0.8, height: 1));
    }
    if (monster == null) return const SizedBox.shrink();
    if (monster.isTrap) {
      return Text(monster.type.emoji, style: TextStyle(fontSize: emojiSize, height: 1));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(monster.type.emoji, style: TextStyle(fontSize: emojiSize * 0.85, height: 1)),
        Text(
          '${monster.hp}',
          style: TextStyle(
            fontSize: tinySize,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: monster.hp < monster.maxHp ? Colors.redAccent.shade100 : Colors.white70,
          ),
        ),
      ],
    );
  }
}
