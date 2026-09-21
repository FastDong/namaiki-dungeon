import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 2.5D 투영
// ─────────────────────────────────────────────────────────────────────────────

/// 보드 기울임(perspective) 수학. 보드는 아래 변(bottomCenter)을 축으로 뒤로 눕힌다:
/// 아래(가까운) 변은 원래 폭, 위(먼) 변은 좁아진다.
///
/// Flutter 의 Transform 히트테스트는 perspective 를 제거하고 역변환하므로(최대 반 칸 오차),
/// 탭 판정은 [unproject] 로 직접 역산한다.
class BoardProjection {
  BoardProjection._();

  static const double tiltDeg = 38;
  static const double perspective = 0.0013;
  static final double _c = cos(tiltDeg * pi / 180);
  static final double _s = sin(tiltDeg * pi / 180);

  /// 보드 전체에 적용하는 행렬 (Transform.alignment = bottomCenter 와 함께 사용).
  static Matrix4 boardMatrix() => Matrix4.identity()
    ..setEntry(3, 2, perspective)
    ..rotateX(-tiltDeg * pi / 180);

  /// 보드 위에 "세워서" 그리는 스프라이트용 역회전 (Transform.alignment = bottomCenter).
  static Matrix4 billboardMatrix() => Matrix4.rotationX(tiltDeg * pi / 180);

  /// 바닥에 수직으로 서는 면(기둥 앞면)용 회전.
  static Matrix4 wallMatrix() => Matrix4.rotationX(pi / 2);

  /// 보드 정사각 한 변이 [side] 일 때 투영된 높이 (아래 변 기준).
  static double projectedHeight(double side) {
    final ly = -side;
    final w = 1 - perspective * _s * ly;
    return -(_c * ly / w);
  }

  /// 축(bottomCenter) 기준 화면 좌표 (sx, sy) → 보드 로컬 좌표(축 기준, ly ≤ 0 이 위쪽).
  static Offset unproject(Offset screenFromPivot) {
    final sx = screenFromPivot.dx, sy = screenFromPivot.dy;
    final denom = _c + perspective * _s * sy;
    if (denom.abs() < 1e-6) return const Offset(double.nan, double.nan);
    final ly = sy / denom;
    final w = 1 - perspective * _s * ly;
    return Offset(sx * w, ly);
  }

  /// 축 기준 보드 로컬 좌표 → 화면 좌표 (검증/테스트용).
  static Offset project(Offset localFromPivot) {
    final lx = localFromPivot.dx, ly = localFromPivot.dy;
    final w = 1 - perspective * _s * ly;
    return Offset(lx / w, _c * ly / w);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 벡터 스프라이트
// ─────────────────────────────────────────────────────────────────────────────

enum SpriteKind { slime, goblin, orc, trap, hero, throne, entrance }

extension SpriteKindX on MonsterType {
  SpriteKind get sprite => switch (this) {
        MonsterType.slime => SpriteKind.slime,
        MonsterType.goblin => SpriteKind.goblin,
        MonsterType.orc => SpriteKind.orc,
        MonsterType.trap => SpriteKind.trap,
      };
}

/// 이모지 대신 쓰는 간단한 벡터 스프라이트. [spikeRaise] 는 함정 발동 시 가시 솟음(px).
class Sprite extends StatelessWidget {
  const Sprite(this.kind, {super.key, this.size = 32, this.spikeRaise = 0, this.hurt = false});

  final SpriteKind kind;
  final double size;
  final double spikeRaise;
  final bool hurt;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: ValueKey('sprite_${kind.name}'),
      size: Size(size, size),
      painter: SpritePainter(kind, spikeRaise: spikeRaise, hurt: hurt),
    );
  }
}

class SpritePainter extends CustomPainter {
  const SpritePainter(this.kind, {this.spikeRaise = 0, this.hurt = false});

