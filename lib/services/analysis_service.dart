import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/appliance_model.dart';
import '../models/bill_model.dart';
import '../utils/appliance_energy.dart';
import '../utils/appliance_rate.dart';
import '../utils/calculator.dart';
import '../utils/cycle_projection.dart';
import '../utils/forecaster.dart';
import '../utils/seasonal_curves.dart';
import '../utils/thai_date_utils.dart';
import 'firestore_service.dart';

// คิดเงินจากหน่วยที่คาดการณ์ (TOU ใช้ peakUnits/offPeakUnits, อื่นๆ ใช้ units)
// ผู้เรียกผูกอัตราของผู้ใช้ไว้ให้ เช่น ประเภทอัตรา พื้นที่ และค่า Ft
typedef UnitPricer = double Function({
  required double units,
  required double peakUnits,
  required double offPeakUnits,
});

/// สรุปสัดส่วนการใช้พลังงานของอุปกรณ์ 1 ชิ้น ในช่วงเวลาที่กำหนด
class ApplianceUsage {
  final ApplianceModel appliance;
  final double kWh;
  final double cost; // ประมาณการด้วยอัตราเฉลี่ยต่อหน่วยเดียวกับหน้าอุปกรณ์ (ApplianceRate)
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

/// ผลคาดการณ์ "ยอดบิลรอบปัจจุบัน" (รอบที่ยังไม่ปิด) จากอัตราเฉลี่ยต่อวัน
/// ต่างจาก forecastNextMonth ที่คาดการณ์ "เดือนถัดไปทั้งเดือน" ด้วย seasonal curve
/// (เมื่อรู้ area+meterType) หรือ linear regression (เมื่อไม่รู้)
/// อันนี้ตอบคำถามว่า "ถ้าใช้ในอัตรานี้ต่อไปจนสิ้นรอบบิล จะจบที่เท่าไหร่"
class CurrentCycleForecast {
  final double currentCost; // ใช้ไปแล้วเท่าไหร่ (บาท) ตั้งแต่ต้นรอบจนถึงวันนี้
  final double forecastCost; // คาดว่าจะจบรอบที่เท่าไหร่ (บาท)
  final double currentUnits; // ใช้ไปแล้วเท่าไหร่ (หน่วย)
  final double forecastUnits; // คาดว่าจะจบรอบที่เท่าไหร่ (หน่วย)
  final int daysElapsed; // ผ่านมาแล้วกี่วันในรอบนี้
  final int remainingDays; // เหลืออีกกี่วันจะตัดรอบ
  final int cycleLengthDays; // รอบบิลนี้ยาวกี่วันทั้งหมด
  // เดือนของใบแจ้งหนี้รอบนี้ (= เดือนของวันตัดรอบ วันที่ 1) ตรงกับ year/month
  // ของบิลที่ระบบจะปิดให้เมื่อจบรอบ
  final DateTime billMonth;

