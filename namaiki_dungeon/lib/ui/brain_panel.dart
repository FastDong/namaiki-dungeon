import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import 'theme.dart';

/// 두뇌 패널: 용사가 "보는" 상태(인접 4칸/HP/물약/직전이동) + 5행동 Q값 막대.
/// 정책이 QTablePolicy 가 아니면 "규칙 기반 용사(학습 전)" 표시.
class BrainPanel extends StatelessWidget {
  const BrainPanel({super.key});

  static String adjLabel(AdjKind k) => switch (k) {
        AdjKind.wall => '벽',
        AdjKind.empty => '빈칸',
        AdjKind.weakMonster => '약한 마물',
        AdjKind.strongMonster => '강한 마물',
        AdjKind.trap => '함정',
        AdjKind.throne => '왕좌',
      };

  static Color adjColor(AdjKind k) => switch (k) {
        AdjKind.wall => DungeonColors.muted,
        AdjKind.empty => DungeonColors.parchment,
        AdjKind.weakMonster => DungeonColors.potion,
        AdjKind.strongMonster => DungeonColors.violet,
        AdjKind.trap => DungeonColors.danger,
        AdjKind.throne => DungeonColors.gold,
      };

  static String hpBucketLabel(int b) => switch (b) {
        0 => '≤25%',
        1 => '≤50%',
        2 => '≤75%',
        _ => '>75%',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final q = c.currentQ;
    final f = c.currentFeatures;
    final isQ = c.activePolicy is QTablePolicy;
    final last = c.lastAction;

    return Container(
      key: const ValueKey('brain_panel'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: DungeonColors.stone,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DungeonColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, size: 16, color: DungeonColors.violet),
              const SizedBox(width: 6),
              Text('용사의 두뇌', style: DungeonFonts.title(size: 14, color: DungeonColors.parchment)),
              const Spacer(),
              Text(
                isQ ? 'Q-table · ${c.activePolicy.name}' : '규칙 기반 용사(학습 전)',
                key: const ValueKey('brain_policy_label'),
                style: DungeonFonts.body(size: 11, color: isQ ? DungeonColors.violet : DungeonColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!isQ)
            Text(
              '왕좌 방향으로 직진하는 규칙. 웨이브 6부터는 학습한 Q-table 용사가 등장한다.',
              style: DungeonFonts.body(size: 11, color: DungeonColors.muted),
            )
          else if (f == null || q == null)
            Text('웨이브를 시작하면 용사가 보는 상태와 행동 가치를 보여준다.',
                style: DungeonFonts.body(size: 11, color: DungeonColors.muted))
          else ...[
            _FeatureRow(f: f),
            const SizedBox(height: 8),
            SizedBox(height: 64, child: _QBars(q: q, chosen: last)),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.f});

  final StateFeatures f;

  @override
  Widget build(BuildContext context) {
    final dirs = ['↑', '↓', '←', '→'];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 4 && i < f.adj.length; i++)
          _Chip(text: '${dirs[i]} ${BrainPanel.adjLabel(f.adj[i])}', color: BrainPanel.adjColor(f.adj[i])),
        _Chip(text: 'HP ${BrainPanel.hpBucketLabel(f.hpBucket)}', color: DungeonColors.ember),
        _Chip(text: f.hasPotion ? '물약 있음' : '물약 없음', color: DungeonColors.potion),
        _Chip(text: '직전 ${f.lastMove?.korean ?? '없음'}', color: DungeonColors.muted),
        _Chip(text: '왕좌 ${_goal(f.goalDx, f.goalDy)}', color: DungeonColors.gold),
      ],
    );
  }

  static String _goal(int dx, int dy) {
    final b = StringBuffer();
    if (dy < 0) b.write('↑');
    if (dy > 0) b.write('↓');
    if (dx < 0) b.write('←');
    if (dx > 0) b.write('→');
    return b.isEmpty ? '도착' : b.toString();
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: DungeonFonts.body(size: 10.5, color: color, weight: FontWeight.w600, height: 1.2)),
    );
  }
}

/// 5행동 Q값 막대. 선택 행동 ember, 나머지 회색. 음수는 기준선 아래.
class _QBars extends StatelessWidget {
  const _QBars({required this.q, required this.chosen});

  final List<double> q;
  final HeroAction? chosen;

  @override
  Widget build(BuildContext context) {
    final maxAbs = q.fold<double>(0.5, (m, v) => v.abs() > m ? v.abs() : m);
    return LayoutBuilder(
      builder: (context, c) {
        final labelH = 14.0;
        final half = (c.maxHeight - labelH) / 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < HeroAction.values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      SizedBox(
                        height: half * 2,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 기준선
                            Positioned(
                              left: 0,
                              right: 0,
                              top: half,
                              child: Container(height: 1, color: DungeonColors.line),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: _v(i) >= 0 ? half - _h(i, half, maxAbs) : half,
                              child: AnimatedContainer(
                                key: ValueKey('qbar_${HeroAction.values[i].name}'),
                                duration: const Duration(milliseconds: 120),
                                height: _h(i, half, maxAbs),
                                decoration: BoxDecoration(
                                  color: HeroAction.values[i] == chosen
                                      ? DungeonColors.ember
                                      : DungeonColors.muted.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            Positioned(
                              top: _v(i) >= 0 ? half + 2 : half - 14,
                              child: Text(
                                _v(i).toStringAsFixed(1),
                                style: DungeonFonts.body(size: 9, color: DungeonColors.muted, height: 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: labelH,
                        child: Text(
                          HeroAction.values[i].korean,
                          style: DungeonFonts.body(
                            size: 10,
                            color: HeroAction.values[i] == chosen ? DungeonColors.ember : DungeonColors.parchment,
                            weight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _v(int i) => i < q.length ? q[i] : 0;
  double _h(int i, double half, double maxAbs) => (_v(i).abs() / maxAbs * half).clamp(2.0, half);
}
