import 'dart:collection';

import 'balance.dart';
import 'models.dart';

/// 7x7 던전 맵. 기둥(벽)은 고정, 마물/함정은 플레이어(또는 배치 봇)가 배치.
///
/// 규칙 (PLAN.md §3):
/// - 배치 가능 칸 = 기둥·입구·왕좌·입구 인접 2칸을 제외한 36칸. 한 칸에 하나.
/// - `shortestPath()`는 마물을 무시하고 기둥만 장애물로 보는 입구→왕좌 BFS.
class GridMap {
  /// 기둥 포함 빈 맵.
  GridMap();

  /// 배치된 마물/함정 (pos → monster).
  final Map<Pos, Monster> monsters = {};

  /// 기둥 칸 집합 (Balance.pillars에서 1회 생성).
  static final Set<Pos> _pillars = {
    for (final p in Balance.pillars) Pos(p[0], p[1]),
  };

  /// 입구 인접 배치 금지 칸 집합.
  static final Set<Pos> _forbiddenNearEntrance = {
    for (final p in Balance.forbiddenNearEntrance) Pos(p[0], p[1]),
  };

  bool isPillar(Pos p) => _pillars.contains(p);

  /// 지금 이 칸에 배치할 수 있는가 = 배치 가능 칸이면서 비어 있음.
  /// 칸 종류만 보려면 [isPlaceableCell].
  bool isPlaceable(Pos p) => isPlaceableCell(p) && !monsters.containsKey(p);

  bool isThrone(Pos p) => p == Pos.throne;
  bool isEntrance(Pos p) => p == Pos.entrance;

  /// 점유 여부와 무관한 칸 종류 판정: 맵 안이고 기둥·입구·왕좌·입구 인접 칸이 아니면 true.
  static bool isPlaceableCell(Pos p) =>
      p.inBounds &&
      !_pillars.contains(p) &&
      p != Pos.entrance &&
      p != Pos.throne &&
      !_forbiddenNearEntrance.contains(p);

  /// 배치 불가(칸 점유/금지 칸/맵 밖)면 false.
  bool place(MonsterType t, Pos p) {
    if (!isPlaceable(p)) return false;
    monsters[p] = Monster.fresh(t, p);
    return true;
  }

  /// 해당 칸에 마물이 없으면 false.
  bool remove(Pos p) => monsters.remove(p) != null;

  /// 배치된 전체 마나 비용 합.
  int get totalCost {
    var sum = 0;
    for (final m in monsters.values) {
      sum += m.type.spec.cost;
    }
    return sum;
  }

  /// 깊은 복사 (Monster까지 복제). 이후 원본과 독립.
  GridMap clone() {
    final g = GridMap();
    for (final e in monsters.entries) {
      g.monsters[e.key] = e.value.clone();
    }
    return g;
  }

  /// {"m":[{"t":type.index,"p":pos.index,"hp":hp},...]} — pos.index 오름차순(결정론).
  Map<String, dynamic> toJson() {
    final list = monsters.values.toList()
      ..sort((a, b) => a.pos.index.compareTo(b.pos.index));
    return {'m': [for (final m in list) m.toJson()]};
  }

  factory GridMap.fromJson(Map<String, dynamic> j) {
    final g = GridMap();
    final raw = j['m'];
    if (raw is List) {
      for (final item in raw) {
        final m = Monster.fromJson(Map<String, dynamic>.from(item as Map));
        g.monsters[m.pos] = m;
      }
    }
    return g;
  }

  /// 입구→왕좌 BFS 최단 경로 (마물 무시, 기둥만 장애물). 입구와 왕좌 포함.
  /// 이웃 탐색 순서는 [moveActions](상/하/좌/우) 고정 → 결정론.
  List<Pos> shortestPath() {
    const start = Pos.entrance;
    const goal = Pos.throne;
    final prev = <Pos, Pos>{};
    final visited = <Pos>{start};
    final queue = Queue<Pos>()..add(start);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      if (cur == goal) break;
      for (final a in moveActions) {
        final n = cur.move(a);
        if (!n.inBounds || isPillar(n) || visited.contains(n)) continue;
        visited.add(n);
        prev[n] = cur;
        queue.add(n);
      }
    }
    if (!visited.contains(goal)) return const [];
    final path = <Pos>[goal];
    var cur = goal;
    while (cur != start) {
      cur = prev[cur]!;
      path.add(cur);
    }
    return path.reversed.toList();
  }

  /// 배치 가능한 36칸 (행 우선 순서: y 바깥, x 안쪽).
  static List<Pos> placeableCells() => [
        for (var y = 0; y < Balance.rows; y++)
          for (var x = 0; x < Balance.cols; x++)
            if (isPlaceableCell(Pos(x, y))) Pos(x, y),
      ];
}
