import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/bill_model.dart';
import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/cycle_projection.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/forecaster.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/onboarding_guide.dart';
import '../settings/settings_screen.dart';
import 'dashboard_styles.dart';
import 'notification_screen.dart';
import 'record_meter_screen.dart';

class DashboardScreen extends StatefulWidget {
  // true เฉพาะตอนเพิ่ง setup เสร็จหมาดๆ (MainShell ส่งต่อมาจาก setup_screen) ใช้
  // กันไม่ให้แจ้งเตือนหลายๆ อย่างยิง popup รัวพร้อมกันตั้งแต่เปิดแอปครั้งแรก
  // (ยังเห็นแค่ welcome พอ ที่เหลือถ้ามีจะถูกบันทึกเงียบๆ ไว้ในหน้าแจ้งเตือนแทน
  // ไปดูเองได้)
  final bool justCompletedSetup;

  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  // เป็น null ได้ถ้าหน้านี้ถูก push ตรงๆ แยกจาก MainShell (เช่นดีบัก/เทส)
  final ValueChanged<int>? onNavTap;

  const DashboardScreen({
    super.key,
    this.justCompletedSetup = false,
    this.onNavTap,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  UserModel? _user;
  ElectricityLogModel? _latestElectricityLog;
  WaterLogModel? _latestWaterLog;
  List<ElectricityLogModel> _electricityLogs = [];
  List<WaterLogModel> _waterLogs = [];

  double _currentElectricityFromStart = 0;
  double _currentWaterFromStart = 0;
  double _currentElectricityCost = 0;
  double _currentWaterCost = 0;

  // ----- ยอดคาดการณ์ (แยกไฟฟ้า/น้ำ) -----
  double _forecastTotal = 0;
  double _forecastElectricityCost = 0;
  double _forecastWaterCost = 0;

  // true = มี log ในรอบนี้ที่บันทึกห่างจากต้นรอบอย่างน้อย 1 วัน (ไฟหรือน้ำ
  // อย่างใดอย่างหนึ่ง) พอจะคำนวณอัตรา "หน่วย/วัน" ได้แล้ว ถ้า false ยอด
  // คาดการณ์จะเท่ากับยอดที่ใช้ไปแล้วเฉยๆ ซึ่งไม่ใช่การคาดการณ์จริง
  // ใช้บอก UI ให้แจ้งผู้ใช้ว่ายังไม่มีข้อมูลพอ แทนการโชว์ตัวเลขคาดการณ์
  bool _hasForecastData = true;

  // ----- ยอดเดือนก่อน (ใช้เทียบ "พุ่งขึ้น") -----
  double _lastMonthElectricityCost = 0;
  double _lastMonthWaterCost = 0;

  bool _isLoading = true;

  // true = โหลดข้อมูลไม่สำเร็จ (ออฟไลน์/Firestore error) → โชว์หน้า "ลองใหม่"
  // แทนตัวเลข 0 เงียบๆ ที่ทำให้ผู้ใช้เข้าใจผิดว่าข้อมูลหาย
  bool _loadFailed = false;
  int _unreadNotifications =
      0; // จำนวนแจ้งเตือนที่ยังไม่อ่าน (badge ที่ปุ่มกระดิ่ง)

  // เช็คแค่ "ครั้งแรก" ที่ _loadData() รัน (ไม่ใช่ทุกครั้งที่ pull-to-refresh)
  // ใช้คู่กับ widget.justCompletedSetup เพื่อทำให้แจ้งเตือนเงียบแค่รอบเดียว
  bool _isFirstLoad = true;

  // กันโหลดซ้อนกัน — ดู _loadData/_runBackgroundTasks
  bool _loadInFlight = false;
  bool _reloadPending = false;
  bool _backgroundInFlight = false;

  // รายจ่ายประจำของเดือนบิลรอบนี้ (ไม่ใช่ user.fixedCost ที่เป็นยอดของเดือน
  // ปฏิทินปัจจุบัน) — ตรงกับที่ compileBill จะใส่ในบิลของรอบนี้
  double _billFixedCost = 0;

  @override
  void initState() {
    super.initState();
    _loadData();

    // แท็บนี้ถูกเก็บไว้ใน IndexedStack ของ MainShell ตลอด ไม่มี route
    // pop/push ให้ RouteAware ทำงานตอนสลับแท็บ เลยต้องฟัง DataRefreshBus
    // แทน — พอมีการแก้/ลบข้อมูลจากแท็บอื่น (เช่น ลบ log ที่หน้าตั้งค่า)
    // หน้านี้จะโหลดข้อมูลใหม่ให้เองโดยไม่ต้องรอผู้ใช้ pull-to-refresh
    DataRefreshBus.instance.version.addListener(_onDataChangedElsewhere);

    // โชว์คู่มือเริ่มต้นใช้งาน (เฉพาะครั้งแรกที่เข้า Dashboard เท่านั้น)
    // ใช้ addPostFrameCallback เพื่อรอให้ widget tree พร้อมก่อนเปิด dialog
    //
    // หมายเหตุ: notifyWelcome() ยิงที่ setup_screen.dart (ไม่ใช่ที่นี่) เพราะ
    // Dashboard.initState รันทุกครั้งที่เข้าหน้านี้ (ทั้ง login เก่าและใหม่)
    // ขณะที่ setup_screen.dart รันแค่ครั้งเดียวตอนบัญชีใหม่ทำ setup เสร็จ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OnboardingGuide.showIfFirstTime(context);
    });
  }

  void _onDataChangedElsewhere() {
    if (mounted) _loadData();
  }

  // =====================================================================
  // ค่ามิเตอร์ต้นรอบที่ตั้งไว้ (ถ้ามี) ยังตรงกับ "รอบบิลปัจจุบัน" ไหม
  //
  // ทำไมต้องเช็คเพิ่ม: electricityStartConfigured/waterStartConfigured
  // (ที่การ์ดใช้เช็คอยู่แล้ว) บอกแค่ว่า "เคยตั้งค่าไปหรือยัง" ไม่ได้บอกว่า
  // ค่านั้นเป็นของรอบไหน — พอข้ามวันตัดรอบบิลไปแล้ว ถ้า user ยังไม่ได้เข้าไป
  // ตั้งเลขมิเตอร์ต้นรอบใหม่ของรอบนี้ ค่า start เดิมที่ยังค้างอยู่คือของ
  // "รอบก่อน" แต่ flag ยังเป็น true อยู่เหมือนเดิม ถ้าปล่อยให้กรอก log
  // รายวันได้เลยตอนนี้ ระบบจะเอาเลขมิเตอร์วันนี้ไปลบกับ start ของรอบก่อน
  // (ที่เลขน้อยกว่ามาก) ได้ "หน่วยที่ใช้" ที่รวมทั้งรอบเก่า+รอบใหม่ปนกันมั่ว
  //
  // ใช้ EnergyForecaster.matchesCurrentCycle ตัวเดียวกับหน้าตั้งเลขมิเตอร์
  // ต้นรอบ (settings_start_meter.dart) เพื่อให้ทุกจุดตัดสิน "รอบปัจจุบัน"
  // ตรงกัน — ใช้ร่วมกันทั้งไฟและน้ำ เพราะ UserModel เก็บ
  // startBillingMonth/Year ไว้แค่ชุดเดียว
  bool get _startMeterMatchesCurrentCycle {
    final user = _user;
    if (user == null) return false;
    return EnergyForecaster.matchesCurrentCycle(
      billingMonth: user.startBillingMonth,
      billingYear: user.startBillingYear,
      billingDay: user.billingDay,
    );
  }

