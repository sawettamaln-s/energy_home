// เทสข้อสังเกตในหน้าวิเคราะห์ (AnalysisService.generateUtilityInsights) — แต่ละ
// ข้อต้องบอกชื่อบิลที่พูดถึง ข้อที่พูดถึงคนละรอบวางติดกันจึงไม่ดูขัดกันเอง
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AnalysisService(firestore: FakeFirebaseFirestore());

  BillModel bill(int month, double cost, {double units = 0}) => BillModel(
      id: 'b$month', uid: 'u', year: 2026, month: month, electricityCost: cost, electricityUsed: units);

  // หน่วยต่อวันแบบง่าย (รอบละ 30 วัน) — บิลไม่มีหน่วยคืน null เหมือนในแอป
  double? perDay(BillModel b) => b.electricityUsed > 0 ? b.electricityUsed / 30 : null;
  double bangkokFactor(int m) => service.seasonalFactorForMonth(
      month: m, area: 'bangkok', meterType: 'normal', isWater: false);

  List<String> trendInsights(List<BillModel> bills, {bool seasonal = true}) => service
      .generateUtilityInsights(
        label: 'ค่าไฟ',
        bills: bills,
        selector: (b) => b.electricityCost,
        mom: null,
        yoy: null,
        usagePerDay: perDay,
        usageLabel: 'การใช้ไฟ',
        seasonalFactor: seasonal ? bangkokFactor : null,
      )
      .map((i) => i.text)
      .where((t) => t.contains('ต่อเนื่อง 3 เดือน'))
      .toList();

  test('รอบนี้คาดว่าสูงขึ้น แต่บิลที่ปิดแล้วลดลง 3 เดือน -> ทั้งสองข้อบอกชื่อบิล', () {
    final bills = [bill(8, 1400, units: 350), bill(9, 1300, units: 325), bill(10, 1200, units: 300)];
    // บิล ต.ค. วันละ 10 หน่วย รอบ พ.ย. คาดว่า 372 หน่วยใน 31 วัน = วันละ 12 (+20%)
    final insights = service.generateUtilityInsights(
      label: 'ค่าไฟ',
      bills: bills,
      selector: (b) => b.electricityCost,
      mom: null,
      yoy: null,
      usagePerDay: perDay,
      usageLabel: 'การใช้ไฟ',
      currentCycle: CurrentCycleForecast(
        currentCost: 300,
        forecastCost: 1440,
        currentUnits: 60,
        forecastUnits: 372,
        daysElapsed: 5,
        remainingDays: 26,
        cycleLengthDays: 31,
        billMonth: DateTime(2026, 11, 1),
        projected: true,
      ),
    ).map((i) => i.text).toList();

    expect(insights, contains(contains('การใช้ไฟต่อวันรอบนี้ (บิล พ.ย. 69) คาดว่าจะสูงกว่าบิล ต.ค. 69 ประมาณ 20%')));
    expect(insights, contains(contains('ลดลงต่อเนื่อง 3 เดือน (ส.ค.–ต.ค. 69)')));
  });

  test('บันทึกยังไม่ถึง 1 วันจากต้นรอบ (ยังไม่ได้คาดการณ์) -> ไม่เทียบรอบนี้กับบิลล่าสุด', () {
    final insights = service.generateUtilityInsights(
      label: 'ค่าไฟ',
      bills: [bill(8, 1200, units: 300), bill(9, 1200, units: 300), bill(10, 1200, units: 300)],
      selector: (b) => b.electricityCost,
      mom: null,
      yoy: null,
      usagePerDay: perDay,
      usageLabel: 'การใช้ไฟ',
      // ยอดที่ใช้ไปไม่กี่ชั่วโมง ไม่ใช่ยอดทั้งรอบ ถ้านำไปเทียบจะได้ "ต่ำกว่า 97%"
      currentCycle: CurrentCycleForecast(
        currentCost: 40,
        forecastCost: 40,
        currentUnits: 2,
        forecastUnits: 2,
        daysElapsed: 0,
        remainingDays: 31,
        cycleLengthDays: 31,
        billMonth: DateTime(2026, 11, 1),
        projected: false,
      ),
    ).map((i) => i.text).toList();

    expect(insights, isNot(contains(contains('รอบนี้ ('))));
  });

  group('ข้อสังเกตรอบนี้เทียบบิลล่าสุด', () {
    // บิล ก.พ. วันละ 10 หน่วย รอบ เม.ย. ใช้เพิ่มตามหน้าร้อนพอดี (ตัวคูณ เม.ย. ÷ ก.พ. ≈ 1.29)
    CurrentCycleForecast april(double perDayNow) => CurrentCycleForecast(
          currentCost: 500,
          forecastCost: 1600,
          currentUnits: 120,
          forecastUnits: perDayNow * 30,
          daysElapsed: 10,
          remainingDays: 20,
          cycleLengthDays: 30,
          billMonth: DateTime(2026, 4, 1),
          projected: true,
        );
    List<String> cycleInsights(CurrentCycleForecast c, {bool seasonal = true}) => service
        .generateUtilityInsights(
          label: 'ค่าไฟ',
          bills: [bill(2, 1200, units: 300)],
          selector: (b) => b.electricityCost,
          mom: null,
          yoy: null,
          currentCycle: c,
          usagePerDay: perDay,
          usageLabel: 'การใช้ไฟ',
          seasonalFactor: seasonal ? bangkokFactor : null,
        )
        .map((i) => i.text)
        .where((t) => t.contains('รอบนี้ ('))
        .toList();

    test('ใช้เพิ่มตามฤดูกาลพอดี -> ไม่เตือน (ถ้าไม่หักฤดูกาลจะเตือน)', () {
      final c = april(10 * bangkokFactor(4) / bangkokFactor(2));
      expect(cycleInsights(c), isEmpty);
      expect(cycleInsights(c, seasonal: false), [contains('สูงกว่าบิล ก.พ. 69')]);
    });

    test('ใช้เพิ่มเกินฤดูกาล 20% -> เตือน และบอกว่าหักฤดูกาลแล้ว', () {
      final c = april(12 * bangkokFactor(4) / bangkokFactor(2));
      expect(cycleInsights(c), [contains('ประมาณ 20% แม้หักผลของฤดูกาลแล้ว')]);
    });

    test('บิลล่าสุดไม่มีหน่วย -> ข้ามข้อนี้', () {
      final insights = service
          .generateUtilityInsights(
            label: 'ค่าไฟ',
            bills: [bill(2, 1200)],
            selector: (b) => b.electricityCost,
            mom: null,
            yoy: null,
            currentCycle: april(20),
            usagePerDay: perDay,
          )
          .map((i) => i.text);
      expect(insights.where((t) => t.contains('รอบนี้ (')), isEmpty);
    });
  });

  group('ข้อสังเกตเพิ่ม/ลดต่อเนื่อง 3 เดือน', () {
    // ก.พ.–เม.ย. ตัวคูณฤดูกาล กทม. ขึ้นทุกเดือน (หน้าร้อน)
    test('ใช้เพิ่มตามฤดูกาลพอดี -> ไม่เตือน', () {
      final bills = [
        for (final m in [2, 3, 4]) bill(m, 1000, units: 300 * bangkokFactor(m)),
      ];
      expect(trendInsights(bills), isEmpty);
    });

    test('ใช้เพิ่มเกินฤดูกาล 10% ต่อเดือน -> เตือน และบอกว่าหักฤดูกาลแล้ว', () {
      final bills = [
        bill(2, 1000, units: 300 * bangkokFactor(2)),
        bill(3, 1100, units: 330 * bangkokFactor(3)),
        bill(4, 1200, units: 363 * bangkokFactor(4)),
      ];
      expect(trendInsights(bills), [
        contains('การใช้ไฟต่อวันในบิลที่ปิดแล้วเพิ่มขึ้นต่อเนื่อง 3 เดือน (ก.พ.–เม.ย. 69) แม้หักผลของฤดูกาลแล้ว'),
      ]);
    });

    test('เพิ่มทีละไม่ถึง 5% -> ไม่นับว่าเพิ่มต่อเนื่อง', () {
      final bills = [bill(8, 1200, units: 300), bill(9, 1210, units: 306), bill(10, 1220, units: 312)];
      expect(trendInsights(bills, seasonal: false), isEmpty);
    });

    test('บิลกรอกแค่ยอดเงิน (ไม่มีหน่วย) -> ข้ามข้อนี้ แม้ยอดเงินเพิ่มต่อเนื่อง', () {
      final bills = [bill(8, 1000), bill(9, 1200), bill(10, 1400)];
      expect(trendInsights(bills, seasonal: false), isEmpty);
    });
  });
}
