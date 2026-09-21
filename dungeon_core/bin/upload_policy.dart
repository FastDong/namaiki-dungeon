// 정책 업로더 (M4). Firestore REST API로 policies/{stageN} 메타 문서 + chunks 서브컬렉션(+ curves/run1)을 PATCH.
//
//   dart run bin/upload_policy.dart --project <projectId> --api-key <apiKey> --out out/
//
// 옵션:
//   --out DIR            policy_stage{1,2,3}.json (+ eval.json, curve.csv) 폴더 (기본 out)
//   --stages 1,2,3       업로드할 단계 (기본 1,2,3; 파일 없는 단계는 건너뜀)
//   --collection NAME    대상 컬렉션 (기본 policies; 스모크 테스트는 policies_smoke 등)
//   --version STR        메타 version 문자열 (기본 현재 시각 "2026-09-21T15:00")
//   --no-curves          curves/run1 업로드 생략
//   --dry-run            네트워크 없이 청크 크기·문서 필드만 출력
//   --delete             업로드 대신 해당 단계 문서 + chunks 삭제 (스모크 정리용)
//   --make-smoke DIR     테스트용 가짜 정책(방문 상태 50개) DIR/policy_stage1.json 생성 후 종료
//
// 특징: 청크 ≤ 900KB 검증(초과 시 자동 재분할), 요청 3회 재시도, 멱등(덮어쓰기 + 남는 옛 청크 삭제),
//       업로드 후 GET으로 검증. API 키는 로그에 절대 찍지 않는다.
//
// 정책 파일 형식(bin/evaluate.dart 산출물): {"meta":{stage,name,algorithm,featureSpecVersion,episodes,winRate,
//   avgSteps,trapHits,potionsUsed,kills,stateCount,selectionRule}, "q": <QTable.toSparseJson>}
//   (루트가 곧 sparse JSON {"v","n","q"} 인 파일도 허용)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:http/http.dart' as http;

const int maxChunkBytes = 900 * 1024;
const int maxRetries = 3;
const int curveMaxPoints = 300;

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  if (args.containsKey('help') || args.containsKey('h')) {
    stdout.writeln(_usage);
    return;
  }

  final smokeDir = args['make-smoke'];
  if (smokeDir != null) {
    _makeSmokePolicy(smokeDir);
    return;
  }

  final project = args['project'];
  final apiKey = args['api-key'];
  final dryRun = args.containsKey('dry-run');
  if (project == null || project.isEmpty) _die('--project 가 필요합니다');
  if (!dryRun && (apiKey == null || apiKey.isEmpty)) _die('--api-key 가 필요합니다 (--dry-run 이면 생략 가능)');

  final outDir = args['out'] ?? 'out';
  final collection = args['collection'] ?? 'policies';
  final stages = (args['stages'] ?? '1,2,3')
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
  final version = args['version'] ?? _defaultVersion();
  final uploadCurves = !args.containsKey('no-curves');

  final client = FirestoreRest(project: project, apiKey: apiKey ?? '', dryRun: dryRun);

  if (args.containsKey('delete')) {
    for (final s in stages) {
      await _deleteStage(client, collection, 'stage$s');
    }
    stdout.writeln('삭제 완료: $collection/stage{${stages.join(',')}}');
    client.close();
    return;
  }

  var uploaded = 0;
  final failures = <String>[];
  for (final s in stages) {
    final file = File('$outDir${Platform.pathSeparator}policy_stage$s.json');
    if (!file.existsSync()) {
      stdout.writeln('[stage$s] ${file.path} 없음 → 건너뜀');
      continue;
    }
    try {
      await _uploadStage(client, collection, s, file, version);
      uploaded++;
    } catch (e, st) {
      failures.add('stage$s: $e');
      stderr.writeln('[stage$s] 실패: $e\n$st');
    }
  }

  if (uploadCurves) {
    try {
      await _uploadCurves(client, outDir);
    } catch (e) {
      failures.add('curves: $e');
      stderr.writeln('[curves] 실패: $e');
    }
  }

  client.close();
  stdout.writeln('');
  stdout.writeln('완료: 단계 $uploaded개 업로드${dryRun ? ' (dry-run)' : ''}, 실패 ${failures.length}건');
  for (final f in failures) {
    stdout.writeln('  - $f');
  }
  if (failures.isNotEmpty) exitCode = 1;
}

