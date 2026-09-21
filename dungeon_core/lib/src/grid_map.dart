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

  bool isPillar(Pos p) => throw UnimplementedError('M1');
  bool isPlaceable(Pos p) => throw UnimplementedError('M1');
  bool isThrone(Pos p) => p == Pos.throne;
  bool isEntrance(Pos p) => p == Pos.entrance;

  /// 배치 불가(칸 점유/금지 칸/맵 밖)면 false.
  bool place(MonsterType t, Pos p) => throw UnimplementedError('M1');

  /// 해당 칸에 마물이 없으면 false.
  bool remove(Pos p) => throw UnimplementedError('M1');

  /// 배치된 전체 마나 비용 합.
  int get totalCost => throw UnimplementedError('M1');

  GridMap clone() => throw UnimplementedError('M1');

  Map<String, dynamic> toJson() => throw UnimplementedError('M1');
  factory GridMap.fromJson(Map<String, dynamic> j) => throw UnimplementedError('M1');

  /// 입구→왕좌 BFS 최단 경로 (마물 무시, 기둥만 장애물). 입구와 왕좌 포함.
  List<Pos> shortestPath() => throw UnimplementedError('M1');

  /// 배치 가능한 36칸 (행 우선 순서).
  static List<Pos> placeableCells() => throw UnimplementedError('M1');
}
