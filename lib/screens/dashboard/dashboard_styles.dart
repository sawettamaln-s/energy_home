import 'package:flutter/material.dart';

import '../../styles/app_colors.dart';
import '../../styles/app_typography.dart';

export '../../styles/app_colors.dart';
export '../../styles/app_spacing.dart';
export '../../styles/app_theme.dart';
export '../../styles/app_typography.dart';
export '../../styles/responsive.dart';

/// ===========================================================
/// DashboardStyles
/// สไตล์ที่ใช้ร่วมกันทั้งแอป (ไม่ได้ใช้แค่หน้า Dashboard) — สีอ้างอิงจาก
/// AppColors, text style และกล่อง/เงาของการ์ดที่ใช้ซ้ำ
///
/// import ไฟล์นี้ไฟล์เดียวก็เรียกใช้ AppColors / AppTypography /
/// AppSpacing / context.rf() ได้ครบผ่าน export ด้านบน
/// ===========================================================
class DashboardStyles {
  // ---------- สีหลักของแอป (ดูรายละเอียด/ที่มาของสีที่ AppColors) ----------
  static const Color background = AppColors.background;
  static const Color primaryGreen = AppColors.primaryGreen;
  static const Color textDark = AppColors.textDark;

  // ---------- พื้นหลังไฮไลท์ด้านบนของหน้าแดชบอร์ด ----------
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
  static const Color waterAccent = AppColors.waterAccent;

  // ---------- สีประจำไฟฟ้า/น้ำ (กรอบการ์ดมิเตอร์, ปุ่ม, หัวหน้าบันทึกมิเตอร์) ----------
  static const Color electricityBorder = AppColors.electricityBorder;
  static const Color waterBorder = AppColors.waterBorder;

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = AppColors.spikeUp;
  static const Color spikeDown = AppColors.spikeDown;

  // ---------- ข้อความจาง: hint ในช่องกรอก ----------
  static TextStyle hintStyle =
      TextStyle(color: Colors.grey.shade400, fontSize: AppTypography.body);

  // ---------- Text style ที่ใช้บ่อย ----------
  static const TextStyle sectionTitle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: AppTypography.subtitle,
      color: textDark);
}
