// เทสยืนยันบั๊กที่แก้ไปใน compileBill() (lib/services/firestore_service.dart):
// เดิมบิลที่ระบบ auto-compile ให้ตอนปิดรอบบิล (source: 'compiled') ไม่เคยเซ็ต
// electricityPeakUsed/electricityOffPeakUsed เลยสำหรับมิเตอร์ TOU (มีแต่
// usedElec ยอดรวม) ทำให้กราฟ On-Peak/Off-Peak ในหน้าวิเคราะห์ว่างเปล่าสำหรับ
// บิลส่วนใหญ่ที่เกิดขึ้นจริงในแอป — เทสชุดนี้ครอบ 3 เคสหลัก:
//   1) มิเตอร์ TOU + มีการใช้จริง -> ต้องคำนวณ peak/offpeak used ให้ถูกต้อง
//   2) มิเตอร์ปกติ (ไม่ใช่ TOU) -> ต้อง "ไม่" ไปยุ่งกับ field พวกนี้ ต้องยังเป็น
//      0 เหมือนพฤติกรรมเดิม (regression guard กันไม่ให้กระทบ user ปกติ)
//   3) มิเตอร์ TOU แต่ log ของรอบนี้มีค่ามิเตอร์ <= ค่าต้นรอบ (เช่น ยังไม่ได้
//      บันทึกการใช้จริง หรือมิเตอร์เพิ่งเปลี่ยน) -> ต้องได้ 0 ไม่ใช่ค่าติดลบ
//      (พึ่ง guard ของ EnergyCalculator.calculateUsed() ที่มีอยู่แล้ว)
//
// ใช้ FakeFirebaseFirestore แทนของจริง ไม่ต้องพึ่ง Firebase.initializeApp()
// ตามแพทเทิร์นเดียวกับ test/widget_test.dart
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ช่วงรอบบิลเดียวกันที่ใช้ทดสอบทุกเคส (1 มิ.ย. - 1 ก.ค. 2026)
  final startDate = DateTime(2026, 6, 1);
  final endDate = DateTime(2026, 7, 1);
  final logDate = DateTime(2026, 6, 15);

  Future<BillModel> compileAndFetch(
    FirestoreService service,
    String uid,
  ) async {
    await service.compileBill(uid, 2026, 6, 0, startDate, endDate);
    final bills = await service.getBills(uid);
    expect(bills, isNotEmpty, reason: 'compileBill ควรสร้างบิลสำเร็จ');
    return bills.first;
  }

  test('มิเตอร์ TOU: compileBill คำนวณ electricityPeakUsed/OffPeakUsed ถูกต้อง',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'tou-user';

    await service.createUser(UserModel(
      uid: uid,
      name: 'Tou User',
      email: 'tou@example.com',
      meterType: 'tou',
      startPeakValue: 1000,
      startOffPeakValue: 500,
    ));

    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-1',
      uid: uid,
      date: logDate,
      meterValue: 0, // มิเตอร์ปกติไม่ใช้ในเคส TOU
      peakMeterValue: 1120, // ใช้ไป 120 หน่วย
      offPeakMeterValue: 560, // ใช้ไป 60 หน่วย
      usedFromStart: 180, // ยอดรวม (peak+offpeak) ที่ระบบเคยคำนวณไว้ตอนบันทึก
      cost: 999, // ค่าไฟไม่ใช่จุดที่เทสนี้สนใจ ใส่เลขอะไรก็ได้
    ));

    final bill = await compileAndFetch(service, uid);

    expect(bill.electricityUsed, 180);
    expect(bill.electricityPeakUsed, 120);
    expect(bill.electricityOffPeakUsed, 60);
    expect(bill.source, 'compiled');
  });

  test(
      'มิเตอร์ปกติ (ไม่ใช่ TOU): electricityPeakUsed/OffPeakUsed ต้องเป็น 0 '
      'เหมือนพฤติกรรมเดิม ไม่ถูกแตะต้อง', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'normal-user';

    await service.createUser(UserModel(
      uid: uid,
      name: 'Normal User',
      email: 'normal@example.com',
      meterType: 'normal',
    ));

    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-1',
      uid: uid,
      date: logDate,
      meterValue: 14150,
      usedFromStart: 150,
      cost: 888,
    ));

    final bill = await compileAndFetch(service, uid);

    expect(bill.electricityUsed, 150);
    expect(bill.electricityPeakUsed, 0);
    expect(bill.electricityOffPeakUsed, 0);
  });

  test(
      'มิเตอร์ TOU แต่ค่ามิเตอร์รอบนี้ <= ค่าต้นรอบ (ยังไม่มีการใช้จริง/'
      'มิเตอร์เพิ่งเปลี่ยน): ต้องได้ 0 ไม่ใช่ค่าติดลบ', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'tou-user-nousage';

    await service.createUser(UserModel(
      uid: uid,
      name: 'Tou No Usage',
      email: 'tou-nousage@example.com',
      meterType: 'tou',
      startPeakValue: 1000,
      startOffPeakValue: 500,
    ));

    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-1',
      uid: uid,
      date: logDate,
      meterValue: 0,
      peakMeterValue: 900, // ต่ำกว่าค่าต้นรอบ (มิเตอร์เพิ่งเปลี่ยน/reset)
      offPeakMeterValue: 500, // เท่ากับค่าต้นรอบพอดี
      usedFromStart: 0,
      cost: 0,
    ));

    final bill = await compileAndFetch(service, uid);

    expect(bill.electricityPeakUsed, 0);
    expect(bill.electricityOffPeakUsed, 0);
  });
}