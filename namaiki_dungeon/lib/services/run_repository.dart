import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dungeon_core/dungeon_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_bootstrap.dart';

/// 리더보드 기록 데이터 클래스. Firestore 접근은 아래 [RunRepository].
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

  /// 서버 기록 시각 (읽기 전용; 저장 시엔 serverTimestamp가 들어간다). 로컬 생성 기록은 null.
  final DateTime? createdAt;

  const RunRecord({
    required this.uid,
    required this.nickname,
    required this.wavesCleared,
    required this.stageReached,
    required this.heroDeaths,
    required this.durationSec,
    required this.layoutSnapshot,
    this.createdAt,
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
        createdAt: m['createdAt'] is DateTime ? m['createdAt'] as DateTime : null,
      );

  RunRecord copyWith({String? uid, String? nickname, DateTime? createdAt}) => RunRecord(
        uid: uid ?? this.uid,
        nickname: nickname ?? this.nickname,
        wavesCleared: wavesCleared,
        stageReached: stageReached,
        heroDeaths: heroDeaths,
        durationSec: durationSec,
        layoutSnapshot: layoutSnapshot,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  String toString() =>
      'RunRecord($nickname waves=$wavesCleared stage=$stageReached deaths=$heroDeaths ${durationSec}s)';
}

/// `runs` 컬렉션 접근 (PLAN.md §6).
///
/// - [add]: uid는 `FirebaseAuth.currentUser?.uid`. 로그인돼 있지 않으면 저장을 생략한다(예외 없음).
///   최종 보안 규칙(create: uid 일치, wavesCleared 0..15 int, stageReached ∈ {1,2,3}, nickname ≤ 12자)에 맞게
///   값을 정리한 뒤 `createdAt: serverTimestamp`, `appVersion`을 붙여 저장한다.
/// - [top20]: `orderBy wavesCleared desc, createdAt desc limit 20`. 복합 색인이 없어(failed-precondition)
///   실패하면 콘솔에 색인 생성 링크를 남기고 `wavesCleared desc` 단일 정렬로 폴백한다.
class RunRepository {
  RunRepository({
    this.firestore,
    this.auth,
    this.appVersion = defaultAppVersion,
    this.collection = 'runs',
    void Function(String msg)? log,
  })  : _log = log ?? debugPrint;

  static const String defaultAppVersion = '1.0.0+1';
  static const String defaultNickname = '마왕';
  static const int nicknameMaxLength = 12;
  static const int topLimit = 20;

  /// 테스트 주입용. null이면 Firebase 초기화 후 `FirebaseFirestore.instance` / `FirebaseAuth.instance`.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final String appVersion;
  final String collection;
  final void Function(String msg) _log;

  /// 마지막 top20에서 복합 색인 없음(failed-precondition)이 발생했을 때의 오류 메시지 (색인 생성 링크 포함).
  String? lastIndexHint;

  /// 마지막 top20이 단일 정렬 폴백으로 조회됐는가.
  bool lastUsedFallbackQuery = false;

  /// 마지막 add 결과 (문서 id 또는 생략/실패 사유). 디버그·스낵바용.
  String? lastAddStatus;

  FirebaseFirestore get _db {
    final f = firestore;
    if (f != null) return f;
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase가 초기화되지 않았습니다 (오프라인)');
    }
    return FirebaseFirestore.instance;
  }

  String? get currentUid {
    try {
      final a = auth;
      if (a != null) return a.currentUser?.uid;
      if (!FirebaseBootstrap.isReady) return null;
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// 규칙에 맞게 닉네임 정리 (공백 제거, 비면 기본값, 12자 절단).
  static String sanitizeNickname(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return defaultNickname;
    return t.runes.length <= nicknameMaxLength ? t : String.fromCharCodes(t.runes.take(nicknameMaxLength));
  }

  /// 기록 저장. 로그인 uid가 없으면 생략(false). 성공 true. 예외는 삼키고 로그로 남긴다.
  Future<bool> add(RunRecord r) async {
    final uid = currentUid;
    if (uid == null) {
      lastAddStatus = 'skipped: no uid (익명 로그인 실패/오프라인)';
      _log('[runs] add skipped: no uid');
      return false;
    }
    try {
      final stageCount = Balance.totalWaves ~/ Balance.wavesPerStage;
      final data = <String, dynamic>{
        ...r.toMap(),
        'uid': uid,
        'nickname': sanitizeNickname(r.nickname),
        'wavesCleared': r.wavesCleared.clamp(0, Balance.totalWaves),
        'stageReached': r.stageReached.clamp(1, stageCount),
        'heroDeaths': r.heroDeaths < 0 ? 0 : r.heroDeaths,
        'durationSec': r.durationSec < 0 ? 0 : r.durationSec,
        'appVersion': appVersion,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final ref = await _db.collection(collection).add(data);
      lastAddStatus = 'ok: ${ref.id}';
      _log('[runs] added ${ref.id} (waves=${data['wavesCleared']}, stage=${data['stageReached']}, uid=$uid)');
      return true;
    } catch (e) {
      lastAddStatus = 'failed: $e';
      _log('[runs] add failed: $e');
      return false;
    }
  }

  /// 상위 20 기록. Firestore 사용 불가/조회 실패면 예외를 던진다 (화면이 오류 상태를 보여준다).
  Future<List<RunRecord>> top20() async {
    final db = _db;
    lastUsedFallbackQuery = false;
    final base = db.collection(collection);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await base
          .orderBy('wavesCleared', descending: true)
          .orderBy('createdAt', descending: true)
          .limit(topLimit)
          .get();
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      // 복합 색인 없음. 메시지에 콘솔 색인 생성 링크가 들어 있다.
      lastIndexHint = e.message ?? e.toString();
      _log('[runs] composite index missing → fallback to single orderBy. ${e.message}');
      lastUsedFallbackQuery = true;
      snap = await base.orderBy('wavesCleared', descending: true).limit(topLimit).get();
    }
    final out = <RunRecord>[];
    for (final d in snap.docs) {
      final m = Map<String, dynamic>.from(d.data());
      final ts = m['createdAt'];
      if (ts is Timestamp) m['createdAt'] = ts.toDate();
      out.add(RunRecord.fromMap(m));
    }
    if (lastUsedFallbackQuery) {
      // 폴백 정렬은 동률 순서를 보장하지 않으므로 클라이언트에서 createdAt desc로 2차 정렬.
      out.sort((a, b) {
        final w = b.wavesCleared.compareTo(a.wavesCleared);
        if (w != 0) return w;
        final at = a.createdAt, bt = b.createdAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
    }
    return out;
  }
}
