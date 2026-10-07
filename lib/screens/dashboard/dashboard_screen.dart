import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/forecaster.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/onboarding_guide.dart';
import '../../widgets/quick_cost_sheet.dart';
import '../../widgets/ui/fade_slide_in.dart';
import '../settings/settings_screen.dart';
import 'dashboard_loader.dart';
import 'dashboard_styles.dart';
import 'notification_screen.dart';
import 'record_meter_screen.dart';
import 'widgets/bill_hero_card.dart';
import 'widgets/daily_usage_card.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/fixed_cost_tile.dart';
import 'widgets/load_error_view.dart';
import 'widgets/meter_cards.dart';
import 'widgets/setup_checklist_card.dart';
import 'widgets/starter_visuals.dart';

// =====================================================================
// หน้าหลัก — จัดวางการ์ดและพาไปหน้าอื่นเท่านั้น ข้อมูลและงานเบื้องหลังทั้งหมด
// อยู่ที่ DashboardLoader (dashboard_loader.dart) การ์ดแต่ละใบอยู่ใน widgets/
// =====================================================================
class DashboardScreen extends StatefulWidget {
  // true เฉพาะตอนเพิ่ง setup เสร็จหมาดๆ (MainShell ส่งต่อมาจาก setup_screen) ใช้
  // กันไม่ให้แจ้งเตือนหลายๆ อย่างยิง popup รัวพร้อมกันตั้งแต่เปิดแอปครั้งแรก
  // (ยังเห็นแค่ welcome พอ ที่เหลือถ้ามีจะถูกบันทึกเงียบๆ ไว้ในหน้าแจ้งเตือนแทน
  // ไปดูเองได้)
  final bool justCompletedSetup;

  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  // เป็น null ได้ถ้าหน้านี้ถูก push ตรงๆ แยกจาก MainShell (เช่นดีบัก/เทส)
  final ValueChanged<int>? onNavTap;

  // ส่งเข้ามาได้เพื่อเทส (FakeFirebaseFirestore/MockFirebaseAuth) ไม่ส่ง = ของจริง
  final DashboardLoader? loader;
  final FirebaseAuth? auth;

