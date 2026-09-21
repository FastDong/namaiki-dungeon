import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'hud.dart';

/// 진화 배너 (웨이브 5/10 클리어 뒤 전체화면 반투명).
/// "용사가 N번의 죽음에서 배웠다 — AI Stage k". 승률/학습 횟수는 정책 메타(M6)로 대체될 자리 표시.
class EvolveOverlay extends StatelessWidget {
  const EvolveOverlay({
    super.key,
    this.episodes,
    this.prevWinRate,
    this.winRate,
  });

  /// 정책 메타 (없으면 자리 표시 문구). M6에서 PolicySource.meta로 채운다.
  final int? episodes;
  final double? prevWinRate;
  final double? winRate;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final stage = c.waveStage;
    final deaths = c.heroDeaths;
    final color = StageBadge.colorFor(stage);

    final String metaLine;
    if (winRate != null && prevWinRate != null) {
      metaLine = '평가 승률 ${(prevWinRate! * 100).round()}% → ${(winRate! * 100).round()}%'
          '${episodes != null ? ' · 학습 ${_fmt(episodes!)}회' : ''}';
    } else if (winRate != null) {
      metaLine = '평가 승률 ${(winRate! * 100).round()}%${episodes != null ? ' · 학습 ${_fmt(episodes!)}회' : ''}';
    } else {
      metaLine = '(평가 승률 · 학습 횟수: 정책 메타 연결 예정)';
    }

    return ColoredBox(
      key: const ValueKey('evolve_overlay'),
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡', style: TextStyle(fontSize: 56, height: 1)),
                const SizedBox(height: 12),
                Text(
                  '용사가 진화했다',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '용사가 $deaths번의 죽음에서 배웠다',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
                  child: Text(
                    'AI Stage $stage — ${WaveRules.stageName(stage)} 용사',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                Text(metaLine, style: const TextStyle(fontSize: 13, color: Colors.white60), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const ValueKey('evolve_continue_button'),
                  onPressed: c.dismissEvolve,
                  icon: const Icon(Icons.shield),
                  label: Text('웨이브 ${c.wave} 준비'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
