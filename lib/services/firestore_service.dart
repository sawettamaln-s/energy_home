import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../models/electricity_log_model.dart';
import '../models/fixed_cost_item_model.dart';
import '../models/start_meter_record_model.dart';
import '../models/user_model.dart';
import '../models/water_log_model.dart';
import '../utils/calculator.dart';
import '../utils/data_refresh_bus.dart';
import '../utils/forecaster.dart';

class FirestoreService {
  // เดิม _db ผูกกับ FirebaseFirestore.instance ตรงๆ ทำให้เทสอัตโนมัติ
  // (flutter test) พังทันทีเพราะไม่มี Firebase.initializeApp() ในสภาพแวดล้อม
  // เทส — เปิดช่องให้ฉีด instance ปลอม (เช่น FakeFirebaseFirestore) เข้ามา
  // แทนได้ โดยโค้ดที่เรียกใช้งานจริงไม่ต้องแก้อะไรเลย (ไม่ส่ง param ก็ยังคง
  // ใช้ FirebaseFirestore.instance เหมือนเดิมทุกประการ)
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ==================== USER ====================

  // สร้างข้อมูลผู้ใช้ใหม่
  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  // ดึงข้อมูลผู้ใช้
  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!);
    }
    return null;
  }

  // อัพเดทข้อมูลผู้ใช้ (ครอบคลุมทั้งตั้ง/ล้างค่ามิเตอร์ต้นรอบ ฯลฯ)
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
    DataRefreshBus.instance.notifyChanged();
  }

  // ==================== FIXED COST ITEMS ====================
  // เก็บ Fixed Cost เป็นรายการย่อยๆ (ค่าแก๊ส, อินเทอร์เน็ต, ส่วนกลาง ฯลฯ)
  // แทนยอดเดียวแบบเดิม ทุกครั้งที่เพิ่ม/แก้/ลบรายการ จะคำนวณยอดรวมใหม่แล้ว
  // เก็บ cache ไว้ที่ users/{uid}.fixedCost ด้วย (ดู _recalcFixedCostTotal)
  // เพื่อให้ Dashboard และ compileBill() ที่อ่าน user.fixedCost อยู่แล้ว
  // ทำงานถูกต้องต่อไปโดยไม่ต้องแก้โค้ดจุดอื่นเลย

  Future<void> saveFixedCostItem(FixedCostItemModel item) async {
    await _db
        .collection('users')
        .doc(item.uid)
        .collection('fixed_costs')
        .doc(item.id)
        .set(item.toMap());
    await _recalcFixedCostTotal(item.uid);
  }

  Future<List<FixedCostItemModel>> getFixedCostItems(String uid) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('fixed_costs').get();

    final items = snapshot.docs
        .map((doc) => FixedCostItemModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> deleteFixedCostItem(String uid, String itemId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('fixed_costs')
        .doc(itemId)
        .delete();
    await _recalcFixedCostTotal(uid);
  }

  // รวมยอด fixed cost ทุกรายการแล้วอัปเดต cache ที่ users/{uid}.fixedCost
  Future<void> _recalcFixedCostTotal(String uid) async {
    final items = await getFixedCostItems(uid);
    final total = items.fold<double>(0, (acc, item) => acc + item.amount);
    await updateUser(uid, {'fixedCost': total});
  }

  // ==================== ประวัติค่ามิเตอร์ต้นรอบ ====================

  // เก็บ snapshot ทุกครั้งที่มีการตั้ง/แก้ไขค่ามิเตอร์ต้นรอบ
  Future<void> saveStartMeterRecord(StartMeterRecordModel record) async {
    await _db
        .collection('users')
        .doc(record.uid)
        .collection('start_meter_history')
        .doc(record.id)
        .set(record.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  // ดึงประวัติทั้งหมด เรียงจากล่าสุดไปเก่าสุด
  Future<List<StartMeterRecordModel>> getStartMeterHistory(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('start_meter_history')
        .get();

    final records = snapshot.docs
        .map((doc) =>
            StartMeterRecordModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

    records.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return records;
  }

  // ลบรายการประวัติ (เผื่อบันทึกผิดแล้วอยากลบทิ้ง)
  Future<void> deleteStartMeterRecord(String uid, String recordId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('start_meter_history')
        .doc(recordId)
        .delete();
    DataRefreshBus.instance.notifyChanged();
  }

  // ==================== BILLS ====================

  // บันทึกบิลรายเดือน
  Future<void> saveBill(BillModel bill) async {
    await _db
        .collection('users')
        .doc(bill.uid)
        .collection('bills')
        .doc(bill.id)
        .set(bill.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  // ลบบิล (ใช้สำหรับลบบิลย้อนหลังที่กรอกผิด)
  Future<void> deleteBill(String uid, String billId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .doc(billId)
        .delete();
    DataRefreshBus.instance.notifyChanged();
  }

  /// รวม logs ของรอบบิลที่ปิดแล้ว (startDate -> endDate) → สร้าง Bill
  /// หมายเหตุ: startDate/endDate ต้องเป็นช่วงของรอบบิลที่ "ปิดไปแล้ว"
  /// ไม่ใช่รอบที่กำลังดำเนินอยู่ตอนนี้ (ผู้เรียกเป็นคนคำนวณช่วงมาให้)
  Future<void> compileBill(
    String uid,
    int year,
    int month,
    double fixedCost,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final user = await getUser(uid);
      if (user == null) return;

      // ดึง logs ของรอบบิลที่ปิดแล้ว
      final eLogs =
          await getCurrentMonthElectricityLogs(uid, startDate, endDate);
      final wLogs = await getCurrentMonthWaterLogs(uid, startDate, endDate);

      // ไม่มี log เลยในรอบนี้ → ไม่ต้องสร้างบิลเปล่า
      if (eLogs.isEmpty && wLogs.isEmpty) return;

      // รวมค่า
      double totalElec = eLogs.isNotEmpty ? eLogs.first.cost : 0;
      double totalWater = wLogs.isNotEmpty ? wLogs.first.cost : 0;
      double usedElec = eLogs.isNotEmpty ? eLogs.first.usedFromStart : 0;
      double usedWater = wLogs.isNotEmpty ? wLogs.first.usedFromStart : 0;

      // แก้บั๊ก: มิเตอร์ TOU เดิมไม่เคยเซ็ต electricityPeakUsed/
      // electricityOffPeakUsed ตอน auto-compile บิลตอนปิดรอบเลย (มีแต่
      // usedElec ยอดรวม) ทำให้หน้าวิเคราะห์ (analysis_screen.dart ใช้
      // peakUsedSelector/offPeakUsedSelector วาดกราฟแยก On-Peak/Off-Peak)
      // เห็นบิลที่ compile อัตโนมัติ (ซึ่งเป็นบิลส่วนใหญ่ที่เกิดขึ้นจริงในแอป)
      // เป็น 0 ทั้งคู่เสมอ ทั้งที่ log รายวันมี peakMeterValue/offPeakMeterValue
      // เก็บไว้อยู่แล้ว — คำนวณ delta จากค่ามิเตอร์ต้นรอบ (user.startPeakValue/
      // startOffPeakValue) แบบเดียวกับที่ _recalcCurrentCycleLogs ใน
      // settings_start_meter.dart ทำอยู่แล้ว เพื่อให้บิล 'compiled' ได้ค่า
      // แยกที่ถูกต้องเหมือนบิล 'imported'/'startMeter'
      double peakUsedElec = 0;
      double offPeakUsedElec = 0;
      if (user.meterType == 'tou' && eLogs.isNotEmpty) {
        peakUsedElec = EnergyCalculator.calculateUsed(
            eLogs.first.peakMeterValue ?? 0, user.startPeakValue);
        offPeakUsedElec = EnergyCalculator.calculateUsed(
            eLogs.first.offPeakMeterValue ?? 0, user.startOffPeakValue);
      }

      // สร้าง Bill
      final bill = BillModel(
        id: const Uuid().v4(),
        uid: uid,
        year: year,
        month: month,
        electricityUsed: usedElec,
        electricityPeakUsed: peakUsedElec,
        electricityOffPeakUsed: offPeakUsedElec,
        waterUsed: usedWater,
        electricityCost: totalElec,
        waterCost: totalWater,
        fixedCost: fixedCost,
        totalCost: totalElec + totalWater + fixedCost,
        forecastElectricity: totalElec,
        forecastWater: totalWater,
        forecastTotal: totalElec + totalWater + fixedCost,
        source: 'compiled',
      );

      // บันทึกลง Firestore
      await saveBill(bill);
      debugPrint('✅ Bill compiled for $year-$month');
    } catch (e) {
      debugPrint('❌ Error compiling bill: $e');
    }
  }

  // เช็คว่ามีบิลของปี-เดือนนี้บันทึกไว้แล้วหรือยัง
  Future<bool> billExistsForMonth(String uid, int year, int month) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .where('year', isEqualTo: year)
        .where('month', isEqualTo: month)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  // ดึงบิลทั้งหมด
  Future<List<BillModel>> getBills(String uid) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('bills').get();

    final bills = snapshot.docs
        .map((doc) => BillModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

    // เรียง manual
    bills.sort((a, b) {
      if (a.year != b.year) return b.year.compareTo(a.year);
      return b.month.compareTo(a.month);
    });

    return bills;
  }

  // ==================== APPLIANCES ====================

  // บันทึกเครื่องใช้ไฟฟ้า
  Future<void> saveAppliance(ApplianceModel appliance) async {
    await _db
        .collection('users')
        .doc(appliance.uid)
        .collection('appliances')
        .doc(appliance.id)
        .set(appliance.toMap());
  }

  // ดึงรายการเครื่องใช้ไฟฟ้าทั้งหมด
  Stream<List<ApplianceModel>> getAppliances(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('appliances')
        .snapshots()
        .map((snapshot) => snapshot.docs
            // เติม id ของ document เข้าไปด้วย (เดิมขาด ทำให้ appliance.id
            // เป็นค่าว่างเสมอ ไม่ตรงกับ getBills/fetchBills ที่ merge id ไว้)
            .map((doc) =>
                ApplianceModel.fromMap({...doc.data(), 'id': doc.id}))
            .toList());
  }

  // ลบเครื่องใช้ไฟฟ้า
  Future<void> deleteAppliance(String uid, String applianceId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('appliances')
        .doc(applianceId)
        .delete();
  }

  // ==================== ELECTRICITY LOGS ====================

  Future<void> saveElectricityLog(ElectricityLogModel log) async {
    await _db
        .collection('users')
        .doc(log.uid)
        .collection('electricity_logs')
        .doc(log.id)
        .set(log.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  Future<ElectricityLogModel?> getLatestElectricityLog(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('electricity_logs')
        .orderBy('date', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      return ElectricityLogModel.fromMap(snapshot.docs.first.data());
    }
    return null;
  }

  Future<List<ElectricityLogModel>> getCurrentMonthElectricityLogs(
      String uid, DateTime startDate, DateTime endDate) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('electricity_logs')
        .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('date', isLessThan: endDate.toIso8601String())
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => ElectricityLogModel.fromMap(doc.data()))
        .toList();
  }

  Future<void> deleteElectricityLog(String uid, String logId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('electricity_logs')
        .doc(logId)
        .delete();
    DataRefreshBus.instance.notifyChanged();
  }

  // ==================== WATER LOGS ====================

  Future<void> saveWaterLog(WaterLogModel log) async {
    await _db
        .collection('users')
        .doc(log.uid)
        .collection('water_logs')
        .doc(log.id)
        .set(log.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  Future<WaterLogModel?> getLatestWaterLog(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('water_logs')
        .orderBy('date', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      return WaterLogModel.fromMap(snapshot.docs.first.data());
    }
    return null;
  }

  Future<List<WaterLogModel>> getCurrentMonthWaterLogs(
      String uid, DateTime startDate, DateTime endDate) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('water_logs')
        .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('date', isLessThan: endDate.toIso8601String())
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => WaterLogModel.fromMap(doc.data()))
        .toList();
  }

  Future<void> deleteWaterLog(String uid, String logId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('water_logs')
        .doc(logId)
        .delete();
    DataRefreshBus.instance.notifyChanged();
  }

  // ==================== ลบบัญชี + ข้อมูลทั้งหมด (PDPA) ====================

  // ลบข้อมูลทุก subcollection ของผู้ใช้ทิ้งทั้งหมด แล้วลบ document หลักด้วย
  // ต้องไล่ลบทีละ subcollection เอง เพราะ Firestore ไม่มี cascade delete
  // ให้อัตโนมัติตอนลบ document แม่ — ถ้าลบแค่ users/{uid} เฉยๆ เอกสารย่อย
  // ทั้งหมด (bills, electricity_logs, ...) จะค้างเป็นข้อมูลกำพร้าอยู่ใน
  // Firestore ตลอดไป ไม่ตรงกับสิทธิ "ขอให้ลบข้อมูล" ตาม PDPA
  Future<void> deleteAllUserData(String uid) async {
    final userDoc = _db.collection('users').doc(uid);

    const subcollections = [
      'bills',
      'fixed_costs',
      'start_meter_history',
      'appliances',
      'electricity_logs',
      'water_logs',
    ];

    for (final name in subcollections) {
      await _deleteAllDocsInCollection(userDoc.collection(name));
    }

    await userDoc.delete();
  }

  // ลบเอกสารทั้งหมดใน collection เดียวเป็น batch — จำกัดสูงสุด 500 คำสั่ง
  // ต่อ batch ตามข้อจำกัดของ Firestore WriteBatch จึงต้องแบ่งเป็นชุดๆ
  // ถ้าเอกสารในนั้นมีเกิน 500 ชิ้น (ปกติของแอปนี้ไม่น่าถึง แต่กันไว้)
  Future<void> _deleteAllDocsInCollection(
      CollectionReference<Map<String, dynamic>> ref) async {
    final snapshot = await ref.get();
    if (snapshot.docs.isEmpty) return;

    const batchSize = 500;
    for (var i = 0; i < snapshot.docs.length; i += batchSize) {
      final batch = _db.batch();
      final chunk = snapshot.docs.skip(i).take(batchSize);
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // ==================== Migration: TOU compiled bills ====================

  /// Migration ย้อนหลังสำหรับบั๊กที่แก้ไปใน compileBill(): บิล TOU ที่ระบบ
  /// auto-compile ไปแล้วก่อนแพตช์ (source=='compiled') ไม่มี
  /// electricityPeakUsed/electricityOffPeakUsed เก็บไว้เลย (ค้างเป็น 0)
  /// ฟังก์ชันนี้ไล่คำนวณย้อนหลังให้จาก log รายวันที่มีอยู่จริง ไม่ใช่เดา
  ///
  /// วิธีคำนวณ: ไล่ "เลขมิเตอร์ปิดรอบ" (log ล่าสุดของแต่ละรอบ) เป็นลูกโซ่
  /// ต่อกันไปทีละรอบ (รอบนี้ - รอบก่อนหน้า) แทนที่จะไปจับคู่กับ
  /// start_meter_history ของแต่ละรอบตรงๆ เพราะ:
  ///   - ตัดความเสี่ยงเรื่องตีความว่า record ไหนคู่กับบิลไหนผิดจุด แล้วได้
  ///     ค่าที่ดูสมเหตุสมผลแต่ผิดเงียบๆ (อันตรายกว่าปล่อยว่างไว้เสียอีก)
  ///   - เลขมิเตอร์สะสม (peakMeterValue/offPeakMeterValue) เป็นค่าที่ไม่มี
  ///     วันลดลงเอง ตราบใดที่ log ของทุกรอบยังอยู่ครบ ผลต่างระหว่าง log ปิด
  ///     รอบติดกันจึงถูกต้องเสมอ ไม่ต้องพึ่งการจับคู่ที่อาจกำกวม
  ///
  /// ข้อจำกัดที่ต้องรู้ก่อนใช้ (สำคัญ — อ่านก่อนรัน dryRun:false):
  ///   1) รอบแรกสุดในประวัติไม่มี "รอบก่อนหน้า" ให้ลบ ใช้
  ///      start_meter_history ตัวที่เก่าแก่สุด (เรียงตาม recordedAt) เป็น
  ///      ฐานตั้งต้นแทน ถ้า user ไม่เคยมี record นี้เลยจะข้ามบิลนั้น
  ///   2) ถ้ารอบไหน log รายวันถูกลบไปหมดแล้ว (ไม่เหลือ log ในช่วงนั้นเลย)
  ///      จะข้าม (skip) บิลนั้นไปพร้อมระบุเหตุผล ไม่เดาค่าให้
  ///   3) ใช้ billingDay ปัจจุบันของ user ย้อนสร้างขอบเขตรอบเก่าทุกรอบ —
  ///      ถ้า user เคยเปลี่ยนวันตัดรอบระหว่างทาง ขอบเขตที่ reconstruct ของ
  ///      รอบเก่าๆ ก่อนเปลี่ยนอาจคลาดเคลื่อนไปบ้าง ควรตรวจ preview ดูก่อน
  ///
  /// ค่าเริ่มต้น dryRun=true ตั้งใจให้ต้องเรียกซ้ำแบบ dryRun:false เอง
  /// หลังตรวจ preview แล้วพอใจ กันเขียนทับข้อมูลจริงโดยไม่ได้ตรวจก่อน
  Future<List<TouBillMigrationPreview>> migrateTouCompiledBills(
    String uid, {
    bool dryRun = true,
  }) async {
    final user = await getUser(uid);
    if (user == null || user.meterType != 'tou') {
      debugPrint('⏭️ ข้าม migration: ไม่ใช่ user TOU หรือหา user ไม่เจอ (uid=$uid)');
      return [];
    }

    final billingDay = user.billingDay;
    final bills = await getBills(uid);
    final compiledBills = bills.where((b) => b.source == 'compiled').toList()
      ..sort(
          (a, b) => (a.year * 12 + a.month).compareTo(b.year * 12 + b.month));

    if (compiledBills.isEmpty) return [];

    // ดึง log ไฟฟ้า "ทั้งหมด" ของ user (ไม่จำกัดช่วงวันที่) เรียงเก่า -> ใหม่
    final allLogsSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('electricity_logs')
        .orderBy('date')
        .get();
    final allLogs = allLogsSnapshot.docs
        .map((doc) => ElectricityLogModel.fromMap(doc.data()))
        .toList();

    // ฐานตั้งต้นของรอบแรกสุด: ใช้ start_meter_history ตัวที่เก่าแก่สุด
    final history = await getStartMeterHistory(uid); // ฟังก์ชันเดิมคืน desc
    final earliestRecord = history.isEmpty
        ? null
        : history.reduce(
            (a, b) => a.recordedAt.isBefore(b.recordedAt) ? a : b);

    double? basePeak = earliestRecord?.peakValue;
    double? baseOffPeak = earliestRecord?.offPeakValue;

    final results = <TouBillMigrationPreview>[];

    for (final bill in compiledBills) {
      final endDate = _cutoffDate(bill.year, bill.month, billingDay);
      final startDate =
          EnergyForecaster.getPreviousCycleStart(endDate, billingDay);

      final logsInCycle = allLogs
          .where(
              (l) => !l.date.isBefore(startDate) && l.date.isBefore(endDate))
          .toList(); // allLogs เรียง asc มาแล้วจาก query ด้านบน

      if (logsInCycle.isEmpty || basePeak == null || baseOffPeak == null) {
        results.add(TouBillMigrationPreview(
          billId: bill.id,
          year: bill.year,
          month: bill.month,
          oldPeakUsed: bill.electricityPeakUsed,
          newPeakUsed: bill.electricityPeakUsed,
          oldOffPeakUsed: bill.electricityOffPeakUsed,
          newOffPeakUsed: bill.electricityOffPeakUsed,
          skippedReason: logsInCycle.isEmpty
              ? 'ไม่มี log ไฟฟ้าเหลืออยู่ในช่วงรอบนี้ '
                  '(${startDate.toIso8601String().split('T').first} - '
                  '${endDate.toIso8601String().split('T').first})'
              : 'ไม่มี start_meter_history ให้ใช้เป็นฐานตั้งต้น (รอบแรกสุด)',
        ));
        // รอบนี้ข้าม แต่ถ้ามี log อยู่ก็ยังต้องเดินฐานต่อให้รอบถัดไปคำนวณได้
        if (logsInCycle.isNotEmpty) {
          final closing = logsInCycle.last;
          basePeak = closing.peakMeterValue ?? basePeak;
          baseOffPeak = closing.offPeakMeterValue ?? baseOffPeak;
        }
        continue;
      }

      final closingLog = logsInCycle.last;
      final closingPeak = closingLog.peakMeterValue ?? basePeak;
      final closingOffPeak = closingLog.offPeakMeterValue ?? baseOffPeak;

      final newPeakUsed =
          EnergyCalculator.calculateUsed(closingPeak, basePeak);
      final newOffPeakUsed =
          EnergyCalculator.calculateUsed(closingOffPeak, baseOffPeak);

      results.add(TouBillMigrationPreview(
        billId: bill.id,
        year: bill.year,
        month: bill.month,
        oldPeakUsed: bill.electricityPeakUsed,
        newPeakUsed: newPeakUsed,
        oldOffPeakUsed: bill.electricityOffPeakUsed,
        newOffPeakUsed: newOffPeakUsed,
        matchedLogDate: closingLog.date,
      ));

      if (!dryRun) {
        await saveBill(BillModel(
          id: bill.id,
          uid: bill.uid,
          year: bill.year,
          month: bill.month,
          electricityUsed: bill.electricityUsed,
          electricityPeakUsed: newPeakUsed,
          electricityOffPeakUsed: newOffPeakUsed,
          waterUsed: bill.waterUsed,
          electricityCost: bill.electricityCost,
          waterCost: bill.waterCost,
          fixedCost: bill.fixedCost,
          totalCost: bill.totalCost,
          forecastElectricity: bill.forecastElectricity,
          forecastWater: bill.forecastWater,
          forecastTotal: bill.forecastTotal,
          source: bill.source,
        ));
      }

      // เดินฐานต่อไปสำหรับรอบถัดไป
      basePeak = closingPeak;
      baseOffPeak = closingOffPeak;
    }

    return results;
  }

  // คัดลอกมาจาก EnergyForecaster._safeBillingDate (private เรียกจากนอกไฟล์
  // ไม่ได้) — ต้องเหมือนต้นฉบับเป๊ะเพื่อ reconstruct ขอบเขตรอบเก่าให้ตรงกับ
  // ที่แอปใช้จริงตอน compileBill()
  DateTime _cutoffDate(int year, int month, int billingDay) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final safeDay = billingDay > lastDayOfMonth ? lastDayOfMonth : billingDay;
    return DateTime(year, month, safeDay);
  }
}

/// ผลลัพธ์ของการ migrate บิล TOU แต่ละใบ — ใช้โชว์ preview ให้ตรวจก่อน
/// ตัดสินใจ apply จริง (dryRun:false)
class TouBillMigrationPreview {
  final String billId;
  final int year;
  final int month;
  final double oldPeakUsed;
  final double newPeakUsed;
  final double oldOffPeakUsed;
  final double newOffPeakUsed;
  final DateTime? matchedLogDate;
  final String? skippedReason; // null = แก้ได้จริง, ไม่ null = ข้ามพร้อมเหตุผล

  TouBillMigrationPreview({
    required this.billId,
    required this.year,
    required this.month,
    required this.oldPeakUsed,
    required this.newPeakUsed,
    required this.oldOffPeakUsed,
    required this.newOffPeakUsed,
    this.matchedLogDate,
    this.skippedReason,
  });

  bool get willChange =>
      skippedReason == null &&
      (oldPeakUsed != newPeakUsed || oldOffPeakUsed != newOffPeakUsed);
}