  const DashboardScreen({
    super.key,
    this.justCompletedSetup = false,
    this.onNavTap,
    this.loader,
    this.auth,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardLoader _loader = widget.loader ?? DashboardLoader();
  FirestoreService get _firestoreService => _loader.firestoreService;

  DashboardData? _data;
  bool _isLoading = true;
  // true = โหลดข้อมูลไม่สำเร็จ (ออฟไลน์/Firestore error) → โชว์หน้า "ลองใหม่"
  bool _loadFailed = false;
  int _unreadNotifications = 0; // badge ที่ปุ่มกระดิ่ง

  // เช็คแค่ "ครั้งแรก" ที่ _loadData() รัน (ไม่ใช่ทุกครั้งที่ pull-to-refresh)
  // ใช้คู่กับ widget.justCompletedSetup เพื่อทำให้แจ้งเตือนเงียบแค่รอบเดียว
  bool _isFirstLoad = true;

  // กันโหลดซ้อนกัน — ดู _loadData/_runBackgroundTasks
  bool _loadInFlight = false;
  bool _reloadPending = false;
  bool _backgroundInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadData();

    // แท็บนี้ถูกเก็บไว้ใน IndexedStack ของ MainShell ตลอด ไม่มี route
    // pop/push ให้ RouteAware ทำงานตอนสลับแท็บ เลยต้องฟัง DataRefreshBus
    // แทน — พอมีการแก้/ลบข้อมูลจากแท็บอื่น (เช่น ลบ log ที่หน้าตั้งค่า)
    // หน้านี้จะโหลดข้อมูลใหม่ให้เองโดยไม่ต้องรอผู้ใช้ pull-to-refresh
    DataRefreshBus.instance.version.addListener(_onDataChangedElsewhere);
  }

  void _onDataChangedElsewhere() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_onDataChangedElsewhere);
    super.dispose();
  }

  // =====================================================================
  // โหลดข้อมูลที่หน้าจอต้องใช้ แล้วแสดงผลทันที — งานที่ไม่จำเป็นต่อการแสดงผล
  // (ปิดบิลรอบที่จบ, ไล่รอบที่ขาด, แจ้งเตือน) ทำต่อเบื้องหลังหลังหน้าจอแสดงแล้ว
  //
  // ถ้ามีคำขอโหลดใหม่เข้ามาระหว่างที่กำลังโหลด (เช่น ปิดบิลแล้ว DataRefreshBus
  // แจ้งกลับมา) จะโหลดซ้ำอีกรอบหลังรอบนี้จบ ไม่โหลดซ้อนกัน
  // =====================================================================
  bool _onboardingChecked = false;

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
    DashboardData? loaded;
    try {
      final uid = (widget.auth ?? FirebaseAuth.instance).currentUser!.uid;
      loaded = await _loader.load(uid);
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      _isFirstLoad = false;
      _loadInFlight = false;
      if (mounted) {
        setState(() {
          if (loaded != null) _data = loaded;
          _loadFailed = loaded == null;
          _isLoading = false;
        });
      }
    }

    if (!mounted) return;
    if (_reloadPending) {
      _reloadPending = false;
      _loadData();
      return;
    }
    if (loaded != null) {
      // คู่มือเริ่มต้นใช้งาน (เฉพาะครั้งแรกที่เข้า Dashboard) — เปิดหลังโหลดสำเร็จรอบแรก
      // เพราะต้องรู้พื้นที่/ประเภทมิเตอร์เพื่อบอกรหัสประเภทอัตราค่าไฟ
      // (notifyWelcome() ยิงที่ setup_screen.dart ซึ่งรันครั้งเดียวตอนบัญชีใหม่ทำ setup เสร็จ)
      if (!_onboardingChecked) {
        _onboardingChecked = true;
        OnboardingGuide.showIfFirstTime(context, area: loaded.user?.area, meterType: loaded.user?.meterType);
      }
      _runBackgroundTasks(loaded, silent: silentThisLoad);
    }
  }

  // งานเบื้องหลังหลังหน้าจอแสดงแล้ว (ดู DashboardLoader.runBackgroundTasks)
  // หน้าจอรับผลมาอัปเดต badge แจ้งเตือน และแสดง popup คำแนะนำประเภทอัตราใหม่
  Future<void> _runBackgroundTasks(DashboardData data,
      {required bool silent}) async {
    if (_backgroundInFlight) return;
    _backgroundInFlight = true;
    try {
      final result = await _loader.runBackgroundTasks(data, silent: silent);
      if (!mounted) return;
      if (result.unreadNotifications != null) {
        setState(() => _unreadNotifications = result.unreadNotifications!);
      }
      // คำแนะนำใหม่ → popup พร้อมปุ่มไปปรับ (ผู้ใช้เลือกไว้ทีหลังได้)
      final hint = result.newTariffHint;
      final user = data.user;
      if (hint != null && user != null && !silent) {
        await showTariffHintPopup(
          context,
          hint: hint,
          user: user,
          firestoreService: _firestoreService,
        );
      }
    } finally {
      _backgroundInFlight = false;
    }
  }

  // เปิดหน้าอื่นแล้วโหลดใหม่ตอนกลับมา (เผื่อข้อมูลเปลี่ยน)
  Future<void> _openAndReload(Future<void> Function() open) async {
    await open();
    await _loadData();
  }

  Future<void> _openSettings(SettingsScreen screen) => _openAndReload(
      () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)));

  Future<void> _openStartMeterSetup() =>
      _openAndReload(() => openInvoiceScreen(context, _data!.user!.uid, _firestoreService));

  // กดปุ่มแจ้งเตือน -> หน้า Notification Center พอกลับมา (เผื่อมีการอ่าน/ลบ)
  // รีเฟรชจำนวนที่ยังไม่อ่านใหม่
  Future<void> _onNotificationTap() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationScreen(
          onOpenAnalysis:
              widget.onNavTap == null ? null : () => widget.onNavTap!(1),
        ),
      ),
    );
    final count = await _loader.notifications.getUnreadCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  // เปิดหน้าบันทึกมิเตอร์เต็มจอ — ส่งค่าต้นรอบ/ล่าสุดของยูทิลิตี้นั้นๆ ไปให้
  // ครบ พอปิดหน้ากลับมาแล้วมีการบันทึกสำเร็จ (result.saved) ค่อยโหลดข้อมูล
  // ใหม่ทั้งหน้า — isTou ส่งตาม meterType ของผู้ใช้เสมอ (รวมฝั่งน้ำ) เพราะ
  // หน้านั้นส่งต่อให้หน้าตั้งเลขมิเตอร์ต้นรอบ ซึ่งต้องรู้ว่าไฟฟ้าเป็น TOU ไหม
  Future<void> _openRecordMeter(MeterKind kind) async {
    final data = _data!;
    final user = data.user!;
    final isElectricity = kind == MeterKind.electricity;
    final eLog = data.cycleLatestElectricityLog;
    final wLog = data.cycleLatestWaterLog;
    final result = await Navigator.push<RecordMeterResult>(
      context,
      MaterialPageRoute(
        builder: (context) => RecordMeterScreen(
          kind: kind,
          isTou: data.isTou,
          uid: user.uid,
          firestoreService: _firestoreService,
          area: user.area,
          tariff: user.electricityTariff,
          startValue:
              isElectricity ? user.startElectricityValue : user.startWaterValue,
          lastValue: isElectricity
              ? (eLog?.meterValue ?? user.startElectricityValue)
              : (wLog?.meterValue ?? user.startWaterValue),
          startPeak: user.startPeakValue,
          lastPeak: eLog?.peakMeterValue ?? user.startPeakValue,
          startOffPeak: user.startOffPeakValue,
          lastOffPeak: eLog?.offPeakMeterValue ?? user.startOffPeakValue,
          recentLogs: data.historyFor(kind),
        ),
      ),
    );
    if (result?.saved ?? false) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      body: Container(
        decoration: DashboardStyles.pageHighlight(),
        // วงหมุนเต็มจอเฉพาะโหลดครั้งแรก — โหลดซ้ำ (pull-to-refresh, ข้อมูล
        // เปลี่ยนจากหน้าอื่น, ปิดบิลเบื้องหลังเสร็จ) แสดงข้อมูลเดิมไว้จนตัวเลข
        // ใหม่มา ไม่กะพริบเป็นหน้าว่าง
        child: _isLoading && data == null
            ? const Center(
                child: CircularProgressIndicator(
                    color: DashboardStyles.primaryGreen))
            : (_loadFailed || data == null)
                ? DashboardLoadErrorView(onRetry: _loadData)
                : SafeArea(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: DashboardStyles.primaryGreen,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.v16),
                        child: _buildContent(data),
                      ),
                    ),
                  ),
      ),
      // ผ่าน MainShell บาร์ล่างอยู่ที่ shell ตัวเดียว (แคปซูลเลื่อนระหว่างแท็บได้)
      bottomNavigationBar: widget.onNavTap == null ? const AppBottomNavBar(currentIndex: 0) : null,
    );
  }

  Widget _buildContent(DashboardData data) {
    final user = data.user;
    final now = DateTime.now();
    final billingDay = user?.billingDay ?? 30;

    // ส่วนต่างๆ ค่อยๆ เข้าจอทีละส่วนตอนเปิดหน้าครั้งแรก (โหลดซ้ำไม่เล่นใหม่)
    Widget stagger(int order, Widget child) => FadeSlideIn(
        delay: Duration(milliseconds: 70 * order), child: child);

    final showChecklist = user?.startMeterConfigured == false;
    // การ์ดเขียวยังไม่มียอดให้แสดง: ผู้ใช้ใหม่ หรือขึ้นรอบใหม่แล้วการ์ดมิเตอร์ล็อกทั้งสองฝั่ง
    final heroPending = showChecklist
        ? HeroPending.newUser
        : (!data.electricityMeterReady && !data.waterMeterReady ? HeroPending.newCycle : HeroPending.none);
    final Widget meterSection = showChecklist
        // ยังไม่ได้ตั้งเลขต้นรอบเลยสักฝั่ง -> การ์ดเช็คลิสต์ 3 ขั้นตอน
        ? SetupChecklistCard(
            billingDayDone: user?.billingDayConfigured ?? false,
            onBillingDay: () => _openSettings(const SettingsScreen(
                quickAction: SettingsQuickAction.billingDay)),
            onStartMeter: _openStartMeterSetup,
            onPastBills: _openStartMeterSetup,
          )
        // การ์ดไฟฟ้า/น้ำคู่กัน: ฝั่งที่พร้อมเป็นการ์ดมิเตอร์ ฝั่งที่ยังไม่พร้อม
        // เป็นการ์ดล็อก (IntrinsicHeight ให้สองการ์ดสูงเท่ากัน)
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _electricityCard(data)),
                const SizedBox(width: 12),
                Expanded(child: _waterCard(data)),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // (1) Header: วันที่ + คำทักทาย + ปุ่มแจ้งเตือน
        stagger(
          0,
          DashboardHeader(
            user: user,
            unreadNotifications: _unreadNotifications,
            onNotificationTap: _onNotificationTap,
          ),
        ),
        const SizedBox(height: 18),

        // (2) การ์ดสรุปบิลรอบนี้: ยอดที่ใช้ไปแล้ว + ความคืบหน้าของรอบ
        stagger(
          1,
          BillHeroCard(
            data: data,
            remainingDays: EnergyForecaster.getRemainingDays(now, billingDay),
            daysElapsed: EnergyForecaster.getDaysElapsed(now, billingDay),
            cycleLengthDays:
                EnergyForecaster.getCycleLengthDays(now, billingDay),
            // คาดการณ์สิ้นรอบบิลอยู่ที่แท็บวิเคราะห์ (index 1 ของ MainShell)
            onViewForecast:
                widget.onNavTap == null ? null : () => widget.onNavTap!(1),
            pending: heroPending,
            onQuickCost: heroPending == HeroPending.none || user == null
                ? null
                : () => showQuickCostSheet(context,
                    area: user.area, meterType: user.meterType, tariff: user.electricityTariff),
          ),
        ),
        const SizedBox(height: 24),

        // (3) ไฟฟ้าและน้ำรอบนี้ (การ์ดเช็คลิสต์มีหัวข้อของตัวเองอยู่แล้ว)
        if (!showChecklist) ...[
          stagger(
            2,
            const Text('ไฟฟ้าและน้ำรอบนี้',
                style: TextStyle(
                    fontSize: AppTypography.s16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark)),
          ),
          const SizedBox(height: 10),
        ],

        // ตัวเตือนวันตัดรอบบิล — โชว์เฉพาะบัญชีที่ยังไม่เคยเลือกวันตัดรอบเอง
        // แต่ตั้งเลขมิเตอร์ต้นรอบไปแล้ว (ถ้ายังไม่ได้ตั้งเลขต้นรอบ การ์ดเช็คลิสต์
        // ด้านล่างมีขั้นนี้อยู่แล้ว)
        if (user?.billingDayConfigured == false &&
            user?.startMeterConfigured != false) ...[
          stagger(
            3,
            BillingDayReminderBanner(
              onTap: () => _openSettings(const SettingsScreen(
                  quickAction: SettingsQuickAction.billingDay)),
            ),
          ),
          const SizedBox(height: 10),
        ],

        stagger(3, meterSection),
        const SizedBox(height: 12),

        // (4) รายจ่ายประจำของรอบนี้ (แตะเพื่อไปจัดการ)
        stagger(
          4,
          FixedCostTile(
            amount: data.billFixedCost,
            onTap: () =>
                _openSettings(const SettingsScreen(openFixedCostOnStart: true)),
          ),
        ),
        const SizedBox(height: 16),

        // ผู้ใช้ใหม่: "รู้ไหม" อัตราจริงของผู้ใช้ + ลิงก์หน้าอัตรา (มีเครื่องคิดค่าไฟอยู่บนสุด)
        // ใช้ได้ทันทีโดยไม่ต้องรอข้อมูลบิล (หายไปพร้อมเช็คลิสต์)
        if (showChecklist && user != null) ...[
          stagger(
            5,
            TariffFactCard(
              area: user.area,
              meterType: user.meterType,
              tariff: user.electricityTariff,
              onRates: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RateExplanationScreen(
                      area: user.area, meterType: user.meterType, tariff: user.electricityTariff),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // (5) การใช้รายวันของรอบนี้ (ผู้ใช้ใหม่ยังไม่มีข้อมูลให้แสดง)
        if (!showChecklist) ...[
          stagger(
            5,
            DailyUsageCard(
              data: data,
              cycleDays: data.cycleEnd.difference(data.cycleStart).inDays,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _electricityCard(DashboardData data) {
    final user = data.user;
    if (!data.electricityMeterReady) {
      return MeterLockedCard(
        title: 'ไฟฟ้า',
        icon: Icons.bolt,
        accent: DashboardStyles.electricityAccent,
        borderColor: DashboardStyles.electricityBorder,
        message: (user?.electricityStartConfigured ?? true)
            ? data.staleCycleMessage
            : null,
        onSetStartMeter: _openStartMeterSetup,
      );
    }
    return MeterSummaryCard(
      kind: MeterKind.electricity,
      isTou: data.isTou,
      cost: data.currentElectricityCost,
      units: data.currentElectricityUnits,
      peakShare: data.cyclePeakShare,
      lastRecorded: data.cycleLatestElectricityLog?.date,
      onRecord: () => _openRecordMeter(MeterKind.electricity),
    );
  }

  Widget _waterCard(DashboardData data) {
    final user = data.user;
    if (!data.waterMeterReady) {
      return MeterLockedCard(
        title: 'น้ำ',
        icon: Icons.water_drop,
        accent: DashboardStyles.waterAccent,
        borderColor: DashboardStyles.waterBorder,
        message:
            (user?.waterStartConfigured ?? true) ? data.staleCycleMessage : null,
        onSetStartMeter: _openStartMeterSetup,
      );
    }
    return MeterSummaryCard(
      kind: MeterKind.water,
      cost: data.currentWaterCost,
      units: data.currentWaterUnits,
      lastRecorded: data.cycleLatestWaterLog?.date,
      onRecord: () => _openRecordMeter(MeterKind.water),
    );
  }
}
