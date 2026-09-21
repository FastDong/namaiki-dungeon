import 'balance.dart';
import 'grid_map.dart';
import 'models.dart';

/// 턴제 시뮬레이터. 난수 없음(결정론). 같은 맵 + 같은 행동열 = 같은 결과.
///
/// 규칙 (PLAN.md §3, §5.3):
/// - 이동 행동: 목적지가 빈칸/왕좌면 이동(trail 기록, lastMove 갱신). 마물 칸이면 그 마물을 1회 공격(용사 ATK),
///   마물이 살아있으면 즉시 반격(마물 ATK). 용사는 제자리. 마물 사망 시 칸이 비고 kills++, 보상 rKill.
///   벽/맵 밖이면 제자리(bumpedWall, rWallBump). 함정 칸 진입 시 이동은 성공하고 trapDamage 피해 + rTrapHit(+HP 손실 벌점).
/// - potion: 물약 있으면 HP +potionHeal(최대 maxHp), HP 비율 > potionWasteHpRatio였으면 rPotionWasteHigh 추가.
///   물약 없으면 무효(턴 소모) + rPotionNone.
/// - 직전 이동의 정반대 방향으로 "실제 이동"하면 rReverseMove (공격/물약은 lastMove를 갱신하지 않음).
/// - 매 턴 rStep. HP 손실 1당 rHpLossPerPoint. 종료: 왕좌 도달 rThrone, 사망 rDeath, steps >= maxSteps 이면 gaveUp rTimeout.
/// - 함정은 hp 0이며 공격 대상이 아니고 영구.
///
/// 보상 합산 순서: rStep → 행동별 보상(벽/처치/함정/되돌아가기/물약) → HP 손실 벌점 → 종료 보상.
/// 예: 함정 진입 = rStep + rTrapHit + rHpLossPerPoint*15 = -1 -5 -4.5 = -10.5.
///
/// 이벤트 규약:
/// - moved(pos=도착 칸), reversed(pos=도착 칸, moved 뒤에 붙음)
/// - bumpedWall(pos=시도한 칸)
/// - attacked(pos=마물 칸, amount=용사가 입힌 피해, monster=종류). 반격 피해는 별도 이벤트가 없고
///   hp/hpLost 변화 및 보상에 반영된다. 마물이 죽으면 killed(pos, monster)가 뒤따르고 반격은 없다.
/// - trapHit(pos, amount=피해, monster=trap)
/// - potionUsed(amount=실제 회복량), potionWasted(amount=회복량; 고HP 낭비 또는 물약 없음(amount 0))
class GameSim {
  /// [map]은 내부에서 clone한다. 웨이브가 끝나면 살아남은 마물은 호출자가 [map]에서 HP 회복시켜 재사용.
  GameSim(GridMap map, HeroStats hero)
      : _map = map.clone(),
        _hero = hero,
        _pos = Pos.entrance,
        _hp = hero.maxHp,
        _potions = hero.potions,
        _trail = [Pos.entrance];

  /// clone()용 내부 생성자.
  GameSim._copy(GameSim o)
      : _map = o._map.clone(),
        _hero = o._hero,
        _pos = o._pos,
        _hp = o._hp,
        _potions = o._potions,
        _steps = o._steps,
        _lastMove = o._lastMove,
        _trapHits = o._trapHits,
        _kills = o._kills,
        _hpLost = o._hpLost,
        _potionsUsed = o._potionsUsed,
        _outcome = o._outcome,
        _trail = List<Pos>.of(o._trail);

  final GridMap _map;
  final HeroStats _hero;
  Pos _pos;
  int _hp;
  int _potions;
  int _steps = 0;
  HeroAction? _lastMove;
  int _trapHits = 0;
  int _kills = 0;
  int _hpLost = 0;
  int _potionsUsed = 0;
  Outcome _outcome = Outcome.running;
  final List<Pos> _trail;

