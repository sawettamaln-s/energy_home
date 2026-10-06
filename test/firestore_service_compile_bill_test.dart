// เทสยืนยันการคำนวณของ compileBill() (lib/services/firestore_service.dart):
// บิลที่ระบบ auto-compile ให้ตอนปิดรอบบิล (source: 'compiled') ต้องเซ็ต
// electricityPeakUsed/electricityOffPeakUsed สำหรับมิเตอร์ TOU (ไม่ใช่มีแต่
// usedElec ยอดรวม) ไม่งั้นกราฟ On-Peak/Off-Peak ในหน้าวิเคราะห์จะว่างเปล่า —
// เทสชุดนี้ครอบ 3 เคสหลัก:
//   1) มิเตอร์ TOU + มีการใช้จริง -> ต้องคำนวณ peak/offpeak used ให้ถูกต้อง
//   2) มิเตอร์ปกติ (ไม่ใช่ TOU) -> ต้อง "ไม่" ไปยุ่งกับ field พวกนี้ ต้องยังเป็น
//      0 เหมือนพฤติกรรมเดิม (regression guard กันไม่ให้กระทบ user ปกติ)
//   3) มิเตอร์ TOU แต่ log ของรอบนี้มีค่ามิเตอร์ <= ค่าต้นรอบ (เช่น ยังไม่ได้
//      บันทึกการใช้จริง หรือมิเตอร์เพิ่งเปลี่ยน) -> ต้องได้ 0 ไม่ใช่ค่าติดลบ
//      (พึ่ง guard ของ EnergyCalculator.calculateUsed() ที่มีอยู่แล้ว)
// และครอบการประมาณยอดจากบันทึกครั้งสุดท้ายไปถึงวันตัดรอบ, การเลือกเลข
// ต้นรอบของรอบที่ compile และ fixedCost ของรอบนั้น
//
// ใช้ FakeFirebaseFirestore แทนของจริง ไม่ต้องพึ่ง Firebase.initializeApp()
// ตามแพทเทิร์นเดียวกับ test/widget_test.dart
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/fixed_cost_item_model.dart';
import 'package:energy_home/models/start_meter_record_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/models/water_log_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:energy_home/utils/calculator.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ช่วงรอบบิลเดียวกันที่ใช้ทดสอบทุกเคส (1 มิ.ย. - 1 ก.ค. 2026)
  final startDate = DateTime(2026, 6, 1);
  final endDate = DateTime(2026, 7, 1);
  // บันทึกไม่ถึง 1 นาทีก่อนวันตัดรอบ — ส่วนที่ประมาณเพิ่มถึงวันตัดรอบเป็น 0
  // เคสที่ไม่ได้ทดสอบการประมาณจึงเทียบยอดจาก log ได้ตรงๆ
  final logDate = DateTime(2026, 6, 30, 23, 59, 30);

  Future<BillModel> compileAndFetch(
    FirestoreService service,
    String uid,
  ) async {
    await service.compileBill(uid, 2026, 6, startDate, endDate);
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

  test(
      'มิเตอร์ TOU ที่ตั้งต้นรอบถัดไปไปแล้ว: ต้องลบด้วยต้นรอบของรอบที่ compile '
      '(เดือนที่รอบเริ่ม) ไม่ใช่ต้นรอบถัดไป (เดือนปิดรอบ)', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'tou-next-cycle-set';

    // ผู้ใช้ตั้งต้นรอบ ก.ค. (= เลขปิดรอบ มิ.ย.) ไปแล้ว ค่าบน user จึงเป็นของ ก.ค.
    await service.createUser(UserModel(
      uid: uid,
      name: 'Tou User',
      email: 'tou-next@example.com',
      meterType: 'tou',
      startPeakValue: 1120,
      startOffPeakValue: 560,
    ));
    // ต้นรอบ มิ.ย. (รอบที่กำลัง compile) และต้นรอบ ก.ค. (รอบถัดไป)
    await service.saveStartMeterRecord(StartMeterRecordModel(
      id: 'start-jun',
      uid: uid,
      electricityValue: 0,
      waterValue: 0,
      peakValue: 1000,
      offPeakValue: 500,
      billingMonth: 6,
      billingYear: 2026,
      recordedAt: DateTime(2026, 6, 1),
    ));
    await service.saveStartMeterRecord(StartMeterRecordModel(
      id: 'start-jul',
      uid: uid,
      electricityValue: 0,
      waterValue: 0,
      peakValue: 1120,
      offPeakValue: 560,
      billingMonth: 7,
      billingYear: 2026,
      recordedAt: DateTime(2026, 7, 1),
    ));
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-1',
      uid: uid,
      date: logDate,
      meterValue: 180,
      peakMeterValue: 1120,
      offPeakMeterValue: 560,
      usedFromStart: 180,
      cost: 999,
    ));

    // แอปเรียก compileBill ด้วยเดือนปิดรอบ (ก.ค.) — ดู _loadData ใน dashboard
    await service.compileBill(uid, 2026, 7, startDate, endDate);
    final bill = (await service.getBills(uid)).single;

    expect(bill.electricityPeakUsed, 120);
    expect(bill.electricityOffPeakUsed, 60);
  });

  test(
      'บันทึกครั้งสุดท้ายก่อนวันตัดรอบ: ประมาณยอดถึงวันตัดรอบด้วยอัตราต่อวัน '
      '(ไฟกับน้ำใช้วันที่ของ log ตัวเอง)', () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'project-user';

    await service.createUser(UserModel(
      uid: uid,
      name: 'Project User',
      email: 'project@example.com',
      meterType: 'tou',
      startPeakValue: 1000,
      startOffPeakValue: 500,
    ));

    // ไฟ: บันทึกวันที่ 16 มิ.ย. (ผ่านไป 15 วันจากรอบ 30 วัน) → ยอดคูณ 2
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'e-1',
      uid: uid,
      date: DateTime(2026, 6, 16),
      meterValue: 90,
      peakMeterValue: 1060,
      offPeakMeterValue: 530,
      usedFromStart: 90,
      cost: 400,
    ));
    // น้ำ: บันทึกวันที่ 11 มิ.ย. (ผ่านไป 10 วัน) → ยอดคูณ 3
    await service.saveWaterLog(WaterLogModel(
      id: 'w-1',
      uid: uid,
      date: DateTime(2026, 6, 11),
      meterValue: 105,
      usedFromStart: 5,
      cost: 50,
    ));

    final bill = await compileAndFetch(service, uid);

    // หน่วยประมาณถึงวันตัดรอบ แล้วคิดเงินด้วยตารางอัตราจริง (ไม่ใช่ยอดเงิน x2/x3)
    final expectedElec = await EnergyCalculator.calculateElectricityTOU(
        peakUnits: 120, offPeakUnits: 60);
    final expectedWater = EnergyCalculator.calculateWater(15, 'bangkok');
    expect(bill.electricityUsed, 180);
    expect(bill.electricityPeakUsed, 120);
    expect(bill.electricityOffPeakUsed, 60);
    expect(bill.electricityCost, expectedElec);
    expect(bill.waterUsed, 15);
    expect(bill.waterCost, expectedWater);
    expect(bill.totalCost, expectedElec + expectedWater);
  });

  test(
      'compileBill คำนวณ fixedCost จากรายการที่ active จริงในรอบบิลที่กำลัง '
      'compile (มิ.ย. 2026) ไม่ใช่ยอด fixedCost ของ "วันนี้" ที่ cache ไว้บน '
      'user (regression test กันบั๊ก backfill ใช้ยอดปัจจุบันผิดรอบ)',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);
    const uid = 'fixedcost-user';

    await service.createUser(UserModel(
      uid: uid,
      name: 'Fixed Cost User',
      email: 'fixedcost@example.com',
      meterType: 'normal',
    ));

    // รายการที่ active เฉพาะช่วง มิ.ย. 2026 (รอบที่กำลัง compile) เท่านั้น —
    // สิ้นสุดก่อนเดือนปัจจุบันจริง (วันที่รันเทส) จึงไม่ถูกนับใน
    // _user.fixedCost ที่ cache ไว้ (ถ้ายังอิงเดือนปัจจุบัน)
    await service.saveFixedCostItem(FixedCostItemModel(
      id: 'item-june-only',
      uid: uid,
      name: 'ค่าอินเทอร์เน็ต (ยกเลิกแล้ว)',
      category: 'internet',
      amount: 590,
      createdAt: DateTime(2026, 6, 1),
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 30),
    ));

    // รายการที่เพิ่งเริ่มหลังรอบ มิ.ย. 2026 ไปแล้ว (เช่น สมัครวันนี้) —
    // ต้อง "ไม่" ถูกนับย้อนไปใส่บิลของรอบ มิ.ย. 2026 ที่ compile ย้อนหลัง
    await service.saveFixedCostItem(FixedCostItemModel(
      id: 'item-future-only',
      uid: uid,
      name: 'สมาชิกฟิตเนส (สมัครใหม่)',
      category: 'other',
      amount: 999,
      createdAt: DateTime.now(),
      startDate: DateTime.now(),
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

    expect(bill.fixedCost, 590,
        reason: 'ต้องนับเฉพาะรายการที่ active ในรอบ มิ.ย. 2026 (590) '
            'ไม่รวมรายการที่เพิ่งเริ่มวันนี้ (999)');
    expect(bill.totalCost, 888 + 590);
  });

  test('ผลของ compileBill: สร้างแล้ว / ไม่มี log / ไม่มีผู้ใช้ (ทำไม่สำเร็จ)',
      () async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    const uid = 'user-result';
    expect(await service.compileBill(uid, 2026, 6, startDate, endDate),
        CompileBillResult.failed);

    await service.createUser(UserModel(uid: uid, name: 'x', email: 'x@x.com'));
    expect(await service.compileBill(uid, 2026, 6, startDate, endDate),
        CompileBillResult.noLogs);

    await service.saveElectricityLog(ElectricityLogModel(
        id: 'e1', uid: uid, date: logDate,
        meterValue: 1100, usedFromStart: 100, cost: 400));
    expect(await service.compileBill(uid, 2026, 6, startDate, endDate),
        CompileBillResult.created);
  });

  test('ปิดบิลจากบันทึกช่วงต้นรอบ -> ถ่วงด้วยหน่วยต่อวันของบิลรอบก่อน', () async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    const uid = 'user-prior';
    await service.createUser(
        UserModel(uid: uid, name: 'x', email: 'x@x.com', billingDay: 1));
    // บันทึกครั้งสุดท้าย 4 มิ.ย. (ผ่านไป 3 วัน) ใช้ 60 หน่วย = วันละ 20
    await service.saveElectricityLog(ElectricityLogModel(
        id: 'e1', uid: uid, date: DateTime(2026, 6, 4),
        meterValue: 1060, usedFromStart: 60, cost: 250));
    // บิลรอบก่อน (เดือนบิล มิ.ย. = รอบ 1 พ.ค. - 1 มิ.ย. 31 วัน) วันละ 10
    await service.saveBill(BillModel(
        id: 'prev', uid: uid, year: 2026, month: 6,
        electricityUsed: 310, electricityCost: 1400, source: 'imported'));

    await service.compileBill(uid, 2026, 7, startDate, endDate);
    final bill = await service.getBillForMonth(uid, 2026, 7);
    // อัตราต่อวัน = (60 + 10 × 5) ÷ (3 + 5) = 13.75 เหลือ 27 วัน
    expect(bill!.electricityUsed, closeTo(60 + 13.75 * 27, 0.01));
  });
}
