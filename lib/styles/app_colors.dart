import 'package:flutter/material.dart';

/// ===========================================================
/// AppColors
/// รวมสีทั้งหมดของแอปไว้ที่เดียว — เพิ่ม/แก้สีที่นี่ แล้วเรียกผ่าน
/// AppColors.xxx หรือ DashboardStyles.xxx (ชื่อเดียวกัน) ห้ามฮาร์ดโค้ดสีใหม่
/// ในหน้าจอ
/// ===========================================================
class AppColors {
  AppColors._();

  // ---------- สีหลักของแอป ----------
  static const Color background = Color(0xFFF7F5EC);
  static const Color primaryGreen = Color(0xFF2B4E24);
  // เขียวอ่อนกว่า primaryGreen หนึ่งขั้น — ใช้คู่กันเป็นไล่เฉดของการ์ดเด่น
  static const Color primaryGreenLight = Color(0xFF41703A);
  static const Color textDark = Color(0xFF333333);

  // ---------- พื้นหลังไฮไลท์ของหน้าเนื้อหา (ไล่เฉดเขียว-เหลืองอ่อน) ----------
  static const List<Color> pageHighlightColors = [
    Color(0xFFD7DE94),
    Color(0xFFC9DBA0),
    Color(0xFFDCE9C4),
    Color(0xFFF3F1E0),
    background,
  ];
  static const List<double> pageHighlightStops = [0.0, 0.22, 0.42, 0.66, 1.0];

  // ---------- สีเฉพาะมิเตอร์ไฟฟ้า/น้ำ ----------
  static const Color electricityAccent = Colors.orange;
  static const Color waterAccent = Colors.blue;

  // ---------- สีประจำไฟฟ้า/น้ำ (กรอบการ์ดมิเตอร์, ปุ่ม, หัวหน้าบันทึกมิเตอร์) ----------
  static const Color electricityBorder = Color(0xFFC98A4B); // น้ำตาล-ส้ม
  // สีฟ้าล้วน (ไม่ปนเขียว) — ใช้ร่วมกันหลายจุด: กรอบการ์ดน้ำ, ไอคอนในฟอร์ม
  // ตั้งค่ามิเตอร์ต้นรอบ, เส้นกราฟหน้าวิเคราะห์
  static const Color waterBorder = Color(0xFF1E76C7); // ฟ้าล้วน

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = Color(0xFFE53935); // ค่าใช้จ่ายพุ่งขึ้น
  static const Color spikeDown = Color(0xFF2E7D32); // ค่าใช้จ่ายลดลง

  // ---------- ข้อความ / ช่องกรอก ----------
  static const Color textMuted = Color(0xFF555555); // เนื้อความรองในกล่องข้อความ
  static const Color inputFill = Color(0xFFFAF9F4); // พื้นช่องเลือก (โทนครีม)
  static const Color inputBorder = Color(0xFFD8D5C8);

  // ---------- กล่องเตือน/ข้อควรระวัง (โทนส้ม) ----------
  // ใช้ warning.withValues(alpha: ...) เป็นพื้นกล่อง ไอคอนใช้ warningIcon
  // ข้อความใช้ warningText (เข้มกว่า อ่านง่ายบนพื้นจาง)
  static const Color warning = Color(0xFFFF9800);
  static const Color warningIcon = Color(0xFFEF6C00);
  static const Color warningText = Color(0xFFE65100);
  static const Color warningBorder = Color(0xFFFFCC80);

  // ---------- ระดับความหนัก (เบา -> หนัก) เช่น ชั่วโมงใช้งานของอุปกรณ์ ----------
  static const Color levelMedium = Color(0xFFF9A825); // เหลืองทอง
  static const Color levelHigh = Color(0xFFEF6C00); // ส้ม
  static const Color levelVeryHigh = Color(0xFFC62828); // แดง

  // ---------- กราฟ ----------
  // แท่งหน่วยที่ใช้ (ไฟฟ้า = ทอง, Off-Peak อ่อนกว่า / น้ำ = น้ำเงินเข้ม)
  static const Color electricityUnit = Color(0xFFE8B86D);
  static const Color electricityOffPeak = Color(0xFFF3D9B1);
  static const Color waterUnit = Color(0xFF123F6D);
  // เดือนที่ใช้สูงสุดในกราฟเทรนด์ (ส้มอิฐ)
  static const Color trendPeak = Color(0xFFE2673F);
  // ชิ้นพายอุปกรณ์ — เขียวหลักสลับสีอุ่น ให้ชิ้นติดกันแยกออกจากกันง่าย
  static const List<Color> pieChartPalette = [
    primaryGreen,
    Color(0xFFFFA726), // ส้มทอง
    Color(0xFF26A69A), // เขียวอมฟ้า (teal)
    Color(0xFFFFCA28), // เหลืองทอง
    Color(0xFF8D6E63), // น้ำตาลอบอุ่น
    Color(0xFF66BB6A), // เขียวอ่อน
    Color(0xFFD98E5B), // ส้มดิน
  ];

  // ---------- ฤดูกาล (การ์ดคาดการณ์บิลรอบถัดไป) ----------
  static const Color seasonSummer = Color(0xFFF57C00);
  static const Color seasonRainy = Color(0xFF1E88E5);
  static const Color seasonCool = Color(0xFF0097A7);

  // ---------- กลุ่มหน้าเข้าสู่ระบบ ----------
  static const Color authGreenDark = Color(0xFF1B5E20);
  static const Color authGreenLight = Color(0xFF43A047);
  static const Color googleBlue = Color(0xFF4285F4); // สีแบรนด์ปุ่ม Google
}