import 'package:flutter/foundation.dart';

import '../../models/bill_model.dart';
import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/calculator.dart';
import '../../utils/cycle_projection.dart';
import '../../utils/forecaster.dart';
import '../../utils/tariff_advisor.dart';
import '../../utils/thai_date_utils.dart';
import 'record_meter_screen.dart';

// =====================================================================
// ข้อมูลที่หน้าหลักแสดง 1 ชุด (ไม่เปลี่ยนค่า) — DashboardLoader.load สร้างให้
// หน้าจอเอาไปวาดอย่างเดียว ไม่คำนวณเอง
// =====================================================================
class DashboardData {
  final UserModel? user;
  final DateTime cycleStart;
  final DateTime cycleEnd;

  // log ล่าสุดของทุกรอบ — ใช้เฉพาะเช็ค "ไม่ได้บันทึกมิเตอร์มากี่วัน"
  final ElectricityLogModel? latestElectricityLog;
  final WaterLogModel? latestWaterLog;
  // log ของรอบบิลปัจจุบัน เรียงใหม่สุดก่อน
  final List<ElectricityLogModel> electricityLogs;
  final List<WaterLogModel> waterLogs;

  // ยอดของบิลล่าสุดที่ปิดแล้ว ใช้เทียบ "พุ่งขึ้น"
  final double lastMonthElectricityCost;
  final double lastMonthWaterCost;
  // หน่วยเฉลี่ยต่อวันของบิลล่าสุด (เส้นอ้างอิงในกราฟรายวัน) — null = ไม่มีบิล
  // หรือบิลนั้นไม่มีหน่วยที่ใช้
  final double? lastBillElectricityPerDay;
  final double? lastBillWaterPerDay;
  // รายจ่ายประจำของเดือนบิลรอบนี้ (ไม่ใช่ user.fixedCost ที่เป็นยอดของเดือน
  // ปฏิทินปัจจุบัน) — ตรงกับที่ compileBill จะใส่ในบิลของรอบนี้
  final double billFixedCost;

  // ยอดคาดการณ์สิ้นรอบ (ดู cycle_projection.dart)
  final double forecastElectricityCost;
  final double forecastWaterCost;
  // true = มี log ในรอบนี้ที่บันทึกห่างจากต้นรอบอย่างน้อย 1 วัน (ไฟหรือน้ำ
  // อย่างใดอย่างหนึ่ง) พอจะคำนวณอัตรา "หน่วย/วัน" ได้แล้ว ถ้า false ยอด
  // คาดการณ์จะเท่ากับยอดที่ใช้ไปแล้วเฉยๆ ซึ่งไม่ใช่การคาดการณ์จริง
  final bool hasForecastData;

  const DashboardData({
    required this.user,
    required this.cycleStart,
    required this.cycleEnd,
    this.latestElectricityLog,
    this.latestWaterLog,
    this.electricityLogs = const [],
    this.waterLogs = const [],
    this.lastMonthElectricityCost = 0,
    this.lastMonthWaterCost = 0,
    this.lastBillElectricityPerDay,
    this.lastBillWaterPerDay,
    this.billFixedCost = 0,
    this.forecastElectricityCost = 0,
    this.forecastWaterCost = 0,
    this.hasForecastData = false,
  });

  // log ล่าสุดของรอบบิลปัจจุบัน — null = รอบนี้ยังไม่ได้บันทึก ผู้เรียกใช้
  // ค่าต้นรอบแทน
  ElectricityLogModel? get cycleLatestElectricityLog =>
      electricityLogs.isNotEmpty ? electricityLogs.first : null;
  WaterLogModel? get cycleLatestWaterLog =>
      waterLogs.isNotEmpty ? waterLogs.first : null;

  // ยอดใช้ไปแล้วของรอบนี้ (log เป็นยอดสะสมตั้งแต่ต้นรอบ)
  double get currentElectricityCost => cycleLatestElectricityLog?.cost ?? 0;
  double get currentWaterCost => cycleLatestWaterLog?.cost ?? 0;
  double get currentElectricityUnits =>
      cycleLatestElectricityLog?.usedFromStart ?? 0;
  double get currentWaterUnits => cycleLatestWaterLog?.usedFromStart ?? 0;
  double get forecastTotal => forecastElectricityCost + forecastWaterCost;

  bool get isTou => user?.meterType == 'tou';

