import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
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
  // true เฉพาะตอนเพิ่ง push มาจาก setup_screen/setup_complete_screen หลัง
  // สมัครสมาชิกเสร็จหมาดๆ ใช้กันไม่ให้แจ้งเตือนหลายๆ อย่างยิง popup รัว
  // พร้อมกันตั้งแต่เปิดแอปครั้งแรก (ยังเห็นแค่ welcome พอ ที่เหลือถ้ามี
  // จะถูกบันทึกเงียบๆ ไว้ในหน้าแจ้งเตือนแทน ไปดูเองได้)
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

  // ----- ยอดเดือนก่อน (ใช้เทียบ "พุ่งขึ้น") -----
  double _lastMonthElectricityCost = 0;
  double _lastMonthWaterCost = 0;

  bool _isLoading = true;
  int _unreadNotifications =
      0; // จำนวนแจ้งเตือนที่ยังไม่อ่าน (badge ที่ปุ่มกระดิ่ง)

  // เช็คแค่ "ครั้งแรก" ที่ _loadData() รัน (ไม่ใช่ทุกครั้งที่ pull-to-refresh)
  // ใช้คู่กับ widget.justCompletedSetup เพื่อทำให้แจ้งเตือนเงียบแค่รอบเดียว
  bool _isFirstLoad = true;

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
    // หมายเหตุ: ย้าย notifyWelcome() ไปไว้ที่ setup_screen.dart แทนแล้ว
    // เพราะที่นี่ (Dashboard.initState) รันทุกครั้งที่เข้า Dashboard
    // (ทั้ง login เก่าและใหม่) ทำให้แจ้งเตือนต้อนรับเด้งซ้ำผิดจุดประสงค์
    // ที่ setup_screen.dart จะรันแค่ครั้งเดียวจริงๆ ตอนบัญชีใหม่ทำ setup
    // เสร็จครั้งแรกเท่านั้น
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
  // ใช้สูตรเดียวกับ _AddStartMeterSheet/_StartMeterHistoryScreen ใน
  // settings_start_meter.dart เป๊ะ (_expectedInvoiceMonth + เทียบ
  // startBillingMonth/Year) เพื่อให้ทุกจุดของแอปตัดสิน "รอบปัจจุบัน" ตรงกัน
  // หมด — เป็น field เดียวใช้ร่วมกันทั้งไฟและน้ำ (ไม่แยกรายยูทิลิตี้) เพราะ
  // UserModel เก็บ startBillingMonth/Year ไว้แค่ชุดเดียว
  bool get _startMeterMatchesCurrentCycle {
    final user = _user;
    if (user == null) return false;
    final expected =
        EnergyForecaster.getCycleStart(DateTime.now(), user.billingDay);
    return user.startBillingMonth == expected.month &&
        user.startBillingYear == expected.year;
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

  static const _staleCycleMessage =
      'ตัดรอบบิลใหม่แล้ว ต้องตั้งเลขมิเตอร์ต้นรอบใหม่ก่อนบันทึกค่ะ';

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_onDataChangedElsewhere);
    super.dispose();
  }

  // =====================================================================
  // โหลดข้อมูล: user, log ล่าสุด, log เดือนนี้, ปิดบิลเดือนก่อนถ้ายังไม่ปิด
  // =====================================================================
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // เงียบเฉพาะโหลดรอบแรกจริงๆ หลังสมัครสมาชิกเสร็จ — รอบถัดไป (pull-to-
    // refresh, กลับมาเปิดแอปใหม่) ยิง popup ตามปกติ
    final bool silentThisLoad = widget.justCompletedSetup && _isFirstLoad;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // sync ยอด fixed cost ให้ตรงกับเดือนปัจจุบันก่อนอ่าน user เพราะรายการที่
      // ตั้ง endDate ไว้อาจ "หมดอายุ" ไปแล้วโดยไม่มี save/delete มา trigger recalc
      await _firestoreService.recalcFixedCostTotalForToday(uid);
      _user = await _firestoreService.getUser(uid);

      _latestElectricityLog =
          await _firestoreService.getLatestElectricityLog(uid);
      _latestWaterLog = await _firestoreService.getLatestWaterLog(uid);
      final now = DateTime.now();
      final billingDay = _user?.billingDay ?? 30;
      final DateTime startDate =
          EnergyForecaster.getCycleStart(now, billingDay);
      final DateTime endDate = EnergyForecaster.getCycleEnd(now, billingDay);

      final prevCycleStart =
          EnergyForecaster.getPreviousCycleStart(startDate, billingDay);
      final prevCycleEnd = startDate;
      final billExists = await _firestoreService.billExistsForMonth(
          uid, prevCycleEnd.year, prevCycleEnd.month);
      final bool billJustCreated = !billExists;
      if (!billExists) {
        await _firestoreService.compileBill(
          uid,
          prevCycleEnd.year,
          prevCycleEnd.month,
          _user?.fixedCost ?? 0,
          prevCycleStart,
          prevCycleEnd,
        );
      }

      // ดึงยอดบิลเดือนก่อน (ที่ปิดไปแล้ว) มาเทียบ "พุ่งขึ้น/ลดลง"
      // FirestoreService ไม่มี getBillForMonth ตรง ๆ จึงใช้ getBills() ที่คืนมา
      // เรียงล่าสุดมาก่อนแล้ว แล้วหยิบตัวแรกซึ่งคือบิลที่ปิดล่าสุด
      try {
        final allBills = await _firestoreService.getBills(uid);
        if (allBills.isNotEmpty) {
          _lastMonthElectricityCost = allBills.first.electricityCost;
          _lastMonthWaterCost = allBills.first.waterCost;

          // ----- แจ้งเตือนสรุปจบรอบบิล -----
          // ยิงเฉพาะตอนที่บิลของรอบก่อนหน้านี้ "ถูกสร้างใหม่" ในการโหลดครั้งนี้
          // (กันไม่ให้เตือนซ้ำทุกครั้งที่เปิดแอป เพราะ key กันซ้ำผูกกับ billId)
          if (billJustCreated &&
              allBills.first.year == prevCycleEnd.year &&
              allBills.first.month == prevCycleEnd.month) {
            await NotificationService.instance.notifyCycleSummary(
              billId: allBills.first.id,
              totalCost: allBills.first.totalCost,
              year: allBills.first.year,
              month: allBills.first.month,
              silent: silentThisLoad,
            );
          }
        } else {
          _lastMonthElectricityCost = 0;
          _lastMonthWaterCost = 0;
        }
      } catch (_) {
        _lastMonthElectricityCost = 0;
        _lastMonthWaterCost = 0;
      }

      _electricityLogs = await _firestoreService.getCurrentMonthElectricityLogs(
          uid, startDate, endDate);
      _waterLogs = await _firestoreService.getCurrentMonthWaterLogs(
          uid, startDate, endDate);

      await _calculateCurrentMonth();

      // ===================================================
      // เรียกระบบแจ้งเตือนทั้ง 3 อย่างที่เหลือ หลังคำนวณข้อมูลเสร็จ
      // ===================================================

      // (Scheduled) เตือนใกล้วันตัดรอบบิล — ตั้งล่วงหน้าให้ OS จัดการเอง
      await NotificationService.instance.scheduleBillingReminder(
        billingDate: endDate,
        daysBefore: 3,
      );

      // (Instant) เตือนยังไม่บันทึกมิเตอร์เกิน N วัน — ดูจาก log ล่าสุดที่เก่ากว่า
      final latestLogDates = [
        _latestElectricityLog?.date,
        _latestWaterLog?.date,
      ].whereType<DateTime>().toList();
      if (latestLogDates.isNotEmpty) {
        latestLogDates.sort();
        await NotificationService.instance.checkMeterNotRecorded(
          lastLogDate: latestLogDates.last, // log ล่าสุด (ใหม่ที่สุด)
          silent: silentThisLoad,
        );
      }

      // (Instant) เตือนเมื่อใช้ไฟ/น้ำเกิน 30% ของเดือนก่อน
      await NotificationService.instance.checkUsageSpike(
        currentElectricityCost: _currentElectricityCost,
        lastMonthElectricityCost: _lastMonthElectricityCost,
        currentWaterCost: _currentWaterCost,
        lastMonthWaterCost: _lastMonthWaterCost,
        cycleStart: startDate,
        silent: silentThisLoad,
      );

      // sync ดูว่า scheduled notification (เตือนใกล้วันบิล) ถึงกำหนดยิงแล้ว
      // หรือยัง ถ้าถึงแล้วจะถูกบันทึกเข้า history ให้เห็นในหน้า Notification
      await NotificationService.instance.syncDeliveredScheduledNotifications();

      // (Instant) เตือนล่วงหน้าถ้าคาดการณ์สิ้นเดือนจะสูงกว่าเดือนก่อน
      await NotificationService.instance.checkForecastHigherThanLastMonth(
        forecastTotal: _forecastTotal,
        lastMonthTotal: _lastMonthElectricityCost + _lastMonthWaterCost,
        cycleStart: startDate,
        silent: silentThisLoad,
      );

      // อัปเดตจำนวนแจ้งเตือนที่ยังไม่อ่าน เพื่อโชว์ badge ตัวเลขที่ปุ่มกระดิ่ง
      _unreadNotifications =
          await NotificationService.instance.getUnreadCount();
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      _isFirstLoad = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =====================================================================
  // คำนวณยอดใช้งาน/ค่าใช้จ่ายเดือนนี้ + คาดการณ์สิ้นเดือน (แยกไฟฟ้า/น้ำ)
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

    final now = DateTime.now();
    final remainingDays =
        EnergyForecaster.getRemainingDays(now, _user?.billingDay ?? 30);

    // ----- ค่าเฉลี่ย "บาท/วัน" จริง -----
    // ห้ามเอา dailyUsage (หน่วย/วัน) ไปบวกกับ currentTotal (บาท) ตรง ๆ ผ่าน
    // EnergyForecaster.forecastCurrentMonth เพราะยอดคาดการณ์จะไม่ใช่ "บาท"
    // จริง (หน่วยคนละอย่างกัน) ต้องคำนวณผลต่างของ cost สะสม (field `cost`
    // ใน log เป็นค่าสะสมจากต้นรอบเหมือน usedFromStart) ระหว่างแต่ละครั้งที่
    // บันทึก ให้ได้ "บาทที่เพิ่มขึ้นต่อช่วง" จริง ๆ ก่อนป้อนเข้า movingAverage
    final dailyElectricityCost =
        _dailyCostDeltas(_electricityLogs.map((l) => l.cost).toList());
    final dailyWaterCost =
        _dailyCostDeltas(_waterLogs.map((l) => l.cost).toList());

    _forecastElectricityCost = EnergyForecaster.movingAverage(
      dailyUsage: dailyElectricityCost,
      remainingDays: remainingDays,
      currentTotal: _currentElectricityCost,
    );
    _forecastWaterCost = EnergyForecaster.movingAverage(
      dailyUsage: dailyWaterCost,
      remainingDays: remainingDays,
      currentTotal: _currentWaterCost,
    );
    _forecastTotal = _forecastElectricityCost + _forecastWaterCost;
  }

  // =====================================================================
  // คำนวณ "บาทที่เพิ่มขึ้นต่อครั้งบันทึก" จากค่า cost สะสม (cumulative)
  // ของ log แต่ละตัว เพราะ field `cost` ในโมเดลเป็นยอดสะสมจากต้นรอบ
  // เหมือน usedFromStart ไม่ใช่ค่าต่อช่วงอยู่แล้ว — รับลิสต์ cost ที่เรียง
  // ล่าสุดมาก่อน (ตามที่ FirestoreService คืนมา) แล้วกลับลำดับเป็นเก่า->ใหม่
  // ก่อนหาผลต่าง
  // =====================================================================
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final billingDay = _user?.billingDay ?? 30;
    final remainingDays = EnergyForecaster.getRemainingDays(now, billingDay);
    final daysElapsed = EnergyForecaster.getDaysElapsed(now, billingDay);
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: DashboardStyles.primaryGreen))
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: DashboardStyles.primaryGreen,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // -------------------------------------------------
                      // (1) Header: สวัสดี + ผ่านมา/เหลืออีก + ปุ่ม notification
                      // จัด layout ใหม่ ให้ "สวัสดี" เด่นขึ้น มี avatar กลม
                      // และ progress แถบเล็ก ๆ บอกความคืบหน้าของรอบบิล
                      // -------------------------------------------------
                      _buildHeader(daysElapsed, remainingDays),

                      const SizedBox(height: 18),

                      // -------------------------------------------------
                      // (2) การ์ดค่าใช้จ่ายเดือนนี้
                      // เพิ่ม: สัญลักษณ์พุ่งขึ้น + บรรทัดยอดคาดการณ์แยกไฟฟ้า/น้ำ
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
                      // ตัวเตือนวันตัดรอบบิล — วางไว้ตรงนี้เพราะเกี่ยวข้องกับ
                      // ขั้นตอน "บันทึกมิเตอร์วันนี้ / ตั้งค่ามิเตอร์ต้นรอบ"
                      // (ทั้งคู่คือสิ่งที่ user ใหม่ต้องตั้งค่าก่อนใช้งานจริง)
                      // โชว์เฉพาะบัญชีที่ยังไม่เคยกดเลือกวันตัดรอบบิลเอง
                      // (billingDayConfigured == false)
                      // -------------------------------------------------
                      if (_user?.billingDayConfigured == false) ...[
                        _buildBillingDayReminderBanner(),
                        const SizedBox(height: 10),
                      ],

                      // การ์ดไฟฟ้ากับน้ำอยู่คู่กันแบบ Row ซ้าย-ขวา — ไม่มีช่อง
                      // กรอกอยู่ในการ์ดเองแล้ว (ย้ายไปหน้าเต็มจอ
                      // RecordMeterScreen หมด) การ์ดตรงนี้เหลือแค่โชว์สรุป
                      // ค่าล่าสุด/ต้นรอบ + ปุ่มเดียวพาไปหน้าบันทึก ใช้
                      // IntrinsicHeight ให้การ์ดไฟ (TOU โชว์ 2 บรรทัดสรุป)
                      // กับการ์ดน้ำ (1 บรรทัด) สูงเท่ากัน — เช็ค
                      // startMeterConfigured ของแต่ละฝั่งแยกกัน (ดู
                      // UserModel) ถ้ายังไม่ได้ตั้งเลยสักอย่าง โชว์การ์ดเต็ม
                      // ความกว้าง แต่ถ้าตั้งไปแล้วอย่างน้อย 1 ฝั่ง ให้ใช้งาน
                      // ฝั่งที่พร้อมได้ก่อนเลย ส่วนฝั่งที่ยังไม่พร้อมโชว์
                      // การ์ดล็อกแยกแทนที่จะบล็อกทั้งคู่
                      _user?.startMeterConfigured == false
                          ? _buildStartMeterRequiredCard()
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

  Widget _buildHeader(int daysElapsed, int remainingDays) {
    final totalCycleDays = daysElapsed + remainingDays;
    final progress = totalCycleDays > 0
        ? (daysElapsed / totalCycleDays).clamp(0.0, 1.0)
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
              fontSize: 18,
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
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        DashboardStyles.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
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
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        DashboardStyles.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
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
                  borderRadius: BorderRadius.circular(4),
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
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
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
  // (2) การ์ดค่าใช้จ่ายเดือนนี้
  // พาร์ทนี้ทำหน้าที่: การ์ดเขียวบนสุด โชว์ยอดไฟฟ้า/น้ำปัจจุบัน 2 ช่อง
  // ซ้าย-ขวา และแถบยอดคาดการณ์สิ้นเดือน (รวมไฟฟ้า+น้ำ) ต่อท้ายด้านล่าง
  // =====================================================================
  Widget _buildCostSummaryCard(NumberFormat formatter) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen,
        borderRadius: BorderRadius.circular(20),
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
                      fontSize: 13,
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
          // ยอดคาดการณ์สิ้นเดือน — รวมไฟฟ้า+น้ำ แปะเป็น pill จางๆ บนพื้น
          // เขียวเดิม ให้เห็นตัวเลขปลายทางไม่ต้องรอเลื่อนไปหน้าวิเคราะห์
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.trending_up, color: Colors.white, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ยอดคาดการณ์สิ้นเดือน: '
                    '${formatter.format(_forecastTotal)} บาท',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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

  // -------------------------------------------------------------------
  // บาร์ล่าง — ย้ายไปเป็น widget กลางที่ใช้ร่วมกันทุกหน้าแล้ว
  // ดู lib/widgets/app_bottom_nav_bar.dart
  // -------------------------------------------------------------------

  // =====================================================================
  // แบนเนอร์เล็กเตือนให้ตั้งวันตัดรอบบิล — ต่างจาก
  // _buildStartMeterRequiredCard() ตรงที่ไม่บล็อกการใช้งานอะไรเลย (ระบบยัง
  // ใช้ default 30 คำนวณให้ได้อยู่) จึงออกแบบให้เด่นน้อยกว่า เป็นแถบบางๆ
  // กดแล้วพาไปหน้าตั้งค่า พร้อมเปิด dialog เลือกวันตัดรอบบิลให้เลย
  // (ใช้ SettingsQuickAction.billingDay ตัวเดียวกับที่หน้าอื่นเรียกใช้อยู่
  // แล้ว ไม่ต้องเพิ่ม flow ใหม่)
  // =====================================================================
  Widget _buildBillingDayReminderBanner() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: DashboardStyles.primaryGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
  // การ์ดเตือนให้ตั้งค่ามิเตอร์ต้นรอบก่อน — แสดงแทนช่องกรอกมิเตอร์ปกติ
  // เฉพาะตอนที่ยังไม่ได้ตั้งเลยสักฝั่ง (electricityStartConfigured และ
  // waterStartConfigured เป็น false ทั้งคู่ = startMeterConfigured false)
  // ถ้าตั้งไปแล้วอย่างน้อย 1 ฝั่ง จะไม่โชว์การ์ดนี้อีกต่อไป แต่ไปโชว์
  // _buildMeterLockedCard() แยกเฉพาะฝั่งที่ยังไม่ได้ตั้งแทน (ดูจุดเรียกใช้
  // ใน build()) เพราะถ้าปล่อยให้กรอกเลย ระบบจะเอาเลขมิเตอร์สะสมจริงทั้งก้อน
  // (เช่น 15,234 หน่วย) ไปคำนวณเป็น "หน่วยที่ใช้เดือนนี้" ทันที ทำให้ค่าไฟ/
  // น้ำรอบแรกเพี้ยนมหาศาล และไปกระทบข้อมูลคาดการณ์ในหน้าวิเคราะห์ด้วย
  // =====================================================================
  Widget _buildStartMeterRequiredCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DashboardStyles.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.speed_outlined,
                    color: DashboardStyles.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'ยังไม่ได้ตั้งค่ามิเตอร์ต้นรอบ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // โฟกัสที่ "ผลลัพธ์ที่ยังทำไม่ได้" แทนการเดาสาเหตุที่มา (ผู้ใช้
          // อาจมาจากหลายทาง ไม่ใช่แค่ข้ามขั้นตอนตอนสมัครเสมอไป)
          const Text(
            'ระบบยังคำนวณค่าไฟ/ค่าน้ำให้ไม่ได้ เพราะยังไม่มีเลขมิเตอร์ตั้งต้น',
            style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await openStartMeterSetup(
                  context,
                  _user!.uid,
                  _firestoreService,
                  _user?.meterType == 'tou',
                );
                await _loadData();
              },
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('ตั้งค่ามิเตอร์ต้นรอบ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DashboardStyles.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // การ์ดล็อก — โชว์แทนการ์ดสรุปมิเตอร์ปกติ เฉพาะฝั่งที่ยังไม่ได้ตั้งเลข
  // มิเตอร์ต้นรอบ (electricityStartConfigured / waterStartConfigured เป็น
  // false) ในขณะที่อีกฝั่งตั้งไปแล้ว ไม่ใช้ _buildStartMeterRequiredCard()
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
      padding: const EdgeInsets.all(14),
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
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message ?? 'ยังไม่ได้ตั้งเลขมิเตอร์ต้นรอบฝั่งนี้',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
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
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(isStaleCycle ? Icons.refresh : Icons.add, size: 16),
              label: Text(isStaleCycle ? 'ตั้งรอบใหม่' : 'ตั้งเลย',
                  style: const TextStyle(fontSize: 12.5)),
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
      borderRadius: BorderRadius.circular(14),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: DashboardStyles.whiteCard(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bookmark_outline,
                  color: DashboardStyles.primaryGreen, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Fixed Cost รายจ่ายประจำ',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: DashboardStyles.textDark),
              ),
            ),
            Text(
              '${formatter.format(_user?.fixedCost ?? 0)} บาท',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
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
  // -------------------------------------------------------------------
  Widget _buildSummaryCard(NumberFormat formatter) {
    final cycleEnd =
        EnergyForecaster.getCycleEnd(DateTime.now(), _user?.billingDay ?? 30);
    final cycleEndBuddhistYear = cycleEnd.year + 543;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.summarize_outlined,
                    color: Colors.orange, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ยอดสรุปบิลรอบถัดไป (${thaiMonths[cycleEnd.month - 1]} $cycleEndBuddhistYear)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: DashboardStyles.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSummaryRow(
            'ค่าไฟ + น้ำ (ปัจจุบัน)',
            '${formatter.format(_currentElectricityCost + _currentWaterCost)} บาท',
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            'Fixed Cost',
            '${formatter.format(_user?.fixedCost ?? 0)} บาท',
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: DashboardStyles.creamBorder),
          const SizedBox(height: 16),
          // แถบ "รวมทั้งสิ้น" — แยกเป็นกล่องไฮไลต์ ให้รู้สึกเป็นยอดสุดท้ายจริง ๆ
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รวมทั้งสิ้น',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: DashboardStyles.textDark,
                  ),
                ),
                Text(
                  '${formatter.format((_currentElectricityCost + _currentWaterCost) + (_user?.fixedCost ?? 0))} บาท',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                    color: Colors.orange,
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
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }


  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? DashboardStyles.textDark,
              fontSize: isBold ? 15 : 13,
            )),
        Text(value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? DashboardStyles.textDark,
              fontSize: isBold ? 18 : 14,
            )),
      ],
    );
  }

  // =====================================================================
  // การ์ดสรุปมิเตอร์ (ไฟฟ้า/น้ำ) — แทนที่การ์ดกรอกเลขเดิมทั้งหมด (ทั้ง
  // มิเตอร์ปกติและ TOU) ตัวการ์ดเองไม่มีช่องกรอกแล้ว มีแค่โชว์ค่าล่าสุด/
  // ต้นรอบ แล้วกดปุ่มเดียวพาไปหน้าเต็มจอ RecordMeterScreen แทน (ดูเหตุผล
  // ที่ย้ายออกมาที่ท้ายไฟล์ record_meter_screen.dart)
  // =====================================================================
  // แถวเดียวของการ์ด TOU: ป้าย On-Peak/Off-Peak ทางซ้าย ค่าล่าสุดตัวหนา
  // ตามด้วยต้นรอบสีจางแบบ "/ต้นรอบ" ทางขวา — ให้เห็นต้นรอบเทียบเคียงค่า
  // ล่าสุดได้ทันทีในหน้าแดชบอร์ด ไม่ต้องกดเข้าไปในฟอร์มบันทึกมิเตอร์
  Widget _touMeterRow(
      String label, double? current, double? start, NumberFormat formatter) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: DashboardStyles.textDark)),
        const Spacer(),
        RichText(
          text: TextSpan(
            style: const TextStyle(color: DashboardStyles.textDark),
            children: [
              TextSpan(
                  text: formatter.format(current ?? 0),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              TextSpan(
                  text: ' /${formatter.format(start ?? 0)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ],
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
            ? (_latestElectricityLog?.meterValue ?? _user?.startElectricityValue)
            : (_latestWaterLog?.meterValue ?? _user?.startWaterValue));
    final double? startValue = isTou
        ? null
        : (isElectricity ? _user?.startElectricityValue : _user?.startWaterValue);
    final double? lastPeak =
        isTou ? (_latestElectricityLog?.peakMeterValue ?? _user?.startPeakValue) : null;
    final double? lastOffPeak = isTou
        ? (_latestElectricityLog?.offPeakMeterValue ?? _user?.startOffPeakValue)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                    style: TextStyle(color: borderColor, fontWeight: FontWeight.w600, fontSize: 13.5),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isTou) ...[
            _touMeterRow('On-Peak', lastPeak, _user?.startPeakValue, formatter),
            const SizedBox(height: 6),
            _touMeterRow('Off-Peak', lastOffPeak, _user?.startOffPeakValue, formatter),
          ] else ...[
            if (lastValue != null)
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: DashboardStyles.textDark),
                  children: [
                    TextSpan(
                        text: formatter.format(lastValue),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: ' $unit',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            if (startValue != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('ต้นรอบ ${formatter.format(startValue)} $unit',
                    style: DashboardStyles.lastValueStyle),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openRecordMeter(kind, isTou: isTou),
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeBg,
                foregroundColor: borderColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('บันทึกมิเตอร์', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

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
  // ใหม่ทั้งหน้า
  Future<void> _openRecordMeter(MeterKind kind, {bool isTou = false}) async {
    final isElectricity = kind == MeterKind.electricity;
    final result = await Navigator.push<RecordMeterResult>(
      context,
      MaterialPageRoute(
        builder: (context) => RecordMeterScreen(
          kind: kind,
          isTou: isTou,
          uid: _user!.uid,
          firestoreService: _firestoreService,
          area: _user?.area ?? 'bangkok',
          startValue: isElectricity ? (_user?.startElectricityValue ?? 0) : (_user?.startWaterValue ?? 0),
          lastValue: isElectricity
              ? (_latestElectricityLog?.meterValue ?? _user?.startElectricityValue ?? 0)
              : (_latestWaterLog?.meterValue ?? _user?.startWaterValue ?? 0),
          startPeak: _user?.startPeakValue ?? 0,
          lastPeak: _latestElectricityLog?.peakMeterValue ?? _user?.startPeakValue ?? 0,
          startOffPeak: _user?.startOffPeakValue ?? 0,
          lastOffPeak: _latestElectricityLog?.offPeakMeterValue ?? _user?.startOffPeakValue ?? 0,
          recentLogs: _historyFor(kind),
        ),
      ),
    );

    if (result == null) return;
    if (result.saved) await _loadData();
  }
}