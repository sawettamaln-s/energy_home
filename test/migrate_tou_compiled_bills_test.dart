// เทสยืนยัน migrateTouCompiledBills() (lib/services/firestore_service.dart)
// — ฟังก์ชัน migration ย้อนหลังสำหรับบิล TOU เก่าที่ compile ไปก่อนแพตช์
// compileBill() (บิลเก่าพวกนี้ electricityPeakUsed/electricityOffPeakUsed
// ค้างเป็น 0 อยู่ในฐานข้อมูลจริง เพราะ compileBill() ตอนนั้นยังไม่คำนวณให้)
//
// ครอบ 4 เคสหลัก:
//   1) dryRun=true (ค่า default): คำนวณค่าที่ "ควรจะเป็น" ถูกต้อง แต่ต้อง
//      ไม่เขียนทับข้อมูลจริงใน Firestore เลย
//   2) dryRun=false: ต้องเขียนค่าที่คำนวณได้ลง Firestore จริง โดย field อื่น
//      ของบิล (electricityUsed, cost, source ฯลฯ) ต้องไม่ถูกแตะต้อง
//   3) ไล่คำนวณเป็นลูกโซ่ข้ามหลายรอบถูกต้อง (รอบที่ 2 ใช้เลขปิดรอบของรอบที่ 1
//      เป็นฐาน ไม่ใช่กลับไปใช้ start_meter_history ซ้ำทุกรอบ)
//   4) มิเตอร์ปกติ (ไม่ใช่ TOU) -> คืน list ว่างทันที ไม่ไปยุ่งอะไรเลย
import 'package:energy_home/models/bill_model.dart';
import 'package:energy_home/models/electricity_log_model.dart';
import 'package:energy_home/models/start_meter_record_model.dart';
import 'package:energy_home/models/user_model.dart';
import 'package:energy_home/services/firestore_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // billingDay = 30 (ค่า default ของแอป) ตลอดทุกเทสในไฟล์นี้ เพื่อให้ผลลัพธ์
  // ของ _cutoffDate/getPreviousCycleStart คาดเดาได้ตรงกับที่คำนวณมือไว้:
  //   รอบ 1: 2026-01-30 (รวม) -> 2026-02-28 (ไม่รวม)  [ก.พ. 2026 มี 28 วัน]
  //   รอบ 2: 2026-02-28 (รวม) -> 2026-03-30 (ไม่รวม)
  const uid = 'tou-migration-user';

  Future<FirestoreService> setupTouUserWithHistory() async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.createUser(UserModel(
      uid: uid,
      name: 'Migration Test',
      email: 'migrate@example.com',
      meterType: 'tou',
      billingDay: 30,
    ));

    // ฐานตั้งต้นที่เก่าแก่ที่สุด — ใช้เป็น baseline ของรอบแรก
    await service.saveStartMeterRecord(StartMeterRecordModel(
      id: 'record-earliest',
      uid: uid,
      electricityValue: 0,
      waterValue: 0,
      peakValue: 1000,
      offPeakValue: 500,
      billingMonth: 1,
      billingYear: 2026,
      recordedAt: DateTime(2026, 1, 1),
    ));

    // บิล 'compiled' เก่า 2 ใบ จำลองสภาพก่อนแพตช์: peak/offpeak ค้างเป็น 0
    await service.saveBill(BillModel(
      id: 'bill-feb',
      uid: uid,
      year: 2026,
      month: 2,
      electricityUsed: 180, // ยอดรวมถูกต้องอยู่แล้ว (ไม่เกี่ยวกับบั๊ก)
      electricityPeakUsed: 0,
      electricityOffPeakUsed: 0,
      electricityCost: 999,
      source: 'compiled',
    ));
    await service.saveBill(BillModel(
      id: 'bill-mar',
      uid: uid,
      year: 2026,
      month: 3,
      electricityUsed: 270,
      electricityPeakUsed: 0,
      electricityOffPeakUsed: 0,
      electricityCost: 1200,
      source: 'compiled',
    ));

    // log ปิดรอบของทั้งสองรอบ
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-feb',
      uid: uid,
      date: DateTime(2026, 2, 15),
      meterValue: 0,
      peakMeterValue: 1120, // ใช้ไป 120 จากฐาน 1000
      offPeakMeterValue: 560, // ใช้ไป 60 จากฐาน 500
      usedFromStart: 180,
      cost: 999,
    ));
    await service.saveElectricityLog(ElectricityLogModel(
      id: 'log-mar',
      uid: uid,
      date: DateTime(2026, 3, 15),
      meterValue: 0,
      peakMeterValue: 1300, // ใช้ไป 180 จากฐานรอบก่อน (1120)
      offPeakMeterValue: 650, // ใช้ไป 90 จากฐานรอบก่อน (560)
      usedFromStart: 270,
      cost: 1200,
    ));

    return service;
  }

  test('dryRun=true (default): คำนวณถูกต้องแต่ไม่เขียนทับ Firestore จริง',
      () async {
    final service = await setupTouUserWithHistory();

    final preview = await service.migrateTouCompiledBills(uid);

    expect(preview.length, 2);

    final feb = preview.firstWhere((p) => p.month == 2);
    expect(feb.oldPeakUsed, 0);
    expect(feb.newPeakUsed, 120);
    expect(feb.oldOffPeakUsed, 0);
    expect(feb.newOffPeakUsed, 60);
    expect(feb.willChange, isTrue);

    final mar = preview.firstWhere((p) => p.month == 3);
    expect(mar.newPeakUsed, 180, reason: 'ต่อลูกโซ่จากเลขปิดรอบ ก.พ. (1120)');
    expect(mar.newOffPeakUsed, 90, reason: 'ต่อลูกโซ่จากเลขปิดรอบ ก.พ. (560)');

    // ยืนยันว่า dryRun ไม่เขียนทับจริง — ค่าใน Firestore ต้องยังเป็น 0 เหมือนเดิม
    final billsAfter = await service.getBills(uid);
    for (final b in billsAfter) {
      expect(b.electricityPeakUsed, 0,
          reason: 'dryRun ต้องไม่แก้ข้อมูลจริงเด็ดขาด');
      expect(b.electricityOffPeakUsed, 0);
    }
  });

  test('dryRun=false: ต้องเขียนค่าใหม่ลง Firestore จริง โดยไม่แตะ field อื่น',
      () async {
    final service = await setupTouUserWithHistory();

    await service.migrateTouCompiledBills(uid, dryRun: false);

    final billsAfter = await service.getBills(uid);
    final feb = billsAfter.firstWhere((b) => b.month == 2);
    final mar = billsAfter.firstWhere((b) => b.month == 3);

    expect(feb.electricityPeakUsed, 120);
    expect(feb.electricityOffPeakUsed, 60);
    expect(feb.electricityUsed, 180, reason: 'ยอดรวมเดิมต้องไม่ถูกแก้');
    expect(feb.electricityCost, 999, reason: 'ค่าใช้จ่ายเดิมต้องไม่ถูกแก้');
    expect(feb.source, 'compiled', reason: 'source เดิมต้องไม่ถูกแก้');

    expect(mar.electricityPeakUsed, 180);
    expect(mar.electricityOffPeakUsed, 90);
  });

  test('มิเตอร์ปกติ (ไม่ใช่ TOU): คืน list ว่างทันที ไม่ไปยุ่งอะไรเลย',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.createUser(UserModel(
      uid: 'normal-user',
      name: 'Normal',
      email: 'normal@example.com',
      meterType: 'normal',
    ));
    await service.saveBill(BillModel(
      id: 'bill-1',
      uid: 'normal-user',
      year: 2026,
      month: 2,
      electricityUsed: 100,
      source: 'compiled',
    ));

    final preview = await service.migrateTouCompiledBills('normal-user');
    expect(preview, isEmpty);
  });

  test('รอบที่ไม่มี log เหลืออยู่เลย -> ข้ามพร้อมระบุเหตุผล ไม่เดาค่า',
      () async {
    final firestore = FakeFirebaseFirestore();
    final service = FirestoreService(firestore: firestore);

    await service.createUser(UserModel(
      uid: uid,
      name: 'No Log',
      email: 'nolog@example.com',
      meterType: 'tou',
      billingDay: 30,
    ));
    await service.saveStartMeterRecord(StartMeterRecordModel(
      id: 'record-earliest',
      uid: uid,
      electricityValue: 0,
      waterValue: 0,
      peakValue: 1000,
      offPeakValue: 500,
      billingMonth: 1,
      billingYear: 2026,
      recordedAt: DateTime(2026, 1, 1),
    ));
    await service.saveBill(BillModel(
      id: 'bill-feb',
      uid: uid,
      year: 2026,
      month: 2,
      electricityUsed: 180,
      source: 'compiled',
    ));
    // ไม่มี electricity_logs เลยในรอบนี้ (สมมติว่าถูกลบไปแล้ว)

    final preview = await service.migrateTouCompiledBills(uid);

    expect(preview.length, 1);
    expect(preview.first.skippedReason, isNotNull);
    expect(preview.first.willChange, isFalse);
  });
}