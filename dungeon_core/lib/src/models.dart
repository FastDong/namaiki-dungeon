import 'balance.dart';

/// 격자 좌표. x = 열(col), y = 행(row). 입구 (0,0), 왕좌 (6,6).
class Pos {
  final int x, y;
  const Pos(this.x, this.y);

  static const Pos entrance = Pos(Balance.entranceX, Balance.entranceY);
  static const Pos throne = Pos(Balance.throneX, Balance.throneY);

  Pos move(HeroAction a) {
    switch (a) {
      case HeroAction.up:
        return Pos(x, y - 1);
      case HeroAction.down:
        return Pos(x, y + 1);
      case HeroAction.left:
        return Pos(x - 1, y);
      case HeroAction.right:
        return Pos(x + 1, y);
      case HeroAction.potion:
        return this;
    }
  }

  bool get inBounds => x >= 0 && y >= 0 && x < Balance.cols && y < Balance.rows;

  int manhattan(Pos o) => (x - o.x).abs() + (y - o.y).abs();

  /// 직렬화용 인덱스 (y * cols + x).
  int get index => y * Balance.cols + x;
  factory Pos.fromIndex(int i) => Pos(i % Balance.cols, i ~/ Balance.cols);

  @override
  bool operator ==(Object other) => other is Pos && other.x == x && other.y == y;
  @override
  int get hashCode => x * 31 + y;
  @override
  String toString() => '($x,$y)';
}

enum MonsterType { slime, goblin, orc, trap }

class MonsterSpec {
  final int hp, atk, cost;
  const MonsterSpec(this.hp, this.atk, this.cost);
}

/// 함정은 hp 0(공격 불가·막지 않음), atk = 진입 시 피해.
const Map<MonsterType, MonsterSpec> monsterSpecs = {
  MonsterType.slime: MonsterSpec(10, 2, 1),
  MonsterType.goblin: MonsterSpec(24, 5, 3),
  MonsterType.orc: MonsterSpec(40, 9, 6),
  MonsterType.trap: MonsterSpec(0, Balance.trapDamage, 2),
};

extension MonsterTypeX on MonsterType {
  MonsterSpec get spec => monsterSpecs[this]!;
  bool get isTrap => this == MonsterType.trap;
  String get korean => switch (this) {
        MonsterType.slime => '슬라임',
        MonsterType.goblin => '고블린',
        MonsterType.orc => '오크',
        MonsterType.trap => '가시함정',
      };
  String get emoji => switch (this) {
        MonsterType.slime => '🟢',
        MonsterType.goblin => '👺',
        MonsterType.orc => '👹',
        MonsterType.trap => '🔺',
      };
}

class Monster {
  final MonsterType type;
  final Pos pos;
  int hp;
  Monster(this.type, this.pos, this.hp);
  factory Monster.fresh(MonsterType t, Pos p) => Monster(t, p, t.spec.hp);

  int get atk => type.spec.atk;
  int get maxHp => type.spec.hp;
  bool get isTrap => type.isTrap;
  Monster clone() => Monster(type, pos, hp);

  Map<String, dynamic> toJson() => {'t': type.index, 'p': pos.index, 'hp': hp};
  factory Monster.fromJson(Map<String, dynamic> j) => Monster(
        MonsterType.values[j['t'] as int],
        Pos.fromIndex(j['p'] as int),
        j['hp'] as int,
      );
}

class HeroStats {
  final int maxHp, atk, potions;
  const HeroStats(this.maxHp, this.atk, this.potions);
  factory HeroStats.forWave(int wave) =>
      HeroStats(Balance.heroHp(wave), Balance.heroAtk(wave), Balance.potions);

  Map<String, dynamic> toJson() => {'hp': maxHp, 'atk': atk, 'pot': potions};
  factory HeroStats.fromJson(Map<String, dynamic> j) =>
      HeroStats(j['hp'] as int, j['atk'] as int, j['pot'] as int);
}

enum HeroAction { up, down, left, right, potion }

extension HeroActionX on HeroAction {
  bool get isMove => this != HeroAction.potion;
  HeroAction? get opposite => switch (this) {
        HeroAction.up => HeroAction.down,
        HeroAction.down => HeroAction.up,
        HeroAction.left => HeroAction.right,
        HeroAction.right => HeroAction.left,
        HeroAction.potion => null,
      };
  String get korean => switch (this) {
        HeroAction.up => '위',
        HeroAction.down => '아래',
        HeroAction.left => '왼쪽',
        HeroAction.right => '오른쪽',
        HeroAction.potion => '물약',
      };
}

/// 4개 이동 행동만 (potion 제외).
const List<HeroAction> moveActions = [
  HeroAction.up, HeroAction.down, HeroAction.left, HeroAction.right,
];

enum Outcome { running, heroDied, reachedThrone, gaveUp }

extension OutcomeX on Outcome {
  /// 마왕(플레이어) 입장에서 방어 성공인가.
  bool get defended => this == Outcome.heroDied || this == Outcome.gaveUp;
}

enum EventType { moved, bumpedWall, attacked, killed, trapHit, potionUsed, potionWasted, reversed }

class Event {
  final EventType type;
  final Pos? pos;
  final int? amount;
  final MonsterType? monster;
  const Event(this.type, {this.pos, this.amount, this.monster});
  @override
  String toString() =>
      'Event($type${pos != null ? ' $pos' : ''}${amount != null ? ' $amount' : ''}${monster != null ? ' $monster' : ''})';
}

class StepResult {
  final double reward;
  final Outcome outcome;
  final List<Event> events;
  const StepResult(this.reward, this.outcome, this.events);
  bool get done => outcome != Outcome.running;
}
