import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';

/// 게임 오버 / 승리 전체화면. "다시 시작"은 메뉴로 돌아간다.
class EndScreen extends StatelessWidget {
  const EndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final victory = c.phase == Phase.victory;
    final run = _safeRun(c);

    final minutes = c.durationSec ~/ 60;
    final seconds = c.durationSec % 60;

    return ColoredBox(
      key: ValueKey(victory ? 'victory_screen' : 'game_over_screen'),
      color: Colors.black.withValues(alpha: 0.9),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(victory ? '🏆' : '💀', style: const TextStyle(fontSize: 64, height: 1)),
                const SizedBox(height: 12),
                Text(
                  victory ? '승리!' : '왕좌가 함락됐다',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  victory
                      ? '${WaveRules.totalWaves}웨이브를 모두 막아냈다. 용사는 끝내 마왕을 넘지 못했다.'
                      : '웨이브 ${c.wave}의 용사가 왕좌에 도달했다.',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _Row('막아낸 웨이브', '${c.wavesCleared} / ${WaveRules.totalWaves}'),
                _Row('도달 단계', 'AI Stage ${run.stageReached} (${WaveRules.stageName(run.stageReached)})'),
                _Row('용사 처치', '${c.heroDeaths}회'),
                _Row('플레이 시간', '$minutes분 $seconds초'),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const ValueKey('back_to_menu_button'),
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: const Icon(Icons.replay),
                  label: const Text('다시 시작 (메뉴로)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// buildRun은 맵 직렬화를 포함하므로 (코어 미구현 시) 실패해도 화면은 떠야 한다.
  static ({int stageReached}) _safeRun(GameController c) {
    try {
      return (stageReached: c.buildRun().stageReached);
    } catch (_) {
      return (stageReached: WaveRules.stageForWave(c.wave));
    }
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: const TextStyle(color: Colors.white60)),
            TextSpan(text: value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
