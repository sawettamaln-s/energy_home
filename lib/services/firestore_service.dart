import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../models/electricity_log_model.dart';
import '../models/fixed_cost_item_model.dart';
import '../models/start_meter_record_model.dart';
import '../models/user_model.dart';
import '../models/water_log_model.dart';
import '../utils/calculator.dart';
import '../utils/cycle_projection.dart';
import '../utils/data_refresh_bus.dart';
import '../utils/forecaster.dart';

class FirestoreService {
  // รับ FirebaseFirestore instance ผ่าน constructor ได้ (optional) เพื่อให้
  // เทสอัตโนมัติ (flutter test) ฉีด instance ปลอม (เช่น FakeFirebaseFirestore)
  // เข้ามาแทนได้ โดยไม่ต้องมี Firebase.initializeApp() ในสภาพแวดล้อมเทส
  // ถ้าไม่ส่ง param จะใช้ FirebaseFirestore.instance ตามปกติ
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
  // ทุกครั้งที่เพิ่ม/แก้/ลบรายการ จะคำนวณยอดรวมใหม่แล้วเก็บ cache ไว้ที่
  // users/{uid}.fixedCost ด้วย (ดู _recalcFixedCostTotal) เพื่อให้ Dashboard
  // ใช้ค่านี้แสดงผลได้เลยโดยไม่ต้อง query รายการย่อยซ้ำทุกครั้ง
  // หมายเหตุ: compileBill() "ไม่" ใช้ cache นี้ — คำนวณ fixedCost ของตัวเอง
  // แยกต่างหากจาก _calcFixedCostForMonth() ตาม (year, month) ของรอบบิลที่
  // กำลัง compile เพราะ cache นี้สะท้อนแค่เดือนปัจจุบันเท่านั้น ใช้กับรอบ
  // บิลเก่า/backfill ไม่ได้ (ดูคอมเมนต์ที่ compileBill())

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

  // รวมยอด fixed cost เฉพาะรายการที่ "แอคทีฟ" ในเดือนที่ระบุ (ดูตามช่วง
  // startDate/endDate ของแต่ละรายการ) แล้วอัปเดต cache ที่ users/{uid}.fixedCost
  //
  // หมายเหตุ: cache นี้ trigger จากการ save/delete เท่านั้น แต่ endDate จะ
  // "หมดอายุ" ไปเองตามเวลาที่ผ่านไปโดยไม่มี write event ใดๆ มาสั่ง recalc ให้
  // ดังนั้นหน้าจอที่ต้องการยอดล่าสุดจริงๆ (เช่น dashboard ตอนเปิดแอป) ควรเรียก
  // recalcFixedCostTotalForToday() ซ้ำตอน init ด้วย ไม่ใช่พึ่งพา cache เฉยๆ
  Future<void> _recalcFixedCostTotal(String uid, {DateTime? forMonth}) async {
    final month = forMonth ?? DateTime.now();
    final total = await _calcFixedCostForMonth(uid, month);

    // เขียนเฉพาะตอนยอดเปลี่ยนจริงๆ เท่านั้น — updateUser() broadcast ผ่าน
    // DataRefreshBus ทุกครั้งที่เขียน ถ้าเขียนทั้งที่ยอดเท่าเดิม (เช่นตอนถูก
    // เรียกจาก dashboard ทุกครั้งที่เปิดหน้า) จะกลายเป็น loop ไม่จบ:
    // เขียน → broadcast → dashboard/analysis ฟังแล้วโหลดใหม่ → เรียก recalc
    // อีกรอบ → เขียนอีก → broadcast อีก → ... (จอหมุนๆ ไม่หยุด)
    final current = await getUser(uid);
    final currentTotal = current?.fixedCost ?? 0;
    if ((currentTotal - total).abs() < 0.01) return;

    await updateUser(uid, {'fixedCost': total});
  }

  // เรียกจากภายนอก (เช่น dashboard ตอนโหลดหน้า) เพื่อ refresh cache ยอด fixed
  // cost ให้ตรงกับเดือนปัจจุบัน เผื่อมีรายการหมดอายุไปโดยไม่มีการ save/delete ใดๆ
  Future<void> recalcFixedCostTotalForToday(String uid) async {
    await _recalcFixedCostTotal(uid, forMonth: DateTime.now());
  }

  // รวมยอด fixed cost เฉพาะรายการที่ active ใน "เดือนปฏิทิน" ที่ระบุ (ไม่ผูก
  // กับ cache ของ user.fixedCost เลย) — ใช้ทั้งจาก _recalcFixedCostTotal
  // (สำหรับเดือนปัจจุบัน) และจาก compileBill() (สำหรับรอบบิลเก่า/backfill)
  // ที่ต้องคำนวณยอด fixed cost ที่ "active จริงตอนนั้น" ไม่ใช่ยอดวันนี้
  Future<double> _calcFixedCostForMonth(String uid, DateTime month) async {
    final items = await getFixedCostItems(uid);
    return items
        .where((item) => item.isActiveInMonth(month))
        .fold<double>(0, (acc, item) => acc + item.amount);
  }

