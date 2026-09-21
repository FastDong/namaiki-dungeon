import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game/game_controller.dart';
import 'services/firebase_bootstrap.dart';
import 'services/policy_loader.dart';
import 'services/policy_repository.dart';
import 'services/run_repository.dart';
import 'ui/menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NamaikiBoot());
}

/// M6 `policy_loader.dart`의 에셋 로더를 PolicyRepository 폴백으로 연결한다 (Firestore 실패/버전 불일치 시).
/// 에셋에 없어 GreedyPolicy로 폴백된 단계는 여기서 빼고, PolicyRepository가 'greedy fallback'으로 로그를 남긴다.
AssetPolicyLoader get assetPolicyLoader => () async {
      final loaded = await loadAssetPoliciesWithMeta();
      final out = <int, PolicySource>{};
      for (final e in loaded.policies.entries) {
        final p = e.value;
        if (p is! QTablePolicy) continue;
        final m = loaded.meta[e.key];
        out[e.key] = PolicySource(
          policy: p,
          meta: <String, dynamic>{
            'stage': m?.stage ?? e.key,
            'name': m?.name ?? p.name,
            'algorithm': 'tabular_q_learning',
            'featureSpecVersion': Balance.featureSpecVersion,
            'episodes': m?.episodes,
            'winRate': m?.winRate,
            'avgSteps': m?.avgSteps,
            'trapHits': m?.trapHits,
            'potionsUsed': m?.potionsUsed,
            'kills': m?.kills,
            'stateCount': p.table.visitedCount,
            'source': 'assets',
          },
        );
      }
      return out;
    };

/// 부팅 시퀀스: Firebase 초기화(실패해도 계속) → 정책 로드(Firestore → 에셋 → greedy) → [NamaikiApp].
/// 로딩 중엔 스플래시("용사의 기억을 불러오는 중…").
class NamaikiBoot extends StatefulWidget {
  const NamaikiBoot({super.key});

  @override
  State<NamaikiBoot> createState() => _NamaikiBootState();
}

class _BootResult {
  const _BootResult(this.store, this.runs);
  final PolicyMetaStore store;
  final RunRepository runs;
}

class _NamaikiBootState extends State<NamaikiBoot> {
  late final Future<_BootResult> _future = _boot();

  Future<_BootResult> _boot() async {
    final boot = await FirebaseBootstrap.init();
    final repo = PolicyRepository(assetLoader: assetPolicyLoader);
    Map<int, PolicySource> sources;
    try {
      sources = await repo.loadAll();
    } catch (e) {
      // loadAll은 내부에서 전부 폴백하지만, 만약을 위해 마지막 방어선.
      debugPrint('[boot] loadAll failed: $e → greedy');
      final stageCount = Balance.totalWaves ~/ Balance.wavesPerStage;
      sources = {
        for (var s = 1; s <= stageCount; s++)
          s: PolicySource(policy: const GreedyPolicy(), meta: {'stage': s, 'source': 'greedy'}),
      };
    }
    final store = PolicyMetaStore(sources, bootstrap: boot);
    debugPrint('[boot] ${store.summary}');
    return _BootResult(store, RunRepository());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootResult>(
      future: _future,
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return const SplashScreen();
        return NamaikiApp(
          policies: r.store.policies,
          metaStore: r.store,
          runRepository: r.runs,
        );
      },
    );
  }
}

/// 로딩 스플래시. 다크 테마(배경 #120F1A, 강조 #A879FF, 텍스트 #EFE6D3).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message = '용사의 기억을 불러오는 중…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF120F1A);
    const accent = Color(0xFFA879FF);
    const text = Color(0xFFEFE6D3);
    return MaterialApp(
      title: '마왕의 던전',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: bg),
      home: Scaffold(
        key: const ValueKey('splash_screen'),
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👑', style: TextStyle(fontSize: 56, height: 1)),
              const SizedBox(height: 14),
              const Text('마왕의 던전',
                  style: TextStyle(color: text, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 22),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: accent, strokeWidth: 3),
              ),
              const SizedBox(height: 14),
              Text(message, style: const TextStyle(color: text, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱 루트. 다크 테마, 한국어 UI 문자열.
///
/// [policies]는 GameController 주입용(기존 구조 유지). [metaStore]/[runRepository]를 주면 Provider로 UI에 전달하고
/// (M6 evolve_overlay가 `PolicyMetaStore.maybeOf(context)`로 메타를 읽는다), 없으면 policies로부터 만든다.
/// 게임오버/승리 기록은 [RunRecorderObserver]가 PlayScreen 라우트의 GameController phase를 듣고 저장한다.
class NamaikiApp extends StatefulWidget {
  const NamaikiApp({
    super.key,
    required this.policies,
    this.metaStore,
    this.runRepository,
  });

  final Map<int, HeroPolicy> policies;
  final PolicyMetaStore? metaStore;
  final RunRepository? runRepository;

  @override
  State<NamaikiApp> createState() => _NamaikiAppState();
}

class _NamaikiAppState extends State<NamaikiApp> {
  late final PolicyMetaStore _store = widget.metaStore ??
      PolicyMetaStore({
        for (final e in widget.policies.entries)
          e.key: PolicySource(
            policy: e.value,
            meta: {'stage': e.key, 'source': e.value is QTablePolicy ? 'assets' : 'greedy'},
          ),
      });
  late final RunRepository _runs = widget.runRepository ?? RunRepository();
  late final RunRecorderObserver _recorder = RunRecorderObserver(_runs);

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.deepPurple,
      visualDensity: VisualDensity.compact,
    );
    return MultiProvider(
      providers: [
        Provider<PolicyMetaStore>.value(value: _store),
        Provider<RunRepository>.value(value: _runs),
      ],
      child: MaterialApp(
        title: '마왕의 던전',
        debugShowCheckedModeBanner: false,
        theme: dark,
        darkTheme: dark,
        themeMode: ThemeMode.dark,
        navigatorObservers: [_recorder],
        home: MenuScreen(policies: widget.policies),
      ),
    );
  }
}

