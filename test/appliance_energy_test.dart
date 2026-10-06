// เทสสูตรหน่วยไฟของเครื่องใช้ไฟฟ้า (lib/utils/appliance_energy.dart) — สูตร
// มาตรฐาน วัตต์ × ชั่วโมงที่ใช้ ÷ 1,000 ทุกประเภทเหมือนกัน
import 'package:energy_home/models/appliance_model.dart';
import 'package:energy_home/utils/appliance_energy.dart';
import 'package:flutter_test/flutter_test.dart';

ApplianceModel _appliance(double watt, String? iconKey, String end,
        {String name = 'x', List<int> days = const [0, 1, 2, 3, 4, 5, 6]}) =>
    ApplianceModel(
      id: 'a',
      uid: 'u',
      name: name,
      watt: watt,
      iconKey: iconKey,
      schedules: [ScheduleModel(days: days, startTime: '00:00', endTime: end)],
    );

void main() {
  test('วัตต์ × ชั่วโมง ÷ 1,000 — ทุกประเภทคิดสูตรเดียวกัน', () {
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(900, 'ac_unit', '08:00')), closeTo(7.2, 1e-9));
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(100, 'kitchen', '10:00')), closeTo(1.0, 1e-9));
    expect(ApplianceEnergy.kWhPerActiveDay(_appliance(1200, 'iron', '01:00')), closeTo(1.2, 1e-9));
  });

  test('หน่วยต่อเดือนคิดตามจำนวนวันที่ใช้ต่อสัปดาห์', () {
    // เตารีด 1,200 วัตต์ วันละ 1 ชม. สัปดาห์ละ 2 วัน -> 1.2 × 2/7 × 30
    expect(ApplianceEnergy.kWhForPeriod(_appliance(1200, 'iron', '01:00', days: [5, 6]), 30),
        closeTo(1.2 * 2 / 7 * 30, 1e-9));
  });

  test('ข้อมูลเก่าที่ไม่มี iconKey จับประเภทจากชื่อ', () {
    expect(ApplianceEnergy.typeKey(_appliance(100, null, '24:00', name: 'ตู้เย็น')), 'kitchen');
    expect(ApplianceEnergy.typeKey(_appliance(100, null, '24:00', name: 'เครื่องของฉัน')), isNull);
  });
}
