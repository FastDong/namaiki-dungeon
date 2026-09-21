/// 파일 시스템이 없는 플랫폼(웹)용 스텁. Trainer는 앱에서 실행되지 않으므로 호출되면 안 된다.
///
/// trainer.dart가 `import 'trainer_fs_stub.dart' if (dart.library.io) 'trainer_fs_io.dart'`로
/// 고르기 때문에 dungeon_core 자체는 dart:io를 무조건 임포트하지 않는다.
class TrainerFs {
  TrainerFs(this.outDir);
  final String outDir;

  static const String checkpointsSub = 'checkpoints';
  static const String curveFile = 'curve.csv';

  Never _unsupported() => throw UnsupportedError('이 플랫폼에서는 학습 산출물을 파일로 쓸 수 없습니다 (dart:io 없음)');

  /// outDir/checkpoints 생성 + curve.csv 를 헤더 한 줄로 새로 만든다.
  void prepare(String csvHeader) => _unsupported();

  /// outDir/checkpoints/ep_N.json 저장.
  void writeCheckpoint(int episode, String sparseJson) => _unsupported();

  /// curve.csv 한 줄 추가.
  void appendCurveRow(String row) => _unsupported();
}
