import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 深色影院风:近黑底 + 一个冷调的淡紫蓝强调色,颜色主要交给海报和剧照。
class AppColors {
  static const bg = Color(0xFF0B0C10);
  static const surface = Color(0xFF14161B);
  static const surfaceHi = Color(0xFF1D2027);
  static const text = Color(0xFFF1F0ED);
  static const textDim = Color(0xFF9B9EA8);
  static const accent = Color(0xFF8C9BFF);
  static const line = Color(0x1AFFFFFF);
}

const kFontFallback = <String>['Microsoft YaHei UI', 'Segoe UI', 'PingFang SC'];

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF0B0C10),
    secondary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamilyFallback: kFontFallback,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: AppColors.line,
  );
}

/// 桌面端:允许鼠标拖动横向列表。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
