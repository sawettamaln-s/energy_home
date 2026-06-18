import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../models/electricity_log_model.dart';
import '../models/meter_log_model.dart';
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

  // ==================== METER LOGS ====================

  // บันทึกค่ามิเตอร์
  Future<void> saveMeterLog(MeterLogModel log) async {
    await _db
        .collection('users')
        .doc(log.uid)
        .collection('meter_logs')
        .doc(log.id)
        .set(log.toMap());
  }

  // ดึงประวัติค่ามิเตอร์ทั้งหมด
  Stream<List<MeterLogModel>> getMeterLogs(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('meter_logs')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MeterLogModel.fromMap(doc.data()))
            .toList());
  }

  // ดึงค่ามิเตอร์ล่าสุด
  Future<MeterLogModel?> getLatestMeterLog(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('meter_logs')
        .orderBy('date', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return MeterLogModel.fromMap(snapshot.docs.first.data());
    }
    return null;
  }

  // ดึงค่ามิเตอร์ในรอบเดือนปัจจุบัน
  Future<List<MeterLogModel>> getCurrentMonthLogs(
      String uid, DateTime startDate, DateTime endDate) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('meter_logs')
        .where('date', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('date', isLessThanOrEqualTo: endDate.toIso8601String())
        .orderBy('date')
        .get();

    return snapshot.docs
        .map((doc) => MeterLogModel.fromMap(doc.data()))
        .toList();
  }

  // ลบค่ามิเตอร์
  Future<void> deleteMeterLog(String uid, String logId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('meter_logs')
        .doc(logId)
        .delete();
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

  // ดึงบิลทั้งหมด
  Future<List<BillModel>> getBills(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .orderBy('year', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => BillModel.fromMap(doc.data()))
        .toList();
  }

  // ดึงบิลย้อนหลัง N เดือน
  Future<List<BillModel>> getRecentBills(String uid, int months) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .orderBy('year', descending: true)
        .limit(months)
        .get();

    return snapshot.docs
        .map((doc) => BillModel.fromMap(doc.data()))
        .toList();
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