  final SpriteKind kind;
  final double spikeRaise;
  final bool hurt;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    switch (kind) {
      case SpriteKind.slime:
        _slime(canvas, s);
      case SpriteKind.goblin:
        _goblin(canvas, s);
      case SpriteKind.orc:
        _orc(canvas, s);
      case SpriteKind.trap:
        _trap(canvas, s);
      case SpriteKind.hero:
        _hero(canvas, s);
      case SpriteKind.throne:
        _throne(canvas, s);
      case SpriteKind.entrance:
        _entrance(canvas, s);
    }
    canvas.restore();
  }

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;

  void _eyes(Canvas c, double s, double cx, double cy, double gap, double r, Color color, {double pupil = 0.5}) {
    for (final dx in [-gap, gap]) {
      c.drawCircle(Offset(cx + dx, cy), r, _fill(Colors.white));
      c.drawCircle(Offset(cx + dx + r * 0.15, cy + r * 0.1), r * pupil, _fill(color));
    }
  }

  void _slime(Canvas c, double s) {
    final body = Path()
      ..moveTo(s * 0.5, s * 0.12)
      ..cubicTo(s * 0.72, s * 0.32, s * 0.9, s * 0.5, s * 0.9, s * 0.68)
      ..cubicTo(s * 0.9, s * 0.88, s * 0.72, s * 0.95, s * 0.5, s * 0.95)
      ..cubicTo(s * 0.28, s * 0.95, s * 0.1, s * 0.88, s * 0.1, s * 0.68)
      ..cubicTo(s * 0.1, s * 0.5, s * 0.28, s * 0.32, s * 0.5, s * 0.12)
      ..close();
    c.drawPath(body, _fill(hurt ? const Color(0xFFB9F0C4) : const Color(0xFF4FD37A)));
    c.drawPath(body, _stroke(const Color(0xFF2A8A4A), s * 0.05));
    // 하이라이트
    c.drawOval(Rect.fromLTWH(s * 0.28, s * 0.36, s * 0.14, s * 0.22), _fill(Colors.white.withValues(alpha: 0.35)));
    _eyes(c, s, s * 0.5, s * 0.66, s * 0.14, s * 0.075, const Color(0xFF1B3A24));
  }

  void _goblin(Canvas c, double s) {
    final face = const Color(0xFF6FBE4E);
    // 귀
    final earL = Path()
      ..moveTo(s * 0.22, s * 0.5)
      ..lineTo(s * 0.02, s * 0.3)
      ..lineTo(s * 0.3, s * 0.34)
      ..close();
    final earR = Path()
      ..moveTo(s * 0.78, s * 0.5)
      ..lineTo(s * 0.98, s * 0.3)
      ..lineTo(s * 0.7, s * 0.34)
      ..close();
    c.drawPath(earL, _fill(face));
    c.drawPath(earR, _fill(face));
    c.drawOval(Rect.fromLTWH(s * 0.2, s * 0.24, s * 0.6, s * 0.66), _fill(hurt ? const Color(0xFFCFF0C0) : face));
    c.drawOval(Rect.fromLTWH(s * 0.2, s * 0.24, s * 0.6, s * 0.66), _stroke(const Color(0xFF3B7A2A), s * 0.045));
    _eyes(c, s, s * 0.5, s * 0.5, s * 0.14, s * 0.08, const Color(0xFFE5484D), pupil: 0.65);
    // 씩 웃는 입 + 이빨
    c.drawArc(Rect.fromLTWH(s * 0.33, s * 0.56, s * 0.34, s * 0.2), 0.15 * pi, 0.7 * pi, false,
        _stroke(const Color(0xFF1E3A16), s * 0.045));
    c.drawRect(Rect.fromLTWH(s * 0.44, s * 0.66, s * 0.05, s * 0.06), _fill(Colors.white));
    c.drawRect(Rect.fromLTWH(s * 0.53, s * 0.66, s * 0.05, s * 0.06), _fill(Colors.white));
  }

  void _orc(Canvas c, double s) {
    final skin = hurt ? const Color(0xFFE0C0A8) : const Color(0xFF8B5A3C);
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.1, s * 0.12, s * 0.8, s * 0.8), Radius.circular(s * 0.28)),
      _fill(skin),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.1, s * 0.12, s * 0.8, s * 0.8), Radius.circular(s * 0.28)),
      _stroke(const Color(0xFF4A2A18), s * 0.05),
    );
    // 눈썹 + 눈
    c.drawLine(Offset(s * 0.24, s * 0.38), Offset(s * 0.42, s * 0.44), _stroke(const Color(0xFF3A2010), s * 0.06));
    c.drawLine(Offset(s * 0.76, s * 0.38), Offset(s * 0.58, s * 0.44), _stroke(const Color(0xFF3A2010), s * 0.06));
    _eyes(c, s, s * 0.5, s * 0.52, s * 0.17, s * 0.07, const Color(0xFFF2C14E), pupil: 0.6);
    // 입 + 엄니
    c.drawRect(Rect.fromLTWH(s * 0.3, s * 0.7, s * 0.4, s * 0.08), _fill(const Color(0xFF3A2010)));
    final tuskL = Path()
      ..moveTo(s * 0.33, s * 0.72)
      ..lineTo(s * 0.37, s * 0.58)
      ..lineTo(s * 0.42, s * 0.72)
      ..close();
    final tuskR = Path()
      ..moveTo(s * 0.58, s * 0.72)
      ..lineTo(s * 0.63, s * 0.58)
      ..lineTo(s * 0.67, s * 0.72)
      ..close();
    c.drawPath(tuskL, _fill(const Color(0xFFF5EBD8)));
    c.drawPath(tuskR, _fill(const Color(0xFFF5EBD8)));
  }

  void _trap(Canvas c, double s) {
    // 바닥 판
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.08, s * 0.7, s * 0.84, s * 0.2), Radius.circular(s * 0.05)),
      _fill(const Color(0xFF4A4458)),
    );
    final raise = spikeRaise;
    final spike = hurt ? DungeonColors.danger : const Color(0xFF9A9AAE);
    for (var i = 0; i < 3; i++) {
      final cx = s * (0.25 + 0.25 * i);
      final p = Path()
        ..moveTo(cx - s * 0.1, s * 0.72)
        ..lineTo(cx, s * 0.3 - raise)
        ..lineTo(cx + s * 0.1, s * 0.72)
        ..close();
      c.drawPath(p, _fill(spike));
      c.drawPath(p, _stroke(const Color(0xFF5C5C70), s * 0.03));
    }
  }

  void _hero(Canvas c, double s) {
    // 망토/방패 실루엣 (ember)
    final cape = Path()
      ..moveTo(s * 0.5, s * 0.3)
      ..lineTo(s * 0.86, s * 0.48)
      ..lineTo(s * 0.8, s * 0.96)
      ..lineTo(s * 0.2, s * 0.96)
      ..lineTo(s * 0.14, s * 0.48)
      ..close();
    c.drawPath(cape, _fill(DungeonColors.ember));
    c.drawPath(cape, _stroke(const Color(0xFFB34A22), s * 0.04));
    // 방패 문양
    c.drawCircle(Offset(s * 0.5, s * 0.7), s * 0.09, _fill(DungeonColors.gold));
    // 얼굴 (살구색)
    c.drawCircle(Offset(s * 0.5, s * 0.3), s * 0.2, _fill(const Color(0xFFF6C9A8)));
    // 머리카락/투구
    c.drawArc(Rect.fromCircle(center: Offset(s * 0.5, s * 0.3), radius: s * 0.21), pi, pi, true,
        _fill(const Color(0xFF6B3E2E)));
    _eyes(c, s, s * 0.5, s * 0.32, s * 0.07, s * 0.035, const Color(0xFF2A1A12), pupil: 0.8);
    // 검 (오른쪽)
    c.drawLine(Offset(s * 0.9, s * 0.2), Offset(s * 0.9, s * 0.7), _stroke(const Color(0xFFD9DEE8), s * 0.06));
    c.drawLine(Offset(s * 0.82, s * 0.66), Offset(s * 0.98, s * 0.66), _stroke(DungeonColors.gold, s * 0.05));
  }

  void _throne(Canvas c, double s) {
    // 방석
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.12, s * 0.66, s * 0.76, s * 0.26), Radius.circular(s * 0.08)),
      _fill(const Color(0xFF6B2B3A)),
    );
    // 왕관
    final crown = Path()
      ..moveTo(s * 0.18, s * 0.62)
      ..lineTo(s * 0.14, s * 0.24)
      ..lineTo(s * 0.34, s * 0.42)
      ..lineTo(s * 0.5, s * 0.14)
      ..lineTo(s * 0.66, s * 0.42)
      ..lineTo(s * 0.86, s * 0.24)
      ..lineTo(s * 0.82, s * 0.62)
      ..close();
    c.drawPath(crown, _fill(DungeonColors.gold));
    c.drawPath(crown, _stroke(const Color(0xFFB88A1E), s * 0.04));
    for (final x in [0.3, 0.5, 0.7]) {
      c.drawCircle(Offset(s * x, s * 0.52), s * 0.045, _fill(DungeonColors.violet));
    }
  }

  void _entrance(Canvas c, double s) {
    // 아치문
    final arch = Path()
      ..moveTo(s * 0.18, s * 0.94)
      ..lineTo(s * 0.18, s * 0.42)
      ..arcToPoint(Offset(s * 0.82, s * 0.42), radius: Radius.circular(s * 0.32))
      ..lineTo(s * 0.82, s * 0.94)
      ..close();
    c.drawPath(arch, _fill(const Color(0xFF3B3350)));
    final inner = Path()
      ..moveTo(s * 0.28, s * 0.94)
      ..lineTo(s * 0.28, s * 0.46)
      ..arcToPoint(Offset(s * 0.72, s * 0.46), radius: Radius.circular(s * 0.22))
      ..lineTo(s * 0.72, s * 0.94)
      ..close();
    c.drawPath(inner, _fill(const Color(0xFF0C0A12)));
    // 문 안 빛
    c.drawPath(inner, _fill(DungeonColors.violet.withValues(alpha: 0.18)));
    c.drawPath(arch, _stroke(const Color(0xFF5A5075), s * 0.035));
  }

  @override
  bool shouldRepaint(covariant SpritePainter old) =>
      old.kind != kind || old.spikeRaise != spikeRaise || old.hurt != hurt;
}