  // สัดส่วนหน่วย On-Peak (0–1) ที่ใช้ในรอบนี้ของมิเตอร์ TOU = เลขล่าสุดลบ
  // เลขต้นรอบของแต่ละช่วง — null = ไม่ใช่ TOU, รอบนี้ยังไม่ได้จด หรือยังไม่มี
  // หน่วยที่ใช้เลย
  double? get cyclePeakShare {
    final log = cycleLatestElectricityLog;
    final u = user;
    if (!isTou || log == null || u == null) return null;
    final peak = ((log.peakMeterValue ?? u.startPeakValue) - u.startPeakValue)
        .clamp(0.0, double.infinity);
    final offPeak =
        ((log.offPeakMeterValue ?? u.startOffPeakValue) - u.startOffPeakValue)
            .clamp(0.0, double.infinity);
    final total = peak + offPeak;
    return total > 0 ? peak / total : null;
  }

  // ค่ามิเตอร์ต้นรอบที่ตั้งไว้ยังตรงกับรอบบิลปัจจุบันไหม — flag
  // electricityStartConfigured/waterStartConfigured บอกแค่ว่าเคยตั้งหรือยัง
  // ไม่ได้บอกว่าเป็นของรอบไหน ถ้าข้ามวันตัดรอบไปแล้วยังไม่ได้ตั้งของรอบใหม่
  // แล้วปล่อยให้บันทึก ระบบจะเอาเลขวันนี้ไปลบกับต้นรอบของรอบก่อน ได้หน่วยที่
  // ใช้ปนกันสองรอบ — ตัดสินด้วย EnergyForecaster.matchesCurrentCycle ตัวเดียว
  // กับหน้าตั้งเลขต้นรอบ โดยยึดรอบบิลชุดเดียวกับข้อมูลนี้ (cycleStart)
  // (startBillingMonth/Year = เดือนที่รอบเริ่ม ใช้ร่วมกันทั้งไฟและน้ำ)
  bool get startMeterMatchesCurrentCycle {
    final u = user;
    if (u == null) return false;
    return EnergyForecaster.matchesCurrentCycle(
      billingMonth: u.startBillingMonth,
      billingYear: u.startBillingYear,
      billingDay: u.billingDay,
      now: cycleStart,
    );
  }

  // พร้อมบันทึก log รายวันไหม (แยกรายยูทิลิตี้) = เคยตั้งค่ามาก่อน และค่านั้น
  // ยังตรงกับรอบปัจจุบัน ไม่พร้อม = การ์ดล็อกให้ตั้งเลขต้นรอบก่อน
  bool get electricityMeterReady =>
      (user?.electricityStartConfigured ?? true) &&
      startMeterMatchesCurrentCycle;
  bool get waterMeterReady =>
      (user?.waterStartConfigured ?? true) && startMeterMatchesCurrentCycle;

  // ข้อความบนการ์ดล็อกเมื่อเลขต้นรอบที่ตั้งไว้ไม่ตรงกับรอบปัจจุบัน — บอกวันที่
  // รอบปัจจุบันเริ่มเสมอ ถ้าเลขต้นรอบเป็นของรอบที่ "ใหม่กว่า" รอบปัจจุบัน แปลว่า
  // วันตัดรอบบิลถูกเปลี่ยน (รอบบิลไม่มีทางเดินถอยหลังเอง) จึงบอกสาเหตุนั้นแทน
  String get staleCycleMessage {
    final startDate = '${cycleStart.day} ${thaiMonths[cycleStart.month - 1]}';
    final startKey =
        (user?.startBillingYear ?? 0) * 12 + (user?.startBillingMonth ?? 0);
    final currentKey = cycleStart.year * 12 + cycleStart.month;
    if (startKey > currentKey) {
      return 'วันตัดรอบบิลเปลี่ยนแล้ว รอบปัจจุบันเริ่ม $startDate '
          'ต้องตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ';
    }
    return 'รอบบิลใหม่เริ่ม $startDate แล้ว ต้องตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ';
  }

  // ประวัติการบันทึกของรอบนี้ (ใหม่สุดก่อน) ให้หน้าบันทึกมิเตอร์แสดง
  List<MeterHistoryEntry> historyFor(MeterKind kind) {
    final logs = kind == MeterKind.electricity
        ? electricityLogs.map((l) => (l.date, l.usedFromLast, l.cost))
        : waterLogs.map((l) => (l.date, l.usedFromLast, l.cost));
    return [
      for (final (date, usedFromLast, cost) in logs)
        MeterHistoryEntry(date: date, usedFromLast: usedFromLast, cost: cost),
    ];
  }
}

