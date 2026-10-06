// เทสสูตรหน่วยไฟของเครื่องใช้ไฟฟ้า (lib/utils/appliance_energy.dart) — ตู้เย็น/แอร์
// คิดเฉพาะช่วงที่คอมเพรสเซอร์ทำงานโดยประมาณ อุปกรณ์อื่นคิดเต็มทุกชั่วโมง
import 'package:energy_home/models/appliance_model.dart';
import 'package:energy_home/utils/appliance_energy.dart';
import 'package:flutter_test/flutter_test.dart';

ApplianceModel _appliance(double watt, String? iconKey, String end, {List<int> days = const [0, 1, 2, 3, 4, 5, 6]}) =>
    ApplianceModel(
      id: 'a',
      uid: 'u',
      name: 'x',
      watt: watt,
      iconKey: iconKey,
      schedules: [ScheduleModel(days: days, startTime: '00:00', endTime: end)],
    );

void main() {
  test('ตู้เย็น 100 วัตต์ เปิด 24 ชม. -> 0.84 หน่วย/วัน ไม่ใช่ 2.4', () {
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(100, 'kitchen', '24:00')), closeTo(0.84, 1e-9));
  });

  test('แอร์ 900 วัตต์ เปิด 8 ชม. -> คิด 60% = 4.32 หน่วย/วัน', () {
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(900, 'ac_unit', '08:00')), closeTo(4.32, 1e-9));
  });

  test('อุปกรณ์อื่น/เพิ่มเอง คิดเต็มทุกชั่วโมง', () {
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(1200, 'iron', '01:00')), closeTo(1.2, 1e-9));
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(100, null, '24:00')), closeTo(2.4, 1e-9));
  });

  test('หน่วยต่อเดือนคิดตามจำนวนวันที่ใช้ต่อสัปดาห์', () {
    // เตารีด 1,200 วัตต์ ชั่วโมงละครั้ง สัปดาห์ละ 2 วัน -> 1.2 × 2/7 × 30
    expect(ApplianceEnergy.kWhForPeriod(_appliance(1200, 'iron', '01:00', days: [5, 6]), 30),
        closeTo(1.2 * 2 / 7 * 30, 1e-9));
  });

  test('ข้อมูลเก่าที่ไม่มี iconKey แต่ชื่อตรงรายการ (ตู้เย็น) -> คิดแบบตู้เย็น', () {
    final old = ApplianceModel(
      id: 'a',
      uid: 'u',
      name: 'ตู้เย็น',
      watt: 100,
      schedules: [ScheduleModel(days: const [0, 1, 2, 3, 4, 5, 6], startTime: '00:00', endTime: '24:00')],
    );
    expect(ApplianceEnergy.typeKey(old), 'kitchen');
    expect(ApplianceEnergy.kWhPerActiveDay(old), closeTo(0.84, 1e-9));
  });
}