/// 게임오버/승리 시 `RunRepository.add(controller.buildRun())`을 호출하는 얇은 리스너.
///
/// PlayScreen은 MenuScreen이 `ChangeNotifierProvider` (GameController)로 감싸 push하므로 main.dart에서 직접
/// 그 컨트롤러를 받을 수 없다. 대신 NavigatorObserver로 라우트가 push된 다음 프레임에 라우트 서브트리에서
/// `GameController`를 찾아 listener를 붙이고, pop 시 떼어낸다. 기록은 phase가 gameOver/victory로 **진입**할 때 1회.
class RunRecorderObserver extends NavigatorObserver {
  RunRecorderObserver(this.repository, {this.onRecorded});

  final RunRepository repository;

  /// 기록 시도 후 콜백 (성공 여부, 기록). 스낵바/디버그용.
  final void Function(bool ok, RunRecord run)? onRecorded;

  final Map<Route<dynamic>, _Attachment> _byRoute = {};
  final Set<GameController> _attached = <GameController>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! ModalRoute) return;
    _scheduleAttach(route, retries: 3);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _detach(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _detach(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _detach(oldRoute);
    if (newRoute is ModalRoute) _scheduleAttach(newRoute, retries: 3);
  }

  void _scheduleAttach(ModalRoute<dynamic> route, {required int retries}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_byRoute.containsKey(route) || !route.isActive) return;
      final ctx = route.subtreeContext;
      if (ctx == null || ctx is! Element) {
        if (retries > 0) _scheduleAttach(route, retries: retries - 1);
        return;
      }
      final c = _findController(ctx);
      if (c == null) return; // 플레이 라우트가 아님
      if (_attached.contains(c)) return; // 같은 컨트롤러(예: admin 시트)엔 중복 부착 안 함
      final a = _Attachment(c, c.phase);
      a.listener = () => _onChanged(a);
      c.addListener(a.listener);
      _byRoute[route] = a;
      _attached.add(c);
      debugPrint('[runs] recorder attached (phase=${c.phase.name})');
    });
  }

  void _detach(Route<dynamic> route) {
    final a = _byRoute.remove(route);
    if (a == null) return;
    _attached.remove(a.controller);
    try {
      a.controller.removeListener(a.listener);
    } catch (_) {
      // 이미 dispose된 컨트롤러면 무시.
    }
  }

  void _onChanged(_Attachment a) {
    final c = a.controller;
    final prev = a.lastPhase;
    final now = c.phase;
    a.lastPhase = now;
    if (prev == now) return;
    final terminal = now == Phase.gameOver || now == Phase.victory;
    final wasTerminal = prev == Phase.gameOver || prev == Phase.victory;
    if (!terminal || wasTerminal) return;
    RunRecord run;
    try {
      run = c.buildRun();
    } catch (e) {
      debugPrint('[runs] buildRun failed: $e');
      return;
    }
    // fire-and-forget: 저장 실패해도 화면 흐름엔 영향 없음.
    repository.add(run).then((ok) {
      debugPrint('[runs] record ${ok ? 'saved' : 'skipped'}: $run');
      onRecorded?.call(ok, run);
    }).catchError((Object e) {
      debugPrint('[runs] record error: $e');
    });
  }

  /// 라우트 서브트리에서 `Provider<GameController>`를 찾는다 (깊이·방문 수 제한).
  static GameController? _findController(Element root) {
    GameController? found;
    var budget = 300;
    void visit(Element e, int depth) {
      if (found != null || budget-- <= 0 || depth > 24) return;
      try {
        found = Provider.of<GameController>(e, listen: false);
        return;
      } on ProviderNotFoundException {
        // 아래로 계속
      } catch (_) {
        return;
      }
      e.visitChildElements((child) => visit(child, depth + 1));
    }

    root.visitChildElements((child) => visit(child, 1));
    return found;
  }
}

class _Attachment {
  _Attachment(this.controller, this.lastPhase);
  final GameController controller;
  Phase lastPhase;
  late VoidCallback listener;
}
