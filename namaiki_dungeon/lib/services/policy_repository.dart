import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'firebase_bootstrap.dart';

/// 단계별 용사 정책 + 출처 메타 (PLAN.md §11 앱 인터페이스).
///
/// [meta]는 Firestore `policies/{stageId}` 문서 필드(또는 에셋 파일의 메타)를 그대로 담는다:
/// stage, name, algorithm, featureSpecVersion, episodes, winRate, avgSteps, trapHits, potionsUsed, kills,
/// stateCount, chunkCount, version, createdAt. 없는 키는 null.
class PolicySource {
  final HeroPolicy policy;
  final Map<String, dynamic> meta;
  final bool fromFirestore;

  const PolicySource({
    required this.policy,
    required this.meta,
    this.fromFirestore = false,
  });

  /// 출처 라벨: 'firestore' | 'assets' | 'greedy' (meta['source']가 있으면 그것).
  String get source => (meta['source'] as String?) ?? (fromFirestore ? 'firestore' : (policy is QTablePolicy ? 'assets' : 'greedy'));

  bool get isLearned => policy is QTablePolicy;

  int? get stage => (meta['stage'] as num?)?.toInt();
  String? get name => meta['name'] as String?;
  int? get episodes => (meta['episodes'] as num?)?.toInt();
  double? get winRate => (meta['winRate'] as num?)?.toDouble();
  double? get avgSteps => (meta['avgSteps'] as num?)?.toDouble();
  double? get trapHits => (meta['trapHits'] as num?)?.toDouble();
  double? get potionsUsed => (meta['potionsUsed'] as num?)?.toDouble();
  double? get kills => (meta['kills'] as num?)?.toDouble();
  int? get stateCount => (meta['stateCount'] as num?)?.toInt();
  String? get version => meta['version'] as String?;

  PolicySource copyWith({Map<String, dynamic>? meta}) =>
      PolicySource(policy: policy, meta: meta ?? this.meta, fromFirestore: fromFirestore);

  @override
  String toString() => 'PolicySource(stage=$stage, source=$source, states=$stateCount, winRate=$winRate)';
}

/// 에셋 정책 로더 시그니처 (M6 `policy_loader.dart`의 `loadAssetPolicies()`).
typedef AssetPolicyLoader = Future<Map<int, PolicySource>> Function();

/// 정책 로딩: Firestore 우선 → 에셋 폴백 → GreedyPolicy 폴백.
///
/// Firestore `policies/stageN` 문서 + `chunks` 서브컬렉션 전부를 읽어 [QTable.fromChunks] →
/// [QTablePolicy] (ε = [Balance.epsPlay]). `featureSpecVersion != Balance.featureSpecVersion`,
/// 타임아웃, 청크 수 불일치, 파싱 실패면 그 단계는 에셋으로 폴백한다.
class PolicyRepository {
  PolicyRepository({
    this.firestore,
    this.assetLoader,
    this.collection = 'policies',
    int? stageCount,
    void Function(String msg)? log,
  })  : stageCount = stageCount ?? (Balance.totalWaves ~/ Balance.wavesPerStage),
        _log = log ?? debugPrint;

  /// 테스트 주입용. null이면 Firebase 초기화 후 `FirebaseFirestore.instance`.
  final FirebaseFirestore? firestore;
  final AssetPolicyLoader? assetLoader;
  final String collection;
  final int stageCount;
  final void Function(String msg) _log;

  /// 마지막 loadAll에서 단계별로 남긴 진단 메시지 (UI/보고용).
  final Map<int, String> diagnostics = {};

