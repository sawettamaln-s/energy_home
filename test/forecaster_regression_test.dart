// เทสเส้นแนวโน้ม (EnergyForecaster.linearRegression) ที่ใช้คาดการณ์เมื่อยัง
// ไม่รู้พื้นที่/ประเภทมิเตอร์ — ครอบกรณีเดือนติดกันและกรณีมีเดือนขาดหาย
import 'package:energy_home/utils/forecaster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('เดือนติดกัน: ไม่ส่งลำดับเดือน -> ต่อเส้นตรงไปเดือนถัดไป', () {
    final forecast = EnergyForecaster.linearRegression(
      monthlyValues: [100, 200, 300],
      forecastMonth: 4,
    );
    expect(forecast, 400);
  });

  test('มีเดือนขาดหาย: วางจุดตามลำดับเดือนจริง ความชันไม่เพี้ยน', () {
    // เพิ่มเดือนละ 100 บาท แต่เดือนที่ 3-4 ไม่มีข้อมูล
    final forecast = EnergyForecaster.linearRegression(
      monthlyValues: [100, 200, 500],
      monthIndexes: [1, 2, 5],
      forecastMonth: 6,
    );
    expect(forecast, 600);
  });

  test('ลำดับเดือนยาวไม่เท่าข้อมูล -> แจ้งข้อผิดพลาด', () {
    expect(
      () => EnergyForecaster.linearRegression(
        monthlyValues: [100, 200],
        monthIndexes: [1],
        forecastMonth: 3,
      ),
      throwsArgumentError,
    );
  });
}
