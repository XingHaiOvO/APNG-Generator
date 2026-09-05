import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() {
  runApp(const ApngGeneratorApp());
}

/// 「极简纸感」设计令牌：
/// 近白底 #F8F9FE / 靛蓝 #6366F1 / 白卡片 + 浅靛蓝描边（亮色）
/// 深蓝黑底 #0F1117 / 靛蓝亮调 #818CF8（暗色）
class ApngGeneratorApp extends StatelessWidget {
  const ApngGeneratorApp({super.key});

  static const _seed = Color(0xFF6366F1);

  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: const Color(0xFF6366F1),
        onPrimary: Colors.white,
        secondary: const Color(0xFF818CF8),
        surface: const Color(0xFFF8F9FE),
        surfaceContainerLowest: Colors.white,
        surfaceContainer: Colors.white,
        onSurface: const Color(0xFF1E293B),
        onSurfaceVariant: const Color(0xFF64748B),
        outlineVariant: const Color(0xFFE0E7FF),
        error: const Color(0xFFDC2626),
      );
    }
    return base.copyWith(
      primary: const Color(0xFF818CF8),
      onPrimary: const Color(0xFF10132A),
      secondary: const Color(0xFF6366F1),
      surface: const Color(0xFF0F1117),
      surfaceContainerLowest: const Color(0xFF171923),
      surfaceContainer: const Color(0xFF1B1E2B),
      onSurface: const Color(0xFFE2E8F0),
      onSurfaceVariant: const Color(0xFF94A3B8),
      outlineVariant: const Color(0xFF2A2E40),
      error: const Color(0xFFF87171),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = _scheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: scheme.surfaceContainerLowest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APNG 生成器',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
