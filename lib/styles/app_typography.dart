import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'responsive.dart';

/// ===========================================================
/// AppTypography
/// รวมขนาดฟอนต์ของแอปไว้ที่เดียว
///
/// มี 2 รูปแบบให้ใช้:
///   1) ค่าคงที่ (caption/hint/body/... หรือ sN = N px) — ใช้กับ TextStyle
///      แบบ const (ไม่ยืดหยุ่นตามจอ แต่ยังถูกจำกัดสเกลรวมที่ main.dart)
///   2) AppTypography.scaled(context, ...) — คืน TextStyle ที่ปรับขนาด
///      ตามความกว้างจอผ่าน context.rf() (ตอนนี้ใช้ที่ AppTopBar)
/// ===========================================================
class AppTypography {
  AppTypography._();

  // ---------- สเกลขนาดฟอนต์พื้นฐาน (อ้างอิงจอมาตรฐาน 375px) ----------
  static const double caption = 11;
  static const double hint = 12;
  static const double body = 14;
  static const double subtitle = 15;
  static const double title = 16;
  static const double heading = 19;

  // ---------- ขนาดตามจริงที่ใช้ทั่วแอป (sN = N px, s12_5 = 12.5 px) ----------
  // มีหลายขนาดเพราะแต่ละจุดจูนมาเฉพาะที่ (ตาราง/ชิป/กราฟ ฯลฯ)
  static const double s8 = 8;
  static const double s9 = 9;
  static const double s9_5 = 9.5;
  static const double s10 = 10;
  static const double s10_5 = 10.5;
  static const double s11 = 11;
  static const double s11_5 = 11.5;
  static const double s12 = 12;
  static const double s12_5 = 12.5;
  static const double s13 = 13;
  static const double s13_5 = 13.5;
  static const double s14 = 14;
  static const double s14_5 = 14.5;
  static const double s15 = 15;
  static const double s15_5 = 15.5;
  static const double s16 = 16;
  static const double s17 = 17;
  static const double s18 = 18;
  static const double s19 = 19;
  static const double s20 = 20;
  static const double s22 = 22;
  static const double s24 = 24;
  static const double s26 = 26;
  static const double s32 = 32;

  /// สร้าง TextStyle ที่ปรับขนาดตามจอจริง (responsive)
  static TextStyle scaled(
    BuildContext context, {
    required double size,
    FontWeight weight = FontWeight.normal,
    Color color = AppColors.textDark,
  }) {
    return TextStyle(
      fontSize: context.rf(size),
      fontWeight: weight,
      color: color,
    );
  }
}