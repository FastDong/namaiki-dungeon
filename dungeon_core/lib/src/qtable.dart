import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'balance.dart';
import 'feature_encoder.dart';

/// 표 기반 Q 함수. 학습 시 dense Float32List(stateCount*5) = 9.3MB, 저장은 방문 상태만 sparse JSON.
///
/// sparse JSON 형식: {"v": featureSpecVersion, "n": 5, "q": {"stateIndex": [q0,q1,q2,q3,q4], ...}}
/// 청크: 같은 형식을 statesPerChunk 상태씩 나눈 문자열 배열. fromChunks는 순서 무관하게 병합.
///
/// "방문"은 오직 [markVisited] 플래그로 판정한다 (낙관 초기값 +2가 거의 모든 상태에 들어가므로 |q|>0 은 기준이 못 된다).
/// Trainer는 Q 갱신 시 반드시 [markVisited]를 호출해야 sparse JSON에 포함된다. [set]은 플래그를 건드리지 않는다.
class QTable {
  QTable()
      : _q = Float32List(FeatureEncoder.stateCount * FeatureEncoder.actionCount),
        _visited = Uint8List(FeatureEncoder.stateCount),
        _visitedCount = 0;

  QTable._(this._q, this._visited, this._visitedCount);

  final Float32List _q;

  /// 상태별 방문 플래그 (0/1).
  final Uint8List _visited;
  int _visitedCount;

  static const int _n = FeatureEncoder.actionCount;

  /// 직접 접근이 필요한 학습 루프용 (읽기 전용 취급).
  Float32List get raw => _q;

  double get(int s, int a) => _q[s * _n + a];
  void set(int s, int a, double v) => _q[s * _n + a] = v;

  /// 길이 5 (복사본).
  List<double> row(int s) {
    final base = s * _n;
    return List<double>.generate(_n, (a) => _q[base + a], growable: false);
  }

  /// max_a Q(s,a). 할당 없음 (Q-learning 목표값 계산용).
  double maxValue(int s) {
    final base = s * _n;
    var best = _q[base];
    for (var a = 1; a < _n; a++) {
      final v = _q[base + a];
      if (v > best) best = v;
    }
    return best;
  }

  /// 동점은 rng로 랜덤 선택. 단독 최대면 rng를 소비하지 않는다. 할당 없음.
  int argmax(int s, Random rng) {
    final base = s * _n;
    var best = _q[base];
    var bestIdx = 0;
    var ties = 1;
    for (var a = 1; a < _n; a++) {
      final v = _q[base + a];
      if (v > best) {
        best = v;
        bestIdx = a;
        ties = 1;
      } else if (v == best) {
        ties++;
      }
    }
    if (ties == 1) return bestIdx;
    var k = rng.nextInt(ties);
    for (var a = 0; a < _n; a++) {
      if (_q[base + a] == best) {
        if (k == 0) return a;
        k--;
      }
    }
    return bestIdx; // 도달 불가 (NaN 방어)
  }

  /// 방문 플래그가 있는 상태 수.
  int get visitedCount => _visitedCount;

  /// 방문 상태 표시 (Trainer가 update 시 호출). 낙관 초기값과 구분하기 위해 필요.
  void markVisited(int s) {
    if (_visited[s] == 0) {
      _visited[s] = 1;
      _visitedCount++;
    }
  }

  bool isVisited(int s) => _visited[s] != 0;

  /// 방문 상태 인덱스 오름차순.
  Int32List _visitedIndices() {
    final out = Int32List(_visitedCount);
    var k = 0;
    for (var s = 0; s < FeatureEncoder.stateCount && k < _visitedCount; s++) {
      if (_visited[s] != 0) out[k++] = s;
    }
    return out;
  }

  /// 방문 상태만 포함하는 sparse JSON (인덱스 오름차순, [decimals] 자리 반올림).
  String toSparseJson({int decimals = 2}) {
    final idx = _visitedIndices();
    return _sparseJsonOf(idx, 0, idx.length, decimals);
  }