// ผลของงานเบื้องหลัง ที่หน้าจอต้องเอาไปแสดงต่อ
class DashboardBackgroundResult {
  final int? unreadNotifications; // null = อ่านจำนวนไม่ได้
  // คำแนะนำประเภทอัตราที่เพิ่งเกิดครั้งแรก — หน้าจอแสดง popup
  final TariffHint? newTariffHint;

  const DashboardBackgroundResult({
    this.unreadNotifications,
    this.newTariffHint,
  });
}

// =====================================================================
// งานข้อมูลของหน้าหลัก แยกจากหน้าจอ — รับ FirestoreService/NotificationService
// จากภายนอกได้ (เทสส่ง FakeFirebaseFirestore เข้ามา) ไม่แตะ widget
//   load()               : โหลดเฉพาะที่หน้าจอแสดง (พร้อมกัน) แล้วคำนวณยอด
//   runBackgroundTasks() : ปิดบิลรอบที่จบ, ไล่รอบที่ขาด, คำแนะนำประเภทอัตรา,
//                          ค่า Ft งวดใหม่, เช็คแจ้งเตือน — ทำหลังหน้าจอแสดงแล้ว
// =====================================================================
class DashboardLoader {
  final FirestoreService firestoreService;
  final NotificationService notifications;

  DashboardLoader({
    FirestoreService? firestoreService,
    NotificationService? notifications,
  })  : firestoreService = firestoreService ?? FirestoreService(),
        notifications = notifications ?? NotificationService.instance;

  // หน่วยต่อวันของบิล = หน่วยทั้งรอบ ÷ จำนวนวันของรอบนั้น (บิลตั้งชื่อตาม
  // เดือนที่ปิดรอบ รอบจึงจบที่วันตัดรอบของเดือนบิล)
  static double? _perDay(BillModel? bill, double? used, int billingDay) {
    if (bill == null || used == null || used <= 0) return null;
    final end = EnergyForecaster.safeBillingDate(bill.year, bill.month, billingDay);
    final start = EnergyForecaster.getPreviousCycleStart(end, billingDay);
    final days = end.difference(start).inDays;
    return days > 0 ? used / days : null;
  }

  Future<DashboardData> load(String uid, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    // ต้องรู้ billingDay ก่อนถึงจะรู้ขอบเขตรอบบิล
    final user = await firestoreService.getUser(uid);
    final billingDay = user?.billingDay ?? 30;
    final cycleStart = EnergyForecaster.getCycleStart(today, billingDay);
    final cycleEnd = EnergyForecaster.getCycleEnd(today, billingDay);

    // ที่เหลือไม่ขึ้นต่อกัน โหลดพร้อมกัน
    final results = await Future.wait<Object?>([
      firestoreService.getLatestElectricityLog(uid),
      firestoreService.getLatestWaterLog(uid),
      firestoreService.getCurrentMonthElectricityLogs(uid, cycleStart, cycleEnd),
      firestoreService.getCurrentMonthWaterLogs(uid, cycleStart, cycleEnd),
      // บิลล่าสุด (ที่ปิดไปแล้ว) ใช้เทียบ "พุ่งขึ้น/ลดลง" — อ่านไม่ได้ถือว่า
      // ยังไม่มีบิล ไม่ทำให้ทั้งหน้าโหลดไม่สำเร็จ
      firestoreService
          .getLatestBill(uid)
          .then<BillModel?>((b) => b, onError: (_) => null),
      // รายจ่ายประจำของเดือนบิลรอบนี้ (= เดือนของวันตัดรอบ) กติกาเดียวกับ
      // compileBill ยอดบนหน้าหลักจึงตรงกับบิลที่จะปิดออกมา
      firestoreService.calcFixedCostForMonth(
          uid, DateTime(cycleEnd.year, cycleEnd.month, 1)),
    ]);
    final electricityLogs = results[2] as List<ElectricityLogModel>;
    final waterLogs = results[3] as List<WaterLogModel>;
    final latestBill = results[4] as BillModel?;

    // คาดการณ์สิ้นรอบ: ประมาณหน่วยจากอัตราต่อวัน แล้วคิดเงินด้วยตารางอัตรา
    // จริง — ฝั่งไหนยังหาอัตราไม่ได้ใช้ยอดที่ใช้ไปแล้วแทน
    final area = user?.area ?? 'bangkok';
    final elec = await projectElectricityToCycleEnd(
      latest: electricityLogs.isNotEmpty ? electricityLogs.first : null,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      meterType: user?.meterType ?? 'normal',
      area: area,
      startPeak: user?.startPeakValue ?? 0,
      startOffPeak: user?.startOffPeakValue ?? 0,
      tariff: user?.electricityTariff ?? EnergyCalculator.tariffStandard,
    );
    final water = projectWaterToCycleEnd(
      latest: waterLogs.isNotEmpty ? waterLogs.first : null,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      area: area,
    );

    return DashboardData(
      user: user,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      latestElectricityLog: results[0] as ElectricityLogModel?,
      latestWaterLog: results[1] as WaterLogModel?,
      electricityLogs: electricityLogs,
      waterLogs: waterLogs,
      lastMonthElectricityCost: latestBill?.electricityCost ?? 0,
      lastMonthWaterCost: latestBill?.waterCost ?? 0,
      lastBillElectricityPerDay:
          _perDay(latestBill, latestBill?.electricityUsed, billingDay),
      lastBillWaterPerDay: _perDay(latestBill, latestBill?.waterUsed, billingDay),
      billFixedCost: results[5] as double,
      forecastElectricityCost: elec.cost,
      forecastWaterCost: water.cost,
      hasForecastData: elec.projected || water.projected,
    );
  }

