// เทส EnergyForecaster.projectToCycleEnd (lib/utils/forecaster.dart) — การ
// คาดการณ์ยอดสิ้นรอบจากอัตราเฉลี่ยต่อวัน ที่แดชบอร์ด/หน้าวิเคราะห์/แจ้งเตือน
// "แนวโน้มสูงกว่าเดือนก่อน" ใช้ร่วมกัน
//
// จุดสำคัญ: ต้องคิดอัตราตามจำนวนวันจริง ไม่ใช่ตามจำนวนครั้งที่บันทึก —
// คนที่บันทึกทุกวันกับคนที่บันทึกทุก 3 วันด้วยการใช้งานเท่ากัน ต้องได้
// ยอดคาดการณ์เท่ากัน
import 'package:energy_home/utils/forecaster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // รอบบิล 30 วัน: 1 มิ.ย. - 1 ก.ค. 2026
  final cycleStart = DateTime(2026, 6, 1);
  final cycleEnd = DateTime(2026, 7, 1);

  test('ใช้วันละ 10 บาท ณ วันที่ 10 ของรอบ -> คาดการณ์ 300 บาทตอนสิ้นรอบ', () {
    final forecast = EnergyForecaster.projectToCycleEnd(
      currentTotal: 100,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: DateTime(2026, 6, 11),
    );
    expect(forecast, 300);
  });

  test('บันทึกทุก 3 วัน (ครั้งละ +30 บาท = วันละ 10 บาท) -> คาดการณ์ 300 ไม่ใช่เกินจริง',
      () {
    // บันทึกวันที่ 4, 7, 10 ยอดสะสม 30, 60, 90 — ถ้าเอา "+30 ต่อครั้ง" ไปคิด
    // เป็นวันละ 30 จะได้ 90 + 30 × 21 = 720 ซึ่งเกินจริง 2 เท่ากว่า ฟังก์ชันนี้
    // ใช้แค่ยอดสะสมกับวันที่ จึงได้อัตราวันละ 10 ถูกต้อง
    final forecast = EnergyForecaster.projectToCycleEnd(
      currentTotal: 90,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: DateTime(2026, 6, 10),
    );
    expect(forecast, 300);
  });

  test('บันทึกล่าสุดเมื่อหลายวันก่อน -> นับวันที่เหลือจากวันที่บันทึก ไม่ใช่จากวันนี้',
      () {
    // บันทึกล่าสุดวันที่ 16 (ผ่านไป 15 วัน ใช้ไป 150) เหลือ 15 วัน -> 300
    final forecast = EnergyForecaster.projectToCycleEnd(
      currentTotal: 150,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: DateTime(2026, 6, 16),
    );
    expect(forecast, 300);
  });

  test('บันทึกห่างจากต้นรอบไม่ถึง 1 วัน -> ยังคาดการณ์ไม่ได้ (null)', () {
    final forecast = EnergyForecaster.projectToCycleEnd(
      currentTotal: 20,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: DateTime(2026, 6, 1, 20),
    );
    expect(forecast, isNull);
  });

  test('บันทึกตรงวันตัดรอบพอดี -> ไม่มีวันเหลือ ได้ยอดที่ใช้ไปแล้ว', () {
    final forecast = EnergyForecaster.projectToCycleEnd(
      currentTotal: 300,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: cycleEnd,
    );
    expect(forecast, 300);
  });

  group('ถ่วงด้วยหน่วยต่อวันของบิลรอบก่อน', () {
    test('วันแรกใช้เยอะผิดปกติ -> ยอดคาดการณ์ถูกดึงเข้าหาบิลก่อน', () {
      // วันแรกใช้ 30 (ปกติวันละ 10) — ไม่ถ่วง = 900, ถ่วง 5 วัน = (30+50)/6 ต่อวัน
      final raw = EnergyForecaster.projectToCycleEnd(
        currentTotal: 30,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        lastRecordedAt: DateTime(2026, 6, 2),
      );
      final blended = EnergyForecaster.projectToCycleEnd(
        currentTotal: 30,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        lastRecordedAt: DateTime(2026, 6, 2),
        priorPerDay: 10,
      );
      expect(raw, 900);
      expect(blended, closeTo(30 + 80 / 6 * 29, 0.01));
    });

    test('ยิ่งบันทึกนาน ข้อมูลรอบนี้ยิ่งมีน้ำหนัก', () {
      // วันละ 20 ตลอด 20 วัน บิลก่อนวันละ 10 -> อัตรา (400+50)/25 = 18
      final forecast = EnergyForecaster.projectToCycleEnd(
        currentTotal: 400,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        lastRecordedAt: DateTime(2026, 6, 21),
        priorPerDay: 10,
      );
      expect(forecast, closeTo(400 + 18 * 10, 0.01));
    });

    test('ยังไม่ได้ใช้เลย (ยอดสะสม 0) -> ไม่ถ่วง คาดการณ์ 0', () {
      final forecast = EnergyForecaster.projectToCycleEnd(
        currentTotal: 0,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        lastRecordedAt: DateTime(2026, 6, 4),
        priorPerDay: 10,
      );
      expect(forecast, 0);
    });
  });
}
