// เทสยอดเงินคาดการณ์บิลรอบถัดไป (AnalysisService.forecastCostFromUnits):
// ทายหน่วยก่อน แล้วคิดเงินด้วยตารางอัตรา — ยอดเงินต้องเท่ากับหน่วยที่ทายได้
// คิดตามอัตราจริงเสมอ ไม่ใช่เอายอดเงินไปคูณตัวคูณฤดูกาล
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AnalysisService(firestore: FakeFirebaseFirestore());
  const ft = 0.1623;

  double priceNormal({
    required double units,
    required double peakUnits,
    required double offPeakUnits,
  }) =>
      EnergyCalculator.electricityCost(units, ftRate: ft);

  double priceTou({
    required double units,
    required double peakUnits,
    required double offPeakUnits,
  }) =>
      EnergyCalculator.electricityTouCost(
          peakUnits: peakUnits, offPeakUnits: offPeakUnits, ftRate: ft);

  BillModel bill(int month, double used, double cost,
          {double peak = 0, double offPeak = 0}) =>
      BillModel(
        id: 'b$month',
        uid: 'u',
        year: 2026,
        month: month,
        electricityUsed: used,
        electricityPeakUsed: peak,
        electricityOffPeakUsed: offPeak,
        electricityCost: cost,
      );

  double unitsForecast(List<BillModel> bills) => service.forecastNextMonth(
        bills,
        selector: (b) => b.electricityUsed,
        area: 'bangkok',
        meterType: 'normal',
      );

  test('ยอดเงิน = หน่วยที่ทายได้ คิดตามตารางอัตรา', () {
    final bills = [bill(4, 320, 1500), bill(5, 380, 1800), bill(6, 300, 1400)];
    final cost = service.forecastCostFromUnits(
      bills,
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceNormal,
      area: 'bangkok',
      meterType: 'normal',
    );
    expect(cost, EnergyCalculator.electricityCost(unitsForecast(bills), ftRate: ft));
  });

  test('บิลที่มีแต่ยอดเงินไม่มีหน่วย ไม่ถูกนำมาทาย', () {
    final withUnits = [bill(5, 380, 1800), bill(6, 300, 1400)];
    final cost = service.forecastCostFromUnits(
      [bill(4, 0, 1500), ...withUnits],
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceNormal,
      area: 'bangkok',
      meterType: 'normal',
    );
    expect(cost,
        EnergyCalculator.electricityCost(unitsForecast(withUnits), ftRate: ft));
  });

  test('TOU แบ่งหน่วยที่ทายได้เป็น On/Off-Peak ตามสัดส่วนของบิลเดิม', () {
    // On-Peak 25% ของหน่วยรวมทุกบิล
    final bills = [
      bill(5, 400, 1700, peak: 100, offPeak: 300),
      bill(6, 400, 1700, peak: 100, offPeak: 300),
    ];
    final units = service.forecastNextMonth(
      bills,
      selector: (b) => b.electricityUsed,
      area: 'bangkok',
      meterType: 'tou',
    );
    final cost = service.forecastCostFromUnits(
      bills,
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceTou,
      peakSelector: (b) => b.electricityPeakUsed,
      offPeakSelector: (b) => b.electricityOffPeakUsed,
      area: 'bangkok',
      meterType: 'tou',
    );
    expect(
        cost,
        EnergyCalculator.electricityTouCost(
            peakUnits: units * 0.25, offPeakUnits: units * 0.75, ftRate: ft));
  });

  test('ไม่มีบิลที่มีหน่วยเลย -> ทายจากยอดเงินแทน', () {
    final bills = [bill(5, 0, 1800), bill(6, 0, 1400)];
    final cost = service.forecastCostFromUnits(
      bills,
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceNormal,
      area: 'bangkok',
      meterType: 'normal',
    );
    expect(
        cost,
        service.forecastNextMonth(bills,
            selector: (b) => b.electricityCost,
            area: 'bangkok',
            meterType: 'normal'));
  });

  test('หลายเดือนข้างหน้า เรียงตามเดือนถัดจากบิลล่าสุด', () {
    final bills = [bill(4, 320, 1500), bill(5, 380, 1800), bill(6, 300, 1400)];
    final costs = service.forecastNextMonthsCost(
      bills,
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceNormal,
      area: 'bangkok',
      meterType: 'normal',
    );
    expect(costs, [
      for (final m in [7, 8, 9])
        service.forecastCostFromUnits(
          bills,
          costSelector: (b) => b.electricityCost,
          usedSelector: (b) => b.electricityUsed,
          price: priceNormal,
          area: 'bangkok',
          meterType: 'normal',
          targetMonth: DateTime(2026, m, 1),
        ),
    ]);
  });
}
