import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'play_screen.dart';

/// 메뉴: 제목, 게임 시작, 리더보드(준비 중), 짧은 설명.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.policies});

  /// 단계 → 용사 정책. PlayScreen의 GameController에 그대로 주입된다.
  final Map<int, HeroPolicy> policies;

  void _startGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<GameController>(
          create: (_) => GameController(policies),
          child: const PlayScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('👑', textAlign: TextAlign.center, style: TextStyle(fontSize: 64, height: 1)),
                  const SizedBox(height: 12),
                  Text(
                    '마왕의 던전',
                    textAlign: TextAlign.center,
                    style: tt.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '죽을수록 똑똑해지는 용사',
                    textAlign: TextAlign.center,
                    style: tt.titleMedium?.copyWith(color: cs.primary),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    key: const ValueKey('start_button'),
                    onPressed: () => _startGame(context),
                    icon: const Icon(Icons.play_arrow),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('게임 시작', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('leaderboard_button'),
                    onPressed: () {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('리더보드는 준비 중입니다')));
                    },
                    icon: const Icon(Icons.leaderboard),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('리더보드', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('어떻게 노나', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        _Line('🔮', '마나로 마물과 함정을 배치해 왕좌 👑를 지킨다. 시작 ${WaveRules.startMana}, 웨이브마다 +${WaveRules.manaPerWave}.'),
                        _Line('🧝', '용사는 강화학습(Q-learning)으로 미리 훈련된 AI. 총 ${WaveRules.totalWaves}웨이브.'),
                        _Line('⚡', '${Balance.wavesPerStage}웨이브를 막을 때마다 더 많이 학습한 용사가 등장한다 (Stage 1→2→3).'),
                        _Line('💀', '용사가 왕좌에 닿으면 게임 오버. 용사 HP 0 또는 ${WaveRules.maxSteps}턴 초과면 방어 성공.'),
                      ],
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

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14, height: 1.3)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }
}
