import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../utils/forecaster.dart';
import 'firestore_service.dart';

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
  bool get isUnchanged => diff == 0;
}

/// ผลพยากรณ์ "ยอดบิลรอบปัจจุบัน" (รอบที่ยังไม่ปิด) ด้วย Moving Average
/// ต่างจาก forecastNextMonth ที่พยากรณ์ "เดือนถัดไปทั้งเดือน" ด้วย Linear Regression
/// อันนี้ตอบคำถามว่า "ถ้าใช้ในอัตรานี้ต่อไปจนสิ้นรอบบิล จะจบที่เท่าไหร่"
class CurrentCycleForecast {
  final double currentCost; // ใช้ไปแล้วเท่าไหร่ (บาท) ตั้งแต่ต้นรอบจนถึงวันนี้
  final double forecastCost; // คาดว่าจะจบรอบที่เท่าไหร่ (บาท)
  final double currentUnits; // ใช้ไปแล้วเท่าไหร่ (หน่วย)
  final double forecastUnits; // คาดว่าจะจบรอบที่เท่าไหร่ (หน่วย)
  final int daysElapsed; // ผ่านมาแล้วกี่วันในรอบนี้
  final int remainingDays; // เหลืออีกกี่วันจะตัดรอบ
  final int cycleLengthDays; // รอบบิลนี้ยาวกี่วันทั้งหมด

  CurrentCycleForecast({
    required this.currentCost,
    required this.forecastCost,
    required this.currentUnits,
    required this.forecastUnits,
    required this.daysElapsed,
    required this.remainingDays,
    required this.cycleLengthDays,
  });

  /// ความคืบหน้าของรอบบิล 0.0 - 1.0 (ใช้ทำ progress bar)
  double get progress {
    if (cycleLengthDays <= 0) return 0;
    return (daysElapsed / cycleLengthDays).clamp(0, 1);
  }

  /// มีข้อมูล log บ้างไหม (ถ้ายังไม่บันทึกมิเตอร์เลยในรอบนี้ ทุกค่าจะเป็น 0)
  bool get hasData => currentCost > 0 || currentUnits > 0;
}

/// ระดับความสำคัญของ insight ใช้กำหนดสี/ไอคอนตอนแสดงผล
enum InsightLevel { good, warning, neutral }

/// ข้อสังเกต/คำแนะนำ 1 ข้อ ที่สร้างจากข้อมูลจริงของผู้ใช้
class AnalysisInsight {
  final String text;
  final InsightLevel level;

  AnalysisInsight(this.text, this.level);
}

