import 'package:dungeon_core/dungeon_core.dart';
import 'package:flutter/material.dart';

import 'game/wave_rules.dart';
import 'ui/menu_screen.dart';

void main() {
  // 정책 주입 지점. 지금은 단계 1~3 모두 GreedyPolicy 스텁.
  // M6: PolicyRepository.loadAll()의 QTablePolicy로 교체. M7: Firebase 초기화는 여기 앞에 붙인다.
  final Map<int, HeroPolicy> policies = {
    for (var s = 1; s <= WaveRules.stageCount; s++) s: const GreedyPolicy(),
  };
  runApp(NamaikiApp(policies: policies));
}

/// 앱 루트. 다크 테마, 한국어 UI 문자열.
class NamaikiApp extends StatelessWidget {
  const NamaikiApp({super.key, required this.policies});

  final Map<int, HeroPolicy> policies;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.deepPurple,
      visualDensity: VisualDensity.compact,
    );
    return MaterialApp(
      title: '마왕의 던전',
      debugShowCheckedModeBanner: false,
      theme: dark,
      darkTheme: dark,
      themeMode: ThemeMode.dark,
      home: MenuScreen(policies: policies),
    );
  }
}
