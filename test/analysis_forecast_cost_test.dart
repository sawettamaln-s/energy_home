// เทสยอดเงินคาดการณ์บิลรอบถัดไป (AnalysisService.forecastCostFromUnits):
// ทายหน่วยก่อน แล้วคิดเงินด้วยตารางอัตรา — ยอดเงินต้องเท่ากับหน่วยที่ทายได้
// คิดตามอัตราจริงเสมอ ไม่ใช่เอายอดเงินไปคูณตัวคูณฤดูกาล
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:energy_home/utils/tariff_tables.dart';
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

  test('ไม่มีบิลที่มีหน่วยเลย -> แปลงยอดเงินกลับเป็นหน่วยด้วยตารางอัตรา แล้วทายหน่วย', () {
    final bills = [bill(5, 0, 1800), bill(6, 0, 1400)];
    final cost = service.forecastCostFromUnits(
      bills,
      costSelector: (b) => b.electricityCost,
      usedSelector: (b) => b.electricityUsed,
      price: priceNormal,
      area: 'bangkok',
      meterType: 'normal',
    );
    // 1,400 บาทของบิลล่าสุด = หน่วยเต็มที่มากที่สุดที่ไม่เกิน 1,400 บาท
    final units = TariffTables.unitsForBudget(
        1400, (u) => priceNormal(units: u, peakUnits: 0, offPeakUnits: 0))!;
    expect(cost, EnergyCalculator.electricityCost(unitsForecast([bill(6, units.toDouble(), 0)]), ftRate: ft));
    // ไม่ใช่ยอดเงิน × ตัวคูณฤดูกาล
    expect(cost, isNot(service.forecastNextMonth(bills,
        selector: (b) => b.electricityCost, area: 'bangkok', meterType: 'normal')));
  });

  test('TOU ไม่มีบิลแยก On/Off-Peak -> ใช้ยอดเงินบิลล่าสุดตรงๆ ไม่ปรับฤดูกาล', () {
    final bills = [bill(5, 0, 1800), bill(6, 0, 1400)];
    double tou(List<BillModel> bills) => service.forecastCostFromUnits(
          bills,
          costSelector: (b) => b.electricityCost,
          usedSelector: (b) => b.electricityUsed,
          price: priceTou,
          peakSelector: (b) => b.electricityPeakUsed,
          offPeakSelector: (b) => b.electricityOffPeakUsed,
          area: 'bangkok',
          meterType: 'tou',
        );
    expect(tou(bills), 1400);
    expect(
        service.canForecastFromUnits(bills,
            usedSelector: (b) => b.electricityUsed,
            peakSelector: (b) => b.electricityPeakUsed,
            offPeakSelector: (b) => b.electricityOffPeakUsed),
        isFalse);
  });

  group('แท่งคาดการณ์ในกราฟ (forecastChartMonths)', () {
    final bills = [bill(4, 320, 1500), bill(5, 380, 1800), bill(6, 300, 1400)];
    double costFor(List<BillModel> basis, DateTime target) => service.forecastCostFromUnits(
          basis,
          costSelector: (b) => b.electricityCost,
          usedSelector: (b) => b.electricityUsed,
          price: priceNormal,
          area: 'bangkok',
          meterType: 'normal',
          targetMonth: target,
        );
    CurrentCycleForecast cycle({bool projected = true}) => CurrentCycleForecast(
          currentCost: 600,
          forecastCost: 1500,
          currentUnits: 150,
          forecastUnits: 358,
          daysElapsed: 12,
          remainingDays: 19,
          cycleLengthDays: 31,
          billMonth: DateTime(2026, 7, 1),
          projected: projected,
        );

    test('ยังไม่มีบันทึกรอบนี้ -> 3 เดือนถัดจากบิลล่าสุด ทายจากบิลที่ปิดแล้ว', () {
      final costs = service.forecastChartMonths(bills,
          currentCycle: null, isWater: false, forecastFor: costFor, pick: (c) => c.forecastCost);
      expect(costs, [for (final m in [7, 8, 9]) costFor(bills, DateTime(2026, m, 1))]);
    });

    test('รอบนี้คาดการณ์ได้ -> แท่งรอบนี้ใช้ยอดคาดการณ์ เดือนถัดไปทายต่อจากรอบนี้', () {
      final costs = service.forecastChartMonths(bills,
          currentCycle: cycle(), isWater: false, forecastFor: costFor, pick: (c) => c.forecastCost);
      expect(costs[0], 1500);
      // ส.ค. = 358 หน่วยของรอบ ก.ค. ÷ ตัวคูณ ก.ค. × ตัวคูณ ส.ค. แล้วคิดเงิน
      final current = bill(7, 358, 1500);
      expect(costs[1], EnergyCalculator.electricityCost(unitsForecast([current]), ftRate: ft));
      expect(costs[1], isNot(costFor(bills, DateTime(2026, 8, 1))));
    });

    test('บันทึกรอบนี้ยังไม่ถึง 1 วัน -> ไม่ใช้รอบนี้เป็นฐาน', () {
      final costs = service.forecastChartMonths(bills,
          currentCycle: cycle(projected: false),
          isWater: false,
          forecastFor: costFor,
          pick: (c) => c.forecastCost);
      expect(costs, [for (final m in [7, 8, 9]) costFor(bills, DateTime(2026, m, 1))]);
    });
  });

  test('พยากรณ์เดือนถัดไปใช้บิลล่าสุด EnergyForecaster.seasonalRecentMonths เดือน', () {
    // บิลก่อนหน้าใช้ไฟต่างกันมาก ผลต้องขึ้นกับบิลล่าสุดเท่านั้น
    final a = [bill(4, 100, 0), bill(5, 900, 0), bill(6, 300, 0)];
    final b = [bill(4, 800, 0), bill(5, 50, 0), bill(6, 300, 0)];
    expect(EnergyForecaster.seasonalRecentMonths, 1);
    expect(unitsForecast(a), unitsForecast(b));
    expect(unitsForecast(a), unitsForecast([bill(6, 300, 0)]));
  });
}
