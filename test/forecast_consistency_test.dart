// ยอดคาดการณ์สิ้นรอบของ DashboardLoader (ใช้ตัดสินแจ้งเตือน "คาดการณ์สูงกว่า
// เดือนก่อน") กับการ์ดคาดการณ์ "บิลรอบนี้" ของหน้าวิเคราะห์
// (AnalysisService.forecastCurrentCycle) ต้องเป็นตัวเลขเดียวกันทั้งค่าไฟและค่าน้ำ
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/models/water_log_model.dart';
import 'package:energy_home/screens/dashboard/dashboard_loader.dart';
import 'package:energy_home/services/analysis_service.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/forecaster.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'u1';
const _billingDay = 1;

void main() {
  test('ค่าไฟ/ค่าน้ำคาดการณ์สิ้นรอบ หน้าหลักกับหน้าวิเคราะห์ตรงกัน', () async {
    final db = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: db);
    final now = DateTime.now();
    final cycleStart = EnergyForecaster.getCycleStart(now, _billingDay);
    await service.createUser(UserModel(
      uid: _uid,
      name: 'ทดสอบ',
      email: 'u1@example.com',
      billingDay: _billingDay,
      area: 'province',
      startElectricityValue: 1000,
      startWaterValue: 100,
      startBillingMonth: cycleStart.month,
      startBillingYear: cycleStart.year,
      startMeterConfigured: true,
      electricityStartConfigured: true,
      waterStartConfigured: true,
    ));
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'e1',
      uid: _uid,
      date: cycleStart.add(const Duration(hours: 30)),
      meterValue: 1045,
      usedFromStart: 45,
      usedFromLast: 45,
      cost: 200,
    ));
    await service.saveWaterLog(WaterLogModel(
      id: 'w1',
      uid: _uid,
      date: cycleStart.add(const Duration(hours: 30)),
      meterValue: 103,
      usedFromStart: 3,
      usedFromLast: 3,
      cost: 30,
    ));

    final dashboard = await DashboardLoader(firestoreService: service).load(_uid, now: now);
    final analysis = await AnalysisService(firestore: db).forecastCurrentCycle(
      uid: _uid,
      firestoreService: service,
      billingDay: _billingDay,
      area: 'province',
      meterType: 'normal',
    );

    expect(dashboard.hasForecastData, isTrue);
    expect(analysis['electricity']!.forecastCost, closeTo(dashboard.forecastElectricityCost, 0.01));
    expect(analysis['water']!.forecastCost, closeTo(dashboard.forecastWaterCost, 0.01));
  });
}
