import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../game/wave_rules.dart';
import '../services/policy_repository.dart';
import 'theme.dart';

/// 진화 배너 (웨이브 5/10 클리어 뒤 전체화면).
/// 검은 배경, violet 링 3개 확산(900ms), 단계 숫자 0.6→1.0 오버슈트,
/// "용사가 N번의 죽음에서 배웠다 — AI Stage k", 메타가 있으면 "평가 승률 a% → b%, 학습 N회".
class EvolveOverlay extends StatelessWidget {
  const EvolveOverlay({
    super.key,
    this.episodes,
    this.prevWinRate,
    this.winRate,
  });

  /// 정책 메타 (직접 주입). 없으면 트리의 [PolicyMetaStore]에서 읽고, 그것도 없으면 생략.
  final int? episodes;
  final double? prevWinRate;
  final double? winRate;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final stage = c.waveStage;
    final deaths = c.heroDeaths;
    final color = DungeonColors.stage(stage);

    // 메타: 인자 > PolicyMetaStore > 없음
    PolicyMetaStore? store;
    try {
      store = PolicyMetaStore.maybeOf(context);
    } catch (_) {
      store = null;
    }
    final ep = episodes ?? store?.episodes(stage);
    final win = winRate ?? store?.winRate(stage);
    final prev = prevWinRate ?? (stage > 1 ? store?.winRate(stage - 1) : null);

    String? metaLine;
    if (win != null && prev != null) {
      metaLine = '평가 승률 ${(prev * 100).round()}% → ${(win * 100).round()}%'
          '${ep != null ? ' · 학습 ${_fmt(ep)}회' : ''}';
    } else if (win != null) {
      metaLine = '평가 승률 ${(win * 100).round()}%${ep != null ? ' · 학습 ${_fmt(ep)}회' : ''}';
    } else if (ep != null) {
      metaLine = '학습 ${_fmt(ep)}회';
    }

    return ColoredBox(
      key: const ValueKey('evolve_overlay'),
      color: Colors.black.withValues(alpha: 0.94),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // violet 링 3개 확산
          IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('evolve_rings_${c.wave}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, t, _) => CustomPaint(
                  size: const Size(360, 360),
                  painter: _RingsPainter(t, color),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 단계 숫자 오버슈트
                    TweenAnimationBuilder<double>(
                      key: ValueKey('evolve_num_${c.wave}'),
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      builder: (_, s, child) => Transform.scale(scale: s, child: child),
                      child: Container(
                        width: 112,
                        height: 112,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.14),
                          border: Border.all(color: color, width: 3),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
                        ),
                        child: Text(
                          '$stage',
                          style: DungeonFonts.title(size: 64, color: color, height: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '용사가 진화했다',
                      style: DungeonFonts.title(size: 30, color: DungeonColors.parchment),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '용사가 $deaths번의 죽음에서 배웠다 — AI Stage $stage',
                      style: DungeonFonts.body(size: 15, color: DungeonColors.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: color.withValues(alpha: 0.7)),
                      ),
                      child: Text(
                        'AI Stage $stage — ${WaveRules.stageName(stage)} 용사',
                        style: DungeonFonts.body(size: 17, weight: FontWeight.w800, color: color),
                      ),
                    ),
                    if (metaLine != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        metaLine,
                        key: const ValueKey('evolve_meta'),
                        style: DungeonFonts.body(size: 13, color: DungeonColors.parchment.withValues(alpha: 0.75)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      key: const ValueKey('evolve_continue_button'),
                      onPressed: c.dismissEvolve,
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: DungeonColors.void_,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      ),
                      icon: const Icon(Icons.shield),
                      label: Text('웨이브 ${c.wave} 준비'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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

/// violet 링 3개: 시차를 두고 반지름 0→최대, 알파 1→0.
class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide * 0.5;
    for (var i = 0; i < 3; i++) {
      final local = ((t - i * 0.18) / 0.82).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final r = maxR * Curves.easeOutCubic.transform(local);
      final a = (1 - local) * 0.8;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, 4.0 * (1 - local) + 1)
        ..color = color.withValues(alpha: a);
      canvas.drawCircle(center, r, paint);
    }
    // 중심 글로우
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.35 * (1 - t)), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 0.5));
    canvas.drawCircle(center, maxR * 0.5, glow);
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.t != t || old.color != color;
}
