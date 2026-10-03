// เทสการคาดการณ์ยอดสิ้นรอบ (lib/utils/cycle_projection.dart): ประมาณหน่วย
// ถึงวันตัดรอบก่อน แล้วคิดเงินด้วยตารางอัตราจริง — ไม่คูณยอดเงินตามจำนวนวัน
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/water_log_model.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/cycle_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // รอบ 30 วัน บันทึกวันที่ 3 (ผ่านไป 3 วัน) → หน่วยทั้งรอบ = x10
  final cycleStart = DateTime(2026, 6, 1);
  final cycleEnd = DateTime(2026, 7, 1);
  final day3 = DateTime(2026, 6, 4);

  test('ค่าน้ำ: ค่าขั้นต่ำ/ค่าบริการไม่ถูกคูณตามจำนวนวัน', () {
    final costNow = EnergyCalculator.calculateWater(2, 'bangkok');
    final p = projectWaterToCycleEnd(
      latest: WaterLogModel(
          id: 'w', uid: 'u', date: day3, meterValue: 102,
          usedFromStart: 2, cost: costNow),
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      area: 'bangkok',
    );
    expect(p.projected, isTrue);
    expect(p.units, 20);
    expect(p.cost, EnergyCalculator.calculateWater(20, 'bangkok'));
    // คูณยอดเงินตรงๆ จะได้สูงกว่านี้มาก (ค่าขั้นต่ำถูกคูณ 10 เท่า)
    expect(p.cost, lessThan(costNow * 10 / 2));
  });

  test('ค่าไฟปกติ: คิดเงินจากหน่วยที่ประมาณได้', () async {
    final costNow = await EnergyCalculator.calculateElectricity(30, 'bangkok');
    final p = await projectElectricityToCycleEnd(
      latest: ElectricityLogModel(
          id: 'e', uid: 'u', date: day3, meterValue: 1030,
          usedFromStart: 30, cost: costNow),
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      meterType: 'normal',
      area: 'bangkok',
    );
    expect(p.units, 300);
    expect(p.cost, await EnergyCalculator.calculateElectricity(300, 'bangkok'));
    expect(p.cost, lessThan(costNow * 10));
  });

  test('TOU: ประมาณ On-Peak/Off-Peak แยกกันจากเลขต้นรอบ', () async {
    final p = await projectElectricityToCycleEnd(
      latest: ElectricityLogModel(
          id: 'e', uid: 'u', date: day3, meterValue: 30,
          peakMeterValue: 1010, offPeakMeterValue: 520,
          usedFromStart: 30, cost: 100),
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      meterType: 'tou',
      area: 'bangkok',
      startPeak: 1000,
      startOffPeak: 500,
    );
    expect(p.peakUnits, 100);
    expect(p.offPeakUnits, 200);
    expect(p.units, 300);
    expect(
        p.cost,
        await EnergyCalculator.calculateElectricityTOU(
            peakUnits: 100, offPeakUnits: 200));
  });

  test('บันทึกห่างจากต้นรอบไม่ถึง 1 วัน -> ใช้ยอดปัจจุบัน ไม่ถือว่าคาดการณ์', () {
    final p = projectWaterToCycleEnd(
      latest: WaterLogModel(
          id: 'w', uid: 'u', date: DateTime(2026, 6, 1, 12),
          meterValue: 101, usedFromStart: 1, cost: 48.15),
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      area: 'bangkok',
    );
    expect(p.projected, isFalse);
    expect(p.cost, 48.15);
  });

  test('ยังไม่มีบันทึก -> ศูนย์ทั้งหมด', () async {
    final p = await projectElectricityToCycleEnd(
      latest: null,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      meterType: 'normal',
      area: 'bangkok',
    );
    expect(p.projected, isFalse);
    expect(p.cost, 0);
  });
}