  CurrentCycleForecast({
    required this.currentCost,
    required this.forecastCost,
    required this.currentUnits,
    required this.forecastUnits,
    required this.daysElapsed,
    required this.remainingDays,
    required this.cycleLengthDays,
    required this.billMonth,
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

  // true เฉพาะข้อสังเกตที่ชี้ไปยัง "เดือนที่ใช้สูงสุด" — ให้ UI ต่อท้ายด้วย
  // ปุ่มลิงก์ไปแท็บอุปกรณ์ เพื่อให้ผู้ใช้ตรวจสอบต่อได้ทันทีว่าอุปกรณ์ไหน
  // กินไฟเยอะสุด แทนที่จะบอกข้อสังเกตเฉยๆ แล้วจบ
  final bool showApplianceCta;

  AnalysisInsight(this.text, this.level, {this.showApplianceCta = false});
}

class AnalysisService {
  // ฉีด FirebaseFirestore ปลอมได้ในเทส (แบบเดียวกับ FirestoreService)
  // ไม่ส่ง = ใช้ FirebaseFirestore.instance
  AnalysisService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// ดึงบิลทั้งหมดของ user เรียงจากเก่า -> ใหม่
  /// limitMonths: ดึงกี่เดือนล่าสุด (default 24 เดือน เผื่อใช้ YoY)
  ///
  /// Query สั่ง Firestore เรียง year/month ก่อนแล้ว limit ที่ query เลย
  /// เพื่อให้ได้บิล N เดือนล่าสุดจริง (ไม่ใช่สุ่ม)
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

  /// หาบิลที่ตรงกับปี/เดือน (ปฏิทิน) ที่ระบุเป๊ะๆ — ใช้แทนการ index list
  /// ตรงๆ เพราะบันทึกย้อนหลังไม่บังคับให้กรอกครบทุกเดือน (ข้ามเดือนได้)
  /// ถ้า index ชนกันโดยไม่เช็คเดือนจริง จะเทียบผิดเดือนแบบเงียบๆ ได้
  BillModel? _findBillForMonth(List<BillModel> bills, int year, int month) {
    for (final b in bills) {
      if (b.year == year && b.month == month) return b;
    }
    return null;
  }

  /// คืนปี/เดือนปฏิทินที่ย้อนหลังไป [monthsBack] เดือนจาก year/month ที่ให้มา
  /// (Dart จัดการ wrap ปีให้เองตอน month ติดลบ/เกิน 12)
  DateTime _monthsBefore(int year, int month, int monthsBack) {
    return DateTime(year, month - monthsBack, 1);
  }

  /// เทียบเดือนนี้ vs เดือนก่อนหน้า (Month over Month)
  /// bills ต้องเรียงเก่า->ใหม่ และเดือนล่าสุดต้องอยู่ index สุดท้าย
  ///
  /// เช็คปี/เดือนจริงว่าติดกันหรือไม่ก่อนเทียบ ถ้าไม่มีข้อมูลเดือนก่อนหน้า
  /// จริง (เช่นมีแค่เดือน 5 กับ 7 แต่เดือน 6 ไม่มีข้อมูล) จะคืน null
  /// (ไม่โชว์การ์ด MoM) แทนการเอาเดือนที่ห่างกันมาเทียบกันผิดๆ
  ComparisonResult? compareMoM(List<BillModel> bills, {
    required double Function(BillModel) selector,
  }) {
    if (bills.isEmpty) return null; // ข้อมูลไม่พอ
    final current = bills.last;
    final prevMonth = _monthsBefore(current.year, current.month, 1);
    final previous =
        _findBillForMonth(bills, prevMonth.year, prevMonth.month);
    if (previous == null) return null; // เดือนก่อนหน้าจริงไม่มีข้อมูล
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
  /// months: จำนวนเดือนปฏิทินย้อนหลังที่ใช้คำนวณค่าเฉลี่ย (ดีฟอลต์ 6 เดือน)
  ///
  /// ไล่ทีละเดือนปฏิทินย้อนหลังจาก [months] เดือน แล้วเฉลี่ยเฉพาะเดือนที่มี
  /// ข้อมูลจริงในช่วงนั้น เดือนที่ขาดหายไปจะไม่ถูกนับ เพื่อไม่ให้ค่าเฉลี่ย
  /// ครอบคลุมช่วงเวลากว้างกว่าที่บอกไว้
  ComparisonResult? compareToAverage(
    List<BillModel> bills, {
    required double Function(BillModel) selector,
    int months = 6,
  }) {
    if (bills.isEmpty) return null;
    final current = bills.last;

    final recentMatches = <BillModel>[];
    for (int i = 1; i <= months; i++) {
      final target = _monthsBefore(current.year, current.month, i);
      final match = _findBillForMonth(bills, target.year, target.month);
      if (match != null) recentMatches.add(match);
    }

    // ต้องมีอย่างน้อย 2 เดือนก่อนหน้าจริงในช่วงที่กำหนด ไม่งั้นค่าเฉลี่ยไม่มีความหมาย
    if (recentMatches.length < 2) return null;

    final avg =
        recentMatches.map(selector).reduce((a, b) => a + b) / recentMatches.length;

    return ComparisonResult(
      currentValue: selector(current),
      previousValue: avg,
    );
  }

  /// คาดการณ์ "แนวโน้มระยะยาว" ของเดือนถัดไป
  ///
  /// ถ้าใส่ area+meterType มา (รู้ area/meterType ของ user คนนี้) จะใช้
  /// "seasonal curve" (สร้างจากสถิติการใช้จริงรายเดือน ดู tool/seasonal_curves/)
  /// ซึ่งจับรูปแบบฤดูกาลได้ ต่างจาก linear regression ที่จับไม่ได้
  ///
  /// ถ้าไม่ใส่ area/meterType มา จะ fallback ไปใช้ linear regression
  ///
  /// [targetMonth] = เดือนของบิลที่จะคาดการณ์ (วันที่ 1) ไม่ใส่ = เดือนถัดจาก
  /// บิลล่าสุด ต้องอยู่หลังบิลล่าสุด
  double forecastNextMonth(
    List<BillModel> bills, {
    required double Function(BillModel) selector,
    String? area,
    String? meterType,
    bool isWater = false,
    DateTime? targetMonth,
  }) {
    if (bills.isEmpty) return 0;
    final monthlyValues = bills.map(selector).toList();
    final current = bills.last;
    final target =
        targetMonth ?? DateTime(current.year, current.month + 1, 1);

    final curve = _resolveCurve(area: area, meterType: meterType, isWater: isWater);
    if (curve != null) {
      final recentBills = _recentWindow(bills);
      return EnergyForecaster.seasonalForecast(
        recentMonthlyValues: recentBills.map(selector).toList(),
        recentMonths: recentBills.map((b) => b.month).toList(),
        curve: curve,
        forecastMonth: target.month,
      );
    }

    // เส้นแนวโน้มวางบิลตามลำดับเดือนจริง (เดือนที่ขาดเว้นช่องไว้) และทายที่
    // ลำดับเดือนของเป้าหมาย — เป้าหมายต้องอยู่หลังบิลล่าสุดอย่างน้อย 1 เดือน
    final lastIndex = _monthIndex(bills, current.year, current.month);
    final targetIndex = _monthIndex(bills, target.year, target.month);
    return EnergyForecaster.linearRegression(
      monthlyValues: monthlyValues,
      monthIndexes: _monthIndexes(bills),
      forecastMonth: targetIndex > lastIndex ? targetIndex : lastIndex + 1,
    );
  }

  // ลำดับเดือนของ year/month นับจากบิลแรกสุด (บิลแรก = 1) — ใช้เป็นแกน X ของ
  // เส้นแนวโน้ม ให้เดือนที่ขาดหายเว้นช่องตามจริง ไม่ถูกบีบให้ติดกัน
  int _monthIndex(List<BillModel> bills, int year, int month) {
    final first = bills.first;
    return (year * 12 + month) - (first.year * 12 + first.month) + 1;
  }

  List<int> _monthIndexes(List<BillModel> bills) =>
      [for (final b in bills) _monthIndex(bills, b.year, b.month)];

  /// คาดการณ์ "ค่าใช้จ่าย" ของบิลเดือน [targetMonth] (ไม่ส่ง = เดือนถัดจากบิล
  /// ล่าสุด): ทายหน่วยด้วย [forecastNextMonth] แล้วคิดเงินด้วย [price] — ไม่
  /// เอายอดเงินไปคูณตัวคูณฤดูกาลตรงๆ เพราะค่าบริการรายเดือนไม่ขึ้นกับหน่วย และ
  /// อัตราเป็นขั้นบันได หน่วยกับเงินที่คาดการณ์จึงตรงกันตามตารางอัตรา
  ///
  /// ใช้เฉพาะบิลที่มีหน่วย (บิลแรกสุดจากการตั้งเลขต้นรอบอาจมีแต่ยอดเงิน)
  /// TOU แบ่งหน่วยเป็น On/Off-Peak ตามสัดส่วนของบิลที่มีหน่วยแยกช่วง ถ้าไม่มี
  /// บิลที่มีหน่วยเลย (หรือ TOU ที่ไม่มีบิลแยกช่วง) ทายจากยอดเงินแทน
  double forecastCostFromUnits(
    List<BillModel> bills, {
    required double Function(BillModel) costSelector,
    required double Function(BillModel) usedSelector,
    required UnitPricer price,
    double Function(BillModel)? peakSelector,
    double Function(BillModel)? offPeakSelector,
    String? area,
    String? meterType,
    bool isWater = false,
    DateTime? targetMonth,
  }) {
    if (bills.isEmpty) return 0;
    final target =
        targetMonth ?? DateTime(bills.last.year, bills.last.month + 1, 1);
    double fromCost() => forecastNextMonth(
          bills,
          selector: costSelector,
          area: area,
          meterType: meterType,
          isWater: isWater,
          targetMonth: target,
        );

    final withUnits = bills.where((b) => usedSelector(b) > 0).toList();
    if (withUnits.isEmpty) return fromCost();

    final isTou = peakSelector != null && offPeakSelector != null;
    var peakShare = 0.0;
    if (isTou) {
      var peak = 0.0;
      var total = 0.0;
      for (final b in withUnits) {
        final p = peakSelector(b);
        final o = offPeakSelector(b);
        if (p + o <= 0) continue;
        peak += p;
        total += p + o;
      }
      if (total <= 0) return fromCost();
      peakShare = peak / total;
    }

    final units = forecastNextMonth(
      withUnits,
      selector: usedSelector,
      area: area,
      meterType: meterType,
      isWater: isWater,
      targetMonth: target,
    );
    return price(
      units: units,
      peakUnits: isTou ? units * peakShare : 0,
      offPeakUnits: isTou ? units * (1 - peakShare) : 0,
    );
  }

  /// [forecastCostFromUnits] ของ [months] เดือนถัดจากบิลล่าสุด เรียงตามเดือน
  List<double> forecastNextMonthsCost(
    List<BillModel> bills, {
    required double Function(BillModel) costSelector,
    required double Function(BillModel) usedSelector,
    required UnitPricer price,
    double Function(BillModel)? peakSelector,
    double Function(BillModel)? offPeakSelector,
    int months = 3,
    String? area,
    String? meterType,
    bool isWater = false,
  }) {
    if (bills.isEmpty) return List.filled(months, 0);
    final last = bills.last;
    return [
      for (var i = 1; i <= months; i++)
        forecastCostFromUnits(
          bills,
          costSelector: costSelector,
          usedSelector: usedSelector,
          price: price,
          peakSelector: peakSelector,
          offPeakSelector: offPeakSelector,
          area: area,
          meterType: meterType,
          isWater: isWater,
          targetMonth: DateTime(last.year, last.month + i, 1),
        ),
    ];
  }

  /// คืนตัวคูณฤดูกาลของเดือนที่ระบุ (1 = ม.ค. ... 12 = ธ.ค.) ตาม area+meterType
  /// ที่ส่งมา ใช้ประกอบคำอธิบายเหตุผลในการ์ดคาดการณ์ (ดู _seasonReasonText ใน
  /// analysis_utility_tab.dart) — ไม่ได้ใช้คำนวณตัวเลขคาดการณ์เอง (ตัวเลขนั้น
  /// คำนวณผ่าน forecastNextMonth ที่เรียก curve ตรงๆ อยู่แล้ว)
  ///
  /// คืน 1.0 (ไม่มีผลปรับ) ถ้ายังไม่รู้ area/meterType ของ user คนนี้ หรือไม่มี
  /// เคสตรงกับ curve ที่มี
  double seasonalFactorForMonth({
    required int month,
    required String? area,
    required String? meterType,
    required bool isWater,
  }) {
    final curve = _resolveCurve(area: area, meterType: meterType, isWater: isWater);
    if (curve == null) return 1.0;
    return curve[month - 1];
  }

  /// หา seasonal curve ที่ตรงกับ area+meterType — คืน null ถ้าไม่ครบ/ไม่รู้จัก
  /// เคส (ตัวเรียกจะ fallback ไป linear regression เอง)
  List<double>? _resolveCurve({
    required String? area,
    required String? meterType,
    required bool isWater,
  }) {
    if (area == null || meterType == null) return null;
    final caseKey = SeasonalCurves.caseKeyFor(area: area, meterType: meterType);
    final curveMap = isWater ? SeasonalCurves.water : SeasonalCurves.elec;
    return curveMap[caseKey];
  }

  /// ใช้ 3 เดือนล่าสุดเป็นตัวแทน "ระดับการใช้ปัจจุบัน" ของ user คนนี้
  /// (ถ้ามีน้อยกว่า 3 เดือน ใช้เท่าที่มี) — คืนเป็น BillModel เพื่อให้ผู้เรียก
  /// ดึงได้ทั้งค่าที่ต้องการ (ผ่าน selector) และเดือนปฏิทิน (.month) สำหรับหัก
  /// ฤดูกาลออกก่อนเฉลี่ยใน seasonalForecast
  List<BillModel> _recentWindow(List<BillModel> bills, {int months = 3}) {
    if (bills.length <= months) return bills;
    return bills.sublist(bills.length - months);
  }

  /// คาดการณ์ "ยอดบิลรอบปัจจุบัน" (รอบที่กำลังดำเนินอยู่ ยังไม่ปิด) ด้วย
  /// projectElectricityToCycleEnd/projectWaterToCycleEnd (cycle_projection.dart)
  /// ตัวเดียวกับที่หน้าหลัก (dashboard_loader.dart) ใช้ เพื่อให้ตัวเลขตรงกันทั้งแอป
  /// [startPeak]/[startOffPeak] = เลขต้นรอบของรอบปัจจุบัน (TOU เท่านั้น)
  ///
  /// คืนผลลัพธ์เป็น Map ที่มี key 'electricity' และ 'water'
  Future<Map<String, CurrentCycleForecast>> forecastCurrentCycle({
    required String uid,
    required FirestoreService firestoreService,
    required int billingDay,
    required String area,
    required String meterType,
    double startPeak = 0,
    double startOffPeak = 0,
    String tariff = EnergyCalculator.tariffStandard,
  }) async {
    final now = DateTime.now();
    final startDate = EnergyForecaster.getCycleStart(now, billingDay);
    final endDate = EnergyForecaster.getCycleEnd(now, billingDay);
    final cycleLengthDays =
        EnergyForecaster.getCycleLengthDays(now, billingDay);
    final daysElapsed = EnergyForecaster.getDaysElapsed(now, billingDay);
    final remainingDays = EnergyForecaster.getRemainingDays(now, billingDay);
    final billMonth = DateTime(endDate.year, endDate.month, 1);

    final eLogs = await firestoreService.getCurrentMonthElectricityLogs(
        uid, startDate, endDate);
    final wLogs =
        await firestoreService.getCurrentMonthWaterLogs(uid, startDate, endDate);

    // log เรียงใหม่สุดก่อน — ตัวแรกคือยอดสะสม ณ วันที่บันทึกล่าสุด
    final eLast = eLogs.isNotEmpty ? eLogs.first : null;
    final wLast = wLogs.isNotEmpty ? wLogs.first : null;
    // บิลของรอบก่อน (เดือนบิล = เดือนที่รอบนี้เริ่ม) ถ่วงยอดคาดการณ์ช่วงต้นรอบ
    // กติกาเดียวกับหน้าหลัก (DashboardLoader) และ compileBill
    final priorBill = await firestoreService.getBillForMonth(
        uid, startDate.year, startDate.month);
    final eProjection = await projectElectricityToCycleEnd(
      latest: eLast,
      cycleStart: startDate,
      cycleEnd: endDate,
      meterType: meterType,
      area: area,
      startPeak: startPeak,
      startOffPeak: startOffPeak,
      tariff: tariff,
      priorPerDay:
          billUnitsPerDay(priorBill, priorBill?.electricityUsed, billingDay),
    );
    final wProjection = projectWaterToCycleEnd(
      latest: wLast,
      cycleStart: startDate,
      cycleEnd: endDate,
      area: area,
      priorPerDay: billUnitsPerDay(priorBill, priorBill?.waterUsed, billingDay),
    );

    CurrentCycleForecast build(
            double currentCost, double currentUnits, CycleProjection p) =>
        CurrentCycleForecast(
          currentCost: currentCost,
          forecastCost: p.cost,
          currentUnits: currentUnits,
          forecastUnits: p.units,
          daysElapsed: daysElapsed,
          remainingDays: remainingDays,
          cycleLengthDays: cycleLengthDays,
          billMonth: billMonth,
        );

    return {
      'electricity': build(eLast?.cost ?? 0, eLast?.usedFromStart ?? 0, eProjection),
      'water': build(wLast?.cost ?? 0, wLast?.usedFromStart ?? 0, wProjection),
    };
  }

  /// จัดอันดับอุปกรณ์ตามการใช้พลังงาน (มาก -> น้อย) พร้อม % ของยอดรวม
  /// totalDaysInPeriod: 30 = รายเดือน, 365 = รายปี
  /// avgRatePerUnit: อัตราค่าไฟเฉลี่ย บาท/หน่วย — ผู้เรียกส่งอัตราจาก ApplianceRate
  /// ตัวเดียวกับหน้าอุปกรณ์ ไม่ส่ง = ค่าเฉลี่ยประมาณการ
  ///
  /// นับเฉพาะอุปกรณ์ที่มีตารางการใช้งาน (schedules ไม่ว่าง) เท่านั้น
  List<ApplianceUsage> applianceBreakdown(
    List<ApplianceModel> appliances, {
    int totalDaysInPeriod = 30,
    double avgRatePerUnit = ApplianceRate.defaultPerUnit,
  }) {
    final active = appliances.where((a) => a.schedules.isNotEmpty);

    final usages = active.map((a) {
      final kWh = ApplianceEnergy.kWhForPeriod(a, totalDaysInPeriod);
      return ApplianceUsage(
        appliance: a,
        kWh: kWh,
        cost: kWh * avgRatePerUnit,
      );
    }).toList();

    final totalKwh = usages.fold<double>(0, (acc, u) => acc + u.kWh);
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
  /// includeComparisons: false = ไม่สร้างข้อ 3-4 (เทียบปีก่อน/เดือนก่อน) สำหรับ
  /// หน้าที่แสดงการเปรียบเทียบนั้นในการ์ดของตัวเองอยู่แล้ว
  List<AnalysisInsight> generateUtilityInsights({
    required String label,
    required List<BillModel> bills,
    required double Function(BillModel) selector,
    required ComparisonResult? mom,
    required ComparisonResult? yoy,
    CurrentCycleForecast? currentCycle,
    bool trackAppliances = true,
    bool includeComparisons = true,
  }) {
    final insights = <AnalysisInsight>[];

    // ----- 1. คาดการณ์ยอดรอบปัจจุบัน เทียบกับเดือนก่อน -----
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
    // เช็คก่อนว่าเดือนปัจจุบัน, เดือน -1, เดือน -2 มีข้อมูลครบทั้ง 3 เดือน
    // ปฏิทินติดกันจริงหรือไม่ ถ้าไม่ครบ ข้ามข้อสังเกตนี้ไปเลย
    if (bills.isNotEmpty) {
      final current = bills.last;
      final mMinus1 = _monthsBefore(current.year, current.month, 1);
      final mMinus2 = _monthsBefore(current.year, current.month, 2);
      final billMinus1 =
          _findBillForMonth(bills, mMinus1.year, mMinus1.month);
      final billMinus2 =
          _findBillForMonth(bills, mMinus2.year, mMinus2.month);

      if (billMinus1 != null && billMinus2 != null) {
        final last3 = [selector(billMinus2), selector(billMinus1), selector(current)];
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
    }

    // ----- 3. เทียบปีก่อน (เดือนเดียวกัน) -----
    if (includeComparisons && yoy != null && yoy.percentChange != null) {
      if (yoy.isIncrease && yoy.percentChange! >= 25) {
        insights.add(AnalysisInsight(
          '$labelเดือนนี้สูงกว่าเดือนเดียวกันของปีก่อนถึง '
          '${yoy.percentChange!.toStringAsFixed(0)}% มากกว่าปกติ',
          InsightLevel.warning,
        ));
      }
    }

    // ----- 4. เทียบเดือนก่อนแบบพุ่งขึ้นกะทันหัน -----
    if (includeComparisons && mom != null && mom.percentChange != null) {
      if (mom.isIncrease && mom.percentChange! >= 30) {
        insights.add(AnalysisInsight(
          '$labelเดือนนี้พุ่งขึ้นจากเดือนก่อน ${mom.percentChange!.toStringAsFixed(0)}% '
          'แบบกะทันหัน ลองเช็กว่ามีอุปกรณ์ตัวไหนใช้งานนานขึ้นผิดปกติ',
          InsightLevel.warning,
        ));
      }
    }

    // ----- 5. เดือนที่ใช้สูงสุดในข้อมูลที่เก็บไว้ (ช่วยสังเกตรูปแบบ) -----
    if (bills.length >= 3) {
      final peak = bills.reduce(
          (a, b) => selector(a) >= selector(b) ? a : b);
      if (peak != bills.last) {
        insights.add(AnalysisInsight(
          'เดือนที่ใช้$labelสูงสุดในข้อมูลที่เก็บไว้คือ '
          '${thaiMonthsShort[peak.month - 1]} ${(peak.year + 543) % 100} '
          'ที่ ${NumberFormat('#,##0').format(selector(peak))} บาท ลองสังเกตว่าช่วงนั้นมีอะไรต่างจากปกติ',
          InsightLevel.neutral,
          showApplianceCta: trackAppliances,
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