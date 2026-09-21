// 템플릿. 실제 값은 Firebase 콘솔에서 복사해 firebase_options.dart(깃 제외)로 저장한다.
// Firebase 콘솔에서 복사한 설정값 (flutterfire CLI 없이 수기 작성).
// 웹 설정값은 공개 값이며, Firestore 보안 규칙이 실제 접근을 통제한다.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        // iOS/데스크톱은 이 과제 범위 밖. 웹 설정으로 폴백.
        return web;
    }
  }

  static const String projectId = '<YOUR_PROJECT_ID>';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '<YOUR_WEB_API_KEY>',
    authDomain: '<YOUR_PROJECT_ID>.firebaseapp.com',
    projectId: projectId,
    storageBucket: '<YOUR_PROJECT_ID>.firebasestorage.app',
    messagingSenderId: '<YOUR_SENDER_ID>',
    appId: '1:<YOUR_SENDER_ID>:web:c180797dcb8e9d7fe437a1',
  );

  // TODO(android): 콘솔에서 Android 앱(패키지 com.namaiki.namaiki_dungeon) 등록 후
  // google-services.json의 current_key / mobilesdk_app_id 로 교체. 그 전까지는 웹 값으로 동작.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '<YOUR_WEB_API_KEY>',
    projectId: projectId,
    storageBucket: '<YOUR_PROJECT_ID>.firebasestorage.app',
    messagingSenderId: '<YOUR_SENDER_ID>',
    appId: '1:<YOUR_SENDER_ID>:web:c180797dcb8e9d7fe437a1',
  );
}
