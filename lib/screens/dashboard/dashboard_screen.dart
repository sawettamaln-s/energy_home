import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/calculator.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/forecaster.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/info_dialog.dart';
import '../../widgets/onboarding_guide.dart';
import '../settings/settings_screen.dart';
import 'dashboard_styles.dart';
import 'notification_screen.dart';

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
  final _electricityController = TextEditingController(); // normal
  final _electricityPeakController = TextEditingController(); // TOU peak
  final _electricityOffPeakController = TextEditingController(); // TOU off-peak
  final _waterController = TextEditingController();



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
  double _forecastElectricityUnits = 0;
  double _forecastWaterUnits = 0;

  // ----- ยอดเดือนก่อน (ใช้เทียบ "พุ่งขึ้น") -----
  double _lastMonthElectricityCost = 0;
  double _lastMonthWaterCost = 0;

  bool _isLoading = true;
  bool _isSavingElectricity = false;
  bool _isSavingWater = false;
  String _electricityError = '';
  String _waterError = '';
  int _unreadNotifications =
      0; // จำนวนแจ้งเตือนที่ยังไม่อ่าน (badge ที่ปุ่มกระดิ่ง)

  // การ์ด TOU: สลับโชว์ทีละช่วง (0 = On-Peak, 1 = Off-Peak) แทนที่จะโชว์
  // ทั้ง 2 ฟิลด์พร้อมกัน — ทำให้การ์ดสูงพอๆ กับการ์ดน้ำ (ฟิลด์เดียว) บนจอ
  // มือถือ ค่าที่กรอกไว้ในแต่ละช่วงยังอยู่ครบแม้จะสลับแท็บ (ผูกกับ
  // controller เดิม ไม่ได้ล้างตอนสลับ)
  int _touPeriod = 0;

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

    // อัปเดตจุดสถานะ "กรอกแล้ว" บนปุ่มสลับ On-Peak/Off-Peak แบบเรียลไทม์
    // ระหว่างพิมพ์ (ไม่งั้นพอสลับแท็บไปมาจะไม่รู้ว่าอีกช่วงกรอกไปหรือยัง)
    _electricityPeakController.addListener(_onTouFieldChanged);
    _electricityOffPeakController.addListener(_onTouFieldChanged);

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

  void _onTouFieldChanged() {
    if (mounted) setState(() {});
  }

  void _onDataChangedElsewhere() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_onDataChangedElsewhere);
    _electricityPeakController.removeListener(_onTouFieldChanged);
    _electricityOffPeakController.removeListener(_onTouFieldChanged);
    _electricityController.dispose();
    _electricityPeakController.dispose();
    _electricityOffPeakController.dispose();
    _waterController.dispose();
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

      // (Instant) เตือนล่วงหน้าถ้าพยากรณ์สิ้นเดือนจะสูงกว่าเดือนก่อน
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
  // คำนวณยอดใช้งาน/ค่าใช้จ่ายเดือนนี้ + พยากรณ์สิ้นเดือน (แยกไฟฟ้า/น้ำ)
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

    final dailyElectricity = _electricityLogs
        .map((l) => l.usedFromLast)
        .where((v) => v > 0)
        .toList();
    final dailyWater =
        _waterLogs.map((l) => l.usedFromLast).where((v) => v > 0).toList();

    // ----- ค่าเฉลี่ย "บาท/วัน" จริง (แก้จุดที่หน่วยไม่ตรงกัน) -----
    // เดิม: เอา dailyUsage (หน่วย/วัน) ไปบวกกับ currentTotal (บาท) ตรง ๆ
    // ผ่าน EnergyForecaster.forecastCurrentMonth ทำให้ยอดพยากรณ์ค่าใช้จ่าย
    // ไม่ใช่ "บาท" จริง แค่บังเอิญดูสมเหตุสมผลเพราะ ratio หน่วย/บาทใกล้ 1
    // แก้โดยคำนวณผลต่างของ cost สะสม (field `cost` ใน log เป็นค่าสะสมจาก
    // ต้นรอบเหมือน usedFromStart) ระหว่างแต่ละครั้งที่บันทึก ให้ได้ "บาทที่
    // เพิ่มขึ้นต่อช่วง" จริง ๆ แล้วค่อยป้อนเข้า movingAverage
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

    // forecaster.dart ไม่มีฟังก์ชันพยากรณ์ "หน่วยการใช้" ให้ตรง ๆ
    // จึงเรียก movingAverage แบบเดียวกัน แต่ใส่ฐานเป็นหน่วยที่ใช้ไปแล้ว
    // (แทนที่จะเป็นค่าใช้จ่าย) เพื่อพยากรณ์จำนวนหน่วยสิ้นเดือน
    _forecastElectricityUnits = EnergyForecaster.movingAverage(
      dailyUsage: dailyElectricity,
      remainingDays: remainingDays,
      currentTotal: _currentElectricityFromStart,
    );
    _forecastWaterUnits = EnergyForecaster.movingAverage(
      dailyUsage: dailyWater,
      remainingDays: remainingDays,
      currentTotal: _currentWaterFromStart,
    );
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

  // บันทึกค่ามิเตอร์ไฟฟ้า
  Future<void> _saveElectricityLog() async {
    final isTOU = _user?.meterType == 'tou';

    // ค่าต้นรอบ/ล่าสุดของ TOU เตรียมไว้ใช้ทั้งตอน validate และตอนเติมให้
    // อัตโนมัติเวลาผู้ใช้กรอกแค่ช่องเดียว (คำนวณล่วงหน้าตรงนี้เพราะต้องใช้
    // ทั้งก่อนและหลัง setState _isSavingElectricity)
    final startPeak = _user?.startPeakValue ?? 0;
    final startOffPeak = _user?.startOffPeakValue ?? 0;
    final lastPeak = _latestElectricityLog?.peakMeterValue ?? startPeak;
    final lastOffPeak =
        _latestElectricityLog?.offPeakMeterValue ?? startOffPeak;

    if (isTOU) {
      final peakEmpty = _electricityPeakController.text.trim().isEmpty;
      final offPeakEmpty = _electricityOffPeakController.text.trim().isEmpty;
      // เดิมบังคับกรอกครบทั้ง Peak และ Off-Peak — เปลี่ยนให้กรอกแค่ช่อง
      // เดียวก็คำนวณได้เลย เหมือนแบบฟอร์มประมาณการของเว็บ กฟภ/กฟน (ช่องที่
      // เว้นว่างไว้ = ช่วงนั้นไม่ได้ใช้เพิ่ม จะใช้ค่าล่าสุดเดิมแทน)
      if (peakEmpty && offPeakEmpty) {
        setState(() => _electricityError =
            'กรุณากรอกหน่วย Peak หรือ Off-Peak อย่างน้อย 1 ช่องค่ะ');
        return;
      }
    } else {
      if (_electricityController.text.isEmpty) {
        setState(() => _electricityError = 'กรุณากรอกค่ามิเตอร์ไฟฟ้าก่อนค่ะ');
        return;
      }
    }

    double peakValue = 0;
    double offPeakValue = 0;
    double normalValue = 0;

    try {
      if (isTOU) {
        // ช่องไหนเว้นว่างไว้ -> ใช้ค่าล่าสุดเดิม (เท่ากับหน่วยที่ใช้เพิ่ม
        // ในช่วงนั้น = 0)
        peakValue = _electricityPeakController.text.trim().isEmpty
            ? lastPeak
            : double.parse(_electricityPeakController.text);
        offPeakValue = _electricityOffPeakController.text.trim().isEmpty
            ? lastOffPeak
            : double.parse(_electricityOffPeakController.text);
      } else {
        normalValue = double.parse(_electricityController.text);
      }
    } catch (e) {
      setState(() => _electricityError = 'กรุณากรอกเป็นตัวเลขเท่านั้นค่ะ');
      return;
    }

    setState(() {
      _electricityError = '';
      _isSavingElectricity = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      double usedFromStart;
      double usedFromLast;
      double cost;
      double peakUnits = 0;
      double offPeakUnits = 0;

      if (isTOU) {
        if (peakValue < startPeak || offPeakValue < startOffPeak) {
          setState(
              () => _electricityError = 'ค่ามิเตอร์ต้องไม่น้อยกว่าหน่วยต้นรอบค่ะ');
          setState(() => _isSavingElectricity = false);
          return;
        }
        if (peakValue < lastPeak || offPeakValue < lastOffPeak) {
          setState(
              () => _electricityError = 'ค่ามิเตอร์ต้องไม่น้อยกว่าครั้งล่าสุดค่ะ');
          setState(() => _isSavingElectricity = false);
          return;
        }

        peakUnits = EnergyCalculator.calculateUsed(peakValue, startPeak);
        offPeakUnits =
            EnergyCalculator.calculateUsed(offPeakValue, startOffPeak);
        usedFromStart = peakUnits + offPeakUnits;
        usedFromLast = EnergyCalculator.calculateUsed(peakValue, lastPeak) +
            EnergyCalculator.calculateUsed(offPeakValue, lastOffPeak);

        cost = await EnergyCalculator.calculateElectricityByType(
          units: 0,
          meterType: 'tou',
          area: _user?.area ?? 'bangkok',
          peakUnits: peakUnits,
          offPeakUnits: offPeakUnits,
        );
      } else {
        final startE = _user?.startElectricityValue ?? 0;
        final lastE = _latestElectricityLog?.meterValue ?? startE;

        if (normalValue < startE) {
          setState(
              () => _electricityError = 'ค่ามิเตอร์ต้องไม่น้อยกว่าหน่วยต้นรอบ ($startE) ค่ะ');
          setState(() => _isSavingElectricity = false);
          return;
        }
        if (normalValue < lastE) {
          setState(
              () => _electricityError = 'ค่ามิเตอร์ต้องไม่น้อยกว่าครั้งล่าสุด ($lastE) ค่ะ');
          setState(() => _isSavingElectricity = false);
          return;
        }

        usedFromStart = EnergyCalculator.calculateUsed(normalValue, startE);
        usedFromLast = EnergyCalculator.calculateUsed(normalValue, lastE);

        cost = await EnergyCalculator.calculateElectricityByType(
          units: usedFromStart,
          meterType: 'normal',
          area: _user?.area ?? 'bangkok',
        );
      }

      final log = ElectricityLogModel(
        id: const Uuid().v4(),
        uid: uid,
        date: DateTime.now(),
        meterValue: isTOU ? usedFromStart : normalValue,
        peakMeterValue: isTOU ? peakValue : null,
        offPeakMeterValue: isTOU ? offPeakValue : null,
        usedFromStart: usedFromStart,
        usedFromLast: usedFromLast,
        cost: cost,
      );

      await _firestoreService.saveElectricityLog(log);
      _electricityController.clear();
      _electricityPeakController.clear();
      _electricityOffPeakController.clear();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกค่ามิเตอร์ไฟฟ้าเรียบร้อยแล้วค่ะ'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _electricityError = 'เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isSavingElectricity = false);
    }
  }

  // บันทึกค่ามิเตอร์น้ำ
  Future<void> _saveWaterLog() async {
    if (_waterController.text.isEmpty) {
      setState(() => _waterError = 'กรุณากรอกค่ามิเตอร์น้ำก่อนค่ะ');
      return;
    }

    double value;
    try {
      value = double.parse(_waterController.text);
    } catch (e) {
      setState(() => _waterError = 'กรุณากรอกเป็นตัวเลขเท่านั้นค่ะ');
      return;
    }

    final startW = _user?.startWaterValue ?? 0;
    final lastW = _latestWaterLog?.meterValue ?? startW;

    if (value < startW) {
      setState(() => _waterError = 'ต้องไม่น้อยกว่าหน่วยต้นรอบ ($startW) ค่ะ');
      return;
    }
    if (value < lastW) {
      setState(() => _waterError = 'ต้องไม่น้อยกว่าครั้งล่าสุด ($lastW) ค่ะ');
      return;
    }

    setState(() {
      _waterError = '';
      _isSavingWater = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final usedFromStart = EnergyCalculator.calculateUsed(value, startW);
      final usedFromLast = EnergyCalculator.calculateUsed(value, lastW);

      final cost = EnergyCalculator.calculateWater(
        usedFromStart,
        _user?.area ?? 'bangkok',
      );

      final log = WaterLogModel(
        id: const Uuid().v4(),
        uid: uid,
        date: DateTime.now(),
        meterValue: value,
        usedFromStart: usedFromStart,
        usedFromLast: usedFromLast,
        cost: cost,
      );

      await _firestoreService.saveWaterLog(log);
      _waterController.clear();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกค่ามิเตอร์น้ำเรียบร้อยแล้วค่ะ'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() => _waterError = 'เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isSavingWater = false);
    }
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
    final buddhistYear = now.year + 543;

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
                      // (3) การ์ดค่าใช้จ่ายเดือนนี้
                      // เพิ่ม: สัญลักษณ์พุ่งขึ้น + บรรทัดยอดคาดการณ์แยกไฟฟ้า/น้ำ
                      // -------------------------------------------------
                      _buildCostSummaryCard(formatter),

                      const SizedBox(height: 20),

                      // -------------------------------------------------
                      // บันทึกมิเตอร์วันนี้ (เดิม แก้แค่สี hint/last ให้จางลง)
                      // -------------------------------------------------
                      const Text('บันทึกมิเตอร์วันนี้',
                          style: DashboardStyles.sectionTitle),
                      const SizedBox(height: 10),

                      // การ์ดไฟฟ้ากับน้ำอยู่คู่กันแบบ Row ซ้าย-ขวา (กลับมา
                      // ใช้เลย์เอาต์นี้ตามที่ขอ เพราะแบบซ้อน Column เต็ม
                      // ความกว้างเมื่อก่อนดูใหญ่คับจอไป) ใช้ IntrinsicHeight
                      // ให้การ์ด TOU (2 ฟิลด์) กับการ์ดน้ำ (1 ฟิลด์) สูงเท่ากัน
                      _user?.startMeterConfigured == false
                          ? _buildStartMeterRequiredCard()
                          : IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _user?.meterType == 'tou'
                                        ? _buildTOUMeterCard()
                                        : _buildMeterCard(
                                            title: 'ไฟฟ้า',
                                            icon: Icons.bolt,
                                            accent:
                                                DashboardStyles.electricityAccent,
                                            borderColor: DashboardStyles
                                                .electricityBorder,
                                            fieldBg: DashboardStyles
                                                .electricityFieldBg,
                                            controller: _electricityController,
                                            hint: 'เช่น 00000',
                                            lastValue: _latestElectricityLog
                                                    ?.meterValue ??
                                                _user?.startElectricityValue,
                                            startValue:
                                                _user?.startElectricityValue,
                                            error: _electricityError,
                                            isSaving: _isSavingElectricity,
                                            onSave: _saveElectricityLog,
                                            unit: 'หน่วย',
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildMeterCard(
                                      title: 'น้ำ',
                                      icon: Icons.water_drop,
                                      accent: DashboardStyles.waterAccent,
                                      borderColor: DashboardStyles.waterBorder,
                                      fieldBg: DashboardStyles.waterFieldBg,
                                      controller: _waterController,
                                      hint: 'เช่น 00000',
                                      lastValue: _latestWaterLog?.meterValue ??
                                          _user?.startWaterValue,
                                      startValue: _user?.startWaterValue,
                                      error: _waterError,
                                      isSaving: _isSavingWater,
                                      onSave: _saveWaterLog,
                                      unit: 'ลบ.ม.',
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

                      // ยอดรวม (เดิม)
                      _buildSummaryCard(formatter, buddhistYear),
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
          backgroundColor: DashboardStyles.primaryGreen.withOpacity(0.12),
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DashboardStyles.primaryGreen.withOpacity(0.08),
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
          ),
        ),
        const SizedBox(width: 8),
        // -------------------------------------------------------------
        // (2) ปุ่ม notification -> เปิดหน้า Notification Center จริง
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
  // (3) การ์ดค่าใช้จ่ายเดือนนี้
  // พาร์ทนี้ทำหน้าที่: สรุปยอดไฟฟ้า/น้ำของเดือนนี้แบบเทียบกัน พร้อม
  // สัญลักษณ์ "พุ่งขึ้น" ถ้าค่าใช้จ่ายปัจจุบันสูงกว่าเดือนก่อน
  // (ยอดคาดการณ์สิ้นเดือนย้ายไปแสดงที่หน้าวิเคราะห์แทน เพื่อไม่ให้การ์ดนี้แน่นเกินไป)
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
            color: DashboardStyles.primaryGreen.withOpacity(0.25),
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
                  color: Colors.white.withOpacity(0.85), size: 16),
              const SizedBox(width: 6),
              const Text('ค่าใช้จ่ายเดือนนี้',
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
                  isUp: _currentElectricityCost > _lastMonthElectricityCost &&
                      _lastMonthElectricityCost > 0,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildCostCard(
                  icon: Icons.water_drop,
                  label: 'ค่าน้ำ',
                  amount: '${formatter.format(_currentWaterCost)} บาท',
                  sub: '${_currentWaterFromStart.toStringAsFixed(1)} ลบ.ม.',
                  isUp: _currentWaterCost > _lastMonthWaterCost &&
                      _lastMonthWaterCost > 0,
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
              color: Colors.white.withOpacity(0.15),
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
  // ดีไซน์ช่องกรอกมิเตอร์ที่ใช้ร่วมกันทั้งฟิลด์ปกติและฟิลด์ TOU
  // ของเดิมเป็นกล่องสีพื้นเรียบๆไม่มีกรอบเลย ไม่มีสถานะ focus ให้เห็น
  // ของใหม่: มีกรอบบางๆตอนปกติ เด่นขึ้นตอน focus ด้วยสีของแต่ละมิเตอร์
  // และตัวเลขหน่วยท้ายช่องดูเป็น label มากกว่า placeholder ลอยๆ
  // =====================================================================
  InputDecoration _meterFieldDecoration({
    required String hint,
    required String unit,
    required Color accent,
    required Color fieldBg,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: DashboardStyles.hintStyle,
      suffixText: unit,
      suffixStyle: TextStyle(
        color: accent,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
      isDense: true,
      filled: true,
      fillColor: fieldBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    );
  }

  // =====================================================================
  // การ์ดเตือนให้ตั้งค่ามิเตอร์ต้นรอบก่อน — แสดงแทนช่องกรอกมิเตอร์ปกติ
  // เฉพาะบัญชีที่กด "ข้ามไปก่อน" ตอน setup (startMeterConfigured == false)
  // เพราะถ้าปล่อยให้กรอกเลย ระบบจะเอาเลขมิเตอร์สะสมจริงทั้งก้อน (เช่น
  // 15,234 หน่วย) ไปคำนวณเป็น "หน่วยที่ใช้เดือนนี้" ทันที ทำให้ค่าไฟ/น้ำ
  // รอบแรกเพี้ยนมหาศาล และไปกระทบข้อมูลพยากรณ์ในหน้าวิเคราะห์ด้วย
  // =====================================================================
  Widget _buildStartMeterRequiredCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.speed_outlined,
                    color: Colors.orange.shade800, size: 20),
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
          const Text(
            'ตอนสมัครคุณข้ามขั้นตอนนี้ไว้ ต้องตั้งค่ามิเตอร์ต้นรอบก่อน '
            'ระบบถึงจะคำนวณหน่วยที่ใช้และค่าไฟ/ค่าน้ำได้ถูกต้อง',
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
  // การ์ดบันทึกมิเตอร์ (ไฟฟ้า/น้ำ)
  // พาร์ทนี้ทำหน้าที่: ให้ผู้ใช้กรอกเลขมิเตอร์วันนี้ พร้อมโชว์ค่าล่าสุด/ต้นรอบ
  // เป็น "ตัวอย่าง" จาง ๆ ไว้เทียบ (แก้สีให้จางลงตามที่ขอ ผ่าน DashboardStyles)
  // =====================================================================
  Widget _buildMeterCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Color fieldBg,
    required TextEditingController controller,
    required String hint,
    required String error,
    required bool isSaving,
    required VoidCallback onSave,
    required String unit,
    double? lastValue,
    double? startValue,
    Color? borderColor,
  }) {
    final formatter = NumberFormat('#,##0.##');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: DashboardStyles.accentCard(borderColor ?? accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ล่าสุด/ต้นรอบ กลับไปแยกคนละบรรทัดแบบเดิม (บรรทัดเดียวทำให้
          // ล้นช่องแคบเวลาวางการ์ดคู่กันแบบ Row)
          if (lastValue != null)
            Text('ล่าสุด: ${formatter.format(lastValue)} $unit',
                style: DashboardStyles.lastValueStyle),
          if (startValue != null)
            Text('ต้นรอบ: ${formatter.format(startValue)} $unit',
                style: DashboardStyles.lastValueStyle),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DashboardStyles.textDark,
            ),
            decoration: _meterFieldDecoration(
              hint: hint,
              unit: unit,
              accent: accent,
              fieldBg: fieldBg,
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error,
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.menu, size: 16),
              label:
                  const Text('บันทึกมิเตอร์', style: TextStyle(fontSize: 13)),
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
                'Fixed Cost ประจำเดือน',
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
  // การ์ดยอดรวม — พื้นขาว กรอบครีม (เดิม)
  // -------------------------------------------------------------------
  Widget _buildSummaryCard(NumberFormat formatter, int buddhistYear) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DashboardStyles.creamBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                  'ยอดรวมค่าใช้จ่ายเดือน${thaiMonths[DateTime.now().month - 1]} $buddhistYear',
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
          // (เลขที่คำนวณเหมือนเดิมทุกอย่าง แค่ดีไซน์ให้เด่นขึ้น)
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
  // การ์ดยอดไฟฟ้า/น้ำ ในการ์ดสรุปเขียว
  // พาร์ทนี้ทำหน้าที่: แสดงยอดปัจจุบัน + ไอคอน "พุ่งขึ้น" ถ้าสูงกว่าเดือนก่อน
  // และบรรทัดยอดคาดการณ์สิ้นเดือนของรายการนั้น ๆ (ไฟฟ้า หรือ น้ำ) ต่อท้าย
  // =====================================================================
  Widget _buildCostCard({
    required IconData icon,
    required String label,
    required String amount,
    required String sub,
    required bool isUp,
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
        Row(
          children: [
            Text(amount,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            if (isUp) ...[
              const SizedBox(width: 6),
              // สัญลักษณ์พุ่งขึ้น: แสดงเฉพาะตอนค่าใช้จ่ายปัจจุบันสูงกว่าเดือนก่อน
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward, size: 11, color: Colors.white),
                    SizedBox(width: 2),
                    Text('พุ่งขึ้น',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  // อธิบายมิเตอร์ TOU ตอนกำลังจะกรอกค่าจริง — เนื้อหาคล้ายตอน setup แต่เน้น
  // ว่าช่องไหนคือช่องไหน เผื่อผู้ใช้ลืมความหมายไปแล้วตั้งแต่ตอนสมัคร
  void _showTOUInfoPopup() {
    showInfoDialog(
      context,
      title: 'On-Peak / Off-Peak คืออะไร?',
      iconColor: DashboardStyles.primaryGreen,
      message: 'มิเตอร์ TOU แยกคิดค่าไฟตามช่วงเวลาที่ใช้ แทนที่จะคิดรวมทั้งเดือน '
          'เหมือนมิเตอร์ปกติ:\n\n'
          '• On-Peak (T1) — จ-ศ 09:00-22:00: ช่วงเวลาที่ความต้องการใช้ไฟฟ้า '
          'ของประเทศสูง อัตราต่อหน่วยจะแพงกว่า\n\n'
          '• Off-Peak (T2) — จ-ศ 22:00-09:00 และวันหยุด/นักขัตฤกษ์ทั้งวัน: '
          'ช่วงที่ความต้องการใช้ไฟต่ำ อัตราต่อหน่วยจะถูกกว่า\n\n'
          'กรอกเลขที่อ่านได้จากมิเตอร์จริงของแต่ละช่วง หากมิเตอร์ '
          'TOU มีจอแสดงแยก 2 ค่า มักดูได้จากรหัส T1/T2 บนจอ '
          '(บางรุ่นแสดงเป็นรหัสตัวเลขแทน เช่น 11/12 แล้วแต่ยี่ห้อมิเตอร์) '
          'กรอกตามค่านั้นได้ทันที หากมีจอแสดง "ยอดรวม" แยกต่างหากด้วย '
          'ค่านั้นเป็นผลบวกของ T1+T2 สำหรับดูภาพรวมเท่านั้น ไม่ต้องนำมากรอกในแอป\n\n'
          'ระดับแรงดันไฟฟ้า: อัตรา TOU แบ่งราคาตามระดับแรงดัน '
          'ที่มิเตอร์ต่อเข้าระบบด้วย (เช่น ต่ำกว่า 22 กิโลโวลต์, 22-33 '
          'กิโลโวลต์ ฯลฯ) แต่บ้านพักอาศัยทั่วไปแทบทั้งหมดต่อที่แรงดัน '
          'ต่ำกว่า 22 กิโลโวลต์ แอปจึงใช้อัตราของระดับนี้คำนวณให้'
          'โดยอัตโนมัติ',
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

  Widget _buildTOUMeterCard() {
    final formatter = NumberFormat('#,##0.##');
    final lastPeak =
        _latestElectricityLog?.peakMeterValue ?? _user?.startPeakValue;
    final startPeak = _user?.startPeakValue;
    final lastOffPeak =
        _latestElectricityLog?.offPeakMeterValue ?? _user?.startOffPeakValue;
    final startOffPeak = _user?.startOffPeakValue;

    final peakFilled = _electricityPeakController.text.trim().isNotEmpty;
    final offPeakFilled =
        _electricityOffPeakController.text.trim().isNotEmpty;
    final isPeakTab = _touPeriod == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: DashboardStyles.accentCard(DashboardStyles.electricityBorder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: Colors.orange, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ไฟฟ้า (TOU)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _showTOUInfoPopup,
                child: Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ปุ่มสลับ On-Peak / Off-Peak — โชว์ทีละช่วงแทนที่จะยัดทั้ง 2
          // ฟิลด์พร้อมกัน ทำให้การ์ดสูงพอๆ กับการ์ดน้ำ (ฟิลด์เดียว) บนจอ
          // มือถือ จุดเขียวข้างชื่อช่วง = กรอกไว้แล้ว กันลืมว่าเหลืออีก
          // ช่วงที่ยังไม่ได้กรอก
          Row(
            children: [
              Expanded(
                child: _buildTouTabButton(
                  label: 'On-Peak (T1)',
                  selected: isPeakTab,
                  filled: peakFilled,
                  onTap: () => setState(() => _touPeriod = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTouTabButton(
                  label: 'Off-Peak (T2)',
                  selected: !isPeakTab,
                  filled: offPeakFilled,
                  onTap: () => setState(() => _touPeriod = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // เนื้อหาของช่วงที่เลือกอยู่ — ล่าสุด/ต้นรอบ + ช่องกรอก ของช่วง
          // นั้นเท่านั้น (ค่าที่กรอกไว้ในอีกช่วงยังอยู่ครบ ไม่หายตอนสลับ
          // เพราะผูกกับ controller เดิม)
          if (isPeakTab) ...[
            if (lastPeak != null)
              Text('ล่าสุด: ${formatter.format(lastPeak)} หน่วย',
                  style: DashboardStyles.lastValueStyle),
            if (startPeak != null)
              Text('ต้นรอบ: ${formatter.format(startPeak)} หน่วย',
                  style: DashboardStyles.lastValueStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _electricityPeakController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DashboardStyles.textDark,
              ),
              decoration: _meterFieldDecoration(
                hint: 'เช่น 100',
                unit: 'หน่วย',
                accent: Colors.orange,
                fieldBg: DashboardStyles.electricityFieldBg,
              ),
            ),
          ] else ...[
            if (lastOffPeak != null)
              Text('ล่าสุด: ${formatter.format(lastOffPeak)} หน่วย',
                  style: DashboardStyles.lastValueStyle),
            if (startOffPeak != null)
              Text('ต้นรอบ: ${formatter.format(startOffPeak)} หน่วย',
                  style: DashboardStyles.lastValueStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _electricityOffPeakController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DashboardStyles.textDark,
              ),
              decoration: _meterFieldDecoration(
                hint: 'เช่น 200',
                unit: 'หน่วย',
                accent: Colors.deepOrange,
                fieldBg: DashboardStyles.electricityFieldBg,
              ),
            ),
          ],

          if (_electricityError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_electricityError,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingElectricity ? null : _saveElectricityLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _isSavingElectricity
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.menu, size: 18),
              label: const Text('บันทึกมิเตอร์'),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // ปุ่มแท็บสลับ On-Peak/Off-Peak ในการ์ด TOU — โชว์จุดเขียวเล็กๆ ถ้าช่วง
  // นั้นกรอกเลขไว้แล้ว กันลืมว่าเหลืออีกช่วงที่ยังไม่ได้กรอกก่อนกดบันทึก
  // =====================================================================
  Widget _buildTouTabButton({
    required String label,
    required bool selected,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.orange : Colors.grey.shade300,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.orange.shade800
                      : Colors.grey.shade600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (filled) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle,
                  size: 13, color: Colors.green.shade600),
            ],
          ],
        ),
      ),
    );
  }
}