/// 보드 위에 세워서 그리는 래퍼 (아래 변 기준 역회전). 기울인 보드 안에서만 의미가 있다.
class Billboard extends StatelessWidget {
  const Billboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: BoardProjection.billboardMatrix(),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 보드
// ─────────────────────────────────────────────────────────────────────────────

/// 7x7 2.5D 보드. 규칙 판정(기둥/배치 가능)은 전부 [GridMap]에 묻는다.
///
/// 이펙트는 [tick] 이 바뀔 때마다 [events] 를 한 번씩 재생한다 (key 교체 방식).
class BoardGrid extends StatelessWidget {
  const BoardGrid({
    super.key,
    required this.map,
    required this.trail,
    this.heroPos,
    this.buildMode = false,
    this.onCellTap,
    this.events = const [],
    this.tick = 0,
    this.heroDamage = 0,
    this.outcome,
    this.maxSide = 360,
  });

  final GridMap map;
  final List<Pos> trail;
  final Pos? heroPos;
  final bool buildMode;
  final void Function(Pos p)? onCellTap;

  /// 마지막 스텝 이벤트.
  final List<Event> events;

  /// 스텝 카운터 (바뀔 때마다 이펙트 재생).
  final int tick;

  /// 마지막 스텝 용사 피해 (>0 이면 흔들림).
  final int heroDamage;

