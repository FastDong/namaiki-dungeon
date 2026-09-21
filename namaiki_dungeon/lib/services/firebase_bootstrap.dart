import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// [FirebaseBootstrap.init] 결과. 실패해도 앱은 계속 진행한다 (에셋 정책·리더보드 비활성).
class FirebaseBootstrapResult {
  /// `Firebase.initializeApp` 성공 여부. false면 Firestore/Auth 전부 사용 불가.
  final bool ok;

  /// 익명 로그인 uid. null이면 로그인 실패(리더보드 기록은 생략된다).
  final String? uid;

  /// 실패 원인(초기화 또는 로그인). 둘 다 성공이면 null.
  final String? error;

  /// 걸린 시간(ms). 로그/디버그용.
  final int elapsedMs;

  const FirebaseBootstrapResult({
    required this.ok,
    this.uid,
    this.error,
    this.elapsedMs = 0,
  });

  bool get signedIn => uid != null;

  @override
  String toString() => 'FirebaseBootstrapResult(ok=$ok, uid=${uid ?? '-'}, error=${error ?? '-'}, ${elapsedMs}ms)';
}

/// Firebase 초기화 + 익명 로그인. 각각 try/catch, 전체 [timeout] (기본 5초).
///
/// - `initializeApp(options: DefaultFirebaseOptions.currentPlatform)` (이미 초기화돼 있으면 재사용)
/// - `signInAnonymously()` (이미 로그인돼 있으면 그 uid 재사용)
/// - 어느 단계가 실패/타임아웃이어도 예외를 밖으로 던지지 않는다.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static FirebaseBootstrapResult? _last;

  /// 마지막 init 결과 (init 전이면 null).
  static FirebaseBootstrapResult? get last => _last;

  /// Firebase 앱이 초기화되어 있는가 (Firestore/Auth 호출 가능 여부).
  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<FirebaseBootstrapResult> init({
    Duration timeout = const Duration(seconds: 5),
    void Function(String msg)? log,
  }) async {
    final out = log ?? debugPrint;
    final sw = Stopwatch()..start();

    // onTimeout 클로저가 중간 진행 상태를 읽을 수 있게 지역 변수로 추적한다.
    var initOk = false;
    String? uid;
    String? error;

    Future<void> run() async {
      // 1) initializeApp
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        }
        initOk = true;
      } catch (e) {
        error = 'initializeApp 실패: $e';
        out('[firebase] $error');
        return;
      }
      // 2) signInAnonymously
      try {
        final auth = FirebaseAuth.instance;
        final existing = auth.currentUser;
        if (existing != null) {
          uid = existing.uid;
        } else {
          final cred = await auth.signInAnonymously();
          uid = cred.user?.uid;
        }
        if (uid == null) error = 'signInAnonymously: user가 null';
      } catch (e) {
        error = 'signInAnonymously 실패: $e';
        out('[firebase] $error');
      }
    }

    try {
      await run().timeout(timeout);
    } on TimeoutException {
      error ??= 'Firebase 초기화 ${timeout.inSeconds}초 타임아웃';
      out('[firebase] $error (init=$initOk, uid=${uid ?? '-'})');
    } catch (e) {
      error ??= '예상치 못한 오류: $e';
      out('[firebase] $error');
    }

    sw.stop();
    final result = FirebaseBootstrapResult(
      ok: initOk,
      uid: uid,
      error: error,
      elapsedMs: sw.elapsedMilliseconds,
    );
    _last = result;
    out('[firebase] bootstrap $result');
    return result;
  }
}