  // ถ้าล้มเหลวกลางทาง คืนผลเท่าที่ได้ ไม่ throw — หน้าหลักไม่ควรขึ้น "โหลด
  // ข้อมูลไม่สำเร็จ" เพราะงานเบื้องหลัง ปิดบิลแล้ว saveBill จะแจ้ง
  // DataRefreshBus ให้หน้าหลักโหลดตัวเลขใหม่เอง
  Future<DashboardBackgroundResult> runBackgroundTasks(
    DashboardData data, {
    required bool silent,
  }) async {
    final user = data.user;
    if (user == null) return const DashboardBackgroundResult();
    final uid = user.uid;
    final billingDay = user.billingDay;
    var lastElectricity = data.lastMonthElectricityCost;
    var lastWater = data.lastMonthWaterCost;
    TariffHint? newHint;

    try {
      // sync ยอดรายจ่ายประจำที่ cache ไว้บน user ให้ตรงกับเดือนปัจจุบัน (หน้า
      // ตั้งค่าใช้) เพราะรายการที่ตั้ง endDate ไว้อาจหมดอายุไปโดยไม่มีการแก้ไข
      await firestoreService.recalcFixedCostTotalForToday(uid);

      // ----- ปิดบิลรอบที่เพิ่งจบ -----
      final prevCycleStart =
          EnergyForecaster.getPreviousCycleStart(data.cycleStart, billingDay);
      final prevCycleEnd = data.cycleStart;
      final billExists = await firestoreService.billExistsForMonth(
          uid, prevCycleEnd.year, prevCycleEnd.month);
      if (!billExists) {
        await firestoreService.compileBill(uid, prevCycleEnd.year,
            prevCycleEnd.month, prevCycleStart, prevCycleEnd);
        // แจ้งสรุปจบรอบเฉพาะตอนที่บิลรอบนั้นเพิ่งถูกสร้างในครั้งนี้ (key กันซ้ำ
        // ผูกกับ billId) และใช้บิลนี้เทียบ "พุ่งขึ้น" ในการเช็คแจ้งเตือนด้านล่าง
        final latestBill = await firestoreService.getLatestBill(uid);
        if (latestBill != null &&
            latestBill.year == prevCycleEnd.year &&
            latestBill.month == prevCycleEnd.month) {
          lastElectricity = latestBill.electricityCost;
          lastWater = latestBill.waterCost;
          await notifications.notifyCycleSummary(
            billId: latestBill.id,
            totalCost: latestBill.totalCost,
            year: latestBill.year,
            month: latestBill.month,
            silent: silent,
          );
        }
      }

      await _backfillMissedCycles(
        user: user,
        from: prevCycleStart,
        silent: silent,
      );

      // แนะนำให้ตรวจประเภทอัตราค่าไฟ เมื่อบิล 3 เดือนล่าสุดเข้าเงื่อนไขเปลี่ยน
      // ประเภท (มิเตอร์ปกติเท่านั้น) — คำแนะนำใหม่ส่งกลับให้หน้าจอแสดง popup
      if (user.meterType != 'tou') {
        final hint = TariffAdvisor.check(
          bills: await firestoreService.getBills(uid),
          currentTariff: user.electricityTariff,
          meterType: user.meterType,
        );
        if (hint != null &&
            await notifications.notifyTariffHint(hint: hint, silent: silent)) {
          newHint = hint;
        }
      }

      // ค่า Ft งวดใหม่ (ผู้ดูแลแก้ใน Firebase) — อ่านไม่ได้ไม่ถือว่าเปลี่ยน
      final ft = await firestoreService.getFtInfo();
      if (ft != null) {
        await notifications.notifyFtChanged(ft: ft, silent: silent);
      }

      await _runNotificationChecks(
        data,
        lastMonthElectricityCost: lastElectricity,
        lastMonthWaterCost: lastWater,
        silent: silent,
      );
    } catch (e) {
      debugPrint('Dashboard background tasks failed: $e');
    }

    // จำนวนแจ้งเตือนที่ยังไม่อ่าน (badge ที่ปุ่มกระดิ่ง) — อ่านจากเครื่อง
    // อย่างเดียว ทำต่อได้แม้งานด้านบนจะล้มเหลว
    int? unread;
    try {
      unread = await notifications.getUnreadCount();
    } catch (e) {
      debugPrint('Error reading unread notifications: $e');
    }
    return DashboardBackgroundResult(
      unreadNotifications: unread,
      newTariffHint: newHint,
    );
  }

