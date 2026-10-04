// เทส FirestoreService.recalcCurrentCycleLogs — แก้เลขมิเตอร์ต้นรอบของรอบ
// ปัจจุบันแล้ว log ในรอบนี้ต้องคำนวณหน่วย/ค่าใช้จ่ายใหม่จากเลขต้นรอบใหม่
// ส่วน log ของรอบก่อนไม่ถูกแตะ
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/models/water_log_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('คำนวณ log ในรอบปัจจุบันใหม่จากเลขต้นรอบใหม่ ไม่แตะรอบก่อน', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    final user = UserModel(
        uid: 'u', name: 'U', email: 'u@example.com', billingDay: 1);
    await service.createUser(user);

    // รอบปัจจุบัน 1 มิ.ย. - 1 ก.ค. 2026 (เลขต้นรอบเดิม 1000 → ใหม่ 1020)
    await service.saveElectricityLog(ElectricityLogModel(
        id: 'now', uid: 'u', date: DateTime(2026, 6, 10),
        meterValue: 1100, usedFromStart: 100, usedFromLast: 100, cost: 1));
    await service.saveElectricityLog(ElectricityLogModel(
        id: 'old', uid: 'u', date: DateTime(2026, 5, 10),
        meterValue: 900, usedFromStart: 50, cost: 2));
    await service.saveWaterLog(WaterLogModel(
        id: 'w', uid: 'u', date: DateTime(2026, 6, 10),
        meterValue: 130, usedFromStart: 30, cost: 3));

    await service.recalcCurrentCycleLogs(
      user,
      isTou: false,
      recalcElectricity: true,
      recalcWater: false,
      newStartE: 1020,
      newStartPeak: 0,
      newStartOffPeak: 0,
      newStartW: 0,
      now: DateTime(2026, 6, 20),
    );

    Future<Map<String, dynamic>> doc(String col, String id) async =>
        (await firestore.collection('users/u/$col').doc(id).get()).data()!;

    final now = await doc('electricity_logs', 'now');
    expect(now['usedFromStart'], 80);
    expect(now['cost'], await EnergyCalculator.calculateElectricity(80, 'bangkok'));
    expect(now['usedFromLast'], 100, reason: 'ไม่แตะยอดเทียบครั้งก่อน');
    expect((await doc('electricity_logs', 'old'))['usedFromStart'], 50);
    expect((await doc('water_logs', 'w'))['cost'], 3,
        reason: 'ไม่ได้ขอคำนวณฝั่งน้ำ');
  });
}
