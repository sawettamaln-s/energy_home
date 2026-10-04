import 'package:intl/intl.dart';

// =====================================================================
// กติกาตรวจเลขมิเตอร์ที่กรอกในหน้าบันทึกมิเตอร์ (record_meter_screen.dart)
// เลขที่กรอกต้องไม่น้อยกว่าเลขต้นรอบ และไม่น้อยกว่าค่าที่บันทึกล่าสุดของรอบนี้
// (TOU เช็คทีละช่อง On-Peak/Off-Peak) — ไม่ขึ้นกับ widget จึงเทสได้ตรงๆ
// =====================================================================

// ผลการเช็คช่วงของเลขที่กรอก — none = ผ่าน
enum MeterRangeIssue { none, invalid, belowStart, belowLast }

// ค่าที่ใช้คำนวณ + issue ของช่องนั้น + ข้อความใต้ช่อง (ว่าง = ผ่าน)
typedef MeterFieldCheck = ({
  double value,
  MeterRangeIssue issue,
  String message,
});

class MeterReadingCheck {
  // เช็คข้อความที่กรอก 1 ช่อง — แปลงเป็นตัวเลข แล้วเทียบกับต้นรอบ/ค่าล่าสุด
  // ช่องว่างใช้ค่า [fallback] แทน (TOU เว้นช่องได้ = ช่วงนั้นไม่ได้ใช้เพิ่ม)
  // [label] ว่าง = มิเตอร์ปกติ/น้ำ, [unit] = หน่วยที่แสดงในข้อความ
  static MeterFieldCheck check({
    required String label,
    required String text,
    required double fallback,
    required double start,
    required double last,
    required String unit,
  }) {
    if (text.trim().isEmpty) {
      return (value: fallback, issue: MeterRangeIssue.none, message: '');
    }
    final value = double.tryParse(text.replaceAll(',', '').trim());
    if (value == null) {
      return (
        value: 0,
        issue: MeterRangeIssue.invalid,
        message: 'รูปแบบตัวเลขไม่ถูกต้อง กรุณากรอกเฉพาะตัวเลขค่ะ',
      );
    }

    final formatter = NumberFormat('#,##0.##');
    // ชื่อช่อง TOU ลงท้ายด้วยวงเล็บ ต้องเว้นวรรคก่อนข้อความต่อท้าย
    final subject = label.isEmpty ? 'เลขมิเตอร์' : 'เลข $label ';
    if (value < start) {
      return (
        value: value,
        issue: MeterRangeIssue.belowStart,
        message:
            '$subjectต้องไม่น้อยกว่าเลขต้นรอบบิล (${formatter.format(start)} $unit) ค่ะ',
      );
    }
    if (value < last) {
      return (
        value: value,
        issue: MeterRangeIssue.belowLast,
        message:
            '$subjectต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (${formatter.format(last)} $unit) ค่ะ',
      );
    }
    return (value: value, issue: MeterRangeIssue.none, message: '');
  }

  // เลือกคำแนะนำ + ปุ่มด้านล่างจาก issue ของทุกช่อง — ต่ำกว่าต้นรอบมาก่อน
  // (ต้องแก้ต้นรอบก่อนถึงจะเทียบกับค่าล่าสุดได้) ส่วน invalid ไม่มีคำแนะนำ
  // เพิ่ม เพราะข้อความใต้ช่องบอกวิธีแก้อยู่แล้ว
  static MeterRangeIssue helpIssueOf(List<MeterRangeIssue> issues) {
    if (issues.contains(MeterRangeIssue.belowStart)) {
      return MeterRangeIssue.belowStart;
    }
    if (issues.contains(MeterRangeIssue.belowLast)) {
      return MeterRangeIssue.belowLast;
    }
    return MeterRangeIssue.none;
  }
}
