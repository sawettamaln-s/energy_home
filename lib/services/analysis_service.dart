import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';

/// สรุปสัดส่วนการใช้พลังงานของอุปกรณ์ 1 ชิ้น ในช่วงเวลาที่กำหนด
class ApplianceUsage {
  final ApplianceModel appliance;
  final double kWh;
  final double cost; // ประมาณการด้วยอัตราเฉลี่ย (ตรงกับหน้าอุปกรณ์ใช้ 4.5 บาท/หน่วย)
  double percentOfTotal = 0; // จะถูกเซ็ตหลังคำนวณรวมทุกอุปกรณ์แล้ว

  ApplianceUsage({
    required this.appliance,
    required this.kWh,
    required this.cost,
  });
}

/// ผลลัพธ์การเปรียบเทียบ (ใช้ได้ทั้ง MoM และ YoY)
class ComparisonResult {
  final double currentValue;
  final double previousValue;
  final double diff; // current - previous
  final double? percentChange; // null ถ้า previous = 0 (หารไม่ได้)

  ComparisonResult({
    required this.currentValue,
    required this.previousValue,
  })  : diff = currentValue - previousValue,
        percentChange = previousValue == 0
            ? null
            : ((currentValue - previousValue) / previousValue) * 100;

  bool get isIncrease => diff > 0;
}

class AnalysisService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ดึงบิลทั้งหมดของ user เรียงจากเก่า -> ใหม่
  /// limitMonths: ดึงกี่เดือนล่าสุด (default 24 เดือน เผื่อใช้ YoY)
Future<List<BillModel>> fetchBills(String uid, {int limitMonths = 24}) async {
  final snapshot = await _db
      .collection('users')
      .doc(uid)
      .collection('bills')
      .limit(limitMonths)
      .get();

  final bills = snapshot.docs
      .map((doc) => BillModel.fromMap({...doc.data(), 'id': doc.id}))
      .toList();

  // เรียง manual ใน Dart แทน
  bills.sort((a, b) {
    if (a.year != b.year) return b.year.compareTo(a.year);
    return b.month.compareTo(a.month);
  });

  return bills.reversed.toList();
}

  /// เทียบเดือนนี้ vs เดือนก่อนหน้า (Month over Month)
  /// bills ต้องเรียงเก่า->ใหม่ และเดือนล่าสุดต้องอยู่ index สุดท้าย
  ComparisonResult? compareMoM(List<BillModel> bills, {
    required double Function(BillModel) selector,
  }) {
    if (bills.length < 2) return null; // ข้อมูลไม่พอ
    final current = bills.last;
    final previous = bills[bills.length - 2];
    return ComparisonResult(
      currentValue: selector(current),
      previousValue: selector(previous),
    );
  }

  /// เทียบเดือนนี้ของปีนี้ vs เดือนเดียวกันของปีก่อน (Year over Year)
  ComparisonResult? compareYoY(List<BillModel> bills, {
    required double Function(BillModel) selector,
  }) {
    if (bills.isEmpty) return null;
    final current = bills.last;

    BillModel? sameMonthLastYear;
    for (final b in bills) {
      if (b.year == current.year - 1 && b.month == current.month) {
        sameMonthLastYear = b;
        break;
      }
    }
    if (sameMonthLastYear == null) return null; // ไม่มีข้อมูลปีก่อน

    return ComparisonResult(
      currentValue: selector(current),
      previousValue: selector(sameMonthLastYear),
    );
  }

  /// พยากรณ์เดือนถัดไปแบบ Simple Moving Average
  /// monthsToAverage: ใช้กี่เดือนล่าสุดในการเฉลี่ย (default 3)
  double forecastNextMonth(
    List<BillModel> bills, {
    required double Function(BillModel) selector,
    int monthsToAverage = 3,
  }) {
    if (bills.isEmpty) return 0;
    final recent = bills.length <= monthsToAverage
        ? bills
        : bills.sublist(bills.length - monthsToAverage);
    final sum = recent.fold<double>(0, (acc, b) => acc + selector(b));
    return sum / recent.length;
  }

  /// คำนวณ kWh ของอุปกรณ์ 1 ชิ้นในช่วง totalDaysInPeriod วัน
  /// (สูตรเดียวกับที่ใช้ในหน้าอุปกรณ์ เพื่อให้ตัวเลขตรงกันทั้งแอป)
  double _kWhForPeriod(ApplianceModel a, int totalDaysInPeriod) {
    double kWh = 0;
    for (final s in a.schedules) {
      final activeDays = (s.days.length / 7) * totalDaysInPeriod;
      kWh += (a.watt * s.hoursPerDay / 1000) * activeDays;
    }
    return kWh;
  }

  /// จัดอันดับอุปกรณ์ตามการใช้พลังงาน (มาก -> น้อย) พร้อม % ของยอดรวม
  /// totalDaysInPeriod: 30 = รายเดือน, 365 = รายปี
  /// avgRatePerUnit: อัตราค่าไฟเฉลี่ยประมาณการ บาท/หน่วย (ดีฟอลต์ 4.5 ให้ตรงกับหน้าอุปกรณ์)
  List<ApplianceUsage> applianceBreakdown(
    List<ApplianceModel> appliances, {
    int totalDaysInPeriod = 30,
    double avgRatePerUnit = 4.5,
  }) {
    final active = appliances.where((a) => a.isActive && a.schedules.isNotEmpty);

    final usages = active.map((a) {
      final kWh = _kWhForPeriod(a, totalDaysInPeriod);
      return ApplianceUsage(
        appliance: a,
        kWh: kWh,
        cost: kWh * avgRatePerUnit,
      );
    }).toList();

    final totalKwh = usages.fold<double>(0, (sum, u) => sum + u.kWh);
    if (totalKwh > 0) {
      for (final u in usages) {
        u.percentOfTotal = (u.kWh / totalKwh) * 100;
      }
    }

    usages.sort((a, b) => b.kWh.compareTo(a.kWh)); // มาก -> น้อย
    return usages;
  }
}