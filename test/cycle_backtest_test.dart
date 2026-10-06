// เทสแกนคำนวณของสคริปต์วัดความแม่นยำยอดสิ้นรอบ (tool/cycle_backtest/cycle_backtest.dart)
import 'package:flutter_test/flutter_test.dart';

import '../tool/cycle_backtest/cycle_backtest.dart';

void main() {
  // บ้านที่ใช้วันละ 10 หน่วยคงที่ วันตัดรอบวันที่ 1 จดมิเตอร์ทุกวันเวลา 20:00
  List<Reading> dailyReadings(DateTime from, DateTime to, double perDay) => [
        for (var d = from; d.isBefore(to); d = d.add(const Duration(days: 1)))
          (
            at: DateTime(d.year, d.month, d.day, 20),
            usedFromStart: perDay * (DateTime(d.year, d.month, d.day, 20).difference(_cycleStartOf(d)).inMinutes / 1440),
          ),
      ];

  test('สร้างรอบจากเลขต้นรอบที่ติดกัน: หน่วยจริง = ต้นรอบถัดไป − ต้นรอบนี้', () {
    final cycles = buildCycles(
      starts: [
        (year: 2026, month: 3, value: 1000),
        (year: 2026, month: 4, value: 1310), // มี.ค. 31 วัน × 10
        (year: 2026, month: 5, value: 1610), // เม.ย. 30 วัน × 10
        (year: 2026, month: 6, value: 1920), // รอบสุดท้ายยังไม่ปิด -> ไม่วัด
      ],
      readings: dailyReadings(DateTime(2026, 3, 1), DateTime(2026, 6, 1), 10),
      billingDay: 1,
    );
    expect(cycles.map((c) => c.actualUnits), [310, 300, 310]);
    expect(cycles.first.priorPerDay, isNull);
    expect(cycles[1].priorPerDay, closeTo(10, 1e-9));
  });

  test('ใช้ไฟคงที่ -> ทุกวิธีที่ใช้ข้อมูลรอบนี้ทายถูก MAPE ≈ 0', () {
    final cycles = buildCycles(
      starts: [
        (year: 2026, month: 3, value: 1000),
        (year: 2026, month: 4, value: 1310),
        (year: 2026, month: 5, value: 1610),
        (year: 2026, month: 6, value: 1920),
      ],
      readings: dailyReadings(DateTime(2026, 3, 1), DateTime(2026, 6, 1), 10),
      billingDay: 1,
    );
    for (final k in weightGrid) {
      expect(overallMape(evaluate(cycles, k)), lessThan(0.5), reason: 'k=$k');
    }
  });

  test('รอบนี้ใช้มากกว่ารอบก่อน -> k ใหญ่ทายต่ำ (bias ติดลบ) ส่วน k=0 ไม่เอนเอียง', () {
    final readings = [
      ...dailyReadings(DateTime(2026, 3, 1), DateTime(2026, 4, 1), 10),
      ...dailyReadings(DateTime(2026, 4, 1), DateTime(2026, 5, 1), 20),
    ];
    final cycles = buildCycles(
      starts: [
        (year: 2026, month: 3, value: 1000),
        (year: 2026, month: 4, value: 1310),
        (year: 2026, month: 5, value: 1910),
      ],
      readings: readings,
      billingDay: 1,
    );
    final april = cycles.where((c) => c.start.month == 4).toList();
    expect(overallBias(evaluate(april, 0)).abs(), lessThan(0.5));
    expect(overallBias(evaluate(april, 21)), lessThan(-5));
    expect(bestWeight(april), 0);
  });

  test('cross-validation เลือก k จากรอบอื่นเท่านั้น และรายงานได้', () {
    final cycles = buildCycles(
      starts: [
        for (var m = 1; m <= 7; m++) (year: 2026, month: m, value: 1000.0 + (m - 1) * 300),
      ],
      readings: dailyReadings(DateTime(2026, 1, 1), DateTime(2026, 7, 1), 300 / 30),
      billingDay: 1,
    );
    final cv = crossValidate(cycles);
    expect(cv.chosen, hasLength(cycles.length));
    expect(report('ไฟฟ้า', cycles), contains('leave-one-cycle-out'));
  });
}

DateTime _cycleStartOf(DateTime d) => DateTime(d.year, d.month, 1);
