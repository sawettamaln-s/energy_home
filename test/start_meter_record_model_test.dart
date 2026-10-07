// เทสเดือนแรกที่เริ่มติดตาม (StartMeterRecordModel.trackingStartKey) — ขอบเขตย้อนหลัง
// ของการหาเดือนที่ขาดบิลและการไล่ปิดบิลย้อนหลัง
import 'package:energy_home/models/start_meter_record_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StartMeterRecordModel record(int year, int month) => StartMeterRecordModel(
        id: '$year-$month',
        uid: 'u',
        electricityValue: 1,
        waterValue: 0,
        billingMonth: month,
        billingYear: year,
        recordedAt: DateTime(year, month),
      );

  test('ใช้ใบแรกสุดที่กรอก เมื่อเก่ากว่าเดือนตั้งต้นของรอบปัจจุบัน', () {
    final key = StartMeterRecordModel.trackingStartKey(
      [record(2026, 6), record(2026, 3), record(2026, 5)],
      startYear: 2026,
      startMonth: 6,
    );
    expect(key, 2026 * 12 + 3);
  });

  test('ยังไม่มีประวัติ -> ใช้เดือนตั้งต้น (ตอนสมัครคือเดือนที่สมัคร)', () {
    expect(StartMeterRecordModel.trackingStartKey([], startYear: 2026, startMonth: 9), 2026 * 12 + 9);
  });

  test('ไม่มีทั้งประวัติและเดือนตั้งต้น -> 0 (ไม่รู้)', () {
    expect(StartMeterRecordModel.trackingStartKey([], startYear: 0, startMonth: 0), 0);
  });
}