  /// 웨이브 종료 결과 (사망/왕좌 도달 연출).
  final Outcome? outcome;

  /// 보드 최대 한 변 (px).
  final double maxSide;

  /// 레이아웃 높이 / 보드 한 변 비율 (투영 높이 ≈ 0.61 + 세워진 스프라이트 여유).
  static const double footprintRatio = 0.78;
  static const double boardPadding = 6;
  static const double cellGap = 3;

  static double cellSizeFor(double side) => (side - boardPadding * 2 - cellGap * (Balance.cols - 1)) / Balance.cols;

  /// 레이아웃 박스(폭 side, 높이 side*footprintRatio) 안의 탭 위치 → 셀. 보드 밖이면 null.
  static Pos? hitTest(Offset local, double side) {
    final h = side * footprintRatio;
    final fromPivot = Offset(local.dx - side / 2, local.dy - h);
    final l = BoardProjection.unproject(fromPivot);
    if (l.dx.isNaN) return null;
    final bx = l.dx + side / 2 - boardPadding;
    final by = l.dy + side - boardPadding;
    final cs = cellSizeFor(side) + cellGap;
    final x = (bx / cs).floor();
    final y = (by / cs).floor();
    if (x < 0 || y < 0 || x >= Balance.cols || y >= Balance.rows) return null;
    return Pos(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = min(c.maxWidth, maxSide);
        final h = side * footprintRatio;
        return Center(
          child: GestureDetector(
            key: const ValueKey('board_tap_area'),
            behavior: HitTestBehavior.opaque,
            onTapUp: onCellTap == null
                ? null
                : (d) {
                    final p = hitTest(d.localPosition, side);
                    if (p != null) onCellTap!(p);
                  },
            child: SizedBox(
              width: side,
              height: h,
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minWidth: side,
                maxWidth: side,
                minHeight: side,
                maxHeight: side,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: BoardProjection.boardMatrix(),
                  child: _BoardSurface(side: side, grid: this),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoardSurface extends StatelessWidget {
  const _BoardSurface({required this.side, required this.grid});

  final double side;
  final BoardGrid grid;

  @override
  Widget build(BuildContext context) {
    final cs = BoardGrid.cellSizeFor(side);
    const pad = BoardGrid.boardPadding;
    const gap = BoardGrid.cellGap;
    final firstVisit = <Pos, int>{};
    for (var i = 0; i < grid.trail.length; i++) {
      firstVisit.putIfAbsent(grid.trail[i], () => i);
    }
    final map = grid.map;
    final attacked = <Pos, int>{};
    final killed = <Pos, MonsterType>{};
    final trapped = <Pos, int>{};
    for (final e in grid.events) {
      final p = e.pos;
      if (p == null) continue;
      switch (e.type) {
        case EventType.attacked:
          attacked[p] = e.amount ?? 0;
        case EventType.killed:
          killed[p] = e.monster ?? MonsterType.slime;
        case EventType.trapHit:
          trapped[p] = e.amount ?? Balance.trapDamage;
        default:
          break;
      }
    }

    Offset cellOrigin(Pos p) => Offset(pad + p.x * (cs + gap), pad + p.y * (cs + gap));

    final tiles = <Widget>[];
    final standing = <Widget>[];
    for (var y = 0; y < Balance.rows; y++) {
      for (var x = 0; x < Balance.cols; x++) {
        final p = Pos(x, y);
        final o = cellOrigin(p);
        final isPillar = map.isPillar(p);
        tiles.add(Positioned(
          left: o.dx,
          top: o.dy,
          width: cs,
          height: cs,
          child: _Tile(
            key: ValueKey('cell_${p.x}_${p.y}'),
            pos: p,
            map: map,
            visitIndex: firstVisit[p],
            trailLen: grid.trail.length,
            hasHero: grid.heroPos == p,
            buildMode: grid.buildMode,
            flashWhite: attacked.containsKey(p) ? grid.tick : null,
            flashDanger: trapped.containsKey(p) ? grid.tick : null,
          ),
        ));
        if (isPillar) {
          standing.add(Positioned(
            left: o.dx,
            top: o.dy,
            width: cs,
            height: cs,
            child: _Pillar(size: cs),
          ));
          continue;
        }
        final m = map.monsters[p];
        final isThrone = map.isThrone(p);
        final isEntrance = map.isEntrance(p);
        if (m != null || isThrone || isEntrance) {
          standing.add(Positioned(
            left: o.dx,
            top: o.dy,
            width: cs,
            height: cs,
            child: _StandingSprite(
              kind: m != null ? m.type.sprite : (isThrone ? SpriteKind.throne : SpriteKind.entrance),
              size: cs,
              hp: m != null && !m.isTrap ? m.hp / max(1, m.maxHp) : null,
              hurtTick: (m != null && attacked.containsKey(p)) ? grid.tick : null,
              trapTick: (m != null && m.isTrap && trapped.containsKey(p)) ? grid.tick : null,
            ),
          ));
        }
        final v = firstVisit[p];
        if (v != null && grid.heroPos != p) {
          standing.add(Positioned(
            left: o.dx,
            top: o.dy,
            width: cs,
            height: cs,
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(-0.7, 0.9),
                child: Billboard(
                  child: Text(
                    '${v + 1}',
                    style: TextStyle(
                      fontSize: (cs * 0.26).clamp(8.0, 13.0),
                      fontWeight: FontWeight.w800,
                      color: DungeonColors.ember.withValues(alpha: 0.9),
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ));
        }
      }
    }

    // 처치 고스트 + 파티클
    final ghosts = <Widget>[
      for (final e in killed.entries)
        Positioned(
          left: cellOrigin(e.key).dx,
          top: cellOrigin(e.key).dy,
          width: cs,
          height: cs,
          child: _KillBurst(key: ValueKey('kill_${grid.tick}_${e.key.index}'), kind: e.value.sprite, size: cs),
        ),
    ];

    // 데미지 숫자
    final numbers = <Widget>[
      for (final e in attacked.entries)
        Positioned(
          left: cellOrigin(e.key).dx,
          top: cellOrigin(e.key).dy,
          width: cs,
          height: cs,
          child: _FloatText(
            key: ValueKey('dmg_${grid.tick}_${e.key.index}'),
            text: '-${e.value}',
            color: DungeonColors.gold,
            size: cs,
          ),
        ),
      for (final e in trapped.entries)
        Positioned(
          left: cellOrigin(e.key).dx,
          top: cellOrigin(e.key).dy,
          width: cs,
          height: cs,
          child: _FloatText(
            key: ValueKey('trap_${grid.tick}_${e.key.index}'),
            text: '-${e.value}',
            color: DungeonColors.danger,
            size: cs,
          ),
        ),
    ];

    final hero = grid.heroPos;
    final died = grid.outcome == Outcome.heroDied;
    final throne = grid.outcome == Outcome.reachedThrone;

    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 바닥판
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DungeonColors.stone,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DungeonColors.line, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 14)),
                ],
              ),
            ),
          ),
          ...tiles,
          // 사망: violet 숨쉼 / 왕좌 도달: ember 물들임
          if (died || throne)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('board_tint_${grid.tick}_${grid.outcome}'),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: died ? 900 : 700),
                  curve: Curves.easeInOut,
                  builder: (_, t, _) {
                    final a = died ? sin(t * pi) * 0.35 : t * 0.45;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: (died ? DungeonColors.violet : DungeonColors.ember).withValues(alpha: a),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  },
                ),
              ),
            ),
          ...standing,
          ...ghosts,
          if (hero != null)
            AnimatedPositioned(
              key: const ValueKey('hero_layer'),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              left: cellOrigin(hero).dx,
              top: cellOrigin(hero).dy,
              width: cs,
              height: cs,
              child: _HeroSprite(
                size: cs,
                shakeTick: grid.heroDamage > 0 ? grid.tick : null,
                dying: died,
                dyingTick: grid.tick,
              ),
            ),
          ...numbers,
        ],
      ),
    );
  }
}