  // เวอร์ชัน public ของ _calcFixedCostForMonth — ให้หน้าจอที่กรอก/แก้บิลของ
  // เดือนใดเดือนหนึ่ง (เช่น settings_bill_history.dart ตอนเพิ่มบิลย้อนหลัง)
  // ได้ยอดของเดือนนั้นจริง ห้ามใช้ user.fixedCost แทน เพราะเป็นยอดของ
  // "เดือนปัจจุบัน" เท่านั้น
  Future<double> calcFixedCostForMonth(String uid, DateTime month) {
    return _calcFixedCostForMonth(uid, month);
  }

  // ==================== ประเภทอัตราค่าไฟ ====================

  // เปลี่ยนประเภทอัตราค่าไฟ (UserModel.electricityTariff) แล้วคิดเงินของ log
  // ไฟฟ้าทุกอันในรอบบิลปัจจุบันใหม่ด้วยประเภทใหม่ — หน่วยที่บันทึกไว้ไม่เปลี่ยน
  // จึงสลับไป-กลับกี่ครั้งก็ได้ตัวเลขเดิม บิลของรอบที่ปิดแล้วไม่ถูกแตะ (เป็นยอด
  // ตามประเภทที่ใช้ตอนรอบนั้น) มิเตอร์ TOU ไม่ใช้ประเภทอัตรานี้ จึงไม่คำนวณใหม่
  Future<void> setElectricityTariff(
    UserModel user,
    String tariff, {
    DateTime? now,
  }) async {
    if (user.meterType != 'tou') {
      final today = now ?? DateTime.now();
      final startDate = EnergyForecaster.getCycleStart(today, user.billingDay);
      final endDate = EnergyForecaster.getCycleEnd(today, user.billingDay);
      final logs =
          await getCurrentMonthElectricityLogs(user.uid, startDate, endDate);
      if (logs.isNotEmpty) {
        final batch = _db.batch();
        for (final log in logs) {
          final cost = await EnergyCalculator.calculateElectricity(
              log.usedFromStart, user.area,
              tariff: tariff);
          batch.update(
            _db
                .collection('users')
                .doc(user.uid)
                .collection('electricity_logs')
                .doc(log.id),
            {'cost': cost},
          );
        }
        await batch.commit();
      }
    }
    // updateUser แจ้ง DataRefreshBus ครั้งเดียวหลังเขียนครบ
    await updateUser(user.uid, {'electricityTariff': tariff});
  }

  // ==================== ประวัติค่ามิเตอร์ต้นรอบ ====================

