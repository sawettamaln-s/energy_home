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
  static const Color textDark = Color(0xFF333333);
  static const Color creamBorder = Color(0xFFE9DCC5);

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
  static const Color electricityFieldBg = Color(0xFFFFE9D6);
  static const Color waterAccent = Colors.blue;
  static const Color waterFieldBg = Color(0xFFE3F2FD);

  // ---------- สีประจำไฟฟ้า/น้ำ (กรอบการ์ดมิเตอร์, ปุ่ม, หัวหน้าบันทึกมิเตอร์) ----------
  static const Color electricityBorder = Color(0xFFC98A4B); // น้ำตาล-ส้ม
  // สีฟ้าล้วน (ไม่ปนเขียว) — ใช้ร่วมกันหลายจุด: กรอบการ์ดน้ำ, ไอคอนในฟอร์ม
  // ตั้งค่ามิเตอร์ต้นรอบ, เส้นกราฟหน้าวิเคราะห์
  static const Color waterBorder = Color(0xFF1E76C7); // ฟ้าล้วน

  // ---------- สีสถานะ (เพิ่มขึ้น/ลดลง) ----------
  static const Color spikeUp = Color(0xFFE53935); // ค่าใช้จ่ายพุ่งขึ้น
  static const Color spikeDown = Color(0xFF2E7D32); // ค่าใช้จ่ายลดลง
}