/// 바닥 칸.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.pos,
    required this.map,
    required this.visitIndex,
    required this.trailLen,
    required this.hasHero,
    required this.buildMode,
    required this.flashWhite,
    required this.flashDanger,
  });

  final Pos pos;
  final GridMap map;
  final int? visitIndex;
  final int trailLen;
  final bool hasHero;
  final bool buildMode;
  final int? flashWhite;
  final int? flashDanger;

  @override
  Widget build(BuildContext context) {
    final isPillar = map.isPillar(pos);
    final isThrone = map.isThrone(pos);
    final isEntrance = map.isEntrance(pos);
    final monster = map.monsters[pos];

    Color bg = DungeonColors.floor;
    Color border = DungeonColors.line;
    Color? glow;
    if (isPillar) {
      bg = DungeonColors.pillarBottom;
      border = const Color(0xFF2A2438);
    } else if (hasHero) {
      bg = DungeonColors.heroCell;
      border = DungeonColors.ember.withValues(alpha: 0.8);
      glow = DungeonColors.ember;
    } else if (isThrone) {
      bg = DungeonColors.throneCell;
      border = DungeonColors.gold.withValues(alpha: 0.8);
      glow = DungeonColors.gold;
    } else if (monster != null) {
      bg = monster.isTrap ? const Color(0xFF2A2230) : DungeonColors.monsterCell;
      border = monster.isTrap ? const Color(0xFF6A5A70) : DungeonColors.violet.withValues(alpha: 0.75);
      glow = monster.isTrap ? null : DungeonColors.violet;
    } else if (isEntrance) {
      bg = const Color(0xFF1C1A2C);
    }

    final placeable = buildMode && !isPillar && monster == null && !isThrone && !isEntrance && map.isPlaceable(pos);
    if (placeable) border = DungeonColors.violet.withValues(alpha: 0.28);

    final v = visitIndex;
    final trailAlpha = v == null ? 0.0 : (0.18 + v * 0.014).clamp(0.0, 0.6);

    Widget tile = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border, width: 1),
        boxShadow: glow == null ? null : [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 10)],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (v != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: DungeonColors.ember.withValues(alpha: trailAlpha),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          if (flashWhite != null)
            _Flash(key: ValueKey('fw_$flashWhite'), color: Colors.white, alpha: 0.55, ms: 90),
          if (flashDanger != null)
            _Flash(key: ValueKey('fd_$flashDanger'), color: DungeonColors.danger, alpha: 0.6, ms: 180),
        ],
      ),
    );
    return tile;
  }
}

