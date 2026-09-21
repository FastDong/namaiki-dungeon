import 'layout_generator.dart';
import 'qtable.dart';

/// 학습 설정. CLI 인자(bin/train.dart)에서 채운다.
class TrainConfig {
  final int episodes;
  final int seed;
  final int checkpointEvery;

  /// 체크포인트 JSON과 curve.csv를 쓰는 폴더 (예: out/). checkpoints/ep_N.json 형식.
  final String outDir;

  /// 지정하면 커리큘럼 대신 이 tier만 사용 (스모크 런용).
  final Tier? onlyTier;

  /// 스모크 모드: 체크포인트 파일을 쓰지 않고 진행 로그만 출력.
  final bool smoke;

  const TrainConfig({
    required this.episodes,
    this.seed = 7,
    this.checkpointEvery = 2000,
    this.outDir = 'out',
    this.onlyTier,
    this.smoke = false,
  });
}

/// 학습 곡선 한 점 (최근 checkpointEvery 에피소드 집계).
class CurvePoint {
  final int episode;
  final double winRate, avgReturn, avgSteps;
  final String tier;
  const CurvePoint(this.episode, this.winRate, this.avgReturn, this.avgSteps, this.tier);

  String toCsvRow() => '$episode,${winRate.toStringAsFixed(4)},${avgReturn.toStringAsFixed(2)},${avgSteps.toStringAsFixed(2)},$tier';
  static const String csvHeader = 'episode,winRate,avgReturn,avgSteps,tier';
}

/// 표 기반 Q-learning 학습 루프 (PLAN.md §5.4~5.6).
///
/// - Q 초기값: 왕좌에 가까워지는 이동 행동 +optimisticInit, 나머지 0 (상태 최초 방문 시 적용).
/// - ε: epsStart → epsEnd, 전체의 epsDecayFraction 지점까지 선형 감소 후 고정.
/// - α: alpha, 전체의 alphaLateFraction 지점부터 alphaLate.
/// - 커리큘럼: Balance.curriculum* 상수 참조. onlyTier가 있으면 그 tier만.
/// - 에피소드마다 tier에 맞는 웨이브를 샘플해 HeroStats.forWave(w).
/// - checkpointEvery마다 onCheckpoint 호출 + (smoke가 아니면) outDir/checkpoints/ep_N.json 저장 + curve.csv 한 줄 추가.
class Trainer {
  Trainer(this.config);
  final TrainConfig config;

  Future<QTable> run({void Function(int episode, QTable q, CurvePoint p)? onCheckpoint}) =>
      throw UnimplementedError('M3');
}
