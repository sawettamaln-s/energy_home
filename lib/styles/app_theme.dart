import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// ===========================================================
/// AppTheme
/// ธีมกลางของทั้งแอป (Material 3) — ฟอนต์ IBM Plex Sans Thai และรูปทรง/สีของ
/// ปุ่ม ช่องกรอก หน้าต่าง แผ่นด้านล่าง แถบแท็บ ฯลฯ ตั้งไว้ที่นี่ที่เดียว
/// widget ที่ไม่ได้กำหนดสไตล์เองจะได้หน้าตาเดียวกันทั้งแอปโดยอัตโนมัติ
/// ===========================================================
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'IBMPlexSansThai';

  // รัศมีขอบมนมาตรฐาน — การ์ด/หน้าต่างใหญ่ใช้ lg ปุ่ม/ช่องกรอกใช้ md
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      primary: AppColors.primaryGreen,
      surface: Colors.white,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );
    final text = base.textTheme.apply(
      bodyColor: AppColors.textDark,
      displayColor: AppColors.textDark,
    );
    final roundedMd =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd));
    const buttonText = TextStyle(
        fontFamily: fontFamily,
        fontSize: AppTypography.body,
        fontWeight: FontWeight.w600);

    return base.copyWith(
      textTheme: text,
      // เปลี่ยนหน้าแบบเลื่อนจาง (Android) / ปัดข้าง (iOS) ให้ลื่นตาเหมือนแอปสมัยใหม่
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: AppTypography.title,
            fontWeight: FontWeight.w600,
            color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          minimumSize: const Size(64, 44),
          side: BorderSide(
              color: AppColors.primaryGreen.withValues(alpha: 0.35)),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 1.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl - 4)),
        titleTextStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: AppTypography.s17,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textDark,
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: AppTypography.body, color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelStyle: TextStyle(
            fontFamily: fontFamily, fontSize: AppTypography.body, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
            fontFamily: fontFamily, fontSize: AppTypography.body, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        // สวิตช์ที่กดไม่ได้ใช้สีจาง ไม่ให้ดูเหมือนเปิดใช้งานอยู่
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) return null;
          return states.contains(WidgetState.disabled)
              ? AppColors.primaryGreen.withValues(alpha: 0.3)
              : AppColors.primaryGreen;
        }),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primaryGreen),
      dividerTheme: DividerThemeData(
          color: Colors.grey.shade200, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primaryGreen,
        titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark),
      ),
    );
  }
}