/// 칸 점멸 오버레이 (한 번 재생).
class _Flash extends StatelessWidget {
  const _Flash({super.key, required this.color, required this.alpha, required this.ms});

  final Color color;
  final double alpha;
  final int ms;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: alpha, end: 0),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOut,
      builder: (_, a, _) => DecoratedBox(
        decoration: BoxDecoration(color: color.withValues(alpha: a), borderRadius: BorderRadius.circular(7)),
      ),
    );
  }
}

/// 기둥: 윗면(z 로 들어올림) + 바닥에 수직인 앞면 + 그림자.
class _Pillar extends StatelessWidget {
  const _Pillar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final h = size * 0.95;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 그림자 (바닥, 앞쪽으로)
          Positioned(
            left: -2,
            right: -2,
            top: size * 0.5,
            height: size * 0.7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // 앞면 (아래 변에서 수직으로 세움)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: h,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: BoardProjection.wallMatrix(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [DungeonColors.pillarTop, DungeonColors.pillarBottom],
                  ),
                  border: Border.all(color: const Color(0xFF4A4262), width: 1),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                ),
              ),
            ),
          ),
          // 윗면
          Positioned.fill(
            child: Transform(
              transform: Matrix4.translationValues(0, 0, -h),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF453D5E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF5A5075), width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 세워진 스프라이트 + 타원 그림자 + (마물이면) HP바.
class _StandingSprite extends StatelessWidget {
  const _StandingSprite({
    required this.kind,
    required this.size,
    this.hp,
    this.hurtTick,
    this.trapTick,
  });

  final SpriteKind kind;
  final double size;
  final double? hp;
  final int? hurtTick;
  final int? trapTick;

  @override
  Widget build(BuildContext context) {
    final sp = size * 0.82;
    Widget sprite = Sprite(kind, size: sp);
    if (hurtTick != null) {
      sprite = TweenAnimationBuilder<double>(
        key: ValueKey('hurt_$hurtTick'),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 180),
        builder: (_, t, _) => Sprite(kind, size: sp, hurt: t > 0.5),
      );
    }
    if (trapTick != null) {
      sprite = TweenAnimationBuilder<double>(
        key: ValueKey('trap_$trapTick'),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 180),
        builder: (_, t, _) => Sprite(kind, size: sp, spikeRaise: 6 * sin(t * pi), hurt: t > 0.3),
      );
    }
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 타원 그림자 (바닥)
          Positioned(
            left: size * 0.18,
            right: size * 0.18,
            top: size * 0.62,
            height: size * 0.26,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.4)),
              ),
            ),
          ),
          Positioned(
            left: (size - sp) / 2,
            width: sp,
            bottom: size * 0.16,
            height: sp,
            child: Billboard(child: sprite),
          ),
          if (hp != null)
            Positioned(
              left: size * 0.14,
              right: size * 0.14,
              bottom: 4,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    const ColoredBox(color: Color(0xFF3A3350), child: SizedBox.expand()),
                    FractionallySizedBox(
                      widthFactor: hp!.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: const ColoredBox(color: DungeonColors.violet, child: SizedBox.expand()),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 용사 스프라이트: 피격 흔들림, 사망 시 기울며 페이드.
class _HeroSprite extends StatelessWidget {
  const _HeroSprite({required this.size, this.shakeTick, required this.dying, required this.dyingTick});

  final double size;
  final int? shakeTick;
  final bool dying;
  final int dyingTick;

  @override
  Widget build(BuildContext context) {
    final sp = size * 0.86;
    Widget sprite = Sprite(SpriteKind.hero, size: sp);
    if (dying) {
      sprite = TweenAnimationBuilder<double>(
        key: ValueKey('die_$dyingTick'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeIn,
        builder: (_, t, child) => Opacity(
          opacity: 1 - t,
          child: Transform.rotate(angle: t * 80 * pi / 180, alignment: Alignment.bottomCenter, child: child),
        ),
        child: sprite,
      );
    } else if (shakeTick != null) {
      sprite = TweenAnimationBuilder<double>(
        key: ValueKey('shake_$shakeTick'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 120),
        builder: (_, t, child) => Transform.translate(offset: Offset(6 * sin(t * pi * 2), 0), child: child),
        child: sprite,
      );
    }
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size * 0.16,
            right: size * 0.16,
            top: size * 0.62,
            height: size * 0.28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.4)),
              ),
            ),
          ),
          Positioned(
            left: (size - sp) / 2,
            width: sp,
            bottom: size * 0.14,
            height: sp,
            child: Billboard(child: sprite),
          ),
        ],
      ),
    );
  }
}

