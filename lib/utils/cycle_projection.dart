import '../models/electricity_log_model.dart';
import '../models/water_log_model.dart';
import 'calculator.dart';
import 'forecaster.dart';

// ยอดคาดการณ์สิ้นรอบบิลของไฟฟ้าหรือน้ำ 1 ฝั่ง
//
// คาดการณ์เป็น "หน่วย" ด้วยอัตราต่อวัน (EnergyForecaster.projectToCycleEnd)
// แล้วคิดเงินจากหน่วยนั้นด้วยตารางอัตราจริง (EnergyCalculator) — ไม่คูณยอดเงิน
// ตรงๆ เพราะยอดเงินมีส่วนที่ไม่ขึ้นกับหน่วย (ค่าบริการรายเดือน)
// ถ้าคูณตามจำนวนวัน ส่วนนี้จะถูกนับซ้ำหลายเท่าจนยอดสูงเกินจริงช่วงต้นรอบ
// และอัตราขั้นบันไดก็ไม่ได้เพิ่มเป็นเส้นตรงตามหน่วย
class CycleProjection {
  final double units; // หน่วยรวม ณ สิ้นรอบ
  final double peakUnits; // TOU เท่านั้น (ไม่ใช่ TOU = 0)
  final double offPeakUnits; // TOU เท่านั้น (ไม่ใช่ TOU = 0)
  final double cost; // บาท ณ สิ้นรอบ
  // false = ยังหาอัตราต่อวันไม่ได้ (ไม่มีบันทึก หรือบันทึกห่างจากต้นรอบไม่ถึง
  // 1 วัน) ค่าทั้งหมดเป็นยอดปัจจุบัน
  final bool projected;

  const CycleProjection({
    required this.units,
    required this.cost,
    required this.projected,
    this.peakUnits = 0,
    this.offPeakUnits = 0,
  });

  static const empty = CycleProjection(units: 0, cost: 0, projected: false);
}

double? _project(double total, DateTime cycleStart, DateTime cycleEnd,
        DateTime lastRecordedAt) =>
    EnergyForecaster.projectToCycleEnd(
      currentTotal: total,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      lastRecordedAt: lastRecordedAt,
    );

// [startPeak]/[startOffPeak] = เลขมิเตอร์ต้นรอบของรอบที่ log นี้อยู่ (TOU เท่านั้น)
// [tariff] = ประเภทอัตราของมิเตอร์ปกติ (UserModel.electricityTariff)
Future<CycleProjection> projectElectricityToCycleEnd({
  required ElectricityLogModel? latest,
  required DateTime cycleStart,
  required DateTime cycleEnd,
  required String meterType,
  required String area,
  double startPeak = 0,
  double startOffPeak = 0,
  String tariff = EnergyCalculator.tariffStandard,
}) async {
  if (latest == null) return CycleProjection.empty;
  final isTou = meterType == 'tou';
  final peakNow = isTou
      ? EnergyCalculator.calculateUsed(latest.peakMeterValue ?? 0, startPeak)
      : 0.0;
  final offPeakNow = isTou
      ? EnergyCalculator.calculateUsed(latest.offPeakMeterValue ?? 0, startOffPeak)
      : 0.0;

  final units =
      _project(latest.usedFromStart, cycleStart, cycleEnd, latest.date);
  if (units == null) {
    return CycleProjection(
      units: latest.usedFromStart,
      peakUnits: peakNow,
      offPeakUnits: offPeakNow,
      cost: latest.cost,
      projected: false,
    );
  }
  final peak = isTou
      ? _project(peakNow, cycleStart, cycleEnd, latest.date) ?? peakNow
      : 0.0;
  final offPeak = isTou
      ? _project(offPeakNow, cycleStart, cycleEnd, latest.date) ?? offPeakNow
      : 0.0;

  // บันทึกตรงวันตัดรอบพอดี หน่วยไม่เพิ่ม — ใช้ยอดเงินของ log ตามที่บันทึกไว้
  final cost = units <= latest.usedFromStart
      ? latest.cost
      : await EnergyCalculator.calculateElectricityByType(
          units: units,
          meterType: meterType,
          area: area,
          peakUnits: peak,
          offPeakUnits: offPeak,
          tariff: tariff,
        );
  return CycleProjection(
    units: units,
    peakUnits: peak,
    offPeakUnits: offPeak,
    cost: cost,
    projected: true,
  );
}

CycleProjection projectWaterToCycleEnd({
  required WaterLogModel? latest,
  required DateTime cycleStart,
  required DateTime cycleEnd,
  required String area,
}) {
  if (latest == null) return CycleProjection.empty;
  final units =
      _project(latest.usedFromStart, cycleStart, cycleEnd, latest.date);
  if (units == null) {
    return CycleProjection(
        units: latest.usedFromStart, cost: latest.cost, projected: false);
  }
  final cost = units <= latest.usedFromStart
      ? latest.cost
      : EnergyCalculator.calculateWater(units, area);
  return CycleProjection(units: units, cost: cost, projected: true);
}
