import 'package:flutter/material.dart';

/// ===========================================================
/// DashboardStyles
/// รวมสี / ข้อความ / ค่าตกแต่งทั้งหมดของหน้า Dashboard ไว้ที่เดียว
/// แยกออกจาก dashboard_screen.dart เพื่อให้แก้ธีม/สี ได้ง่าย
/// โดยไม่ต้องไปไล่หาในไฟล์ logic
/// ===========================================================
class DashboardStyles {
  // ---------- สีหลักของแอป ----------
  static const Color background = Color(0xFFF5F5F5);
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color textDark = Color(0xFF333333);
  static const Color creamBorder = Color(0xFFE9DCC5);

  // ---------- สีเฉพาะมิเตอร์ไฟฟ้า/น้ำ ----------
  static const Color electricityAccent = Colors.orange;
  static const Color electricityFieldBg = Color(0xFFFFE9D6);
  static const Color waterAccent = Colors.blue;
  static const Color waterFieldBg = Color(0xFFE3F2FD);

  // ---------- สีกรอบการ์ดมิเตอร์วันนี้ (เลย์เอาต์ใหม่ กรอบสีตามประเภท) ----------
  static const Color electricityBorder = Color(0xFFC98A4B); // น้ำตาล-ส้ม
  static const Color waterBorder = Color(0xFF2F9E8F); // เขียวอมฟ้า

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = Color(0xFFE53935); // ค่าใช้จ่ายพุ่งขึ้น
  static const Color spikeDown = Color(0xFF2E7D32); // ค่าใช้จ่ายลดลง

  // ---------- สีตัวอย่าง/hint ในช่องกรอกมิเตอร์ (จางลงตามที่ขอ) ----------
  static TextStyle hintStyle = TextStyle(color: Colors.grey.shade400, fontSize: 14);
  static TextStyle lastValueStyle = TextStyle(fontSize: 11, color: Colors.grey.shade400);

  // ---------- Text style ที่ใช้บ่อย ----------
  static const TextStyle greeting = TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textDark);
  static const TextStyle subGreeting = TextStyle(fontSize: 12, color: Colors.grey);
  static const TextStyle sectionTitle = TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark);

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

  // การ์ดพื้นขาวมีกรอบสี — ใช้กับการ์ดมิเตอร์ไฟฟ้า/น้ำ เลย์เอาต์ใหม่ที่
  // แต่ละการ์ดมีกรอบสีของตัวเองแทนเงาเบาๆ แบบเดิม
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