class AnalysisService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ดึงบิลทั้งหมดของ user เรียงจากเก่า -> ใหม่
  /// limitMonths: ดึงกี่เดือนล่าสุด (default 24 เดือน เผื่อใช้ YoY)
  ///
  /// แก้บั๊ก: เดิม .limit() ถูกเรียกก่อน orderBy ทำให้ Firestore คืนเอกสาร
  /// แบบไม่การันตีลำดับมาก่อน แล้วเรา sort เองทีหลัง — ถ้ามีบิลมากกว่า
  /// limitMonths จะได้ N ใบแบบสุ่ม ไม่ใช่ N ใบที่ใหม่ที่สุดจริง
  /// ตอนนี้ให้ Firestore เรียง year/month ก่อน แล้ว limit ที่ query เลย
  /// (ครั้งแรกที่รัน Firestore อาจโชว์ลิงก์ให้สร้าง composite index ก่อน
  /// แค่กดลิงก์นั้นครั้งเดียวพอ)
  Future<List<BillModel>> fetchBills(String uid, {int limitMonths = 24}) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('bills')
        .orderBy('year', descending: true)
        .orderBy('month', descending: true)
        .limit(limitMonths)
        .get();

    final bills = snapshot.docs
        .map((doc) => BillModel.fromMap({...doc.data(), 'id': doc.id}))
        .toList();

    // ตอนนี้ bills เรียงใหม่ -> เก่าอยู่แล้วจาก Firestore กลับเป็นเก่า -> ใหม่
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

  /// เทียบเดือนปัจจุบันกับ "ค่าเฉลี่ย" ของ N เดือนก่อนหน้า (ไม่รวมเดือนปัจจุบัน)
  /// ให้ภาพที่นิ่งกว่าการเทียบกับเดือนก่อนเดือนเดียว เพราะถ้าเดือนก่อนเป็น
  /// เดือนที่ผิดปกติ (เช่น ไปต่างจังหวัดทั้งเดือน ใช้ไฟน้อยกว่าปกติมาก)
  /// การเทียบ MoM เดือนเดียวจะดูเหมือนเดือนนี้ "พุ่ง" ทั้งที่จริงๆ แค่กลับสู่ปกติ
  /// months: จำนวนเดือนย้อนหลังที่ใช้คำนวณค่าเฉลี่ย (ดีฟอลต์ 6 เดือน)
  ComparisonResult? compareToAverage(
    List<BillModel> bills, {
    required double Function(BillModel) selector,
    int months = 6,
  }) {
    // ต้องมีเดือนปัจจุบัน + อย่างน้อย 2 เดือนก่อนหน้า ไม่งั้นค่าเฉลี่ยไม่มีความหมาย
    if (bills.length < 3) return null;

    final current = bills.last;
    final history = bills.sublist(0, bills.length - 1); // ไม่รวมเดือนปัจจุบัน
    final recent =
        history.length > months ? history.sublist(history.length - months) : history;

    final avg = recent.map(selector).reduce((a, b) => a + b) / recent.length;

    return ComparisonResult(
      currentValue: selector(current),
      previousValue: avg,
    );
  }

  /// พยากรณ์ "แนวโน้มระยะยาว" ของเดือนถัดไป ด้วย Linear Regression (Least Squares)
  /// ใช้ข้อมูลบิลที่ปิดรอบแล้วทั้งหมดเป็น training data (bills ในระบบมีแต่
  /// บิลที่ปิดรอบแล้วเท่านั้น เพราะ compileBill() ใน dashboard ถูกเรียก
  /// เฉพาะรอบก่อนหน้าที่ปิดไปแล้ว ไม่เคย compile รอบที่ยังไม่จบ)
  double forecastNextMonth(
    List<BillModel> bills, {
    required double Function(BillModel) selector,
  }) {
    if (bills.isEmpty) return 0;
    final monthlyValues = bills.map(selector).toList();
    return EnergyForecaster.linearRegression(
      monthlyValues: monthlyValues,
      forecastMonth: monthlyValues.length + 1,
    );
  }

  /// พยากรณ์ "ยอดบิลรอบปัจจุบัน" (รอบที่กำลังดำเนินอยู่ ยังไม่ปิด) ด้วย
  /// Moving Average — ใช้ logic เดียวกับที่ dashboard_screen.dart ใช้คำนวณ
  /// การ์ดพยากรณ์สิ้นเดือน เพื่อให้ตัวเลขตรงกันทั้งแอป
  ///
  /// คืนผลลัพธ์เป็น Map ที่มี key 'electricity' และ 'water'
  Future<Map<String, CurrentCycleForecast>> forecastCurrentCycle({
    required String uid,
    required FirestoreService firestoreService,
    required int billingDay,
  }) async {
    final now = DateTime.now();
    final startDate = EnergyForecaster.getCycleStart(now, billingDay);
    final endDate = EnergyForecaster.getCycleEnd(now, billingDay);
    final cycleLengthDays = endDate.difference(startDate).inDays;
    final daysElapsed = EnergyForecaster.getDaysElapsed(now, billingDay);
    final remainingDays = EnergyForecaster.getRemainingDays(now, billingDay);

    final eLogs = await firestoreService.getCurrentMonthElectricityLogs(
        uid, startDate, endDate);
    final wLogs =
        await firestoreService.getCurrentMonthWaterLogs(uid, startDate, endDate);

    final electricity = _buildCycleForecast(
      currentCost: eLogs.isNotEmpty ? eLogs.first.cost : 0,
      currentUnits: eLogs.isNotEmpty ? eLogs.first.usedFromStart : 0,
      logsCostDescending: eLogs.map((l) => l.cost).toList(),
      dailyUnitsDelta:
          eLogs.map((l) => l.usedFromLast).where((v) => v > 0).toList(),
      remainingDays: remainingDays,
      daysElapsed: daysElapsed,
      cycleLengthDays: cycleLengthDays,
    );

    final water = _buildCycleForecast(
      currentCost: wLogs.isNotEmpty ? wLogs.first.cost : 0,
      currentUnits: wLogs.isNotEmpty ? wLogs.first.usedFromStart : 0,
      logsCostDescending: wLogs.map((l) => l.cost).toList(),
      dailyUnitsDelta:
          wLogs.map((l) => l.usedFromLast).where((v) => v > 0).toList(),
      remainingDays: remainingDays,
      daysElapsed: daysElapsed,
      cycleLengthDays: cycleLengthDays,
    );

    return {'electricity': electricity, 'water': water};
  }

  CurrentCycleForecast _buildCycleForecast({
    required double currentCost,
    required double currentUnits,
    required List<double> logsCostDescending,
    required List<double> dailyUnitsDelta,
    required int remainingDays,
    required int daysElapsed,
    required int cycleLengthDays,
  }) {
    final dailyCostDeltas = _dailyCostDeltas(logsCostDescending);

    final forecastCost = EnergyForecaster.movingAverage(
      dailyUsage: dailyCostDeltas,
      remainingDays: remainingDays,
      currentTotal: currentCost,
    );
    final forecastUnits = EnergyForecaster.movingAverage(
      dailyUsage: dailyUnitsDelta,
      remainingDays: remainingDays,
      currentTotal: currentUnits,
    );

    return CurrentCycleForecast(
      currentCost: currentCost,
      forecastCost: forecastCost,
      currentUnits: currentUnits,
      forecastUnits: forecastUnits,
      daysElapsed: daysElapsed,
      remainingDays: remainingDays,
      cycleLengthDays: cycleLengthDays,
    );
  }

  /// คำนวณ "บาทที่เพิ่มขึ้นต่อครั้งบันทึก" จากค่า cost สะสม (cumulative)
  /// ของ log แต่ละตัว (เหมือน dashboard_screen.dart) เพราะ field `cost`
  /// ในโมเดลเป็นยอดสะสมจากต้นรอบ ไม่ใช่ค่าต่อช่วงอยู่แล้ว — รับลิสต์ cost
  /// ที่เรียงล่าสุดมาก่อน (ตามที่ FirestoreService คืนมา) แล้วกลับลำดับ
  /// เป็นเก่า->ใหม่ก่อนหาผลต่าง
  List<double> _dailyCostDeltas(List<double> costsDescending) {
    if (costsDescending.length < 2) return [];
    final ascending = costsDescending.reversed.toList();
    final deltas = <double>[];
    for (int i = 1; i < ascending.length; i++) {
      final delta = ascending[i] - ascending[i - 1];
      if (delta > 0) deltas.add(delta);
    }
    return deltas;
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
  ///
  /// หมายเหตุ: กรองอุปกรณ์ด้วยการมีตารางการใช้งาน (schedules ไม่ว่าง) เท่านั้น
  /// (เดิมมี field isActive ในโมเดล แต่ไม่มี UI ให้ผู้ใช้ปิด/เปิดจริง
  /// จึงลบ field นี้ทิ้งไปแล้ว เพื่อไม่ให้ดูเหมือนมีฟีเจอร์ที่ใช้งานไม่ได้)
  List<ApplianceUsage> applianceBreakdown(
    List<ApplianceModel> appliances, {
    int totalDaysInPeriod = 30,
    double avgRatePerUnit = 4.5,
  }) {
    final active = appliances.where((a) => a.schedules.isNotEmpty);

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

  /// สร้างข้อสังเกต/คำแนะนำอัตโนมัติจากข้อมูลค่าไฟ/ค่าน้ำของผู้ใช้
  /// label: ใช้ขึ้นต้นข้อความ เช่น 'ค่าไฟ' หรือ 'ค่าน้ำ'
  List<AnalysisInsight> generateUtilityInsights({
    required String label,
    required List<BillModel> bills,
    required double Function(BillModel) selector,
    required ComparisonResult? mom,
    required ComparisonResult? yoy,
    required double forecastNextMonth,
    CurrentCycleForecast? currentCycle,
  }) {
    final insights = <AnalysisInsight>[];

    // ----- 1. พยากรณ์ยอดรอบปัจจุบัน เทียบกับเดือนก่อน -----
    if (currentCycle != null && currentCycle.hasData && bills.isNotEmpty) {
      final lastActual = selector(bills.last);
      if (lastActual > 0) {
        final diffPercent =
            ((currentCycle.forecastCost - lastActual) / lastActual) * 100;
        if (diffPercent >= 15) {
          insights.add(AnalysisInsight(
            'แนวโน้ม$labelรอบนี้คาดว่าจะสูงกว่าเดือนก่อนประมาณ '
            '${diffPercent.toStringAsFixed(0)}% หากใช้งานในอัตราเดิมต่อไป '
            'อาจลองลดการใช้งานในช่วงที่เหลือของรอบบิล',
            InsightLevel.warning,
          ));
        } else if (diffPercent <= -15) {
          insights.add(AnalysisInsight(
            '$labelรอบนี้มีแนวโน้มลดลงจากเดือนก่อนประมาณ '
            '${diffPercent.abs().toStringAsFixed(0)}% ทำได้ดีมาก',
            InsightLevel.good,
          ));
        }
      }
    }

    // ----- 2. เทรนด์ต่อเนื่อง 3 เดือนล่าสุด -----
    if (bills.length >= 3) {
      final last3 = bills.sublist(bills.length - 3).map(selector).toList();
      final increasing = last3[0] < last3[1] && last3[1] < last3[2];
      final decreasing = last3[0] > last3[1] && last3[1] > last3[2];
      if (increasing) {
        insights.add(AnalysisInsight(
          '$labelเพิ่มขึ้นต่อเนื่อง 3 เดือนล่าสุด ควรตรวจสอบว่ามีอุปกรณ์ใช้งานเพิ่มขึ้นหรือไม่',
          InsightLevel.warning,
        ));
      } else if (decreasing) {
        insights.add(AnalysisInsight(
          '$labelลดลงต่อเนื่อง 3 เดือนล่าสุด แนวโน้มดีขึ้นเรื่อย ๆ',
          InsightLevel.good,
        ));
      }
    }

    // ----- 3. เทียบปีก่อน (เดือนเดียวกัน) -----
    if (yoy != null && yoy.percentChange != null) {
      if (yoy.isIncrease && yoy.percentChange! >= 25) {
        insights.add(AnalysisInsight(
          '$labelเดือนนี้สูงกว่าเดือนเดียวกันของปีก่อนถึง '
          '${yoy.percentChange!.toStringAsFixed(0)}% มากกว่าปกติ',
          InsightLevel.warning,
        ));
      }
    }

    // ----- 4. เทียบเดือนก่อนแบบพุ่งขึ้นกะทันหัน -----
    if (mom != null && mom.percentChange != null) {
      if (mom.isIncrease && mom.percentChange! >= 30) {
        insights.add(AnalysisInsight(
          '$labelเดือนนี้พุ่งขึ้นจากเดือนก่อน ${mom.percentChange!.toStringAsFixed(0)}% '
          'แบบกะทันหัน ลองเช็กว่ามีอุปกรณ์ตัวไหนใช้งานนานขึ้นผิดปกติ',
          InsightLevel.warning,
        ));
      }
    }

    // ถ้าไม่มีข้อสังเกตที่น่าเป็นห่วงเลย ให้ feedback เชิงบวกแทนความเงียบ
    if (insights.isEmpty && bills.length >= 2) {
      insights.add(AnalysisInsight(
        '$labelอยู่ในเกณฑ์ปกติ ไม่มีความผิดปกติที่ต้องสนใจในช่วงนี้',
        InsightLevel.neutral,
      ));
    }

    return insights;
  }

  /// ข้อสังเกตเกี่ยวกับสัดส่วนการใช้ไฟของอุปกรณ์
  List<AnalysisInsight> generateApplianceInsights(
    List<ApplianceUsage> breakdown,
  ) {
    final insights = <AnalysisInsight>[];
    if (breakdown.isEmpty) return insights;

    final top = breakdown.first;
    if (top.percentOfTotal >= 50) {
      insights.add(AnalysisInsight(
        '${top.appliance.name} ใช้ไฟคิดเป็น ${top.percentOfTotal.toStringAsFixed(0)}% '
        'ของทั้งหมดเพียงเครื่องเดียว ถ้าลดเวลาใช้งานเครื่องนี้ลงจะเห็นผลชัดเจนที่สุด',
        InsightLevel.warning,
      ));
    } else if (breakdown.length >= 3) {
      insights.add(AnalysisInsight(
        'อุปกรณ์ 3 อันดับแรก (${breakdown.take(3).map((u) => u.appliance.name).join(", ")}) '
        'รวมกันใช้ไฟ ${breakdown.take(3).fold<double>(0, (s, u) => s + u.percentOfTotal).toStringAsFixed(0)}% '
        'ของทั้งหมด',
        InsightLevel.neutral,
      ));
    }

    return insights;
  }
}