/// 모든 게임 수치·보상·RL 하이퍼파라미터. 다른 파일에서 숫자를 하드코딩하지 않는다.
class Balance {
  Balance._();

  // ── 맵 ──────────────────────────────────────────────
  static const int cols = 7, rows = 7;
  static const List<List<int>> pillars = [
    [1, 1], [1, 3], [1, 5],
    [3, 1], [3, 3], [3, 5],
    [5, 1], [5, 3], [5, 5],
  ];
  static const int entranceX = 0, entranceY = 0, throneX = 6, throneY = 6;

  /// 입구 인접 2칸은 배치 금지 (용사가 첫 턴부터 갇히는 것 방지).
  static const List<List<int>> forbiddenNearEntrance = [[1, 0], [0, 1]];

  // ── 진행 ────────────────────────────────────────────
  static const int maxSteps = 80;
  static const int startMana = 12, manaPerWave = 5, totalWaves = 15, wavesPerStage = 5;

  // ── 용사 ────────────────────────────────────────────
  static const int heroBaseHp = 50, heroHpPerWave = 6, heroBaseAtk = 8, heroAtkPerWave = 1;
  static const int potions = 2, potionHeal = 25;
  static const int trapDamage = 15;

  /// 물약 사용이 "낭비"로 간주되는 HP 비율 (이 값 초과 시 사용하면 벌점).
  static const double potionWasteHpRatio = 0.75;

  // ── 보상 ────────────────────────────────────────────
  static const double rThrone = 100, rDeath = -100, rTimeout = -50, rStep = -1, rKill = 5;
  static const double rHpLossPerPoint = -0.3, rTrapHit = -5, rWallBump = -2, rReverseMove = -1;
  static const double rPotionWasteHigh = -3, rPotionNone = -2;

  // ── RL ──────────────────────────────────────────────
  static const double gamma = 0.97, alpha = 0.1, alphaLate = 0.03, epsPlay = 0.03;
  static const double epsStart = 1.0, epsEnd = 0.05, epsDecayFraction = 0.6, optimisticInit = 2.0;

  /// α가 alphaLate로 내려가는 지점 (전체 에피소드 비율).
  static const double alphaLateFraction = 0.7;
  static const int checkpointEvery = 2000;

  /// 커리큘럼: [0, 0.2) easy, [0.2, 0.6) medium, [0.6, 1.0) hard 40% / adversarial 40% / fixed 20%.
  static const double curriculumEasyEnd = 0.2, curriculumMediumEnd = 0.6;
  static const double lateHardShare = 0.4, lateAdversarialShare = 0.4;
  static const int adversarialCandidates = 8, adversarialRollouts = 2;

  /// 단계 선정 승률 문턱 (stage3은 최고 승률 체크포인트).
  static const double stage1WinRate = 0.10, stage2WinRate = 0.45;

  /// 폴백(분위수) 규칙: 문턱 미달 시 학습 진행률 기준.
  static const double stage1Quantile = 0.05, stage2Quantile = 0.30;

  static const int featureSpecVersion = 1;
  static const int statesPerChunk = 6000;

  // ── 파생 ────────────────────────────────────────────
  static int heroHp(int wave) => heroBaseHp + heroHpPerWave * (wave - 1);
  static int heroAtk(int wave) => heroBaseAtk + heroAtkPerWave * (wave - 1);
  static int stageForWave(int wave) => 1 + (wave - 1) ~/ wavesPerStage;

  /// 웨이브 w 시작 시점까지 누적 지급된 마나 (미사용분 이월 전제).
  static int cumulativeMana(int wave) => startMana + manaPerWave * (wave - 1);
}