  // พร้อมบันทึก log รายวันไหม (แยกรายยูทิลิตี้) = เคยตั้งค่ามาก่อน AND
  // ค่านั้นยังตรงกับรอบปัจจุบัน — ใช้ใน build() ตัดสินใจว่าโชว์การ์ดสรุป
  // (กดแล้วไปหน้า RecordMeterScreen) หรือการ์ดล็อกเตือนให้ตั้งมิเตอร์ต้นรอบ
  // ก่อน (ดู _buildMeterLockedCard)
  bool get _electricityMeterReady =>
      (_user?.electricityStartConfigured ?? true) &&
      _startMeterMatchesCurrentCycle;
  bool get _waterMeterReady =>
      (_user?.waterStartConfigured ?? true) && _startMeterMatchesCurrentCycle;

  // ข้อความบนการ์ดล็อกเมื่อเลขต้นรอบที่ตั้งไว้ไม่ตรงกับรอบปัจจุบัน — บอกวันที่
  // รอบปัจจุบันเริ่มเสมอ ถ้าเลขต้นรอบเป็นของรอบที่ "ใหม่กว่า" รอบปัจจุบัน แปลว่า
  // วันตัดรอบบิลถูกเปลี่ยน (รอบบิลไม่มีทางเดินถอยหลังเอง) จึงบอกสาเหตุนั้นแทน
  // การบอกว่าขึ้นรอบใหม่
  String get _staleCycleMessage {
    final user = _user;
    final cycleStart =
        EnergyForecaster.getCycleStart(DateTime.now(), user?.billingDay ?? 30);
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

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_onDataChangedElsewhere);
    super.dispose();
  }

  // =====================================================================
  // โหลดข้อมูลที่หน้าจอต้องใช้ แล้วแสดงผลทันที — งานที่ไม่จำเป็นต่อการแสดงผล
  // (ปิดบิลรอบที่จบ, ไล่รอบที่ขาด, แจ้งเตือน) ทำต่อเบื้องหลังใน
  // _runBackgroundTasks หลังหน้าจอแสดงแล้ว
  //
  // ถ้ามีคำขอโหลดใหม่เข้ามาระหว่างที่กำลังโหลด (เช่น ปิดบิลแล้ว DataRefreshBus
  // แจ้งกลับมา) จะโหลดซ้ำอีกรอบหลังรอบนี้จบ ไม่โหลดซ้อนกัน
  // =====================================================================
  Future<void> _loadData() async {
    if (_loadInFlight) {
      _reloadPending = true;
      return;
    }
    _loadInFlight = true;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    // เงียบเฉพาะโหลดรอบแรกจริงๆ หลังสมัครสมาชิกเสร็จ — รอบถัดไป (pull-to-
    // refresh, กลับมาเปิดแอปใหม่) ยิง popup ตามปกติ
    final bool silentThisLoad = widget.justCompletedSetup && _isFirstLoad;
    DateTime? startDate;
    DateTime? endDate;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // ต้องรู้ billingDay ก่อนถึงจะรู้ขอบเขตรอบบิล
      _user = await _firestoreService.getUser(uid);
      final now = DateTime.now();
      final billingDay = _user?.billingDay ?? 30;
      final cycleStart = EnergyForecaster.getCycleStart(now, billingDay);
      final cycleEnd = EnergyForecaster.getCycleEnd(now, billingDay);
      startDate = cycleStart;
      endDate = cycleEnd;

      // ที่เหลือไม่ขึ้นต่อกัน โหลดพร้อมกัน
      final results = await Future.wait<Object?>([
        _firestoreService.getLatestElectricityLog(uid),
        _firestoreService.getLatestWaterLog(uid),
        _firestoreService.getCurrentMonthElectricityLogs(
            uid, cycleStart, cycleEnd),
        _firestoreService.getCurrentMonthWaterLogs(uid, cycleStart, cycleEnd),
        // บิลล่าสุด (ที่ปิดไปแล้ว) ใช้เทียบ "พุ่งขึ้น/ลดลง" — query เฉพาะใบเดียว
        // อ่านไม่ได้ถือว่ายังไม่มีบิล ไม่ทำให้ทั้งหน้าโหลดไม่สำเร็จ
        _firestoreService
            .getLatestBill(uid)
            .then<BillModel?>((b) => b, onError: (_) => null),
        // รายจ่ายประจำของเดือนบิลรอบนี้ (= เดือนของวันตัดรอบ) ใช้กติกาเดียวกับ
        // compileBill ยอดบนหน้าหลักจึงตรงกับบิลที่จะปิดออกมา
        _firestoreService.calcFixedCostForMonth(
            uid, DateTime(cycleEnd.year, cycleEnd.month, 1)),
      ]);
      _latestElectricityLog = results[0] as ElectricityLogModel?;
      _latestWaterLog = results[1] as WaterLogModel?;
      _electricityLogs = results[2] as List<ElectricityLogModel>;
      _waterLogs = results[3] as List<WaterLogModel>;
      final latestBill = results[4] as BillModel?;
      _lastMonthElectricityCost = latestBill?.electricityCost ?? 0;
      _lastMonthWaterCost = latestBill?.waterCost ?? 0;
      _billFixedCost = results[5] as double;

      await _calculateCurrentMonth();
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      _loadFailed = true;
    } finally {
      _isFirstLoad = false;
      _loadInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    if (_reloadPending) {
      _reloadPending = false;
      _loadData();
      return;
    }
    if (!_loadFailed && startDate != null && endDate != null) {
      _runBackgroundTasks(
        cycleStart: startDate,
        cycleEnd: endDate,
        silent: silentThisLoad,
      );
    }
  }

  // =====================================================================
  // งานเบื้องหลังหลังหน้าจอแสดงแล้ว — ไม่บล็อกการแสดงผล และถ้าล้มเหลวก็ไม่ทำให้
  // หน้าหลักขึ้น "โหลดข้อมูลไม่สำเร็จ" ปิดบิลแล้ว saveBill จะแจ้ง
  // DataRefreshBus ให้หน้านี้โหลดตัวเลขใหม่เอง
  // =====================================================================
  Future<void> _runBackgroundTasks({
    required DateTime cycleStart,
    required DateTime cycleEnd,
    required bool silent,
  }) async {
    if (_backgroundInFlight) return;
    _backgroundInFlight = true;
    try {
      final uid = _user?.uid;
      if (uid == null) return;
      final billingDay = _user?.billingDay ?? 30;

      // sync ยอดรายจ่ายประจำที่ cache ไว้บน user ให้ตรงกับเดือนปัจจุบัน (หน้า
      // ตั้งค่าใช้) เพราะรายการที่ตั้ง endDate ไว้อาจหมดอายุไปโดยไม่มีการแก้ไข
      await _firestoreService.recalcFixedCostTotalForToday(uid);

      // ----- ปิดบิลรอบที่เพิ่งจบ -----
      final prevCycleStart =
          EnergyForecaster.getPreviousCycleStart(cycleStart, billingDay);
      final prevCycleEnd = cycleStart;
      final billExists = await _firestoreService.billExistsForMonth(
          uid, prevCycleEnd.year, prevCycleEnd.month);
      if (!billExists) {
        await _firestoreService.compileBill(
          uid,
          prevCycleEnd.year,
          prevCycleEnd.month,
          prevCycleStart,
          prevCycleEnd,
        );
        // แจ้งสรุปจบรอบเฉพาะตอนที่บิลรอบนั้นเพิ่งถูกสร้างในครั้งนี้ (key กันซ้ำ
        // ผูกกับ billId) และใช้บิลนี้เทียบ "พุ่งขึ้น" ในการเช็คแจ้งเตือนด้านล่าง
        final latestBill = await _firestoreService.getLatestBill(uid);
        if (latestBill != null &&
            latestBill.year == prevCycleEnd.year &&
            latestBill.month == prevCycleEnd.month) {
          _lastMonthElectricityCost = latestBill.electricityCost;
          _lastMonthWaterCost = latestBill.waterCost;
          await NotificationService.instance.notifyCycleSummary(
            billId: latestBill.id,
            totalCost: latestBill.totalCost,
            year: latestBill.year,
            month: latestBill.month,
            silent: silent,
          );
        }
      }

      await _backfillMissedCycles(
        uid: uid,
        billingDay: billingDay,
        from: prevCycleStart,
        silent: silent,
      );

      await _runNotificationChecks(
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        silent: silent,
      );
    } catch (e) {
      debugPrint('Dashboard background tasks failed: $e');
    } finally {
      _backgroundInFlight = false;
    }
  }

  // ----- Backfill รอบบิลที่ขาดหายไปก่อนหน้า [from] -----
  // ถ้า user ไม่ได้เปิดแอปข้าม 2-3 รอบบิลติดกัน รอบที่อยู่ตรงกลางจะไม่มีใครไป
  // compile ให้ ที่นี่จึงไล่ย้อนต่อจาก [from] ไปเรื่อยๆ จนกว่าจะ
  // (1) เจอบิลที่ compile ไว้แล้ว (แปลว่าตามทันประวัติแล้ว) หรือ (2) ย้อนไปถึง
  // เดือนที่ user เริ่มตั้งค่าระบบครั้งแรก (startBillingMonth/Year) หรือ
  // (3) ชนเพดานความปลอดภัย
  // รอบไหนไล่ compile แล้วไม่มี log เลย (user ไม่ได้บันทึกจริงๆ ในรอบนั้น)
  // จะถูกเก็บไว้แจ้งเตือน ไม่ใช่ปล่อยให้หายไปเงียบๆ
  Future<void> _backfillMissedCycles({
    required String uid,
    required int billingDay,
    required DateTime from,
    required bool silent,
  }) async {
    final missedCycles = <String>[];
    DateTime backfillCycleEnd = from;
    const maxBackfillLookback = 24; // กันลูปยาวเกินไปถ้าข้อมูล user ผิดปกติ
    for (var i = 0; i < maxBackfillLookback; i++) {
      final backfillCycleStart =
          EnergyForecaster.getPreviousCycleStart(backfillCycleEnd, billingDay);

      final startY = _user?.startBillingYear ?? 0;
      final startM = _user?.startBillingMonth ?? 0;
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
      final alreadyFlagged =
          await NotificationService.instance.isCycleFlaggedMissing(monthKey);
      if (alreadyFlagged) {
        backfillCycleEnd = backfillCycleStart;
        continue;
      }

      final alreadyExists = await _firestoreService.billExistsForMonth(
          uid, backfillCycleEnd.year, backfillCycleEnd.month);
      if (alreadyExists) break; // ตามทันประวัติที่ compile ไปก่อนหน้านี้แล้ว

      await _firestoreService.compileBill(
        uid,
        backfillCycleEnd.year,
        backfillCycleEnd.month,
        backfillCycleStart,
        backfillCycleEnd,
      );

      final createdNow = await _firestoreService.billExistsForMonth(
          uid, backfillCycleEnd.year, backfillCycleEnd.month);
      if (!createdNow) {
        // ไม่มี log เลยในรอบนี้ = รอบที่ user ไม่ได้บันทึกจริงๆ
        missedCycles.add(monthKey);
      }

      backfillCycleEnd = backfillCycleStart;
    }
    if (missedCycles.isNotEmpty) {
      await NotificationService.instance.notifyMissedCycles(
        months: missedCycles,
        silent: silent,
      );
    }
  }

  // =====================================================================
  // เช็คแจ้งเตือนทั้งหมดหลังคำนวณข้อมูลเสร็จ — แยกจับ error ของตัวเอง
  // เพราะแจ้งเตือนล้มเหลว (เช่น เครื่องไม่อนุญาตให้ตั้งเวลาแจ้งเตือน) ไม่ควร
  // ทำให้หน้าหลักขึ้น "โหลดข้อมูลไม่สำเร็จ" ทั้งที่ข้อมูลโหลดได้ครบแล้ว
  // =====================================================================
  Future<void> _runNotificationChecks({
    required DateTime cycleStart,
    required DateTime cycleEnd,
    required bool silent,
  }) async {
    final notifications = NotificationService.instance;
    try {
      // บันทึกเตือนรอบบิลที่ส่งไปแล้วเข้าประวัติก่อน แล้วค่อยตั้งรอบถัดไป
      // (ถ้าตั้งก่อน กำหนดการเดิมจะถูกเขียนทับจนไม่ได้เข้าประวัติ)
      await notifications.syncDeliveredScheduledNotifications();

      // (Scheduled) เตือนเช้าวันตัดรอบบิล — ตั้งล่วงหน้าให้ OS จัดการเอง
      await notifications.scheduleBillingReminder(
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
      );

      // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน — ดูจาก log ล่าสุด
      // (ใหม่ที่สุด) ของทุกรอบ ไม่ว่าไฟหรือน้ำ และวันที่ตั้งเลขมิเตอร์ต้นรอบ
      // ครั้งล่าสุด (ผู้ใช้ที่ยังไม่เคยบันทึกเลยนับจากวันนั้น)
      final latestLogDates = [
        _latestElectricityLog?.date,
        _latestWaterLog?.date,
      ].whereType<DateTime>().toList()
        ..sort();
      DateTime? startMeterSetAt;
      final uid = _user?.uid;
      if (uid != null && (_user?.startMeterConfigured ?? false)) {
        // ประวัติเรียงตามเวลาที่บันทึก ใหม่สุดก่อน
        final history = await _firestoreService.getStartMeterHistory(uid);
        if (history.isNotEmpty) startMeterSetAt = history.first.recordedAt;
      }
      await notifications.checkMeterNotRecorded(
        lastLogDate: latestLogDates.isNotEmpty ? latestLogDates.last : null,
        startMeterSetAt: startMeterSetAt,
        silent: silent,
      );

      // (Instant) เตือนเมื่อค่าไฟ/น้ำรอบนี้สูงกว่าบิลเดือนก่อนเกิน 30%
      await notifications.checkUsageSpike(
        currentElectricityCost: _currentElectricityCost,
        lastMonthElectricityCost: _lastMonthElectricityCost,
        currentWaterCost: _currentWaterCost,
        lastMonthWaterCost: _lastMonthWaterCost,
        cycleStart: cycleStart,
        silent: silent,
      );

      // (Instant) เตือนล่วงหน้าถ้าคาดการณ์สิ้นรอบจะสูงกว่าเดือนก่อน — ข้าม
      // ถ้ายังไม่มีข้อมูลพอ เพราะ _forecastTotal ตอนนั้นคือยอดที่ใช้ไปแล้วเฉยๆ
      if (_hasForecastData) {
        await notifications.checkForecastHigherThanLastMonth(
          forecastTotal: _forecastTotal,
          lastMonthTotal: _lastMonthElectricityCost + _lastMonthWaterCost,
          cycleStart: cycleStart,
          silent: silent,
        );
      }
    } catch (e) {
      debugPrint('Error running notification checks: $e');
    }

    // จำนวนแจ้งเตือนที่ยังไม่อ่าน (badge ที่ปุ่มกระดิ่ง) — อ่านจากเครื่อง
    // อย่างเดียว ทำต่อได้แม้เช็คด้านบนจะล้มเหลว
    try {
      _unreadNotifications = await notifications.getUnreadCount();
    } catch (e) {
      debugPrint('Error reading unread notifications: $e');
    }
  }

  // =====================================================================
  // คำนวณยอดใช้งาน/ค่าใช้จ่ายรอบนี้ + คาดการณ์สิ้นรอบ (แยกไฟฟ้า/น้ำ)
  // =====================================================================
  Future<void> _calculateCurrentMonth() async {
    if (_electricityLogs.isNotEmpty) {
      final latest = _electricityLogs.first;
      _currentElectricityFromStart = latest.usedFromStart;
      _currentElectricityCost = latest.cost;
    } else {
      _currentElectricityFromStart = 0;
      _currentElectricityCost = 0;
    }

    if (_waterLogs.isNotEmpty) {
      final latest = _waterLogs.first;
      _currentWaterFromStart = latest.usedFromStart;
      _currentWaterCost = latest.cost;
    } else {
      _currentWaterFromStart = 0;
      _currentWaterCost = 0;
    }

    // ----- คาดการณ์สิ้นรอบ: ประมาณหน่วยจากอัตราต่อวัน แล้วคิดเงินด้วยตาราง
    // อัตราจริง (ดู cycle_projection.dart) — log เป็นยอดสะสมตั้งแต่ต้นรอบ จึงใช้
    // log ล่าสุดตัวเดียวพอ ฝั่งไหนยังหาอัตราไม่ได้ใช้ยอดที่ใช้ไปแล้วแทน
    final now = DateTime.now();
    final billingDay = _user?.billingDay ?? 30;
    final cycleStart = EnergyForecaster.getCycleStart(now, billingDay);
    final cycleEnd = EnergyForecaster.getCycleEnd(now, billingDay);
    final area = _user?.area ?? 'bangkok';

    final elec = await projectElectricityToCycleEnd(
      latest: _cycleLatestElectricityLog,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      meterType: _user?.meterType ?? 'normal',
      area: area,
      startPeak: _user?.startPeakValue ?? 0,
      startOffPeak: _user?.startOffPeakValue ?? 0,
    );
    final water = projectWaterToCycleEnd(
      latest: _cycleLatestWaterLog,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      area: area,
    );

    _hasForecastData = elec.projected || water.projected;
    _forecastElectricityCost = elec.cost;
    _forecastWaterCost = water.cost;
    _forecastTotal = _forecastElectricityCost + _forecastWaterCost;
  }

  // กดปุ่ม notification ตรงหัวบาร์ -> เปิดหน้า Notification Center
  // พอกลับมาจากหน้านั้น (เผื่อมีการอ่าน/ลบ) ให้รีเฟรชจำนวนที่ยังไม่อ่านใหม่
  Future<void> _onNotificationTap() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationScreen()),
    );
    final count = await NotificationService.instance.getUnreadCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  // แสดงแทนเนื้อหาหลักเมื่อโหลดข้อมูลไม่สำเร็จ — มีปุ่มลองใหม่
  Widget _buildLoadErrorView() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              const Text(
                'โหลดข้อมูลไม่สำเร็จ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.s17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTypography.s14, height: 1.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DashboardStyles.primaryGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.v32, vertical: AppSpacing.v12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.v12)),
                ),
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final billingDay = _user?.billingDay ?? 30;
    final remainingDays = EnergyForecaster.getRemainingDays(now, billingDay);
    final daysElapsed = EnergyForecaster.getDaysElapsed(now, billingDay);
    final cycleLengthDays =
        EnergyForecaster.getCycleLengthDays(now, billingDay);
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      body: Container(
        decoration: DashboardStyles.pageHighlight(),
        // วงหมุนเต็มจอเฉพาะโหลดครั้งแรก — โหลดซ้ำ (pull-to-refresh, ข้อมูล
        // เปลี่ยนจากหน้าอื่น, ปิดบิลเบื้องหลังเสร็จ) แสดงข้อมูลเดิมไว้จนตัวเลข
        // ใหม่มา ไม่กะพริบเป็นหน้าว่าง
        child: _isLoading && _user == null
          ? const Center(
              child: CircularProgressIndicator(
                  color: DashboardStyles.primaryGreen))
          : _loadFailed
              ? _buildLoadErrorView()
              : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: DashboardStyles.primaryGreen,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.v16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // -------------------------------------------------
                      // (1) Header: avatar + คำทักทาย + ผ่านมา/เหลืออีก
                      // (แถบ progress ของรอบบิล) + ปุ่ม notification
                      // -------------------------------------------------
                      _buildHeader(daysElapsed, remainingDays, cycleLengthDays),

                      const SizedBox(height: 18),

                      // -------------------------------------------------
                      // (2) การ์ดค่าใช้จ่ายรอบนี้ (ไฟฟ้า/น้ำ) + ยอดคาดการณ์สิ้นรอบ
                      // -------------------------------------------------
                      _buildCostSummaryCard(formatter),

                      const SizedBox(height: 20),

                      // -------------------------------------------------
                      // (3) บันทึกมิเตอร์วันนี้
                      // -------------------------------------------------
                      const Text('บันทึกมิเตอร์วันนี้',
                          style: DashboardStyles.sectionTitle),
                      const SizedBox(height: 10),

                      // -------------------------------------------------
                      // ตัวเตือนวันตัดรอบบิล — โชว์เฉพาะบัญชีที่ยังไม่เคยเลือก
                      // วันตัดรอบเอง แต่ตั้งเลขมิเตอร์ต้นรอบไปแล้ว (ถ้ายังไม่ได้
                      // ตั้งเลขต้นรอบ การ์ดเช็คลิสต์ด้านล่างมีขั้นนี้อยู่แล้ว)
                      // -------------------------------------------------
                      if (_user?.billingDayConfigured == false &&
                          _user?.startMeterConfigured != false) ...[
                        _buildBillingDayReminderBanner(),
                        const SizedBox(height: 10),
                      ],

                      // การ์ดไฟฟ้ากับน้ำอยู่คู่กันแบบ Row ซ้าย-ขวา — การ์ดแค่โชว์สรุป
                      // ค่าล่าสุด/ต้นรอบ + ปุ่มเดียวพาไปหน้าบันทึก (RecordMeterScreen)
                      // ใช้ IntrinsicHeight ให้การ์ดไฟ (TOU โชว์ 2 บรรทัดสรุป)
                      // กับการ์ดน้ำ (1 บรรทัด) สูงเท่ากัน
                      // - ยังไม่ได้ตั้งเลขต้นรอบเลยสักฝั่ง -> การ์ดเช็คลิสต์
                      //   เริ่มต้นใช้งาน 3 ขั้นตอน
                      // - ฝั่งที่พร้อม (_electricityMeterReady/_waterMeterReady:
                      //   ตั้งแล้วและตรงกับรอบปัจจุบัน) -> การ์ดสรุป ใช้งานได้เลย
                      // - ฝั่งที่ยังไม่พร้อม -> การ์ดล็อกเฉพาะฝั่งนั้น
                      _user?.startMeterConfigured == false
                          ? _buildSetupChecklistCard()
                          : IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _electricityMeterReady
                                        ? _buildMeterSummaryCard(
                                            kind: MeterKind.electricity,
                                            isTou: _user?.meterType == 'tou',
                                          )
                                        : _buildMeterLockedCard(
                                            title: 'ไฟฟ้า',
                                            icon: Icons.bolt,
                                            accent:
                                                DashboardStyles.electricityAccent,
                                            borderColor: DashboardStyles
                                                .electricityBorder,
                                            message: (_user
                                                        ?.electricityStartConfigured ??
                                                    true)
                                                ? _staleCycleMessage
                                                : null,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _waterMeterReady
                                        ? _buildMeterSummaryCard(
                                            kind: MeterKind.water,
                                          )
                                        : _buildMeterLockedCard(
                                            title: 'น้ำ',
                                            icon: Icons.water_drop,
                                            accent: DashboardStyles.waterAccent,
                                            borderColor:
                                                DashboardStyles.waterBorder,
                                            message: (_user
                                                        ?.waterStartConfigured ??
                                                    true)
                                                ? _staleCycleMessage
                                                : null,
                                          ),
                                  ),
                                ],
                              ),
                            ),

                      const SizedBox(height: 16),

                      // -------------------------------------------------
                      // (4) Fixed Cost: กดแล้วพาไปหน้า Settings (ส่วน fixed cost)
                      // -------------------------------------------------
                      _buildFixedCostRow(formatter),

                      const SizedBox(height: 16),

                      _buildSummaryCard(formatter),
                    ],
                  ),
                ),
              ),
            ),
      ),
      bottomNavigationBar:
          AppBottomNavBar(currentIndex: 0, onTap: widget.onNavTap),
    );
  }

  // =====================================================================
  // (1) Header ส่วนบน: ชื่อผู้ใช้ทักทาย + สถานะรอบบิล + ปุ่ม notification
  // พาร์ทนี้ทำหน้าที่: แสดงตัวตนผู้ใช้และบอกว่าอยู่ตรงไหนของรอบบิลปัจจุบัน
  // (ผ่านมากี่วัน / เหลืออีกกี่วันก่อนปิดรอบ) ให้รู้สึกเข้าใจง่ายตั้งแต่เปิดแอป
  // =====================================================================
  // ทักทายตามช่วงเวลาปัจจุบัน ให้ header ดูมีชีวิตชีวาขึ้นแทนคำว่า
  // "สวัสดี" คงที่ตลอดวัน
  String _greetingText() {
    final hour = DateTime.now().hour;
    final name = _user?.name ?? 'ผู้ใช้';
    final period = hour < 12
        ? 'สวัสดีตอนเช้า'
        : hour < 17
            ? 'สวัสดีตอนบ่าย'
            : 'สวัสดีตอนเย็น';
    return '$period, $name';
  }

  Widget _buildHeader(
      int daysElapsed, int remainingDays, int cycleLengthDays) {
    final progress = cycleLengthDays > 0
        ? (daysElapsed / cycleLengthDays).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar กลมเล็ก ๆ ให้ header ดูมีมิติ ไม่ใช่แค่ตัวอักษรลอย ๆ
        CircleAvatar(
          radius: 22,
          backgroundColor: DashboardStyles.primaryGreen.withValues(alpha: 0.12),
          child: Text(
            ((_user?.name.isNotEmpty ?? false)
                    ? _user!.name.substring(0, 1)
                    : 'U')
                .toUpperCase(),
            style: const TextStyle(
              color: DashboardStyles.primaryGreen,
              fontWeight: FontWeight.bold,
              fontSize: AppTypography.s18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greetingText(), style: DashboardStyles.greeting),
              const SizedBox(height: 5),
              // ผู้ใช้ใหม่ที่ยังไม่ได้ตั้งวันตัดรอบบิล ยังไม่มี "รอบบิล"
              // ให้อ้างอิงจริง ๆ (billingDay ที่ใช้คำนวณ progress ตอนนี้
              // เป็นแค่ default = 30 ไปก่อน) โชว์ป้ายสถานะบัญชีแทนแถบ
              // ผ่านมา/เหลืออีก + progress bar ที่ยังไม่มีความหมายจนกว่า
              // จะตั้งค่าจริง
              if (_user?.billingDayConfigured == false)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v8, vertical: AppSpacing.v3),
                  decoration: BoxDecoration(
                    color: DashboardStyles.primaryGreen.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppSpacing.v20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('บัญชีใหม่', style: DashboardStyles.subGreeting),
                      Text(' • ', style: DashboardStyles.subGreeting),
                      Text('รอดำเนินการเปิดระบบคาดการณ์',
                          style: DashboardStyles.subGreeting),
                    ],
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.v8, vertical: AppSpacing.v3),
                  decoration: BoxDecoration(
                    color: DashboardStyles.primaryGreen.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppSpacing.v20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ผ่านมา $daysElapsed วัน',
                          style: DashboardStyles.subGreeting),
                      const Text(' • ', style: DashboardStyles.subGreeting),
                      Text('เหลืออีก $remainingDays วัน',
                          style: DashboardStyles.subGreeting),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // แถบความคืบหน้าของรอบบิล (บาง ๆ ใต้ข้อความ)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.v4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade200,
                    color: DashboardStyles.primaryGreen,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        // -------------------------------------------------------------
        // ปุ่ม notification -> เปิดหน้า Notification Center จริง
        // พร้อม badge ตัวเลขแจ้งจำนวนรายการที่ยังไม่อ่าน
        // -------------------------------------------------------------
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded,
                  color: DashboardStyles.textDark),
              if (_unreadNotifications > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.v4, vertical: AppSpacing.v1),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.spikeUp,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.s9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: _onNotificationTap,
        ),
      ],
    );
  }

  // =====================================================================
  // (2) การ์ดค่าใช้จ่ายรอบนี้
  // การ์ดเขียวบนสุด โชว์ยอดไฟฟ้า/น้ำที่ใช้ไปแล้ว 2 ช่องซ้าย-ขวา และแถบ
  // ยอดคาดการณ์สิ้นรอบ (รวมไฟฟ้า+น้ำ ไม่รวม Fixed Cost) ต่อท้ายด้านล่าง
  // =====================================================================
  Widget _buildCostSummaryCard(NumberFormat formatter) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v20),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen,
        borderRadius: BorderRadius.circular(AppSpacing.v20),
        boxShadow: [
          BoxShadow(
            color: DashboardStyles.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  color: Colors.white.withValues(alpha: 0.85), size: 16),
              const SizedBox(width: 6),
              const Text('ประมาณการรอบบิลนี้',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: AppTypography.s13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCostCard(
                  icon: Icons.bolt,
                  label: 'ค่าไฟฟ้า',
                  amount: '${formatter.format(_currentElectricityCost)} บาท',
                  sub:
                      '${_currentElectricityFromStart.toStringAsFixed(1)} หน่วย',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildCostCard(
                  icon: Icons.water_drop,
                  label: 'ค่าน้ำ',
                  amount: '${formatter.format(_currentWaterCost)} บาท',
                  sub: '${_currentWaterFromStart.toStringAsFixed(1)} ลบ.ม.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ยอดคาดการณ์สิ้นรอบ — รวมไฟฟ้า+น้ำ แปะเป็น pill จางๆ บนพื้นเขียว
          // ให้เห็นตัวเลขปลายทางไม่ต้องรอเลื่อนไปหน้าวิเคราะห์ ถ้ายังไม่มีข้อมูล
          // พอคำนวณอัตรา (_hasForecastData == false) จะไม่โชว์เป็นตัวเลขคาดการณ์
          // (เพราะจะเท่ากับยอดปัจจุบันพอดี ดูเหมือนระบบฟันธงว่าใช้เท่านี้พอ)
          // แต่โชว์ข้อความจางๆ บอกว่าต้องบันทึกมิเตอร์หลังวันตัดรอบก่อน
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.v8, horizontal: AppSpacing.v12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.v10),
            ),
            child: Row(
              children: [
                Icon(
                  _hasForecastData ? Icons.trending_up : Icons.info_outline,
                  color: Colors.white.withValues(alpha: _hasForecastData ? 1 : 0.75),
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hasForecastData
                        ? 'ยอดคาดการณ์สิ้นรอบบิล: '
                            '${formatter.format(_forecastTotal)} บาท'
                        : 'บันทึกมิเตอร์หลังวันตัดรอบอย่างน้อย 1 วัน เพื่อเริ่มคาดการณ์',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: _hasForecastData ? 1 : 0.75),
                      fontSize: AppTypography.s12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // แบนเนอร์เล็กเตือนให้ตั้งวันตัดรอบบิล — ต่างจาก
  // การ์ดเช็คลิสต์ตรงที่ไม่บล็อกการใช้งานอะไรเลย (ระบบยัง
  // ใช้ default 30 คำนวณให้ได้อยู่) จึงออกแบบให้เด่นน้อยกว่า เป็นแถบบางๆ
  // กดแล้วพาไปหน้าตั้งค่า พร้อมเปิด dialog เลือกวันตัดรอบบิลให้เลย
  // (ใช้ SettingsQuickAction.billingDay ตัวเดียวกับที่หน้าอื่นเรียกใช้อยู่
  // แล้ว ไม่ต้องเพิ่ม flow ใหม่)
  // =====================================================================
  Widget _buildBillingDayReminderBanner() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v12),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const SettingsScreen(quickAction: SettingsQuickAction.billingDay),
          ),
        );
        await _loadData();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v14, vertical: AppSpacing.v12),
        decoration: BoxDecoration(
          color: DashboardStyles.primaryGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.v12),
          border: Border.all(
              color: DashboardStyles.primaryGreen.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_repeat,
                color: DashboardStyles.primaryGreen, size: 19),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'ยังไม่ได้ตั้งวันตัดรอบบิล แตะเพื่อตั้งค่า',
                style: TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 13, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // การ์ดเช็คลิสต์ "เริ่มต้นใช้งาน 3 ขั้นตอน" — แสดงแทนการ์ดมิเตอร์ตอนที่
  // ยังไม่ได้ตั้งเลขมิเตอร์ต้นรอบเลยสักฝั่ง (startMeterConfigured false)
  // แต่ละขั้นกดแล้วพาไปหน้านั้นได้ทันที ลำดับตรงกับคู่มือและเมนูในหน้าตั้งค่า:
  //   1) วันตัดรอบบิล — ติ๊กถูกเมื่อผู้ใช้เลือกวันเองแล้ว (billingDayConfigured)
  //   2) เลขมิเตอร์จากใบแจ้งหนี้ — ทำเสร็จแล้วการ์ดนี้จะหายไป
  //   3) บิลเดือนเก่า (ไม่บังคับ) — ไม่มีติ๊กถูก เพราะทำหรือไม่ทำก็ได้
  // ระหว่างนี้ห้ามบันทึกมิเตอร์รายวัน เพราะถ้าไม่มีเลขตั้งต้น ระบบจะเอาเลข
  // มิเตอร์สะสมทั้งก้อน (เช่น 15,234 หน่วย) ไปนับเป็น "หน่วยที่ใช้รอบนี้"
  // =====================================================================
  Widget _buildSetupChecklistCard() {
    final user = _user;
    final billingDayDone = user?.billingDayConfigured ?? false;

    Future<void> openAndReload(Future<void> Function() open) async {
      await open();
      await _loadData();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v14),
        border: Border.all(color: DashboardStyles.primaryGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.v8),
                decoration: BoxDecoration(
                  color: DashboardStyles.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.v8),
                ),
                child: const Icon(Icons.checklist_rounded,
                    color: DashboardStyles.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'เริ่มต้นใช้งาน 3 ขั้นตอน',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s14_5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ทำขั้นที่ 1–2 ให้ครบ หน้าหลักจะเริ่มคำนวณค่าไฟ/ค่าน้ำให้ค่ะ '
            'เตรียมใบแจ้งหนี้ใบล่าสุดไว้ได้เลย',
            style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600, height: 1.5),
          ),
          const SizedBox(height: 12),
          _setupStep(
            number: 1,
            title: 'ตั้งวันตัดรอบบิล',
            description: 'เลือกวันที่จดเลขมิเตอร์บนใบแจ้งหนี้',
            done: billingDayDone,
            onTap: () => openAndReload(() => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(
                        quickAction: SettingsQuickAction.billingDay),
                  ),
                )),
          ),
          _setupStep(
            number: 2,
            title: 'เลขมิเตอร์จากใบแจ้งหนี้',
            description: 'กรอกเลขมิเตอร์และยอดเงินจากใบแจ้งหนี้ล่าสุด',
            done: false,
            onTap: () => openAndReload(() => openStartMeterSetup(
                  context,
                  user!.uid,
                  _firestoreService,
                  user.meterType == 'tou',
                )),
          ),
          _setupStep(
            number: 3,
            title: 'เพิ่มบิลเดือนเก่า (ไม่บังคับ)',
            description: 'ย้อนหลังได้ 5 เดือน ให้หน้าวิเคราะห์มีข้อมูลทันที',
            done: false,
            onTap: () => openAndReload(() => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoricalBillListScreen(
                      uid: user!.uid,
                      firestoreService: _firestoreService,
                    ),
                  ),
                )),
          ),
        ],
      ),
    );
  }

  // แถวขั้นตอนในการ์ดเช็คลิสต์ — วงกลมเลขขั้น (เสร็จแล้วเป็นติ๊กถูก) +
  // ชื่อขั้น + คำอธิบายสั้น แตะทั้งแถวเพื่อไปทำขั้นนั้น
  Widget _setupStep({
    required int number,
    required String title,
    required String description,
    required bool done,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v8),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? DashboardStyles.primaryGreen
                    : DashboardStyles.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : Text('$number',
                      style: const TextStyle(
                          fontSize: AppTypography.s12_5,
                          fontWeight: FontWeight.bold,
                          color: DashboardStyles.primaryGreen)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: AppTypography.s13_5,
                        fontWeight: FontWeight.w600,
                        color: done ? Colors.grey.shade500 : DashboardStyles.textDark,
                      )),
                  const SizedBox(height: 2),
                  Text(done ? 'ตั้งแล้ว แตะเพื่อเปลี่ยน' : description,
                      style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // การ์ดล็อก — โชว์แทนการ์ดสรุปมิเตอร์ปกติ เฉพาะฝั่งที่ยังไม่ได้ตั้งเลข
  // มิเตอร์ต้นรอบ (electricityStartConfigured / waterStartConfigured เป็น
  // false) ในขณะที่อีกฝั่งตั้งไปแล้ว ไม่ใช้การ์ดเช็คลิสต์ (_buildSetupChecklistCard)
  // บล็อกทั้งคู่ เพราะฝั่งที่กรอกครบแล้วควรใช้งานได้เลย ไม่ต้องรอรอบอีกฝั่ง
  // (เคสมีบิลแค่ใบเดียวในมือ) ขนาด/โครงให้ใกล้เคียง _buildMeterSummaryCard
  // เพื่อให้สูงเท่ากันตอนอยู่ใน Row เดียวกัน
  // =====================================================================
  Widget _buildMeterLockedCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Color borderColor,
    // null = ยังไม่เคยตั้งค่าฝั่งนี้เลย, ไม่ null = เคยตั้งแล้ว
    // แต่รอบบิลเลื่อนไปแล้ว ต้องตั้งค่าต้นรอบใหม่ (ดู _staleCycleMessage)
    String? message,
  }) {
    final isStaleCycle = message != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: DashboardStyles.accentCard(borderColor.withValues(alpha: 0.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent.withValues(alpha: 0.5), size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                  fontSize: AppTypography.s14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message ?? 'ยังไม่ได้ตั้งเลขมิเตอร์ต้นรอบฝั่งนี้',
            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await openStartMeterSetup(
                  context,
                  _user!.uid,
                  _firestoreService,
                  _user?.meterType == 'tou',
                );
                await _loadData();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.v10),
                ),
              ),
              icon: Icon(isStaleCycle ? Icons.refresh : Icons.add, size: 16),
              label: Text(isStaleCycle ? 'ตั้งรอบใหม่' : 'ตั้งเลย',
                  style: const TextStyle(fontSize: AppTypography.s12_5)),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // (4) แถว Fixed Cost
  // พาร์ทนี้ทำหน้าที่: โชว์ยอด fixed cost ประจำเดือน และเมื่อกดจะพาไปหน้า
  // Fixed Cost ในตั้งค่าโดยตรง (ไม่ต้องผ่านหน้าตั้งค่าหลักก่อน)
  // =====================================================================
  Widget _buildFixedCostRow(NumberFormat formatter) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v14),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  const SettingsScreen(openFixedCostOnStart: true)),
        );
        _loadData(); // เผื่อยอด fixed cost เปลี่ยน
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v14),
        decoration: DashboardStyles.whiteCard(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.v8),
              decoration: BoxDecoration(
                color: AppColors.softGreenBg,
                borderRadius: BorderRadius.circular(AppSpacing.v10),
              ),
              child: const Icon(Icons.bookmark_outline,
                  color: DashboardStyles.primaryGreen, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'รายจ่ายประจำ',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTypography.s14,
                    color: DashboardStyles.textDark),
              ),
            ),
            Text(
              '${formatter.format(_billFixedCost)} บาท',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypography.s15,
                color: DashboardStyles.textDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // การ์ดยอดรวม — พื้นขาว กรอบครีม
  // ยอดที่ใช้ไปแล้วของรอบนี้ + รายจ่ายประจำ (ยังไม่ใช่ยอดบิลทั้งรอบ) ถ้ามี
  // ข้อมูลพอคาดการณ์ ต่อท้ายด้วยยอดคาดการณ์ทั้งรอบรวมรายจ่ายประจำ
  // -------------------------------------------------------------------
  Widget _buildSummaryCard(NumberFormat formatter) {
    final cycleEnd =
        EnergyForecaster.getCycleEnd(DateTime.now(), _user?.billingDay ?? 30);
    final cycleEndBuddhistYear = cycleEnd.year + 543;
    final fixedCost = _billFixedCost;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v18),
        border: Border.all(color: DashboardStyles.creamBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.v7),
                decoration: BoxDecoration(
                  color: AppColors.softOrangeBg,
                  borderRadius: BorderRadius.circular(AppSpacing.v9),
                ),
                child: const Icon(Icons.summarize_outlined,
                    color: Colors.orange, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ยอดรวมถึงตอนนี้ (บิล ${thaiMonths[cycleEnd.month - 1]} $cycleEndBuddhistYear)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTypography.s14_5,
                      color: DashboardStyles.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSummaryRow(
            'ค่าไฟ + น้ำ (ใช้ไปแล้ว)',
            '${formatter.format(_currentElectricityCost + _currentWaterCost)} บาท',
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            'รายจ่ายประจำ',
            '${formatter.format(fixedCost)} บาท',
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: DashboardStyles.creamBorder),
          const SizedBox(height: 16),
          // แถบ "รวมถึงตอนนี้" — แยกเป็นกล่องไฮไลต์ ให้เห็นยอดรวมชัด
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v14, vertical: AppSpacing.v13),
            decoration: BoxDecoration(
              color: AppColors.softOrangeBg,
              borderRadius: BorderRadius.circular(AppSpacing.v12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รวมถึงตอนนี้',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s15,
                    color: DashboardStyles.textDark,
                  ),
                ),
                Text(
                  '${formatter.format((_currentElectricityCost + _currentWaterCost) + fixedCost)} บาท',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s19,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          if (_hasForecastData) ...[
            const SizedBox(height: 12),
            _buildSummaryRow(
              'คาดว่าบิลทั้งรอบ (รวมรายจ่ายประจำ)',
              '${formatter.format(_forecastTotal + fixedCost)} บาท',
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================================
  // การ์ดย่อยไฟฟ้า/น้ำ ในการ์ดสรุปเขียว (_buildCostSummaryCard)
  // พาร์ทนี้ทำหน้าที่: แสดงไอคอน + ชื่อรายการ + ยอดเงิน + จำนวนหน่วยที่ใช้
  // =====================================================================
  Widget _buildCostCard({
    required IconData icon,
    required String label,
    required String amount,
    required String sub,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: AppTypography.s12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount,
            style: const TextStyle(
                color: Colors.white,
                fontSize: AppTypography.s20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: Colors.white60, fontSize: AppTypography.s11)),
      ],
    );
  }


  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
              color: DashboardStyles.textDark,
              fontSize: AppTypography.s13,
            )),
        Text(value,
            style: const TextStyle(
              color: DashboardStyles.textDark,
              fontSize: AppTypography.s14,
            )),
      ],
    );
  }

  // =====================================================================
  // การ์ดสรุปมิเตอร์ (ไฟฟ้า/น้ำ) — ไม่มีช่องกรอกในการ์ด มีแค่โชว์ค่าล่าสุด/
  // ต้นรอบ แล้วกดปุ่มเดียวพาไปหน้าเต็มจอ RecordMeterScreen (ดูเหตุผลที่แยก
  // หน้าที่ต้นไฟล์ record_meter_screen.dart)
  // =====================================================================
  // ป้าย On-Peak/Off-Peak ทางซ้าย ค่าล่าสุดทางขวา (ไม่โชว์ต้นรอบในแถวนี้)
  // ไม่ใส่ overflow/maxLines บังคับตัด ปล่อยให้ Text ห่อเองตามพื้นที่จริง
  // ถ้าฟอนต์ระบบถูกซูม/ปรับใหญ่ขึ้นจะยืดหยุ่นตามนั้น
  Widget _touMeterRow(String label, double? current, NumberFormat formatter) {
    final c = current ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
        const Spacer(),
        Flexible(
          child: Text(
            formatter.format(c),
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: AppTypography.s15,
                fontWeight: FontWeight.w600,
                color: DashboardStyles.textDark),
          ),
        ),
      ],
    );
  }

  Widget _buildMeterSummaryCard({
    required MeterKind kind,
    bool isTou = false,
  }) {
    final formatter = NumberFormat('#,##0.##');
    final isElectricity = kind == MeterKind.electricity;
    final borderColor =
        isElectricity ? DashboardStyles.electricityBorder : DashboardStyles.waterBorder;
    final badgeBg =
        isElectricity ? DashboardStyles.electricityFieldBg : DashboardStyles.waterFieldBg;
    final unit = isElectricity ? 'หน่วย' : 'ลบ.ม.';
    final title = isElectricity ? (isTou ? 'ไฟฟ้า (TOU)' : 'ไฟฟ้า') : 'น้ำ';
    final icon = isElectricity ? Icons.bolt : Icons.water_drop;

    final double? lastValue = isTou
        ? null
        : (isElectricity
            ? (_cycleLatestElectricityLog?.meterValue ?? _user?.startElectricityValue)
            : (_cycleLatestWaterLog?.meterValue ?? _user?.startWaterValue));
    final double? startValue = isTou
        ? null
        : (isElectricity ? _user?.startElectricityValue : _user?.startWaterValue);
    final double? lastPeak = isTou
        ? (_cycleLatestElectricityLog?.peakMeterValue ?? _user?.startPeakValue)
        : null;
    final double? lastOffPeak = isTou
        ? (_cycleLatestElectricityLog?.offPeakMeterValue ?? _user?.startOffPeakValue)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: DashboardStyles.accentCard(borderColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                child: Icon(icon, color: borderColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(color: borderColor, fontWeight: FontWeight.w600, fontSize: AppTypography.s13_5),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isTou) ...[
            _touMeterRow('On-Peak', lastPeak, formatter),
            const SizedBox(height: 6),
            _touMeterRow('Off-Peak', lastOffPeak, formatter),
          ] else ...[
            if (lastValue != null)
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: DashboardStyles.textDark),
                  children: [
                    TextSpan(
                        text: formatter.format(lastValue),
                        style: const TextStyle(fontSize: AppTypography.s20, fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: ' $unit',
                        style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            if (startValue != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.v2),
                child: Text('ต้นรอบ ${formatter.format(startValue)} $unit',
                    style: DashboardStyles.lastValueStyle),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openRecordMeter(kind),
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeBg,
                foregroundColor: borderColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v10)),
              ),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('บันทึกมิเตอร์', style: TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // log ล่าสุดของรอบบิลปัจจุบัน (_electricityLogs/_waterLogs เรียงใหม่สุดก่อน)
  // ใช้เป็น "ค่าล่าสุด" บนการ์ดสรุปและหน้าบันทึกมิเตอร์ — null = รอบนี้ยังไม่
  // ได้บันทึก ผู้เรียกใช้ค่าต้นรอบแทน ส่วน _latestElectricityLog/_latestWaterLog
  // (log ล่าสุดทุกรอบ) ใช้เฉพาะเช็ค "ไม่ได้บันทึกมิเตอร์มากี่วัน"
  ElectricityLogModel? get _cycleLatestElectricityLog =>
      _electricityLogs.isNotEmpty ? _electricityLogs.first : null;
  WaterLogModel? get _cycleLatestWaterLog =>
      _waterLogs.isNotEmpty ? _waterLogs.first : null;

  // แปลง log ของรอบนี้เป็น MeterHistoryEntry ให้ RecordMeterScreen ใช้โชว์
  // ประวัติในหน้าสำเร็จ — _electricityLogs/_waterLogs มาจาก
  // getCurrentMonthElectricityLogs/getCurrentMonthWaterLogs ซึ่ง query แบบ
  // orderBy('date', descending: true) อยู่แล้ว (ใหม่สุดอยู่บนสุด) จึงส่งต่อ
  // ตรงๆ ไม่ต้อง reverse
  List<MeterHistoryEntry> _historyFor(MeterKind kind) {
    if (kind == MeterKind.electricity) {
      return _electricityLogs
          .map((log) => MeterHistoryEntry(
              date: log.date, usedFromLast: log.usedFromLast, cost: log.cost))
          .toList();
    }
    return _waterLogs
        .map((log) => MeterHistoryEntry(
            date: log.date, usedFromLast: log.usedFromLast, cost: log.cost))
        .toList();
  }

  // เปิดหน้าบันทึกมิเตอร์เต็มจอ — ส่งค่าต้นรอบ/ล่าสุดของยูทิลิตี้นั้นๆ ไปให้
  // ครบ พอปิดหน้ากลับมาแล้วมีการบันทึกสำเร็จ (result.saved) ค่อยโหลดข้อมูล
  // ใหม่ทั้งหน้า — isTou ส่งตาม meterType ของผู้ใช้เสมอ (รวมฝั่งน้ำ) เพราะ
  // หน้านั้นส่งต่อให้หน้าตั้งเลขมิเตอร์ต้นรอบ ซึ่งต้องรู้ว่าไฟฟ้าเป็น TOU ไหม
  Future<void> _openRecordMeter(MeterKind kind) async {
    final isElectricity = kind == MeterKind.electricity;
    final result = await Navigator.push<RecordMeterResult>(
      context,
      MaterialPageRoute(
        builder: (context) => RecordMeterScreen(
          kind: kind,
          isTou: _user?.meterType == 'tou',
          uid: _user!.uid,
          firestoreService: _firestoreService,
          area: _user?.area ?? 'bangkok',
          startValue: isElectricity ? (_user?.startElectricityValue ?? 0) : (_user?.startWaterValue ?? 0),
          lastValue: isElectricity
              ? (_cycleLatestElectricityLog?.meterValue ?? _user?.startElectricityValue ?? 0)
              : (_cycleLatestWaterLog?.meterValue ?? _user?.startWaterValue ?? 0),
          startPeak: _user?.startPeakValue ?? 0,
          lastPeak: _cycleLatestElectricityLog?.peakMeterValue ?? _user?.startPeakValue ?? 0,
          startOffPeak: _user?.startOffPeakValue ?? 0,
          lastOffPeak:
              _cycleLatestElectricityLog?.offPeakMeterValue ?? _user?.startOffPeakValue ?? 0,
          recentLogs: _historyFor(kind),
        ),
      ),
    );

    if (result == null) return;
    if (result.saved) await _loadData();
  }
}