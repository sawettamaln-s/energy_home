// เทสข้อสังเกตในหน้าวิเคราะห์ (AnalysisService.generateUtilityInsights) — แต่ละ
// ข้อต้องบอกชื่อบิลที่พูดถึง ข้อที่พูดถึงคนละรอบวางติดกันจึงไม่ดูขัดกันเอง
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AnalysisService(firestore: FakeFirebaseFirestore());

  BillModel bill(int month, double cost) =>
      BillModel(id: 'b$month', uid: 'u', year: 2026, month: month, electricityCost: cost);

  test('รอบนี้คาดว่าสูงขึ้น แต่บิลที่ปิดแล้วลดลง 3 เดือน -> ทั้งสองข้อบอกชื่อบิล', () {
    final bills = [bill(8, 1400), bill(9, 1300), bill(10, 1200)];
    final insights = service.generateUtilityInsights(
      label: 'ค่าไฟ',
      bills: bills,
      selector: (b) => b.electricityCost,
      mom: null,
      yoy: null,
      currentCycle: CurrentCycleForecast(
        currentCost: 300,
        forecastCost: 1440, // สูงกว่าบิล ต.ค. 20%
        currentUnits: 60,
        forecastUnits: 330,
        daysElapsed: 5,
        remainingDays: 26,
        cycleLengthDays: 31,
        billMonth: DateTime(2026, 11, 1),
      ),
    ).map((i) => i.text).toList();

    expect(insights, contains(contains('ค่าไฟรอบนี้ (บิล พ.ย. 69) คาดว่าจะสูงกว่าบิล ต.ค. 69 ประมาณ 20%')));
    expect(insights, contains(contains('ลดลงต่อเนื่อง 3 เดือน (ส.ค.–ต.ค. 69)')));
  });
}