  FirebaseFirestore? get _db {
    if (firestore != null) return firestore;
    if (!FirebaseBootstrap.isReady) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// 단계 1..stageCount 전부 로드. 어떤 경우에도 모든 단계에 정책이 들어간 Map을 돌려준다.
  Future<Map<int, PolicySource>> loadAll({Duration timeout = const Duration(seconds: 5)}) async {
    diagnostics.clear();
    final result = <int, PolicySource>{};
    final stages = [for (var s = 1; s <= stageCount; s++) s];

    // 1) Firestore (단계별 병렬, 각각 timeout)
    final db = _db;
    if (db == null) {
      _log('[policy] firestore unavailable (firebase not initialized) → fallback');
    } else {
      final fetched = await Future.wait(
        stages.map((s) => _loadStageFromFirestore(db, s, timeout)),
      );
      for (var i = 0; i < stages.length; i++) {
        final src = fetched[i];
        if (src != null) result[stages[i]] = src;
      }
    }

    // 2) 에셋 폴백 (빠진 단계만)
    final missing = stages.where((s) => !result.containsKey(s)).toList();
    if (missing.isNotEmpty && assetLoader != null) {
      try {
        final assets = await assetLoader!().timeout(timeout);
        for (final s in missing) {
          final a = assets[s];
          if (a == null) continue;
          final meta = Map<String, dynamic>.from(a.meta)..putIfAbsent('source', () => 'assets')..putIfAbsent('stage', () => s);
          result[s] = PolicySource(policy: a.policy, meta: meta, fromFirestore: false);
          _log('policy stage$s loaded from assets (${a.stateCount ?? '?'} states)');
        }
      } catch (e) {
        _log('[policy] asset loader failed: $e');
        for (final s in missing) {
          diagnostics[s] = '${diagnostics[s] ?? ''}; assets: $e';
        }
      }
    }

    // 3) Greedy 폴백
    for (final s in stages) {
      if (result.containsKey(s)) continue;
      result[s] = PolicySource(
        policy: const GreedyPolicy(),
        meta: <String, dynamic>{
          'stage': s,
          'name': 'greedy 대역',
          'algorithm': 'greedy_stub',
          'source': 'greedy',
          'featureSpecVersion': Balance.featureSpecVersion,
        },
        fromFirestore: false,
      );
      _log('policy stage$s greedy fallback${diagnostics[s] != null ? ' (${diagnostics[s]})' : ''}');
    }
    return result;
  }

  /// Firestore에서 단계 하나 로드. 실패/타임아웃/버전 불일치면 null (사유는 [diagnostics]).
  Future<PolicySource?> _loadStageFromFirestore(FirebaseFirestore db, int stage, Duration timeout) async {
    final stageId = 'stage$stage';
    try {
      return await _fetchStage(db, stageId, stage).timeout(timeout);
    } on TimeoutException {
      diagnostics[stage] = 'firestore timeout ${timeout.inSeconds}s';
      _log('[policy] $stageId firestore timeout (${timeout.inSeconds}s)');
    } on FormatException catch (e) {
      diagnostics[stage] = 'firestore parse: ${e.message}';
      _log('[policy] $stageId chunk parse failed: ${e.message}');
    } catch (e) {
      diagnostics[stage] = 'firestore: $e';
      _log('[policy] $stageId firestore failed: $e');
    }
    return null;
  }

  Future<PolicySource?> _fetchStage(FirebaseFirestore db, String stageId, int stage) async {
    final docRef = db.collection(collection).doc(stageId);
    final doc = await docRef.get();
    if (!doc.exists) {
      diagnostics[stage] = 'firestore: $collection/$stageId 없음';
      _log('[policy] $stageId not in firestore');
      return null;
    }
    final meta = _normalizeMeta(doc.data() ?? const {});
    final fsv = (meta['featureSpecVersion'] as num?)?.toInt();
    if (fsv != Balance.featureSpecVersion) {
      diagnostics[stage] = 'featureSpecVersion $fsv != ${Balance.featureSpecVersion}';
      _log('[policy] $stageId featureSpecVersion mismatch ($fsv != ${Balance.featureSpecVersion}) → fallback');
      return null;
    }

    final snap = await docRef.collection('chunks').orderBy(FieldPath.documentId).get();
    final chunks = <String>[];
    for (final d in snap.docs) {
      final data = d.data()['data'];
      if (data is String && data.isNotEmpty) chunks.add(data);
    }
    final expected = (meta['chunkCount'] as num?)?.toInt();
    if (chunks.isEmpty || (expected != null && expected != chunks.length)) {
      diagnostics[stage] = 'chunks ${chunks.length}/${expected ?? '?'}';
      _log('[policy] $stageId chunk count mismatch (${chunks.length}/${expected ?? '?'}) → fallback');
      return null;
    }

    // 큰 JSON 파싱 전에 한 프레임 양보 (스플래시 애니메이션이 멈추지 않게).
    await Future<void>.delayed(Duration.zero);
    final table = QTable.fromChunks(chunks);
    if (table.visitedCount == 0) {
      diagnostics[stage] = 'empty table';
      _log('[policy] $stageId table empty → fallback');
      return null;
    }
    meta['source'] = 'firestore';
    meta.putIfAbsent('stage', () => stage);
    meta['stateCount'] = table.visitedCount;
    final policy = QTablePolicy(table, epsilon: Balance.epsPlay, name: (meta['name'] as String?) ?? stageId);
    _log('policy $stageId loaded from firestore (${table.visitedCount} states)');
    return PolicySource(policy: policy, meta: meta, fromFirestore: true);
  }

  /// Firestore 타입(Timestamp 등)을 순수 Dart 값으로 바꾼 메타 사본.
  static Map<String, dynamic> _normalizeMeta(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (v is Timestamp) {
        out[k] = v.toDate().toIso8601String();
      } else {
        out[k] = v;
      }
    });
    return out;
  }
}

