import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'hud.dart';

/// admin 바텀시트: 단계 강제 토글(없음/1/2/3) + 같은 배치로 다시.
/// 같은 배치에서 stage1/2/3 경로를 나란히 찍기 위한 도구 (PLAN §5.9).
class AdminSheet extends StatelessWidget {
  const AdminSheet({super.key});

  /// PlayScreen에서 호출. 시트 안에서도 같은 GameController를 쓰도록 provider를 넘긴다.
  static Future<void> show(BuildContext context) {
    final controller = context.read<GameController>();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider<GameController>.value(
        value: controller,
        child: const AdminSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: 20),
                const SizedBox(width: 8),
                Text('관리자', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('현재 ${c.phase.korean} · 웨이브 ${c.wave}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Text('AI 단계 강제 (다음 웨이브 시작부터 적용)', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('force_stage_none'),
                  label: const Text('없음 (웨이브 기준)'),
                  selected: c.forcedStage == null,
                  onSelected: (_) => c.forcedStage = null,
                ),
                for (var s = 1; s <= WaveRules.stageCount; s++)
                  ChoiceChip(
                    key: ValueKey('force_stage_$s'),
                    label: Text('Stage $s ${WaveRules.stageName(s)}'),
                    selected: c.forcedStage == s,
                    selectedColor: StageBadge.colorFor(s),
                    onSelected: (_) => c.forcedStage = s,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '적용 정책: ${c.policyForStage(c.stage).name} (Stage ${c.stage})',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const Divider(height: 24),
            ListTile(
              key: const ValueKey('restart_same_layout'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.replay),
              title: const Text('같은 배치로 다시'),
              subtitle: const Text('현재 레이아웃을 유지하고 같은 웨이브를 다시 실행'),
              onTap: () {
                c.restartSameLayout();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
