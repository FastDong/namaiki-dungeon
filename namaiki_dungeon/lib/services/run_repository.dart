/// 리더보드 기록 데이터 클래스. Firestore 접근(RunRepository)은 M7이 이 파일에 추가한다.
class RunRecord {
  final String uid;
  final String nickname;

  /// 막아낸 웨이브 수 (0..15).
  final int wavesCleared;

  /// 도달한 AI 단계 (1..3).
  final int stageReached;

  /// 용사를 처치한 횟수.
  final int heroDeaths;

  /// 플레이 시간(초).
  final int durationSec;

  /// 마지막 배치의 JSON 스냅샷 (GridMap.toJson).
  final String layoutSnapshot;

  const RunRecord({
    required this.uid,
    required this.nickname,
    required this.wavesCleared,
    required this.stageReached,
    required this.heroDeaths,
    required this.durationSec,
    required this.layoutSnapshot,
  });

  /// Firestore 문서 필드용 (createdAt/appVersion은 저장 계층이 붙인다).
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'nickname': nickname,
        'wavesCleared': wavesCleared,
        'stageReached': stageReached,
        'heroDeaths': heroDeaths,
        'durationSec': durationSec,
        'layoutSnapshot': layoutSnapshot,
      };

  factory RunRecord.fromMap(Map<String, dynamic> m) => RunRecord(
        uid: (m['uid'] as String?) ?? '',
        nickname: (m['nickname'] as String?) ?? '마왕',
        wavesCleared: (m['wavesCleared'] as num?)?.toInt() ?? 0,
        stageReached: (m['stageReached'] as num?)?.toInt() ?? 1,
        heroDeaths: (m['heroDeaths'] as num?)?.toInt() ?? 0,
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
        layoutSnapshot: (m['layoutSnapshot'] as String?) ?? '',
      );

  @override
  String toString() =>
      'RunRecord($nickname waves=$wavesCleared stage=$stageReached deaths=$heroDeaths ${durationSec}s)';
}