// ── 단계 업로드 ─────────────────────────────────────────

Future<void> _uploadStage(FirestoreRest fs, String collection, int stage, File file, String version) async {
  final stageId = 'stage$stage';
  stdout.writeln('[$stageId] 읽는 중: ${file.path} (${_mb(file.lengthSync())})');
  final text = file.readAsStringSync();
  final parsed = _parsePolicyFile(text, stage);
  final table = parsed.table;
  final meta = parsed.meta;

  // 청크 분할 (≤ 900KB 검증, 초과 시 statesPerChunk 절반으로 재분할)
  var statesPerChunk = Balance.statesPerChunk;
  List<String> chunks;
  while (true) {
    chunks = table.toChunks(statesPerChunk: statesPerChunk);
    final maxBytes = chunks.fold<int>(0, (m, c) => max(m, utf8.encode(c).length));
    if (maxBytes <= maxChunkBytes || statesPerChunk <= 100) {
      stdout.writeln('[$stageId] 상태 ${table.visitedCount}개 → 청크 ${chunks.length}개 '
          '(청크당 ≤ $statesPerChunk 상태, 최대 ${_kb(maxBytes)})');
      if (maxBytes > maxChunkBytes) {
        throw StateError('청크 크기 ${_kb(maxBytes)} > 900KB (statesPerChunk=$statesPerChunk)');
      }
      break;
    }
    statesPerChunk ~/= 2;
  }
  if (chunks.isEmpty) throw StateError('방문 상태가 0개 — 업로드할 Q값이 없음');

  // 메타 문서 필드 (PLAN §6)
  final fields = <String, dynamic>{
    'stage': stage,
    'name': (meta['name'] as String?) ?? stageId,
    'algorithm': (meta['algorithm'] as String?) ?? 'tabular_q_learning',
    'featureSpecVersion': Balance.featureSpecVersion,
    'episodes': _int(meta['episodes']) ?? 0,
    'winRate': _dbl(meta['winRate']) ?? 0.0,
    'avgSteps': _dbl(meta['avgSteps']) ?? 0.0,
    'trapHits': _dbl(meta['trapHits']) ?? 0.0,
    'potionsUsed': _dbl(meta['potionsUsed']) ?? 0.0,
    'kills': _dbl(meta['kills']) ?? 0.0,
    'stateCount': table.visitedCount,
    'chunkCount': chunks.length,
    'statesPerChunk': statesPerChunk,
    'version': version,
    'createdAt': DateTime.now().toUtc(),
  };
  if (meta['selectionRule'] is String) fields['selectionRule'] = meta['selectionRule'];
  if (meta['demo'] is bool) fields['demoWin'] = meta['demo'];

  // 1) 청크 먼저 (읽는 쪽이 새 메타를 보는 시점에 청크가 모두 있어야 함)
  for (var i = 0; i < chunks.length; i++) {
    final id = i.toString().padLeft(3, '0');
    await fs.patchDocument('$collection/$stageId/chunks/$id', {'data': chunks[i], 'index': i});
    stdout.writeln('[$stageId] chunk $id 업로드 (${_kb(utf8.encode(chunks[i]).length)})');
  }
  // 2) 메타 문서
  await fs.patchDocument('$collection/$stageId', fields);
  stdout.writeln('[$stageId] 메타 문서 업로드 (chunkCount=${chunks.length}, states=${table.visitedCount}, version=$version)');

  // 3) 남은 옛 청크 삭제 (멱등: 이전 업로드가 더 많은 청크였을 때)
  final existing = await fs.listDocumentIds('$collection/$stageId/chunks');
  final stale = existing.where((id) => (int.tryParse(id) ?? -1) >= chunks.length || int.tryParse(id) == null).toList();
  for (final id in stale) {
    await fs.deleteDocument('$collection/$stageId/chunks/$id');
    stdout.writeln('[$stageId] 옛 chunk $id 삭제');
  }

  // 4) 검증
  if (!fs.dryRun) {
    final doc = await fs.getDocument('$collection/$stageId');
    final got = _int(_decodeValue(doc?['fields']?['chunkCount']));
    final ids = await fs.listDocumentIds('$collection/$stageId/chunks');
    if (got != chunks.length || ids.length != chunks.length) {
      throw StateError('검증 실패: chunkCount=$got, chunks 문서 ${ids.length}개 (기대 ${chunks.length})');
    }
    stdout.writeln('[$stageId] 검증 OK: chunkCount=$got, chunks ${ids.length}개');
  }
}

