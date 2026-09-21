import 'dart:convert';

import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'policy_repository.dart' show PolicySource;

/// 정책 파일의 meta 블록. 없는 값은 null.
class PolicyMeta {
  const PolicyMeta({
    required this.stage,
    this.name,
    this.episodes,
    this.winRate,
    this.avgSteps,
    this.trapHits,
    this.potionsUsed,
    this.kills,
  });

  final int stage;
  final String? name;
  final int? episodes;
  final double? winRate;
  final double? avgSteps;
  final double? trapHits;
  final double? potionsUsed;
  final double? kills;

  /// {"stage":1,"name":"...","episodes":N,"winRate":0.1,...} 또는 eval 통계가 "eval" 아래에 있는 형태도 허용.
  factory PolicyMeta.fromJson(Map<String, dynamic> j, {required int fallbackStage}) {
    final eval = j['eval'] is Map ? Map<String, dynamic>.from(j['eval'] as Map) : const <String, dynamic>{};
    num? pick(String k) => (j[k] ?? eval[k]) as num?;
    return PolicyMeta(
      stage: (j['stage'] as num?)?.toInt() ?? fallbackStage,
      name: j['name'] as String?,
      episodes: ((j['episodes'] ?? j['episode']) as num?)?.toInt(),
      winRate: pick('winRate')?.toDouble(),
      avgSteps: pick('avgSteps')?.toDouble(),
      trapHits: pick('trapHits')?.toDouble(),
      potionsUsed: pick('potionsUsed')?.toDouble(),
      kills: pick('kills')?.toDouble(),
    );
  }

  /// PolicySource.meta / Firestore 문서와 같은 키 이름.
  Map<String, dynamic> toJson() => {
        'stage': stage,
        if (name != null) 'name': name,
        if (episodes != null) 'episodes': episodes,
        if (winRate != null) 'winRate': winRate,
        if (avgSteps != null) 'avgSteps': avgSteps,
        if (trapHits != null) 'trapHits': trapHits,
        if (potionsUsed != null) 'potionsUsed': potionsUsed,
        if (kills != null) 'kills': kills,
      };

  @override
  String toString() => 'PolicyMeta(stage=$stage ep=$episodes win=$winRate)';
}

/// 에셋에서 읽은 정책 + 메타.
class LoadedPolicies {
  const LoadedPolicies(this.policies, this.meta);

  final Map<int, HeroPolicy> policies;

  /// 메타가 없는(폴백) 단계는 키가 없다.
  final Map<int, PolicyMeta> meta;
}

/// 에셋 경로. assets/policies/policy_stage{1,2,3}.json
String policyAssetPath(int stage) => 'assets/policies/policy_stage$stage.json';

int get _stageCount => Balance.totalWaves ~/ Balance.wavesPerStage;

/// 에셋에서 단계별 정책을 읽는다. 파일이 없거나 파싱 실패한 단계는 [GreedyPolicy] 로 폴백(메타 없음).
///
/// 형식: {"meta":{...},"q":{"v":1,"n":5,"q":{"idx":[5 numbers]}}} — q 부분은 QTable.fromSparseJson 으로 복원.
/// [load] 는 테스트 주입용 (기본 rootBundle.loadString).
Future<LoadedPolicies> loadAssetPoliciesWithMeta({Future<String> Function(String path)? load}) async {
  final loader = load ?? rootBundle.loadString;
  final policies = <int, HeroPolicy>{};
  final metas = <int, PolicyMeta>{};
  for (var s = 1; s <= _stageCount; s++) {
    final parsed = await _loadOne(s, loader);
    if (parsed == null) {
      policies[s] = const GreedyPolicy();
      continue;
    }
    policies[s] = parsed.$1;
    if (parsed.$2 != null) metas[s] = parsed.$2!;
  }
  return LoadedPolicies(policies, metas);
}

/// 순수 함수: 단계 → 정책 (폴백 포함). 메타가 필요하면 [loadAssetPoliciesWithMeta].
Future<Map<int, HeroPolicy>> loadAssetPolicies() async => (await loadAssetPoliciesWithMeta()).policies;

/// 단계 → 메타 (파일이 없거나 깨진 단계는 키 없음).
Future<Map<int, PolicyMeta>> loadAssetPolicyMeta() async => (await loadAssetPoliciesWithMeta()).meta;

/// M7 `PolicyRepository(assetLoader: …)` 에 그대로 꽂는 어댑터 (`AssetPolicyLoader` 시그니처).
/// 폴백 단계는 GreedyPolicy + {'stage': s, 'source': 'greedy'}, 학습 단계는 {'source': 'assets', 'stateCount': N, ...meta}.
Future<Map<int, PolicySource>> loadAssetPolicySources({Future<String> Function(String path)? load}) async {
  final r = await loadAssetPoliciesWithMeta(load: load);
  return {
    for (final e in r.policies.entries)
      e.key: PolicySource(
        policy: e.value,
        meta: e.value is QTablePolicy
            ? {
                'stage': e.key,
                'source': 'assets',
                'stateCount': (e.value as QTablePolicy).table.visitedCount,
                ...?r.meta[e.key]?.toJson(),
              }
            : {'stage': e.key, 'source': 'greedy'},
      ),
  };
}

/// 정책 JSON 문자열 하나를 파싱. 실패하면 null.
(HeroPolicy, PolicyMeta?)? parsePolicyJson(String text, {required int stage}) {
  try {
    final root = jsonDecode(text);
    if (root is! Map) return null;
    final j = Map<String, dynamic>.from(root);
    final q = j['q'];
    if (q == null) return null;
    final table = QTable.fromSparseJson(q is String ? q : jsonEncode(q));
    PolicyMeta? meta;
    final m = j['meta'];
    if (m is Map) {
      meta = PolicyMeta.fromJson(Map<String, dynamic>.from(m), fallbackStage: stage);
    }
    return (QTablePolicy(table, name: meta?.name ?? 'qtable_stage$stage'), meta);
  } catch (e) {
    debugPrint('policy stage$stage parse failed: $e');
    return null;
  }
}

Future<(HeroPolicy, PolicyMeta?)?> _loadOne(int stage, Future<String> Function(String) loader) async {
  final path = policyAssetPath(stage);
  String text;
  try {
    text = await loader(path);
  } catch (e) {
    debugPrint('policy stage$stage asset missing ($path) → greedy fallback');
    return null;
  }
  final r = parsePolicyJson(text, stage: stage);
  if (r == null) {
    debugPrint('policy stage$stage invalid → greedy fallback');
  } else {
    debugPrint('policy stage$stage loaded from asset (${(r.$1 as QTablePolicy).table.visitedCount} states)');
  }
  return r;
}
