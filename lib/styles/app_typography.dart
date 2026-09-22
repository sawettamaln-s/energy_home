import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'responsive.dart';

/// ===========================================================
/// AppTypography
/// รวมสเกลขนาดฟอนต์ของแอปไว้ที่เดียว แยกออกจาก dashboard_styles.dart
///
/// มี 2 รูปแบบให้ใช้:
///   1) ค่าคงที่ตัวเลข (caption/hint/body/subtitle/title/heading) — ใช้ตอน
///      ต้องการ TextStyle แบบ const เหมือนเดิม (ไม่ยืดหยุ่นตามจอ)
///   2) AppTypography.scaled(context, ...) — คืน TextStyle ที่ปรับขนาด
///      ตามความกว้างจอจริงผ่าน context.rf() ใช้กับจุดที่ต้องการความ
///      ยืดหยุ่นข้ามรุ่นเครื่อง (เช่น AppTopBar, หัวข้อการ์ดสำคัญ)
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

  // ---------- ค่าตัวเลขดิบทั้งหมดที่พบใช้อยู่ทั่วแอป (ก.ย. 2026) ----------
  // ย้ายมาจากเลขลอยๆ ในแต่ละหน้า (fontSize: 12.5 ฯลฯ) ให้มาอยู่ที่เดียว
  // เก็บค่าเดิมไว้ทุกตัวเพื่อไม่ให้หน้าตาแอปเปลี่ยน — ไม่ได้ลดเหลือแค่
  // สเกลด้านบน เพราะแต่ละจุดถูกจูนขนาดมาเฉพาะที่ (ตาราง/ชิป/กราฟ ฯลฯ)
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