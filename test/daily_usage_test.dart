// เทสการแปลงยอดสะสมเป็นการใช้รายวัน (lib/utils/daily_usage.dart)
import 'package:energy_home/utils/daily_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 1);

  test('ยังไม่ได้จด -> ไม่มีข้อมูลทุกวัน', () {
    final v = DailyUsage.spread(cycleStart: start, cycleDays: 31, readings: []);
    expect(v.length, 31);
    expect(v.every((d) => d == null), isTrue);
  });

  test('จดเว้นวัน -> หน่วยที่เพิ่มเฉลี่ยลงแต่ละวันในช่วงนั้น', () {
    final v = DailyUsage.spread(cycleStart: start, cycleDays: 31, readings: [
      (DateTime(2026, 10, 2, 20), 20), // ช่วงแรกครอบวันที่ 1-2 (index 0-1)
      (DateTime(2026, 10, 5, 8), 50), // วันที่ 3-5 (index 2-4) วันละ 10
    ]);
    expect(v.sublist(0, 5), [10, 10, 10, 10, 10]);
    expect(v[5], isNull); // หลังจดครั้งล่าสุดยังไม่มีข้อมูล
  });

  test('จดหลายครั้งในวันเดียว -> รวมเป็นของวันนั้น ยอดลดลงไม่นับติดลบ', () {
    final v = DailyUsage.spread(cycleStart: start, cycleDays: 31, readings: [
      (DateTime(2026, 10, 1, 9), 4),
      (DateTime(2026, 10, 1, 21), 9),
      (DateTime(2026, 10, 2, 9), 7), // พิมพ์ผิดต่ำกว่าเดิม -> วันนี้ 0
      (DateTime(2026, 10, 3, 9), 12),
    ]);
    expect(v.sublist(0, 3), [9, 0, 3]);
  });
}