  // บันทึกเลขมิเตอร์ต้นรอบของรอบบิลหนึ่ง (id เดิม = เขียนทับรายการเดิม)
  Future<void> saveStartMeterRecord(StartMeterRecordModel record) async {
    await _db
        .collection('users')
        .doc(record.uid)
        .collection('start_meter_history')
        .doc(record.id)
        .set(record.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  // ดึงประวัติทั้งหมด เรียงตามเวลาที่บันทึก (recordedAt) ล่าสุดก่อน
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

  // ลบรายการประวัติเลขมิเตอร์ต้นรอบ 1 รอบ
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

  // บันทึกบิลรายเดือน (id เดิม = เขียนทับบิลเดิม)
  Future<void> saveBill(BillModel bill) async {
    await _db
        .collection('users')
        .doc(bill.uid)
        .collection('bills')
        .doc(bill.id)
        .set(bill.toMap());
    DataRefreshBus.instance.notifyChanged();
  }

  // ลบบิล 1 ใบ
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
  /// year/month คือเดือนของใบแจ้งหนี้ = เดือนของ endDate
  ///
  /// ยอดไฟ/น้ำ/หน่วยที่ใช้ เริ่มจาก log ล่าสุดของรอบ (cost/usedFromStart
  /// ของ log เป็นค่าสะสมจากต้นรอบอยู่แล้ว) แล้วประมาณส่วนที่เหลือจนถึงวันตัด
  /// รอบด้วย projectElectricityToCycleEnd/projectWaterToCycleEnd (สูตรเดียวกับ
  /// การ์ด "คาดว่าจะจบรอบที่") เพราะบันทึกครั้งสุดท้ายมักไม่ตรงวันตัดรอบ ถ้าใช้ยอดดิบบิลจะต่ำ
  /// กว่าจริง เมื่อผู้ใช้ตั้งเลขต้นรอบใหม่จากใบแจ้งหนี้ บิล 'startMeter' จะเขียน
  /// ทับด้วยยอดจริง — ไม่มี log เลยจะไม่สร้างบิล
  ///
  /// fixedCost คำนวณเองจาก isActiveInMonth(year, month) ของรอบบิลที่กำลัง
  /// compile (ไม่รับเป็น parameter และไม่ใช้ user.fixedCost ซึ่งเป็น cache ของ
  /// "เดือนปัจจุบัน" เท่านั้น) เพื่อให้บิลย้อนหลังที่ compile ตอน backfill
  /// (ได้ถึง 24 รอบ) ใช้ยอดที่ active จริงในรอบนั้น
  Future<void> compileBill(
    String uid,
    int year,
    int month,
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

      final fixedCost =
          await _calcFixedCostForMonth(uid, DateTime(year, month, 1));

      // log เรียงใหม่สุดก่อน — ตัวแรกคือยอดสะสม ณ วันที่บันทึกล่าสุดของรอบ
      final eLast = eLogs.isNotEmpty ? eLogs.first : null;
      final wLast = wLogs.isNotEmpty ? wLogs.first : null;

      // สำหรับมิเตอร์ TOU: ต้องรู้เลขต้นรอบ On-Peak/Off-Peak เพื่อแยกหน่วยสองช่วง
      // (หน้าวิเคราะห์ analysis_screen.dart ใช้ค่านี้วาดกราฟแยกสองเส้น และ
      // ใช้คิดค่าไฟ TOU ของหน่วยที่ประมาณถึงวันตัดรอบ)
      //
      // ค่าฐานลบใช้ record ใน start_meter_history ที่เป็น "ต้นรอบ" ของรอบที่
      // กำลัง compile — record ของรอบไหนเก็บเดือนที่รอบนั้นเริ่ม
      // (billingMonth/Year = เดือนของ startDate) ห้ามใช้ year/month ที่รับเข้ามา
      // เพราะนั่นคือเดือนปิดรอบ = ต้นรอบของ "รอบถัดไป" (หน่วยที่ใช้จะกลายเป็น ~0)
      // และไม่ใช้ user.startPeakValue/startOffPeakValue ตรงๆ เพราะเป็นค่าของ
      // รอบล่าสุดที่ตั้งไว้ ณ ตอนนี้ ถ้าผู้ใช้ตั้งต้นรอบใหม่ไปแล้วจะไม่ตรงกับรอบ
      // ที่กำลัง compile
      double cycleStartPeak = user.startPeakValue;
      double cycleStartOffPeak = user.startOffPeakValue;
      if (user.meterType == 'tou' && eLast != null) {
        final startHistory = await getStartMeterHistory(uid);
        final cycleStart = startHistory
            .where((r) =>
                r.billingMonth == startDate.month &&
                r.billingYear == startDate.year)
            .toList();
        // ไม่เจอ record ของรอบนี้ (เช่น log เก่าก่อนเคยตั้ง TOU) ใช้ค่าบน user
        // ปัจจุบันเป็นทางเลือกสุดท้าย ดีกว่าไม่มีค่าให้เลย
        if (cycleStart.isNotEmpty) {
          cycleStartPeak = cycleStart.first.peakValue;
          cycleStartOffPeak = cycleStart.first.offPeakValue;
        }
      }

      // ประมาณหน่วยจากวันที่บันทึกล่าสุดไปถึงวันตัดรอบ แล้วคิดเงินด้วยตาราง
      // อัตราจริง (ดู cycle_projection.dart) — ไฟกับน้ำบันทึกคนละวันได้ จึงใช้
      // วันที่ของ log แต่ละฝั่งเอง
      final elec = await projectElectricityToCycleEnd(
        latest: eLast,
        cycleStart: startDate,
        cycleEnd: endDate,
        meterType: user.meterType,
        area: user.area,
        startPeak: cycleStartPeak,
        startOffPeak: cycleStartOffPeak,
        tariff: user.electricityTariff,
      );
      final water = projectWaterToCycleEnd(
        latest: wLast,
        cycleStart: startDate,
        cycleEnd: endDate,
        area: user.area,
      );
      final totalElec = elec.cost;
      final totalWater = water.cost;

      // สร้าง Bill โดยใช้ id แบบตายตัวผูกกับ (year, month) — saveBill()
      // เขียนด้วย .doc(bill.id).set() (ไม่ใช่ .add()) ต่อให้ compileBill()
      // ถูกเรียกซ้อนกันหลายครั้งพร้อมกัน (เช่น เปิดแอปซ้ำๆ/pull-to-refresh
      // รัวๆ) ทุกครั้งจะเขียนทับเอกสารเดียวกันเสมอ (idempotent) จึงไม่มีทาง
      // ได้บิลซ้ำกันสำหรับเดือน/ปีเดียวกัน
      final bill = BillModel(
        id: 'compiled_${year}_${month.toString().padLeft(2, '0')}',
        uid: uid,
        year: year,
        month: month,
        electricityUsed: elec.units,
        electricityPeakUsed: elec.peakUnits,
        electricityOffPeakUsed: elec.offPeakUnits,
        waterUsed: water.units,
        electricityCost: totalElec,
        waterCost: totalWater,
        fixedCost: fixedCost,
        totalCost: totalElec + totalWater + fixedCost,
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

  // ดึงเฉพาะบิลล่าสุด (เดือน/ปีล่าสุด) — ใช้แทน getBills() ในจุดที่ต้องการ
  // แค่บิลล่าสุดตัวเดียว (เช่น dashboard ที่ต้องเอาไปเทียบ "พุ่งขึ้น/ลดลง")
  // orderBy ฟิลด์เดียว (yearMonth) จึงไม่ต้องสร้าง composite index เหมือน
  // การ orderBy('year').orderBy('month') สองฟิลด์พร้อมกัน
  //
  // ข้อควรรู้: บิลใน Firestore ที่ไม่มีฟิลด์ yearMonth จะไม่ถูก query นี้
  // เห็น — BillModel.toMap() ใส่ฟิลด์นี้ให้ทุกครั้งที่บันทึก บิลที่บันทึก
  // ผ่านแอปจึงมีครบ
  Future<BillModel?> getLatestBill(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .orderBy('yearMonth', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return BillModel.fromMap({...doc.data(), 'id': doc.id});
  }

  // ดึงบิลทั้งหมด เรียงเดือนล่าสุดก่อน
  Future<List<BillModel>> getBills(String uid) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('bills').get();

    final bills = snapshot.docs
        .map((doc) => BillModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

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
            // เติม id ของ document เข้าไปด้วย เพื่อป้องกันปัญหา appliance.id เป็นค่าว่าง
            .map((doc) => ApplianceModel.fromMap({...doc.data(), 'id': doc.id}))
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

  /// เครื่องมือแก้ข้อมูลครั้งเดียว (ไม่มีปุ่มเรียกใน UI): บิล TOU ที่ระบบ
  /// compile ไว้ (source=='compiled') แต่ electricityPeakUsed/
  /// electricityOffPeakUsed ค้างเป็น 0 — ไล่คำนวณให้ใหม่จาก log รายวันที่มี
  /// อยู่จริง ไม่ใช่เดา (มีสคริปต์คู่กันที่ tool/migrate_tou_bills.dart ถ้า
  /// แก้สูตรต้องแก้ทั้งสองที่)
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
  /// ค่าเริ่มต้น dryRun = true เพื่อจำลองผลลัพธ์และตรวจสอบข้อมูลล่วงหน้า
  /// ป้องกันการเขียนทับข้อมูลจริงโดยไม่ได้ตั้งใจ
  /// (หากต้องการบันทึกจริง ให้กำหนดค่าเป็น dryRun: false)
  Future<List<TouBillMigrationPreview>> migrateTouCompiledBills(
    String uid, {
    bool dryRun = true,
  }) async {
    final user = await getUser(uid);
    if (user == null || user.meterType != 'tou') {
      debugPrint(
          '⏭️ ข้าม migration: ไม่ใช่ user TOU หรือหา user ไม่เจอ (uid=$uid)');
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
    final history = await getStartMeterHistory(uid); // คืนค่าเรียง desc (ใหม่ -> เก่า)
    final earliestRecord = history.isEmpty
        ? null
        : history.reduce((a, b) => a.recordedAt.isBefore(b.recordedAt) ? a : b);

    double? basePeak = earliestRecord?.peakValue;
    double? baseOffPeak = earliestRecord?.offPeakValue;

    final results = <TouBillMigrationPreview>[];

    for (final bill in compiledBills) {
      final endDate =
          EnergyForecaster.safeBillingDate(bill.year, bill.month, billingDay);
      final startDate =
          EnergyForecaster.getPreviousCycleStart(endDate, billingDay);

      final logsInCycle = allLogs
          .where((l) => !l.date.isBefore(startDate) && l.date.isBefore(endDate))
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

      final newPeakUsed = EnergyCalculator.calculateUsed(closingPeak, basePeak);
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
          source: bill.source,
        ));
      }

      // เดินฐานต่อไปสำหรับรอบถัดไป
      basePeak = closingPeak;
      baseOffPeak = closingOffPeak;
    }

    return results;
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