  /// 한 턴 진행. 종료된 시뮬레이션에 호출하면 [StateError].
  StepResult step(HeroAction a) {
    if (done) {
      throw StateError('이미 종료된 시뮬레이션입니다 ($_outcome)');
    }
    _steps++;
    var reward = Balance.rStep;
    final events = <Event>[];
    final hpBefore = _hp;

    if (a == HeroAction.potion) {
      reward += _usePotion(events);
    } else {
      reward += _move(a, events);
    }

    // HP 손실 벌점 (회복은 벌점 없음). 표시용으로 0 밑으로는 내려가지 않게 클램프.
    if (_hp < 0) _hp = 0;
    final lost = hpBefore - _hp;
    if (lost > 0) {
      _hpLost += lost;
      reward += Balance.rHpLossPerPoint * lost;
    }

    // 종료 판정: 사망 > 왕좌 > 턴 제한.
    if (_hp <= 0) {
      _outcome = Outcome.heroDied;
      reward += Balance.rDeath;
    } else if (_pos == Pos.throne) {
      _outcome = Outcome.reachedThrone;
      reward += Balance.rThrone;
    } else if (_steps >= Balance.maxSteps) {
      _outcome = Outcome.gaveUp;
      reward += Balance.rTimeout;
    }

    return StepResult(reward, _outcome, List.unmodifiable(events));
  }

  /// 물약 처리. 반환값 = 추가 보상(벌점).
  double _usePotion(List<Event> events) {
    if (_potions <= 0) {
      events.add(const Event(EventType.potionWasted, amount: 0));
      return Balance.rPotionNone;
    }
    final wasHigh = _hp / _hero.maxHp > Balance.potionWasteHpRatio;
    _potions--;
    _potionsUsed++;
    final room = _hero.maxHp - _hp;
    final healed = room < Balance.potionHeal ? room : Balance.potionHeal;
    _hp += healed;
    events.add(Event(EventType.potionUsed, amount: healed));
    if (wasHigh) {
      events.add(Event(EventType.potionWasted, amount: healed));
      return Balance.rPotionWasteHigh;
    }
    return 0;
  }

  /// 이동/공격 처리. 반환값 = 추가 보상.
  double _move(HeroAction a, List<Event> events) {
    final target = _pos.move(a);
    if (!target.inBounds || _map.isPillar(target)) {
      events.add(Event(EventType.bumpedWall, pos: target));
      return Balance.rWallBump;
    }

    final m = _map.monsters[target];
    if (m != null && !m.isTrap) {
      // 공격: 용사는 제자리, lastMove 불변.
      m.hp -= _hero.atk;
      events.add(Event(EventType.attacked, pos: target, amount: _hero.atk, monster: m.type));
      if (m.hp <= 0) {
        _map.monsters.remove(target);
        _kills++;
        events.add(Event(EventType.killed, pos: target, monster: m.type));
        return Balance.rKill;
      }
      // 반격
      _hp -= m.atk;
      return 0;
    }

    // 실제 이동 (빈칸 / 함정 / 왕좌)
    var reward = 0.0;
    final reversed = _lastMove != null && a == _lastMove!.opposite;
    _pos = target;
    _trail.add(target);
    events.add(Event(EventType.moved, pos: target));
    if (reversed) {
      events.add(Event(EventType.reversed, pos: target));
      reward += Balance.rReverseMove;
    }
    _lastMove = a;

    if (m != null && m.isTrap) {
      _hp -= m.atk;
      _trapHits++;
      events.add(Event(EventType.trapHit, pos: target, amount: m.atk, monster: m.type));
      reward += Balance.rTrapHit;
    }
    return reward;
  }

  bool get done => _outcome != Outcome.running;
  Outcome get outcome => _outcome;

  Pos get heroPos => _pos;
  int get hp => _hp;
  int get maxHp => _hero.maxHp;
  int get atk => _hero.atk;
  int get potions => _potions;
  int get steps => _steps;
  HeroAction? get lastMove => _lastMove;

  /// 이 시뮬레이션의 용사 스탯 원본.
  HeroStats get hero => _hero;

  int get trapHits => _trapHits;
  int get kills => _kills;
  int get hpLost => _hpLost;
  int get potionsUsed => _potionsUsed;

  /// 방문 순서 (입구 포함, 공격으로 제자리인 턴은 추가하지 않음). 읽기 전용 뷰.
  List<Pos> get trail => List.unmodifiable(_trail);

  /// 현재 상태의 맵 (죽은 마물은 제거됨, 살아있는 마물은 현재 HP).
  /// 내부 객체를 그대로 돌려주므로(인코더 성능) 호출자는 읽기 전용으로 다뤄야 한다.
  GridMap get map => _map;

  /// 깊은 복사 (맵 포함). 이후 원본과 독립.
  GameSim clone() => GameSim._copy(this);
}