/// 로드된 정책·메타를 UI(진화 배너, admin 시트, 메뉴)에 전달하는 단순 저장소.
/// main.dart가 `Provider<PolicyMetaStore>`로 트리 상단에 넣는다. `PolicyMetaStore.maybeOf(context)`로 읽는다.
class PolicyMetaStore {
  PolicyMetaStore(this.sources, {this.bootstrap});

  final Map<int, PolicySource> sources;

  /// Firebase 초기화 결과 (없으면 null).
  final FirebaseBootstrapResult? bootstrap;

  /// GameController에 주입할 단계 → 정책.
  Map<int, HeroPolicy> get policies => {for (final e in sources.entries) e.key: e.value.policy};

  PolicySource? operator [](int stage) => sources[stage];

  Map<String, dynamic>? metaFor(int stage) => sources[stage]?.meta;
  double? winRate(int stage) => sources[stage]?.winRate;
  int? episodes(int stage) => sources[stage]?.episodes;
  int? stateCount(int stage) => sources[stage]?.stateCount;
  String? nameOf(int stage) => sources[stage]?.name;

  /// 'firestore' | 'assets' | 'greedy' | null
  String? sourceOf(int stage) => sources[stage]?.source;

  bool get anyFromFirestore => sources.values.any((s) => s.fromFirestore);
  bool get anyLearned => sources.values.any((s) => s.isLearned);
  bool get allGreedy => sources.values.every((s) => !s.isLearned);

  /// 한 줄 요약 (메뉴 하단 표시용). 예: "정책: Firestore 3/3 · uid ok"
  String get summary {
    final fs = sources.values.where((s) => s.fromFirestore).length;
    final assets = sources.values.where((s) => !s.fromFirestore && s.isLearned).length;
    final greedy = sources.values.where((s) => !s.isLearned).length;
    final parts = <String>[];
    if (fs > 0) parts.add('Firestore $fs');
    if (assets > 0) parts.add('에셋 $assets');
    if (greedy > 0) parts.add('대역 $greedy');
    final auth = bootstrap == null
        ? ''
        : bootstrap!.signedIn
            ? ' · 익명 로그인 ✓'
            : ' · 오프라인';
    return '용사 정책: ${parts.join(' / ')}$auth';
  }

  /// Provider에서 읽기 (없으면 null; 테스트·미주입 상황 안전).
  static PolicyMetaStore? maybeOf(BuildContext context) {
    try {
      return Provider.of<PolicyMetaStore>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
