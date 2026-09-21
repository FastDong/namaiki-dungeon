import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import 'board_grid.dart';
import 'leaderboard_screen.dart';
import 'play_screen.dart';
import 'theme.dart';

/// 메뉴: 제목, 게임 시작, 리더보드, 짧은 설명. 던전 팔레트 + 벡터 스프라이트.
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
    final learned = policies.values.whereType<QTablePolicy>().length;

    return Theme(
      data: DungeonTheme.of(context),
      child: Scaffold(
        backgroundColor: DungeonColors.void_,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.5),
              radius: 1.2,
              colors: [Color(0xFF221A38), DungeonColors.void_],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 왕좌 + 마물 행렬
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Sprite(SpriteKind.slime, size: 30),
                          const SizedBox(width: 8),
                          const Sprite(SpriteKind.goblin, size: 34),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DungeonColors.gold.withValues(alpha: 0.1),
                              boxShadow: [BoxShadow(color: DungeonColors.gold.withValues(alpha: 0.35), blurRadius: 28)],
                            ),
                            child: const Sprite(SpriteKind.throne, size: 64),
                          ),
                          const SizedBox(width: 10),
                          const Sprite(SpriteKind.orc, size: 36),
                          const SizedBox(width: 8),
                          const Sprite(SpriteKind.trap, size: 30),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '마왕의 던전',
                        textAlign: TextAlign.center,
                        style: DungeonFonts.title(size: 40, color: DungeonColors.parchment),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '죽을수록 똑똑해지는 용사',
                        textAlign: TextAlign.center,
                        style: DungeonFonts.body(size: 16, color: DungeonColors.violet, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        key: const ValueKey('start_button'),
                        onPressed: () => _startGame(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: DungeonColors.ember,
                          foregroundColor: DungeonColors.void_,
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text('게임 시작', style: TextStyle(fontSize: 18)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const ValueKey('leaderboard_button'),
                        onPressed: () => Navigator.of(context).push(LeaderboardScreen.route()),
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
                          color: DungeonColors.stone,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: DungeonColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('어떻게 노나', style: DungeonFonts.title(size: 15)),
                            const SizedBox(height: 8),
                            _Line(
                              const Sprite(SpriteKind.throne, size: 18),
                              '마나로 마물과 함정을 배치해 왕좌를 지킨다. 시작 ${WaveRules.startMana}, 웨이브마다 +${WaveRules.manaPerWave}.',
                            ),
                            _Line(
                              const Sprite(SpriteKind.hero, size: 18),
                              '용사는 강화학습(Q-learning)으로 미리 훈련된 AI. 총 ${WaveRules.totalWaves}웨이브.',
                            ),
                            _Line(
                              const Icon(Icons.bolt, size: 18, color: DungeonColors.violet),
                              '${Balance.wavesPerStage}웨이브를 막을 때마다 더 많이 학습한 용사가 등장한다 (Stage 1→2→3).',
                            ),
                            _Line(
                              const Sprite(SpriteKind.trap, size: 18),
                              '용사가 왕좌에 닿으면 게임 오버. 용사 HP 0 또는 ${WaveRules.maxSteps}턴 초과면 방어 성공.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        learned > 0 ? '학습된 용사 정책 $learned/${policies.length}단계 로드됨' : '학습 정책 없음 — 규칙 기반 용사(학습 전)',
                        textAlign: TextAlign.center,
                        style: DungeonFonts.body(size: 11.5, color: DungeonColors.muted),
                      ),
                    ],
                  ),
                ),
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

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, height: 20, child: Center(child: icon)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: DungeonFonts.body(size: 13, color: DungeonColors.parchment, height: 1.35))),
        ],
      ),
    );
  }
}
