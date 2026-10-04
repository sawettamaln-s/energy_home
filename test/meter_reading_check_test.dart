// เทสกติกาตรวจเลขมิเตอร์ที่กรอก (lib/utils/meter_reading_check.dart) โดยตรง
// ไม่ต้องเปิดหน้าจอ — หน้าจอทั้งหน้าเทสอยู่ที่ record_meter_screen_test.dart
import 'package:energy_home/utils/meter_reading_check.dart';
import 'package:flutter_test/flutter_test.dart';

MeterFieldCheck _check(String text, {String label = ''}) =>
    MeterReadingCheck.check(
      label: label,
      text: text,
      fallback: 1100,
      start: 1000,
      last: 1100,
      unit: 'หน่วย',
    );

void main() {
  test('ไม่น้อยกว่าทั้งต้นรอบและค่าล่าสุด -> ผ่าน (รับเลขที่มีจุลภาค)', () {
    final r = _check('1,250.5');
    expect(r.issue, MeterRangeIssue.none);
    expect(r.value, 1250.5);
    expect(r.message, isEmpty);
  });

  test('ช่องว่าง -> ใช้ค่า fallback และถือว่าผ่าน', () {
    final r = _check('  ');
    expect(r.issue, MeterRangeIssue.none);
    expect(r.value, 1100);
  });

  test('ไม่ใช่ตัวเลข -> invalid', () {
    expect(_check('12a').issue, MeterRangeIssue.invalid);
  });

  test('ต่ำกว่าต้นรอบ -> belowStart พร้อมเลขต้นรอบในข้อความ', () {
    final r = _check('900');
    expect(r.issue, MeterRangeIssue.belowStart);
    expect(r.message, 'เลขมิเตอร์ต้องไม่น้อยกว่าเลขต้นรอบบิล (1,000 หน่วย) ค่ะ');
  });

  test('ไม่ต่ำกว่าต้นรอบ แต่ต่ำกว่าค่าล่าสุด -> belowLast', () {
    final r = _check('1050', label: 'On-Peak (T1)');
    expect(r.issue, MeterRangeIssue.belowLast);
    expect(r.message,
        'เลข On-Peak (T1) ต้องไม่น้อยกว่าค่าที่บันทึกล่าสุด (1,100 หน่วย) ค่ะ');
  });

  test('คำแนะนำด้านล่าง: ต่ำกว่าต้นรอบมาก่อน, invalid ไม่มีคำแนะนำ', () {
    expect(
        MeterReadingCheck.helpIssueOf(
            [MeterRangeIssue.belowLast, MeterRangeIssue.belowStart]),
        MeterRangeIssue.belowStart);
    expect(MeterReadingCheck.helpIssueOf([MeterRangeIssue.belowLast]),
        MeterRangeIssue.belowLast);
    expect(MeterReadingCheck.helpIssueOf([MeterRangeIssue.invalid]),
        MeterRangeIssue.none);
  });
}
