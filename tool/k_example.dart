// k_example.dart
//
// ตัวอย่างสมมติสำหรับอธิบายสูตรคาดการณ์ยอดสิ้นรอบ เทียบ k = 0, 3 และ 5 บนบิลต้นรอบ
// เดียวกันและการจดมิเตอร์ชุดเดียวกัน คำนวณด้วยฟังก์ชันจริงของแอป
// (EnergyForecaster.projectToCycleEnd, TariffTables) ไม่ใช่หลักฐานความแม่นยำ
// (หลักฐานอยู่ที่ docs/k_cv/ จาก tool/backtest_cycle_k_cv.dart)
//
// สมมติ: วันตัดรอบวันที่ 9 (รอบ 9 ต.ค. - 8 พ.ย. 2569) กทม. มิเตอร์ปกติ Ft 0.1623
// บิลรอบก่อน ไฟฟ้า 10 หน่วย/วัน น้ำ 0.5 ลบ.ม./วัน ใช้จริงวันธรรมดาน้อย เสาร์-อาทิตย์มาก
// จดเวลา 20:00 เลขมิเตอร์อ่านได้เป็นจำนวนเต็ม
//
// วิธีใช้: dart run tool/k_example.dart > docs/k_cv/k_example_data.txt
//   แล้ววาดรูป python tool/plot_k_example.py docs/k_cv/k_example_data.txt assets/fonts docs/k_cv
// ผลต่อบรรทัด: วันที่|วันที่ผ่านไป|เลขมิเตอร์|ใช้ไปแล้ว|k0 หน่วย|k0 บาท|k3 หน่วย|k3 บาท|k5 หน่วย|k5 บาท
// บรรทัดที่ขึ้นต้นด้วย # = ชื่อยูทิลิตี้|หน่วยจริงทั้งรอบ|บาทจริงทั้งรอบ
import 'dart:io';

import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/tariff_tables.dart';

const ft = 0.1623;
final start = DateTime(2026, 10, 9); // วันตัดรอบ 9 → รอบ 9 ต.ค. - 8 พ.ย.
final end = DateTime(2026, 11, 9);

// การใช้จริงรายวัน: เสาร์-อาทิตย์ใช้หนัก
double elecDay(DateTime d) => d.weekday >= 6 ? 16 : 9;
double waterDay(DateTime d) => d.weekday >= 6 ? 0.8 : 0.45;

// เลขสะสมตั้งแต่ต้นรอบถึงเวลา t (ใช้เท่าๆ กันตลอดวัน)
double usedUntil(DateTime t, double Function(DateTime) perDay) {
  var sum = 0.0;
  for (var d = start; d.isBefore(t); d = d.add(const Duration(days: 1))) {
    final dayEnd = d.add(const Duration(days: 1));
    final upto = t.isBefore(dayEnd) ? t : dayEnd;
    sum += perDay(d) * upto.difference(d).inMinutes / 1440;
  }
  return sum;
}

void run(String name, double startMeter, double Function(DateTime) perDay, double priorPerDay,
    double Function(double) price, String unit) {
  final actual = usedUntil(end, perDay);
  stdout.writeln('#$name|${actual.toStringAsFixed(3)}|${price(actual).toStringAsFixed(2)}');
  for (final day in [2, 3, 5, 10, 19, 20]) {
    final t = start.add(Duration(days: day, hours: 20));
    final meter = (startMeter + usedUntil(t, perDay)).floorToDouble(); // มิเตอร์อ่านได้เป็นจำนวนเต็ม
    final used = meter - startMeter;
    String p(double k) {
      final u = EnergyForecaster.projectToCycleEnd(
          currentTotal: used, cycleStart: start, cycleEnd: end, lastRecordedAt: t,
          priorPerDay: priorPerDay, priorWeight: k)!;
      return '${u.toStringAsFixed(1)}|${price(u).toStringAsFixed(2)}';
    }
    final dd = t.difference(start).inMinutes / 1440;
    stdout.writeln('${t.day}/${t.month}|${dd.toStringAsFixed(3)}|${meter.toStringAsFixed(0)}|${used.toStringAsFixed(0)}|${p(0)}|${p(3)}|${p(5)}');
  }
}

void main() {
  run('ไฟฟ้า', 12345, elecDay, 300 / 30, (u) => TariffTables.electricity(u, ftRate: ft), 'หน่วย');
  run('น้ำ', 1234, waterDay, 15 / 30, (u) => TariffTables.waterMwaCost(u), 'ลบ.ม.');
}