  /// [json]의 "v"가 [Balance.featureSpecVersion]과 다르거나 형식이 깨졌으면 [FormatException].
  /// 포함된 상태는 방문 표시된다.
  factory QTable.fromSparseJson(String json) {
    final t = QTable();
    t._mergeSparseJson(json);
    return t;
  }

  /// 방문 상태를 인덱스 오름차순으로 [statesPerChunk]개씩 잘라 각각 완전한 sparse JSON 문자열로.
  /// 방문 상태가 없으면 빈 리스트.
  List<String> toChunks({int statesPerChunk = Balance.statesPerChunk, int decimals = 2}) {
    if (statesPerChunk <= 0) {
      throw ArgumentError.value(statesPerChunk, 'statesPerChunk', '양수여야 함');
    }
    final idx = _visitedIndices();
    final chunks = <String>[];
    for (var start = 0; start < idx.length; start += statesPerChunk) {
      final end = min(start + statesPerChunk, idx.length);
      chunks.add(_sparseJsonOf(idx, start, end, decimals));
    }
    return chunks;
  }

  /// 순서 무관 병합. 같은 상태가 여러 청크에 있으면 뒤의 것이 덮어쓴다. 병합된 상태는 방문 표시.
  factory QTable.fromChunks(List<String> chunks) {
    final t = QTable();
    for (final c in chunks) {
      t._mergeSparseJson(c);
    }
    return t;
  }

  QTable clone() => QTable._(Float32List.fromList(_q), Uint8List.fromList(_visited), _visitedCount);

  // ── 직렬화 내부 ─────────────────────────────────────

  String _sparseJsonOf(Int32List idx, int start, int end, int decimals) {
    final b = StringBuffer()
      ..write('{"v":')
      ..write(Balance.featureSpecVersion)
      ..write(',"n":')
      ..write(_n)
      ..write(',"q":{');
    for (var i = start; i < end; i++) {
      if (i > start) b.write(',');
      final s = idx[i];
      final base = s * _n;
      b
        ..write('"')
        ..write(s)
        ..write('":[');
      for (var a = 0; a < _n; a++) {
        if (a > 0) b.write(',');
        b.write(_fmt(_q[base + a], decimals));
      }
      b.write(']');
    }
    b.write('}}');
    return b.toString();
  }

  /// [decimals] 자리 반올림 후 불필요한 0/소수점 제거 ("2.00" → "2", "-0.30" → "-0.3", "-0" → "0").
  static String _fmt(double v, int decimals) {
    if (!v.isFinite) return '0';
    final s = v.toStringAsFixed(decimals);
    var end = s.length;
    if (decimals > 0) {
      while (end > 0 && s.codeUnitAt(end - 1) == 0x30 /* '0' */) {
        end--;
      }
      if (end > 0 && s.codeUnitAt(end - 1) == 0x2E /* '.' */) end--;
    }
    final out = end == s.length ? s : s.substring(0, end);
    return out == '-0' ? '0' : out;
  }

  void _mergeSparseJson(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('sparse JSON 루트가 객체가 아님');
    }
    final v = decoded['v'];
    if (v != Balance.featureSpecVersion) {
      throw FormatException('featureSpecVersion 불일치: $v (기대 ${Balance.featureSpecVersion})');
    }
    final n = decoded['n'];
    if (n != null && n != _n) {
      throw FormatException('행동 수 불일치: $n (기대 $_n)');
    }
    final q = decoded['q'];
    if (q is! Map<String, dynamic>) {
      throw const FormatException('"q"가 객체가 아님');
    }
    q.forEach((key, value) {
      final s = int.tryParse(key);
      if (s == null || s < 0 || s >= FeatureEncoder.stateCount) {
        throw FormatException('상태 인덱스 범위 밖: $key');
      }
      if (value is! List || value.length != _n) {
        throw FormatException('상태 $key 의 Q 배열 길이가 $_n 이 아님');
      }
      final base = s * _n;
      for (var a = 0; a < _n; a++) {
        final x = value[a];
        if (x is! num) throw FormatException('상태 $key 행동 $a 값이 숫자가 아님');
        _q[base + a] = x.toDouble();
      }
      markVisited(s);
    });
  }
}
