import 'dart:io';

/// VM(CLI)용 학습 산출물 파일 쓰기. 공개 API는 trainer_fs_stub.dart와 동일해야 한다.
class TrainerFs {
  TrainerFs(this.outDir);
  final String outDir;

  static const String checkpointsSub = 'checkpoints';
  static const String curveFile = 'curve.csv';

  String get _checkpointDir => '$outDir${Platform.pathSeparator}$checkpointsSub';
  String get _curvePath => '$outDir${Platform.pathSeparator}$curveFile';

  /// outDir/checkpoints 생성 + curve.csv 를 헤더 한 줄로 새로 만든다 (기존 파일은 덮어씀).
  void prepare(String csvHeader) {
    Directory(_checkpointDir).createSync(recursive: true);
    File(_curvePath).writeAsStringSync('$csvHeader\n');
  }

  /// outDir/checkpoints/ep_N.json 저장.
  void writeCheckpoint(int episode, String sparseJson) {
    File('$_checkpointDir${Platform.pathSeparator}ep_$episode.json').writeAsStringSync(sparseJson);
  }

  /// curve.csv 한 줄 추가.
  void appendCurveRow(String row) {
    File(_curvePath).writeAsStringSync('$row\n', mode: FileMode.append);
  }
}