Future<void> _deleteStage(FirestoreRest fs, String collection, String stageId) async {
  final ids = await fs.listDocumentIds('$collection/$stageId/chunks');
  for (final id in ids) {
    await fs.deleteDocument('$collection/$stageId/chunks/$id');
    stdout.writeln('[$stageId] chunk $id 삭제');
  }
  await fs.deleteDocument('$collection/$stageId');
  stdout.writeln('[$stageId] 메타 문서 삭제');
  if (!fs.dryRun) {
    final doc = await fs.getDocument('$collection/$stageId');
    final left = await fs.listDocumentIds('$collection/$stageId/chunks');
    stdout.writeln('[$stageId] 삭제 검증: 문서 ${doc == null ? '없음(OK)' : '남아 있음!'}, chunks ${left.length}개');
  }
}

// ── curves/run1 (옵션) ──────────────────────────────────

Future<void> _uploadCurves(FirestoreRest fs, String outDir) async {
  final csv = File('$outDir${Platform.pathSeparator}curve.csv');
  if (!csv.existsSync()) {
    stdout.writeln('[curves] ${csv.path} 없음 → 생략');
    return;
  }
  final lines = csv.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) {
    stdout.writeln('[curves] 데이터 행 없음 → 생략');
    return;
  }
  final header = lines.first.split(',').map((s) => s.trim()).toList();
  int col(String name) => header.indexOf(name);
  final iEp = col('episode'), iWin = col('winRate'), iRet = col('avgReturn'), iSteps = col('avgSteps');
  if (iEp < 0 || iWin < 0) {
    stdout.writeln('[curves] 헤더에 episode/winRate 없음 → 생략');
    return;
  }
  final points = <Map<String, num>>[];
  for (final l in lines.skip(1)) {
    final c = l.split(',');
    if (c.length <= max(iEp, iWin)) continue;
    final ep = int.tryParse(c[iEp].trim());
    final win = double.tryParse(c[iWin].trim());
    if (ep == null || win == null) continue;
    points.add({
      'ep': ep,
      'win': _round(win, 4),
      'reward': iRet >= 0 && iRet < c.length ? _round(double.tryParse(c[iRet].trim()) ?? 0, 2) : 0,
      'steps': iSteps >= 0 && iSteps < c.length ? _round(double.tryParse(c[iSteps].trim()) ?? 0, 2) : 0,
    });
  }
  // ≤ 300점으로 다운샘플
  List<Map<String, num>> sampled = points;
  if (points.length > curveMaxPoints) {
    sampled = [];
    for (var i = 0; i < curveMaxPoints; i++) {
      sampled.add(points[(i * (points.length - 1) / (curveMaxPoints - 1)).round()]);
    }
  }
  final markers = <int>[];
  final evalFile = File('$outDir${Platform.pathSeparator}eval.json');
  if (evalFile.existsSync()) {
    try {
      final ev = jsonDecode(evalFile.readAsStringSync());
      final st = ev is Map ? ev['stages'] : null;
      if (st is Map) {
        for (final k in ['stage1', 'stage2', 'stage3']) {
          final v = _int(st[k]);
          if (v != null) markers.add(v);
        }
      }
    } catch (e) {
      stdout.writeln('[curves] eval.json 파싱 실패($e) → stageMarkers 생략');
    }
  }
  await fs.patchDocument('curves/run1', {
    'data': jsonEncode(sampled),
    'points': sampled.length,
    'stageMarkers': markers,
    'updatedAt': DateTime.now().toUtc(),
  });
  stdout.writeln('[curves] curves/run1 업로드 (${sampled.length}점, markers=$markers)');
}

