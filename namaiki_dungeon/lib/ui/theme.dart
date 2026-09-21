import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 디자인 시안 확정 팔레트 + 글꼴. 색은 여기서만 정의한다.
class DungeonColors {
  DungeonColors._();

  static const Color void_ = Color(0xFF120F1A); // 배경
  static const Color stone = Color(0xFF1E1A2A); // 패널
  static const Color floor = Color(0xFF241F31); // 바닥칸
  static const Color line = Color(0xFF3A3350);
  static const Color parchment = Color(0xFFEFE6D3); // 텍스트
  static const Color muted = Color(0xFF9A8FB0);
  static const Color violet = Color(0xFFA879FF); // 마물/마법/AI 단계
  static const Color ember = Color(0xFFFF7A45); // 용사/피격/HP
  static const Color gold = Color(0xFFF2C14E); // 마나/왕좌
  static const Color potion = Color(0xFF5AD07A);
  static const Color danger = Color(0xFFE5484D); // 함정 발동

  // 칸 배경
  static const Color monsterCell = Color(0xFF2B2145);
  static const Color heroCell = Color(0xFF3A2418);
  static const Color throneCell = Color(0xFF33280F);
  static const Color pillarTop = Color(0xFF3B3350);
  static const Color pillarBottom = Color(0xFF17131F);

  /// AI 단계 색 (1: 초록빛, 2: 금빛, 3: violet).
  static Color stage(int s) => switch (s) {
        1 => potion,
        2 => gold,
        _ => violet,
      };
}

/// 글꼴 헬퍼. google_fonts 는 네트워크에서 받아오므로 실패/오프라인/테스트에서는 기본 폰트로 폴백한다.
class DungeonFonts {
  DungeonFonts._();

  /// 런타임 페치가 꺼져 있으면(테스트) google_fonts 를 아예 호출하지 않는다.
  static bool get _enabled {
    try {
      return GoogleFonts.config.allowRuntimeFetching;
    } catch (_) {
      return false;
    }
  }

  /// 제목: Black Han Sans.
  static TextStyle title({double size = 28, Color color = DungeonColors.parchment, double? height}) {
    final base = TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w900, height: height ?? 1.1);
    if (!_enabled) return base;
    try {
      return GoogleFonts.blackHanSans(textStyle: base.copyWith(fontWeight: FontWeight.w400));
    } catch (_) {
      return base;
    }
  }

  /// 본문: Noto Sans KR.
  static TextStyle body({
    double size = 14,
    Color color = DungeonColors.parchment,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    final base = TextStyle(fontSize: size, color: color, fontWeight: weight, height: height ?? 1.3);
    if (!_enabled) return base;
    try {
      return GoogleFonts.notoSansKr(textStyle: base);
    } catch (_) {
      return base;
    }
  }

  /// 앱 전체 TextTheme (본문 폰트 적용).
  static TextTheme textTheme(TextTheme base) {
    if (!_enabled) return base.apply(bodyColor: DungeonColors.parchment, displayColor: DungeonColors.parchment);
    try {
      return GoogleFonts.notoSansKrTextTheme(base)
          .apply(bodyColor: DungeonColors.parchment, displayColor: DungeonColors.parchment);
    } catch (_) {
      return base.apply(bodyColor: DungeonColors.parchment, displayColor: DungeonColors.parchment);
    }
  }
}

/// 플레이/메뉴 화면에 씌우는 ThemeData (main.dart 는 건드리지 않고 화면 안에서 Theme 로 감싼다).
class DungeonTheme {
  DungeonTheme._();

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.dark(
      primary: DungeonColors.violet,
      onPrimary: DungeonColors.void_,
      secondary: DungeonColors.ember,
      onSecondary: DungeonColors.void_,
      tertiary: DungeonColors.gold,
      onTertiary: DungeonColors.void_,
      surface: DungeonColors.void_,
      onSurface: DungeonColors.parchment,
      surfaceContainer: DungeonColors.stone,
      surfaceContainerHigh: DungeonColors.floor,
      surfaceContainerHighest: DungeonColors.line,
      surfaceContainerLow: DungeonColors.stone,
      surfaceContainerLowest: DungeonColors.void_,
      onSurfaceVariant: DungeonColors.muted,
      outline: DungeonColors.line,
      outlineVariant: DungeonColors.line,
      error: DungeonColors.danger,
      primaryContainer: DungeonColors.monsterCell,
      onPrimaryContainer: DungeonColors.parchment,
      secondaryContainer: DungeonColors.heroCell,
      onSecondaryContainer: DungeonColors.parchment,
      tertiaryContainer: DungeonColors.throneCell,
      onTertiaryContainer: DungeonColors.gold,
      errorContainer: Color(0xFF4A1F22),
      onErrorContainer: DungeonColors.parchment,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: DungeonColors.void_,
      canvasColor: DungeonColors.stone,
      cardColor: DungeonColors.stone,
      dividerColor: DungeonColors.line,
      textTheme: DungeonFonts.textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: DungeonColors.void_,
        foregroundColor: DungeonColors.parchment,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: DungeonFonts.title(size: 20),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: DungeonColors.stone),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DungeonColors.stone,
        contentTextStyle: DungeonFonts.body(size: 13),
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DungeonColors.violet,
          foregroundColor: DungeonColors.void_,
          textStyle: DungeonFonts.body(size: 14, weight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DungeonColors.parchment,
          side: const BorderSide(color: DungeonColors.line),
          textStyle: DungeonFonts.body(size: 14, weight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: DungeonColors.floor,
        selectedColor: DungeonColors.violet,
        labelStyle: DungeonFonts.body(size: 12, weight: FontWeight.w600),
        side: const BorderSide(color: DungeonColors.line),
      ),
    );
  }
}
