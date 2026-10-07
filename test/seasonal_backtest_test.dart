// เทสแกนของสคริปต์ทดลองเส้นฤดูกาลเฉพาะบ้าน (tool/seasonal_backtest/seasonal_backtest.dart)
import 'package:flutter_test/flutter_test.dart';

import '../tool/seasonal_backtest/seasonal_backtest.dart';

void main() {
  // บ้านที่ใช้ไฟตามรูปแบบฤดูกาลเดียวกันทุกปี: เดือน 4-5 ใช้ 150 นอกนั้น 100
  MonthlySeries seasonalHouse({double scale = 1}) => {
        for (var k = monthKey(2022, 10); k <= monthKey(2024, 10); k++)
          k: (monthOf(k) == 4 || monthOf(k) == 5 ? 150 : 100) * scale,
      };

  test('เส้นประเทศจาก 12 เดือนแรก เฉลี่ยเท่ากับ 1 และเดือนร้อนสูงกว่า', () {
    final curve = nationalCurve([seasonalHouse(), seasonalHouse(scale: 2)], monthKey(2022, 10));
    expect(curve.reduce((a, b) => a + b) / 12, closeTo(1, 1e-9));
    expect(curve[3], greaterThan(curve[0]));
    expect(curve[3] / curve[0], closeTo(1.5, 1e-9));
  });

  test('รูปแบบฤดูกาลคงที่ -> วิธีของแอปทายถูกทุกเดือน แต่ "เท่าเดือนก่อน" พลาดช่วงเปลี่ยนฤดู', () {
    final houses = [seasonalHouse(), seasonalHouse(scale: 1.5)];
    final curve = nationalCurve(houses, monthKey(2022, 10));
    final targets = [for (var k = monthKey(2023, 10); k <= monthKey(2024, 10); k++) k];
    expect(score(houses, targets, appSeasonal(curve), fullHistory).mape, lessThan(1e-6));
    expect(score(houses, targets, appSeasonal(curve, window: 1), fullHistory).mape, lessThan(1e-6));
    expect(score(houses, targets, lastMonth(), fullHistory).mape, greaterThan(1));
  });

  test('ผสมเส้นบ้าน: λ = ∞ ได้เส้นประเทศ, λ = 0 ได้เส้นของบ้านเอง', () {
    final national = List<double>.filled(12, 1);
    final personal = List<double>.generate(12, (i) => i == 3 ? 2 : 1);
    expect(blend(national, personal, double.infinity), national);
    expect(blend(national, personal, 0)[3], 2);
    expect(blend(national, personal, 1)[3], 1.5);
  });
}
