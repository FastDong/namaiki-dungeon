import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/wave_rules.dart';
import '../services/run_repository.dart';

/// 리더보드: `runs` 상위 20 (순위·닉네임·웨이브·단계·시간). 로딩/오류/빈 상태, 새로고침.
/// 다크 테마 고정색: 배경 #120F1A, 패널 #1E1A2A, 강조 #A879FF, 텍스트 #EFE6D3.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.repository});

  /// 주입 안 하면 `Provider<RunRepository>` → 없으면 새 인스턴스.
  final RunRepository? repository;

  static const Color bg = Color(0xFF120F1A);
  static const Color panel = Color(0xFF1E1A2A);
  static const Color accent = Color(0xFFA879FF);
  static const Color text = Color(0xFFEFE6D3);
  static const Color muted = Color(0x99EFE6D3);

  static Route<void> route({RunRepository? repository}) =>
      MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(repository: repository));

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late RunRepository _repo;
  Future<List<RunRecord>>? _future;
  int _reloads = 0;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? _resolveRepo();
    _future = _load();
  }

  RunRepository _resolveRepo() {
    try {
      return Provider.of<RunRepository>(context, listen: false);
    } on ProviderNotFoundException {
      return RunRepository();
    }
  }

  Future<List<RunRecord>> _load() async => _repo.top20();

  Future<void> _refresh() async {
    setState(() {
      _reloads++;
      _future = _load();
    });
    try {
      await _future;
    } catch (_) {
      // 오류는 FutureBuilder가 표시한다.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: LeaderboardScreen.bg,
        colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: LeaderboardScreen.accent,
              surface: LeaderboardScreen.panel,
              onSurface: LeaderboardScreen.text,
            ),
      ),
      child: Scaffold(
        backgroundColor: LeaderboardScreen.bg,
        appBar: AppBar(
          backgroundColor: LeaderboardScreen.bg,
          foregroundColor: LeaderboardScreen.text,
          title: const Text('리더보드'),
          actions: [
            IconButton(
              key: const ValueKey('leaderboard_refresh'),
              tooltip: '새로고침',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
            ),
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<List<RunRecord>>(
            key: ValueKey(_reloads),
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const _Message(
                  key: ValueKey('leaderboard_loading'),
                  icon: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(color: LeaderboardScreen.accent, strokeWidth: 3),
                  ),
                  title: '기록을 불러오는 중…',
                );
              }
              if (snap.hasError) {
                return _Message(
                  key: const ValueKey('leaderboard_error'),
                  icon: const Icon(Icons.cloud_off, size: 40, color: LeaderboardScreen.accent),
                  title: '리더보드를 불러오지 못했다',
                  subtitle: _shortError(snap.error),
                  action: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: LeaderboardScreen.accent, foregroundColor: Colors.black),
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                );
              }
              final rows = snap.data ?? const <RunRecord>[];
              if (rows.isEmpty) {
                return _Message(
                  key: const ValueKey('leaderboard_empty'),
                  icon: const Text('👑', style: TextStyle(fontSize: 40, height: 1)),
                  title: '아직 기록이 없다',
                  subtitle: '첫 번째 마왕이 되어 보자.',
                  action: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: LeaderboardScreen.accent),
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('새로고침'),
                  ),
                );
              }
              return RefreshIndicator(
                color: LeaderboardScreen.accent,
                backgroundColor: LeaderboardScreen.panel,
                onRefresh: _refresh,
                child: ListView.separated(
                  key: const ValueKey('leaderboard_list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) return _Header(fallback: _repo.lastUsedFallbackQuery);
                    final r = rows[i - 1];
                    return _RunTile(rank: i, run: r);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _shortError(Object? e) {
    final s = e?.toString() ?? '알 수 없는 오류';
    if (s.contains('초기화되지 않았') || s.contains('core/no-app') || s.contains('No Firebase App')) {
      return '오프라인이거나 Firebase에 연결하지 못했다.';
    }
    if (s.contains('permission-denied')) return '읽기 권한이 없다 (보안 규칙 확인).';
    if (s.contains('unavailable')) return '서버에 연결할 수 없다. 네트워크를 확인하자.';
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.fallback});

  final bool fallback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(
            '상위 ${RunRepository.topLimit} · 막아낸 웨이브 순',
            style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 12, letterSpacing: 0.3),
          ),
          const Spacer(),
          if (fallback)
            Tooltip(
              message: '복합 색인 생성 전이라 웨이브 순으로만 정렬됐다',
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 14, color: LeaderboardScreen.muted),
                  SizedBox(width: 4),
                  Text('단순 정렬', style: TextStyle(color: LeaderboardScreen.muted, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.rank, required this.run});

  final int rank;
  final RunRecord run;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final top = rank <= 3;
    final m = run.durationSec ~/ 60;
    final s = run.durationSec % 60;
    final stageColor = switch (run.stageReached) {
      1 => const Color(0xFF6FCF97),
      2 => const Color(0xFFF2C94C),
      _ => const Color(0xFFEB5757),
    };

    return Container(
      key: ValueKey('leaderboard_row_$rank'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: LeaderboardScreen.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: top ? LeaderboardScreen.accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
          width: top ? 1.2 : 1,
        ),
        boxShadow: top
            ? [BoxShadow(color: LeaderboardScreen.accent.withValues(alpha: 0.18), blurRadius: 14, spreadRadius: 1)]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: top
                ? Text(_medals[rank - 1], style: const TextStyle(fontSize: 24, height: 1))
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.nickname.isEmpty ? RunRepository.defaultNickname : run.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: LeaderboardScreen.text,
                    fontSize: 16,
                    fontWeight: top ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Chip(
                      label: 'Stage ${run.stageReached} ${WaveRules.stageName(run.stageReached)}',
                      color: stageColor,
                    ),
                    Text('⏱ $m분 ${s.toString().padLeft(2, '0')}초',
                        style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 12)),
                    if (run.heroDeaths > 0)
                      Text('💀 ${run.heroDeaths}', style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 12)),
                    if (run.createdAt != null)
                      Text(_fmtDate(run.createdAt!), style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${run.wavesCleared}',
                style: const TextStyle(
                  color: LeaderboardScreen.accent,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text('/ ${Balance.totalWaves} 웨이브', style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.month}/${l.day} ${two(l.hour)}:${two(l.minute)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.title, this.subtitle, this.action});

  final Widget icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: LeaderboardScreen.text, fontSize: 17, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: LeaderboardScreen.muted, fontSize: 13)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
