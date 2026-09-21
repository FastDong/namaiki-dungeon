import 'dart:math';
import 'dart:typed_data';

import 'balance.dart';
import 'feature_encoder.dart';

/// 표 기반 Q 함수. 학습 시 dense Float32List(stateCount*5) = 9.3MB, 저장은 방문 상태만 sparse JSON.
///
/// sparse JSON 형식: {"v": featureSpecVersion, "n": 5, "q": {"stateIndex": [q0,q1,q2,q3,q4], ...}}
/// 청크: 같은 형식을 statesPerChunk 상태씩 나눈 문자열 배열. fromChunks는 순서 무관하게 병합.
class QTable {
  QTable() : _q = Float32List(FeatureEncoder.stateCount * FeatureEncoder.actionCount);

  final Float32List _q;

  /// 직접 접근이 필요한 학습 루프용 (읽기 전용 취급).
  Float32List get raw => _q;

  double get(int s, int a) => _q[s * FeatureEncoder.actionCount + a];
  void set(int s, int a, double v) => _q[s * FeatureEncoder.actionCount + a] = v;

  /// 길이 5 (복사본).
  List<double> row(int s) => throw UnimplementedError('M1');

  /// 동점은 rng로 랜덤 선택.
  int argmax(int s, Random rng) => throw UnimplementedError('M1');

  /// 값이 하나라도 0이 아닌 상태 수 (또는 방문 플래그가 있는 상태 수).
  int get visitedCount => throw UnimplementedError('M1');

  /// 방문 상태 표시 (Trainer가 update 시 호출). 낙관 초기값과 구분하기 위해 필요.
  void markVisited(int s) => throw UnimplementedError('M1');
  bool isVisited(int s) => throw UnimplementedError('M1');

  String toSparseJson({int decimals = 2}) => throw UnimplementedError('M1');
  factory QTable.fromSparseJson(String json) => throw UnimplementedError('M1');

  List<String> toChunks({int statesPerChunk = Balance.statesPerChunk, int decimals = 2}) =>
      throw UnimplementedError('M1');
  factory QTable.fromChunks(List<String> chunks) => throw UnimplementedError('M1');

  QTable clone() => throw UnimplementedError('M1');
}
