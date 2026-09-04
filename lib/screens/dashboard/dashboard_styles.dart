import 'package:flutter/material.dart';

/// ===========================================================
/// DashboardStyles
/// รวมสี / ข้อความ / ค่าตกแต่งทั้งหมดของหน้า Dashboard ไว้ที่เดียว
/// แยกออกจาก dashboard_screen.dart เพื่อให้แก้ธีม/สี ได้ง่าย
/// โดยไม่ต้องไปไล่หาในไฟล์ logic
/// ===========================================================
class DashboardStyles {
  // ---------- สีหลักของแอป ----------
  // ปรับโทนใหม่ (ส.ค. 2026): เขียวป่าเข้มขึ้น + พื้นครีมอุ่นแทนเทาแบน
  // primaryGreen ถูกอ้างอิงเป็น AppBar/ปุ่ม/ไอคอนหลักทั่วทั้งแอปอยู่แล้ว
  // (dashboard, วิเคราะห์, อุปกรณ์, ตั้งค่า) แก้ค่าที่นี่ที่เดียวจึงไล่สี
  // ใหม่ไปทั้งระบบพร้อมกันโดยไม่ต้องแก้ทีละหน้า
  static const Color background = Color(0xFFF7F5EC);
  static const Color primaryGreen = Color(0xFF2B4E24);
  static const Color textDark = Color(0xFF333333);
  static const Color creamBorder = Color(0xFFE9DCC5);

  // ---------- พื้นหลังไฮไลท์ของหน้าเนื้อหา (ธีมใหม่) ----------
  // ไล่เฉดเขียว-เหลืองอ่อนจากกึ่งกลางด้านบน จางลงมาเป็นพื้นครีม `background`
  // ใช้ RadialGradient วงกว้าง (แทนวงรีแบนแบบ CSS) เพื่อให้ดูเป็นแถบ
  // ไม่ใช่จุดแหลม — center อยู่เหนือกรอบจอ, radius ใหญ่พอให้ขอบจางกลืนกับ
  // background ก่อนถึงครึ่งล่างของจอ
  static const List<Color> _pageHighlightColors = [
    Color(0xFFD7DE94),
    Color(0xFFC9DBA0),
    Color(0xFFDCE9C4),
    Color(0xFFF3F1E0),
    background,
  ];
  static const List<double> _pageHighlightStops = [0.0, 0.22, 0.42, 0.66, 1.0];

  static BoxDecoration pageHighlight() => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -1.2),
          radius: 1.6,
          colors: _pageHighlightColors,
          stops: _pageHighlightStops,
        ),
      );

  // ---------- สีเฉพาะมิเตอร์ไฟฟ้า/น้ำ ----------
  static const Color electricityAccent = Colors.orange;
  static const Color electricityFieldBg = Color(0xFFFFE9D6);
  static const Color waterAccent = Colors.blue;
  static const Color waterFieldBg = Color(0xFFE3F2FD);

  // ---------- สีกรอบการ์ดมิเตอร์วันนี้ (เลย์เอาต์ใหม่ กรอบสีตามประเภท) ----------
  static const Color electricityBorder = Color(0xFFC98A4B); // น้ำตาล-ส้ม
  // สีฟ้าล้วน (ไม่ปนเขียว) — ใช้ร่วมกันหลายจุด: กรอบการ์ดน้ำ, ไอคอนในฟอร์ม
  // ตั้งค่ามิเตอร์ต้นรอบ, เส้นกราฟหน้าวิเคราะห์
  static const Color waterBorder = Color(0xFF1E76C7); // ฟ้าล้วน

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = Color(0xFFE53935); // ค่าใช้จ่ายพุ่งขึ้น
  static const Color spikeDown = Color(0xFF2E7D32); // ค่าใช้จ่ายลดลง

  // ---------- สีตัวอย่าง/hint ในช่องกรอกมิเตอร์ (จางลงตามที่ขอ) ----------
  static TextStyle hintStyle = TextStyle(color: Colors.grey.shade400, fontSize: 14);
  static TextStyle lastValueStyle = TextStyle(fontSize: 11, color: Colors.grey.shade400);

  // ---------- Text style ที่ใช้บ่อย ----------
  static const TextStyle greeting = TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textDark);
  // ฟอนต์ขาวแบบเดิม อ่านออกได้เพราะ chip พื้นหลังทึบขึ้น (ดู pageHighlight
  // header chip ใน dashboard_screen.dart) — ไม่ต้องพึ่งสีตัวอักษรเข้ม
  static const TextStyle subGreeting = TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500);
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