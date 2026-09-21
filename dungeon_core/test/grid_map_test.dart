import 'dart:convert';

import 'package:dungeon_core/src/balance.dart';
import 'package:dungeon_core/src/grid_map.dart';
import 'package:dungeon_core/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('GridMap 기본 판정', () {
    final map = GridMap();

    test('기둥 9칸은 Balance.pillars와 일치', () {
      var count = 0;
      for (var y = 0; y < Balance.rows; y++) {
        for (var x = 0; x < Balance.cols; x++) {
          if (map.isPillar(Pos(x, y))) count++;
        }
      }
      expect(count, Balance.pillars.length);
      for (final p in Balance.pillars) {
        expect(map.isPillar(Pos(p[0], p[1])), isTrue);
      }
      expect(map.isPillar(Pos.entrance), isFalse);
    });

    test('입구/왕좌 판정', () {
      expect(map.isEntrance(Pos.entrance), isTrue);
      expect(map.isThrone(Pos.throne), isTrue);
      expect(map.isEntrance(Pos.throne), isFalse);
    });
  });

  group('GridMap 배치', () {
    test('금지 칸(기둥/입구/왕좌/입구 인접/맵 밖) 배치는 false', () {
      final map = GridMap();
      expect(map.place(MonsterType.slime, Pos.entrance), isFalse);
      expect(map.place(MonsterType.slime, Pos.throne), isFalse);
      for (final p in Balance.pillars) {
        expect(map.place(MonsterType.slime, Pos(p[0], p[1])), isFalse);
      }
      for (final p in Balance.forbiddenNearEntrance) {
        expect(map.place(MonsterType.trap, Pos(p[0], p[1])), isFalse);
      }
      expect(map.place(MonsterType.slime, const Pos(-1, 0)), isFalse);
      expect(map.place(MonsterType.slime, Pos(Balance.cols, 0)), isFalse);
      expect(map.monsters, isEmpty);
      expect(map.totalCost, 0);
    });

    test('점유 칸 배치는 false, remove 후 다시 배치 가능', () {
      final map = GridMap();
      const p = Pos(2, 0);
      expect(map.place(MonsterType.orc, p), isTrue);
      expect(map.isPlaceable(p), isFalse);
      expect(map.place(MonsterType.slime, p), isFalse);
      expect(map.monsters[p]!.type, MonsterType.orc);
      expect(map.monsters[p]!.hp, MonsterType.orc.spec.hp);
      expect(map.remove(p), isTrue);
      expect(map.remove(p), isFalse);
      expect(map.isPlaceable(p), isTrue);
      expect(map.place(MonsterType.slime, p), isTrue);
    });

    test('totalCost = 배치 비용 합', () {
      final map = GridMap();
      map.place(MonsterType.slime, const Pos(2, 0));
      map.place(MonsterType.goblin, const Pos(2, 2));
      map.place(MonsterType.orc, const Pos(6, 5));
      map.place(MonsterType.trap, const Pos(4, 4));
      final expected = MonsterType.slime.spec.cost +
          MonsterType.goblin.spec.cost +
          MonsterType.orc.spec.cost +
          MonsterType.trap.spec.cost;
      expect(map.totalCost, expected);
      map.remove(const Pos(6, 5));
      expect(map.totalCost, expected - MonsterType.orc.spec.cost);
    });

    test('placeableCells는 36칸, 행 우선, 전부 배치 가능', () {
      final cells = GridMap.placeableCells();
      expect(cells.length, 36);
      expect(cells.toSet().length, 36);
      // 행 우선 순서: index 단조 증가
      for (var i = 1; i < cells.length; i++) {
        expect(cells[i].index, greaterThan(cells[i - 1].index));
      }
      final map = GridMap();
      for (final c in cells) {
        expect(map.isPlaceable(c), isTrue, reason: '$c');
        expect(map.place(MonsterType.trap, c), isTrue, reason: '$c');
      }
      expect(map.monsters.length, 36);
      expect(map.totalCost, 36 * MonsterType.trap.spec.cost);
    });
  });

  group('GridMap 복제/직렬화', () {
    test('clone은 깊은 복사', () {
      final map = GridMap();
      map.place(MonsterType.goblin, const Pos(3, 2));
      final c = map.clone();
      c.monsters[const Pos(3, 2)]!.hp = 1;
      c.place(MonsterType.slime, const Pos(0, 3));
      expect(map.monsters[const Pos(3, 2)]!.hp, MonsterType.goblin.spec.hp);
      expect(map.monsters.length, 1);
      expect(c.monsters.length, 2);
    });

    test('toJson → fromJson 왕복 동일 (형식 {"m":[{t,p,hp}]})', () {
      final map = GridMap();
      map.place(MonsterType.orc, const Pos(6, 5));
      map.place(MonsterType.slime, const Pos(2, 0));
      map.place(MonsterType.trap, const Pos(4, 4));
      map.monsters[const Pos(6, 5)]!.hp = 7; // 손상된 HP도 보존

      final json = map.toJson();
      expect(json.keys, ['m']);
      final list = json['m'] as List;
      expect(list.length, 3);
      // pos.index 오름차순
      expect(list.map((e) => (e as Map)['p']).toList(), [const Pos(2, 0).index, const Pos(4, 4).index, const Pos(6, 5).index]);
      expect(list.first, {'t': MonsterType.slime.index, 'p': const Pos(2, 0).index, 'hp': MonsterType.slime.spec.hp});

      // 문자열 왕복까지
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      final back = GridMap.fromJson(decoded);
      expect(back.monsters.length, 3);
      for (final e in map.monsters.entries) {
        final m = back.monsters[e.key];
        expect(m, isNotNull, reason: '${e.key}');
        expect(m!.type, e.value.type);
        expect(m.pos, e.value.pos);
        expect(m.hp, e.value.hp);
      }
      expect(back.totalCost, map.totalCost);
      expect(jsonEncode(back.toJson()), jsonEncode(json));
    });

    test('빈 맵 왕복', () {
      final back = GridMap.fromJson(GridMap().toJson());
      expect(back.monsters, isEmpty);
    });
  });

  group('GridMap.shortestPath', () {
    test('입구→왕좌 길이 13 (맨해튼 12 + 1), 기둥 없음, 인접 연속', () {
      final map = GridMap();
      final path = map.shortestPath();
      expect(path.length, Pos.entrance.manhattan(Pos.throne) + 1);
      expect(path.length, 13);
      expect(path.first, Pos.entrance);
      expect(path.last, Pos.throne);
      for (var i = 1; i < path.length; i++) {
        expect(path[i].manhattan(path[i - 1]), 1);
        expect(map.isPillar(path[i]), isFalse);
        expect(path[i].inBounds, isTrue);
      }
    });

    test('마물이 있어도 경로는 동일 (마물 무시)', () {
      final map = GridMap();
      final before = map.shortestPath();
      for (final c in GridMap.placeableCells()) {
        map.place(MonsterType.orc, c);
      }
      expect(map.shortestPath(), before);
    });
  });
}