  // ----- Backfill รอบบิลที่ขาดหายไปก่อนหน้า [from] -----
  // ถ้า user ไม่ได้เปิดแอปข้าม 2-3 รอบบิลติดกัน รอบที่อยู่ตรงกลางจะไม่มีใครไป
  // compile ให้ ที่นี่จึงไล่ย้อนต่อจาก [from] ไปเรื่อยๆ จนกว่าจะ
  // (1) เจอบิลที่ compile ไว้แล้ว (แปลว่าตามทันประวัติแล้ว) หรือ (2) ย้อนไปถึง
  // เดือนที่ user เริ่มตั้งค่าระบบครั้งแรก (startBillingMonth/Year) หรือ
  // (3) ชนเพดานความปลอดภัย หรือ (4) compile ไม่สำเร็จ (ลองใหม่โหลดครั้งถัดไป)
  // รอบไหนไล่ compile แล้วไม่มี log เลย (user ไม่ได้บันทึกจริงๆ ในรอบนั้น)
  // จะถูกเก็บไว้แจ้งเตือน ไม่ใช่ปล่อยให้หายไปเงียบๆ
  Future<void> _backfillMissedCycles({
    required UserModel user,
    required DateTime from,
    required bool silent,
  }) async {
    final uid = user.uid;
    final missedCycles = <String>[];
    DateTime backfillCycleEnd = from;
    const maxBackfillLookback = 24; // กันลูปยาวเกินไปถ้าข้อมูล user ผิดปกติ
    for (var i = 0; i < maxBackfillLookback; i++) {
      final backfillCycleStart = EnergyForecaster.getPreviousCycleStart(
          backfillCycleEnd, user.billingDay);

      final startY = user.startBillingYear;
      final startM = user.startBillingMonth;
      if (startY != 0 &&
          (backfillCycleEnd.year < startY ||
              (backfillCycleEnd.year == startY &&
                  backfillCycleEnd.month < startM))) {
        break;
      }

      final monthKey = '${backfillCycleEnd.month}/${backfillCycleEnd.year}';
      // รอบนี้เคยไล่เช็คแล้วครั้งก่อนๆ ว่าไม่มี log เลย และแจ้งเตือนไปแล้ว —
      // ไม่มีทาง log ย้อนหลังเข้ามาเองได้อีกสำหรับรอบที่ปิดไปแล้ว (นอกจาก user
      // ไปกรอกผ่านหน้าประวัติบิลตรงๆ ซึ่งสร้าง bill doc เองอยู่แล้ว ไม่ต้องพึ่ง
      // compileBill) ข้ามรอบนี้ไปเลย กัน query+compile ซ้ำเปล่าๆ ทุกครั้งที่เปิดแอป
      // แต่ยัง "ไม่ break" เพราะรอบที่เก่ากว่านี้อาจยังไม่เคยถูกเช็คเลยก็ได้
      if (await notifications.isCycleFlaggedMissing(monthKey)) {
        backfillCycleEnd = backfillCycleStart;
        continue;
      }

      final alreadyExists = await firestoreService.billExistsForMonth(
          uid, backfillCycleEnd.year, backfillCycleEnd.month);
      if (alreadyExists) break; // ตามทันประวัติที่ compile ไปก่อนหน้านี้แล้ว

      final result = await firestoreService.compileBill(uid,
          backfillCycleEnd.year, backfillCycleEnd.month, backfillCycleStart,
          backfillCycleEnd);
      // ทำไม่สำเร็จ (เช่น ออฟไลน์) ไม่ได้แปลว่ารอบนี้ไม่ได้บันทึก — หยุดไล่
      // ตรงนี้โดยไม่ติดป้ายรอบนี้ โหลดครั้งถัดไปจะไล่ต่อจากรอบเดิมเอง
      if (result == CompileBillResult.failed) break;
      if (result == CompileBillResult.noLogs) {
        // ไม่มี log เลยในรอบนี้ = รอบที่ user ไม่ได้บันทึกจริงๆ
        missedCycles.add(monthKey);
      }

      backfillCycleEnd = backfillCycleStart;
    }
    if (missedCycles.isNotEmpty) {
      await notifications.notifyMissedCycles(
        months: missedCycles,
        silent: silent,
      );
    }
  }