// ── 정책 파일 파싱 ──────────────────────────────────────

class _ParsedPolicy {
  _ParsedPolicy(this.table, this.meta);
  final QTable table;
  final Map<String, dynamic> meta;
}

_ParsedPolicy _parsePolicyFile(String text, int stage) {
  final root = jsonDecode(text);
  if (root is! Map) throw const FormatException('정책 파일 루트가 객체가 아님');
  final j = Map<String, dynamic>.from(root);
  Map<String, dynamic> meta = {};
  String sparse;
  if (j.containsKey('v') && j.containsKey('n') && j['q'] is Map) {
    // 루트가 곧 sparse JSON
    sparse = text;
  } else {
    final q = j['q'] ?? j['table'] ?? j['qtable'];
    if (q == null) throw const FormatException('정책 파일에 "q"가 없음');
    sparse = q is String ? q : jsonEncode(q);
    final m = j['meta'];
    if (m is Map) meta = Map<String, dynamic>.from(m);
  }
  final table = QTable.fromSparseJson(sparse); // featureSpecVersion 검증 포함 (불일치면 FormatException)
  meta.putIfAbsent('stage', () => stage);
  return _ParsedPolicy(table, meta);
}

// ── 스모크용 가짜 정책 ──────────────────────────────────

void _makeSmokePolicy(String dir) {
  final rng = Random(7);
  final t = QTable();
  final used = <int>{};
  while (used.length < 50) {
    final s = rng.nextInt(FeatureEncoder.stateCount);
    if (!used.add(s)) continue;
    for (var a = 0; a < FeatureEncoder.actionCount; a++) {
      t.set(s, a, (rng.nextDouble() * 20 - 10));
    }
    t.markVisited(s);
  }
  final meta = {
    'stage': 1,
    'name': '스모크 테스트 정책',
    'algorithm': 'tabular_q_learning',
    'featureSpecVersion': Balance.featureSpecVersion,
    'episodes': 0,
    'winRate': 0.0,
    'avgSteps': 0.0,
    'trapHits': 0.0,
    'potionsUsed': 0.0,
    'kills': 0.0,
    'stateCount': t.visitedCount,
    'selectionRule': 'smoke',
  };
  Directory(dir).createSync(recursive: true);
  final path = '$dir${Platform.pathSeparator}policy_stage1.json';
  File(path).writeAsStringSync('{"meta":${jsonEncode(meta)},"q":${t.toSparseJson()}}');
  stdout.writeln('스모크 정책 생성: $path (방문 상태 ${t.visitedCount}개)');
}

// ── Firestore REST 클라이언트 ────────────────────────────

class FirestoreRest {
  FirestoreRest({required this.project, required this.apiKey, this.dryRun = false});

  final String project;
  final String apiKey;
  final bool dryRun;
  final http.Client _client = http.Client();

  String get _base => 'https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents';

  Uri _uri(String path, [Map<String, String>? extra]) =>
      Uri.parse('$_base/$path').replace(queryParameters: {if (apiKey.isNotEmpty) 'key': apiKey, ...?extra});

  void close() => _client.close();

  /// PATCH(생성 또는 전체 덮어쓰기). [fields]는 Dart 값 → Firestore Value 로 인코딩.
  Future<void> patchDocument(String path, Map<String, dynamic> fields) async {
    final body = jsonEncode({'fields': {for (final e in fields.entries) e.key: _encodeValue(e.value)}});
    if (dryRun) {
      stdout.writeln('  [dry-run] PATCH $path (${_kb(utf8.encode(body).length)})');
      return;
    }
    await _retry('PATCH $path', () async {
      final r = await _client.patch(_uri(path), headers: _json, body: body);
      _check(r, 'PATCH $path');
    });
  }

  /// GET. 404면 null.
  Future<Map<String, dynamic>?> getDocument(String path) async {
    if (dryRun) return null;
    return _retry('GET $path', () async {
      final r = await _client.get(_uri(path));
      if (r.statusCode == 404) return null;
      _check(r, 'GET $path');
      return jsonDecode(r.body) as Map<String, dynamic>;
    });
  }