/// 위로 떠오르며 사라지는 숫자 (세워서).
class _FloatText extends StatelessWidget {
  const _FloatText({super.key, required this.text, required this.color, required this.size});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (_, t, _) => Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: size * 0.55 + 18 * t,
                height: size * 0.5,
                child: Billboard(
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: (size * 0.36).clamp(11.0, 18.0),
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 처치: 마물 스케일 1→0.4 + 알파 0, violet 입자 6개 방사 (260ms).
class _KillBurst extends StatelessWidget {
  const _KillBurst({super.key, required this.kind, required this.size});

  final SpriteKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sp = size * 0.82;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (_, t, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (size - sp) / 2,
              width: sp,
              bottom: size * 0.16,
              height: sp,
              child: Billboard(
                child: Opacity(
                  opacity: 1 - t,
                  child: Transform.scale(scale: 1 - 0.6 * t, alignment: Alignment.bottomCenter, child: Sprite(kind, size: sp)),
                ),
              ),
            ),
            for (var i = 0; i < 6; i++)
              Positioned(
                left: size / 2 + cos(i * pi / 3) * size * 0.45 * t - 3,
                top: size * 0.45 + sin(i * pi / 3) * size * 0.45 * t - 3,
                width: 6,
                height: 6,
                child: Billboard(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: DungeonColors.violet.withValues(alpha: 1 - t),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
