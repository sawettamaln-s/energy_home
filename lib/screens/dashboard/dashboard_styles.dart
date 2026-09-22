import 'package:flutter/material.dart';

import '../../styles/app_colors.dart';
import '../../styles/app_typography.dart';

export '../../styles/app_colors.dart';
export '../../styles/app_spacing.dart';
export '../../styles/app_typography.dart';
export '../../styles/responsive.dart';

/// ===========================================================
/// DashboardStyles
/// รวมข้อความ / ค่าตกแต่งของหน้า Dashboard ไว้ที่เดียว
///
/// ปรับ ก.ย. 2026: แยกสี (AppColors) และสเกลฟอนต์ (AppTypography)
/// ออกไปเป็นไฟล์ของตัวเองใน lib/styles/ เพื่อให้แก้แต่ละหมวด (สี /
/// ขนาดตัวอักษร / ระยะห่าง) ได้อย่างเป็นสัดส่วน ไม่ต้องไล่หาปนกับ
/// logic การ์ด/เงาที่อยู่ในไฟล์นี้ — ไฟล์นี้ยังคง export ชื่อเดิมทั้งหมด
/// ไว้ (DashboardStyles.xxx) เพื่อไม่ต้องแก้ import ในไฟล์อื่นที่ใช้อยู่
/// ไฟล์ใหม่ที่ยังไม่ได้ปรับ สามารถ import ไฟล์นี้ไฟล์เดียวแล้วเรียกใช้
/// AppColors / AppTypography / AppSpacing ได้เลยผ่าน export ด้านบน
/// ===========================================================
class DashboardStyles {
  // ---------- สีหลักของแอป (ดูรายละเอียด/ที่มาของสีที่ AppColors) ----------
  static const Color background = AppColors.background;
  static const Color primaryGreen = AppColors.primaryGreen;
  static const Color textDark = AppColors.textDark;
  static const Color creamBorder = AppColors.creamBorder;

  // ---------- พื้นหลังไฮไลท์ของหน้าเนื้อหา (ธีมใหม่) ----------
  // ไล่เฉดเขียว-เหลืองอ่อนจากกึ่งกลางด้านบน จางลงมาเป็นพื้นครีม `background`
  // ใช้ RadialGradient วงกว้าง (แทนวงรีแบนแบบ CSS) เพื่อให้ดูเป็นแถบ
  // ไม่ใช่จุดแหลม — center อยู่เหนือกรอบจอ, radius ใหญ่พอให้ขอบจางกลืนกับ
  // background ก่อนถึงครึ่งล่างของจอ
  static BoxDecoration pageHighlight() => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -1.2),
          radius: 1.6,
          colors: AppColors.pageHighlightColors,
          stops: AppColors.pageHighlightStops,
        ),
      );

  // ---------- สีเฉพาะมิเตอร์ไฟฟ้า/น้ำ ----------
  static const Color electricityAccent = AppColors.electricityAccent;
  static const Color electricityFieldBg = AppColors.electricityFieldBg;
  static const Color waterAccent = AppColors.waterAccent;
  static const Color waterFieldBg = AppColors.waterFieldBg;

  // ---------- สีกรอบการ์ดมิเตอร์วันนี้ (เลย์เอาต์ใหม่ กรอบสีตามประเภท) ----------
  static const Color electricityBorder = AppColors.electricityBorder;
  static const Color waterBorder = AppColors.waterBorder;

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = AppColors.spikeUp;
  static const Color spikeDown = AppColors.spikeDown;

  // ---------- สีตัวอย่าง/hint ในช่องกรอกมิเตอร์ (จางลงตามที่ขอ) ----------
  static TextStyle hintStyle =
      TextStyle(color: Colors.grey.shade400, fontSize: AppTypography.body);
  static TextStyle lastValueStyle =
      TextStyle(fontSize: AppTypography.caption, color: Colors.grey.shade400);

  // ---------- Text style ที่ใช้บ่อย ----------
  static const TextStyle greeting = TextStyle(
      fontSize: AppTypography.heading,
      fontWeight: FontWeight.bold,
      color: textDark);
  // ฟอนต์ขาว อ่านออกได้เพราะ chip พื้นหลังทึบ (ดู pageHighlight
  // header chip ใน dashboard_screen.dart) — ไม่ต้องพึ่งสีตัวอักษรเข้ม
  static const TextStyle subGreeting = TextStyle(
      fontSize: AppTypography.hint,
      color: Colors.white,
      fontWeight: FontWeight.w500);
  static const TextStyle sectionTitle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: AppTypography.subtitle,
      color: textDark);

  // ---------- กล่อง/เงา ที่ใช้ซ้ำกันหลายการ์ด ----------
  static BoxDecoration whiteCard({double radius = 14}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // การ์ดพื้นขาวมีกรอบสี — ใช้กับการ์ดมิเตอร์ไฟฟ้า/น้ำ แต่ละการ์ดมีกรอบสี
  // ของตัวเอง
  static BoxDecoration accentCard(Color borderColor, {double radius = 16}) =>
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );
}