  Future<void> deleteDocument(String path) async {
    if (dryRun) {
      stdout.writeln('  [dry-run] DELETE $path');
      return;
    }
    await _retry('DELETE $path', () async {
      final r = await _client.delete(_uri(path));
      if (r.statusCode == 404) return;
      _check(r, 'DELETE $path');
    });
  }

  /// 컬렉션의 문서 id 목록 (필드 없이 이름만, 페이지네이션 처리).
  Future<List<String>> listDocumentIds(String collectionPath) async {
    if (dryRun) return const [];
    final ids = <String>[];
    String? token;
    do {
      final page = await _retry('LIST $collectionPath', () async {
        final r = await _client.get(_uri(collectionPath, {
          'pageSize': '300',
          'mask.fieldPaths': 'index',
          if (token != null) 'pageToken': token,
        }));
        _check(r, 'LIST $collectionPath');
        return jsonDecode(r.body) as Map<String, dynamic>;
      });
      final docs = page['documents'];
      if (docs is List) {
        for (final d in docs) {
          final name = (d as Map)['name'] as String;
          ids.add(name.substring(name.lastIndexOf('/') + 1));
        }
      }
      token = page['nextPageToken'] as String?;
    } while (token != null);
    ids.sort();
    return ids;
  }

  static const _json = {'Content-Type': 'application/json'};

  Future<T> _retry<T>(String what, Future<T> Function() fn) async {
    Object? last;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await fn().timeout(const Duration(seconds: 60));
      } catch (e) {
        last = e;
        if (attempt < maxRetries) {
          final wait = Duration(seconds: 1 << (attempt - 1));
          stderr.writeln('  $what 실패 ($attempt/$maxRetries): ${_scrub(e.toString())} → ${wait.inSeconds}s 후 재시도');
          await Future<void>.delayed(wait);
        }
      }
    }
    throw StateError('$what: $maxRetries회 실패 — ${_scrub(last.toString())}');
  }

  void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw HttpException('$what → HTTP ${r.statusCode}: ${_scrub(r.body.length > 400 ? r.body.substring(0, 400) : r.body)}');
  }

  /// 오류 메시지에 API 키가 섞여 나가지 않게 제거.
  String _scrub(String s) => apiKey.isEmpty ? s : s.replaceAll(apiKey, '<api-key>');
}

// ── Firestore Value 인코딩/디코딩 ───────────────────────

Map<String, dynamic> _encodeValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v.isFinite ? v : 0.0};
  if (v is String) return {'stringValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is List) return {'arrayValue': {'values': v.map(_encodeValue).toList()}};
  if (v is Map) {
    return {'mapValue': {'fields': {for (final e in v.entries) e.key.toString(): _encodeValue(e.value)}}};
  }
  return {'stringValue': v.toString()};
}

Object? _decodeValue(Object? v) {
  if (v is! Map) return null;
  if (v.containsKey('integerValue')) return int.tryParse(v['integerValue'].toString());
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('timestampValue')) return v['timestampValue'];
  return null;
}

// ── 유틸 ────────────────────────────────────────────────

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
double? _dbl(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
num _round(double v, int d) => double.parse(v.toStringAsFixed(d));
String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';
String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';

String _defaultVersion() {
  final n = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}';
}

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq > 0) {
      out[a.substring(2, eq)] = a.substring(eq + 1);
    } else if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      out[a.substring(2)] = argv[++i];
    } else {
      out[a.substring(2)] = '';
    }
  }
  return out;
}

Never _die(String msg) {
  stderr.writeln('오류: $msg\n');
  stderr.writeln(_usage);
  exit(2);
}

const String _usage = '''
dart run bin/upload_policy.dart --project <projectId> --api-key <apiKey> [--out out/]
  --stages 1,2,3       업로드할 단계 (기본 1,2,3)
  --collection NAME    대상 컬렉션 (기본 policies)
  --version STR        메타 version 문자열 (기본 현재 시각)
  --no-curves          curves/run1 생략
  --dry-run            네트워크 없이 검증만
  --delete             해당 단계 문서 + chunks 삭제
  --make-smoke DIR     테스트용 가짜 정책 생성 (DIR/policy_stage1.json)
''';
