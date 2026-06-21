import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../models/electricity_log_model.dart';
import '../models/user_model.dart';
import '../models/water_log_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  // อัพเดทข้อมูลผู้ใช้
  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
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
      final eLogs = await getCurrentMonthElectricityLogs(uid, startDate, endDate);
      final wLogs = await getCurrentMonthWaterLogs(uid, startDate, endDate);

      // ไม่มี log เลยในรอบนี้ → ไม่ต้องสร้างบิลเปล่า
      if (eLogs.isEmpty && wLogs.isEmpty) return;

      // รวมค่า
      double totalElec = eLogs.fold(0, (sum, log) => sum + log.cost);
      double totalWater = wLogs.fold(0, (sum, log) => sum + log.cost);
      double usedElec = eLogs.isNotEmpty ? eLogs.first.usedFromStart : 0;
      double usedWater = wLogs.isNotEmpty ? wLogs.first.usedFromStart : 0;

      // สร้าง Bill
      final bill = BillModel(
        id: const Uuid().v4(),
        uid: uid,
        year: year,
        month: month,
        electricityUsed: usedElec,
        waterUsed: usedWater,
        electricityCost: totalElec,
        waterCost: totalWater,
        fixedCost: fixedCost,
        totalCost: totalElec + totalWater + fixedCost,
        forecastElectricity: totalElec,
        forecastWater: totalWater,
        forecastTotal: totalElec + totalWater + fixedCost,
        isComplete: false,
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
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .get();

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

  // ดึงบิลย้อนหลัง N เดือน
  Future<List<BillModel>> getRecentBills(String uid, int months) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .limit(months)
        .get();

    final bills = snapshot.docs
        .map((doc) => BillModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

    // เรียง manual
    bills.sort((a, b) {
      if (a.year != b.year) return b.year.compareTo(a.year);
      return b.month.compareTo(a.month);
    });

    return bills.reversed.toList();
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
            .map((doc) => ApplianceModel.fromMap(doc.data()))
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
        .where('date', isLessThanOrEqualTo: endDate.toIso8601String())
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
  }

  // ==================== WATER LOGS ====================

  Future<void> saveWaterLog(WaterLogModel log) async {
    await _db
        .collection('users')
        .doc(log.uid)
        .collection('water_logs')
        .doc(log.id)
        .set(log.toMap());
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
        .where('date', isLessThanOrEqualTo: endDate.toIso8601String())
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
  }
}