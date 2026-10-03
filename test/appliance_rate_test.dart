// เทสอัตราค่าไฟต่อหน่วยที่ใช้ประมาณค่าไฟอุปกรณ์ (lib/utils/appliance_rate.dart)
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/utils/appliance_rate.dart';
import 'package:flutter_test/flutter_test.dart';

BillModel _bill(int year, int month, {double used = 0, double cost = 0}) =>
    BillModel(
      id: '${year}_$month',
      uid: 'u',
      year: year,
      month: month,
      electricityUsed: used,
      electricityCost: cost,
    );

void main() {
  test('ยังไม่มีบิล -> ใช้ค่าเฉลี่ยประมาณการ', () {
    final rate = ApplianceRate.fromBills([]);
    expect(rate.perUnit, ApplianceRate.defaultPerUnit);
    expect(rate.isFromBill, isFalse);
  });

  test('ใช้บิลเดือนล่าสุดที่มีทั้งค่าไฟและหน่วย ไม่ว่าจะเรียงแบบไหน', () {
    final rate = ApplianceRate.fromBills([
      _bill(2026, 8, used: 400, cost: 2000), // 5.00 บาท/หน่วย (ล่าสุด)
      _bill(2026, 6, used: 300, cost: 1200),
      _bill(2026, 7, used: 350, cost: 1400),
    ]);
    expect(rate.perUnit, 5.0);
    expect(rate.sourceBill!.month, 8);
  });

  test('บิลล่าสุดไม่มีหน่วยที่ใช้ -> ข้ามไปใช้บิลก่อนหน้า', () {
    final rate = ApplianceRate.fromBills([
      _bill(2026, 7, used: 300, cost: 1200), // 4.00 บาท/หน่วย
      _bill(2026, 8, used: 0, cost: 1500),
    ]);
    expect(rate.perUnit, 4.0);
  });

  test('อัตราผิดปกติ (กรอกหน่วยผิด) -> ไม่นำมาใช้', () {
    final rate = ApplianceRate.fromBills([
      _bill(2026, 8, used: 10, cost: 2000), // 200 บาท/หน่วย
    ]);
    expect(rate.isFromBill, isFalse);
    expect(rate.perUnit, ApplianceRate.defaultPerUnit);
  });
}