  // เช็คแจ้งเตือนทั้งหมด — แยกจับ error ของตัวเอง เพราะแจ้งเตือนล้มเหลว (เช่น
  // เครื่องไม่อนุญาตให้ตั้งเวลาแจ้งเตือน) ไม่ควรทำให้งานอื่นหยุด
  Future<void> _runNotificationChecks(
    DashboardData data, {
    required double lastMonthElectricityCost,
    required double lastMonthWaterCost,
    required bool silent,
  }) async {
    try {
      // บันทึกเตือนรอบบิลที่ส่งไปแล้วเข้าประวัติก่อน แล้วค่อยตั้งรอบถัดไป
      // (ถ้าตั้งก่อน กำหนดการเดิมจะถูกเขียนทับจนไม่ได้เข้าประวัติ)
      await notifications.syncDeliveredScheduledNotifications();

      // (Scheduled) เตือนเช้าวันตัดรอบบิล — ตั้งล่วงหน้าให้ OS จัดการเอง
      await notifications.scheduleBillingReminder(
        cycleStart: data.cycleStart,
        cycleEnd: data.cycleEnd,
      );

      // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน — ดูจาก log ล่าสุด
      // (ใหม่ที่สุด) ของทุกรอบ ไม่ว่าไฟหรือน้ำ และวันที่ตั้งเลขมิเตอร์ต้นรอบ
      // ครั้งล่าสุด (ผู้ใช้ที่ยังไม่เคยบันทึกเลยนับจากวันนั้น)
      final latestLogDates = [
        data.latestElectricityLog?.date,
        data.latestWaterLog?.date,
      ].whereType<DateTime>().toList()
        ..sort();
      DateTime? startMeterSetAt;
      final user = data.user;
      if (user != null && user.startMeterConfigured) {
        // ประวัติเรียงตามเวลาที่บันทึก ใหม่สุดก่อน
        final history = await firestoreService.getStartMeterHistory(user.uid);
        if (history.isNotEmpty) startMeterSetAt = history.first.recordedAt;
      }
      await notifications.checkMeterNotRecorded(
        lastLogDate: latestLogDates.isNotEmpty ? latestLogDates.last : null,
        startMeterSetAt: startMeterSetAt,
        silent: silent,
      );

      // (Instant) เตือนเมื่อค่าไฟ/น้ำรอบนี้สูงกว่าบิลเดือนก่อนเกิน 30%
      await notifications.checkUsageSpike(
        currentElectricityCost: data.currentElectricityCost,
        lastMonthElectricityCost: lastMonthElectricityCost,
        currentWaterCost: data.currentWaterCost,
        lastMonthWaterCost: lastMonthWaterCost,
        cycleStart: data.cycleStart,
        silent: silent,
      );

      // (Instant) เตือนล่วงหน้าถ้าคาดการณ์สิ้นรอบจะสูงกว่าเดือนก่อน — ข้าม
      // ถ้ายังไม่มีข้อมูลพอ เพราะยอดคาดการณ์ตอนนั้นคือยอดที่ใช้ไปแล้วเฉยๆ
      if (data.hasForecastData) {
        await notifications.checkForecastHigherThanLastMonth(
          forecastTotal: data.forecastTotal,
          lastMonthTotal: lastMonthElectricityCost + lastMonthWaterCost,
          cycleStart: data.cycleStart,
          silent: silent,
        );
      }
    } catch (e) {
      debugPrint('Error running notification checks: $e');
    }
  }
}
