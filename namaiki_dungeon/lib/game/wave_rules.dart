import 'package:dungeon_core/dungeon_core.dart';

/// 웨이브 진행 규칙 래퍼. 숫자는 전부 `Balance`에서만 읽는다 (앱은 규칙을 재구현하지 않는다).
class WaveRules {
  WaveRules._();

  /// 총 웨이브 수 (15).
  static int get totalWaves => Balance.totalWaves;

  /// 단계 수 (15 / 5 = 3).
  static int get stageCount => Balance.totalWaves ~/ Balance.wavesPerStage;

  /// 시작 마나 (12).
  static int get startMana => Balance.startMana;

  /// 웨이브 클리어마다 지급되는 마나 (5).
  static int get manaPerWave => Balance.manaPerWave;

  /// 턴 제한 (80).
  static int get maxSteps => Balance.maxSteps;

  /// 웨이브 w 용사 스탯 (HP 50+6(w−1), ATK 8+(w−1), 물약 2).
  static HeroStats heroFor(int wave) => HeroStats.forWave(wave);

  /// 웨이브 → AI 단계 (1~5: 1, 6~10: 2, 11~15: 3).
  static int stageForWave(int wave) => Balance.stageForWave(wave);

  /// 웨이브 w 시작 시점까지 누적 지급된 마나 (12 + 5(w−1)).
  static int cumulativeMana(int wave) => Balance.cumulativeMana(wave);

  /// [fromWave] → [toWave]로 넘어갈 때 단계가 바뀌는가 (5→6, 10→11).
  static bool isStageTransition(int fromWave, int toWave) =>
      stageForWave(fromWave) != stageForWave(toWave);

  /// 마지막 웨이브인가.
  static bool isFinalWave(int wave) => wave >= Balance.totalWaves;

  /// 단계 표시 이름.
  static String stageName(int stage) => switch (stage) {
        1 => '풋내기',
        2 => '노련한',
        3 => '각성한',
        _ => '알 수 없는',
      };
}
