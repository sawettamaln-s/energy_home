import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/appliance_model.dart';
import '../../models/bill_model.dart';
import '../../services/analysis_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/data_refresh_bus.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/info_dialog.dart';
import '../dashboard/dashboard_styles.dart';

class AnalysisScreen extends StatefulWidget {
  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  final ValueChanged<int>? onNavTap;

  const AnalysisScreen({super.key, this.onNavTap});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  final AnalysisService _analysisService = AnalysisService();
  final FirestoreService _firestoreService = FirestoreService();

  late TabController _tabController;
  List<BillModel> _bills = [];
  List<ApplianceModel> _appliances = [];
  Map<String, CurrentCycleForecast>? _currentCycle;
  bool _isLoading = true;
  // ใช้ตัดสินว่าแท็บไฟฟ้าควรโชว์กราฟแท่งซ้อน On-Peak/Off-Peak หรือแท่งเดียว
  // ปกติ — เฉพาะแท็บไฟฟ้าเท่านั้น แท็บน้ำไม่มี TOU จึงไม่ต้องส่งไปเลย
  bool _isTou = false;

  // เก็บ subscription ของ stream อุปกรณ์ไว้ เพื่อ cancel ตอน dispose
  // (เดิมไม่เก็บไว้เลย ทำให้ setState ถูกเรียกหลัง widget dispose ไปแล้ว
  // ถ้า user ออกจากหน้านี้ระหว่างที่ Firestore ยังส่ง snapshot ใหม่เข้ามา)
  StreamSubscription<List<ApplianceModel>>? _applianceSub;

  static const _green = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    // แท็บนี้ถูกเก็บไว้ใน IndexedStack ของ MainShell ตลอด ไม่มี route
    // pop/push ให้ RouteAware ทำงานตอนสลับแท็บ เลยต้องฟัง DataRefreshBus
    // แทน (แพทเทิร์นเดียวกับ DashboardScreen) — พอมีการแก้/ลบข้อมูลจากแท็บ
    // อื่น (เช่น ลบ log ที่หน้าตั้งค่า) หน้านี้จะโหลดข้อมูลใหม่ให้เองโดย
    // ไม่ต้องรอผู้ใช้ pull-to-refresh
    DataRefreshBus.instance.version.addListener(_onDataChangedElsewhere);
  }

  void _onDataChangedElsewhere() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_onDataChangedElsewhere);
    _applianceSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // ต้องดึง user มาก่อน เพื่อเอา billingDay ไปคำนวณขอบเขตรอบบิลปัจจุบัน
      // และเอา meterType ไปตัดสินว่าแท็บไฟฟ้าควรโชว์กราฟแยก On-Peak/Off-Peak
      // ไหม (ดู _isTou ด้านบน)
      final user = await _firestoreService.getUser(uid);
      final billingDay = user?.billingDay ?? 30;
      final isTou = user?.meterType == 'tou';

      final bills = await _analysisService.fetchBills(uid);

      final currentCycle = await _analysisService.forecastCurrentCycle(
        uid: uid,
        firestoreService: _firestoreService,
        billingDay: billingDay,
      );

      _applianceSub?.cancel();
      _applianceSub = _firestoreService.getAppliances(uid).listen((data) {
        if (mounted) setState(() => _appliances = data);
      });

      if (!mounted) return;
      setState(() {
        _bills = bills;
        _currentCycle = currentCycle;
        _isTou = isTou;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _green,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('วิเคราะห์',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'ไฟฟ้า'),
            Tab(text: 'น้ำ'),
            Tab(text: 'อุปกรณ์'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _green,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _UtilityTab(
                    bills: _bills,
                    analysisService: _analysisService,
                    selector: (b) => b.electricityCost,
                    usedSelector: (b) => b.electricityUsed,
                    unitLabel: 'หน่วย',
                    title: 'ค่าไฟฟ้า',
                    label: 'ค่าไฟ',
                    accentColor: DashboardStyles.electricityBorder,
                    // พาเลตใหม่: ใช้สีน้ำตาล-ส้ม #C98A4B เดียวกับกรอบการ์ด
                    // มิเตอร์ไฟฟ้าที่หน้า Dashboard/ปุ่มสลับมุมมองด้านบนอยู่
                    // แล้ว (เดิมเป็นแดง #D0311E ซึ่งเป็นคนละโทนกับปุ่มสลับ
                    // ที่ใช้สีน้ำตาล-ส้ม ทำให้ดูไม่เป็นชุดเดียวกัน) หน่วย
                    // ใช้เฉดทองอ่อนกว่าในตระกูลสีเดียวกัน, Off-Peak อ่อน
                    // กว่านั้นอีกขั้น ให้ไล่โทนอุ่นเดียวกันตลอดทั้งกราฟ
                    costColor: const Color(0xFFC98A4B),
                    unitColor: const Color(0xFFE8B86D),
                    touOffPeakColor: const Color(0xFFF3D9B1),
                    currentCycle: _currentCycle?['electricity'],
                    onViewAppliances: () => _tabController.animateTo(2),
                    isTou: _isTou,
                    peakUsedSelector: (b) => b.electricityPeakUsed,
                    offPeakUsedSelector: (b) => b.electricityOffPeakUsed,
                  ),
                  _UtilityTab(
                    bills: _bills,
                    analysisService: _analysisService,
                    selector: (b) => b.waterCost,
                    usedSelector: (b) => b.waterUsed,
                    unitLabel: 'ลบ.ม.',
                    title: 'ค่าน้ำ',
                    label: 'ค่าน้ำ',
                    accentColor: DashboardStyles.waterBorder,
                    // พาเลตใหม่: ใช้สีฟ้า #1E76C7 เดียวกับกรอบการ์ดมิเตอร์น้ำ/
                    // ปุ่มสลับมุมมองด้านบน (เดิมเป็นฟ้าคนละเฉด #4274D9 ทำให้
                    // ดูไม่ใช่ชุดสีเดียวกันเป๊ะๆ) หน่วยใช้น้ำเงินเข้มกว่าใน
                    // ตระกูลเดียวกันแทนโทนที่ออกม่วง
                    costColor: const Color(0xFF1E76C7),
                    unitColor: const Color(0xFF123F6D),
                    currentCycle: _currentCycle?['water'],
                    onViewAppliances: () => _tabController.animateTo(2),
                    trackAppliances: false,
                  ),
                  _ApplianceTab(
                    appliances: _appliances,
                    analysisService: _analysisService,
                  ),
                ],
              ),
            ),
      bottomNavigationBar:
          AppBottomNavBar(currentIndex: 1, onTap: widget.onNavTap),
    );
  }
}

// ==================== Tab ไฟฟ้า / น้ำ ====================
class _UtilityTab extends StatelessWidget {
  final List<BillModel> bills;
  final AnalysisService analysisService;
  final double Function(BillModel) selector; // ค่าใช้จ่าย (บาท)
  // หน่วยที่ใช้จริง (electricityUsed/waterUsed) — เพิ่มใหม่สำหรับกราฟเทรนด์
  // หน่วยที่ใช้ แยกจาก selector (ค่าใช้จ่าย) เพราะเป็นคนละมิติกัน บิลบาง
  // เดือนอาจมีค่าใช้จ่ายแต่ไม่มีหน่วย (เช่น บิลที่มาจากการตั้งเลขมิเตอร์
  // ต้นรอบครั้งแรกสุดของบัญชี ที่คำนวณ delta หน่วยที่ใช้ไม่ได้จริงๆ)
  final double Function(BillModel) usedSelector;
  final String unitLabel; // หน่วยที่ใช้ เช่น 'หน่วย'
  final String title; // หัวข้อยาว เช่น 'ค่าไฟฟ้า' ใช้ในกราฟเทรนด์
  final String label; // หัวข้อสั้น เช่น 'ค่าไฟ' ใช้ในข้อความ insight
  // สีประจำยูทิลิตี้ (ส้ม = ไฟฟ้า, ฟ้าอมเขียว = น้ำ) ใช้กับกราฟเทรนด์และ
  // ปุ่มสลับมุมมอง (ค่าใช้จ่าย/หน่วย) ให้ตรงกับโทนสีที่ dashboard ใช้อยู่
  // แล้ว (DashboardStyles.electricityBorder/waterBorder) แทนที่จะใช้สีเขียว
  // เดียวกันหมดทั้ง 2 แท็บเหมือนเดิม แยกไม่ออกว่ากำลังดูแท็บไหนอยู่จากกราฟ
  final Color accentColor;
  // พาเลตสีจริงของกราฟแท่งเทรนด์ ต่อโหมด "ค่าใช้จ่าย"/"หน่วย" — เลือกเฉด
  // เฉพาะของแต่ละยูทิลิตี้ (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน) ตรงตาม swatch
  final Color costColor;
  final Color unitColor;
  final Color? touOffPeakColor;
  final CurrentCycleForecast? currentCycle;
  // TOU เท่านั้น (แท็บไฟฟ้า) — ใช้ให้กราฟเทรนด์ฝั่ง "หน่วยที่ใช้" โชว์เป็น
  // แท่งซ้อน On-Peak/Off-Peak แทนแท่งทึบสีเดียว แท็บน้ำไม่ส่งมาเลย (default
  // false/null) จึงยังเป็นแท่งเดียวเหมือนเดิมทุกอย่าง
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;

  // เรียกตอนกดปุ่ม "ดูอุปกรณ์" ในการ์ดข้อสังเกต (เดือนที่ใช้สูงสุด) — ให้
  // AnalysisScreen สลับ TabController ไปแท็บอุปกรณ์ (index 2) แทนที่จะบอก
  // ข้อสังเกตเฉยๆ แล้วจบ ผู้ใช้กดต่อไปดูได้เลยว่าเครื่องไหนกินไฟเยอะสุด
  final VoidCallback? onViewAppliances;

  // หน้าอุปกรณ์เก็บเฉพาะข้อมูลการใช้ไฟฟ้า (ไม่มีตารางอุปกรณ์ใช้น้ำ) — ใช้
  // ตัวนี้กันไม่ให้ปุ่ม CTA "ดูอุปกรณ์" โผล่ในแท็บน้ำ ซึ่งกดไปแล้วจะเจอ
  // ข้อมูลที่ไม่เกี่ยวข้องกับสิ่งที่ผู้ใช้กำลังดูอยู่
  final bool trackAppliances;

  static const _green = Color(0xFF2E7D32);
  final _fmt = NumberFormat('#,##0.00');
  final _fmtUnit = NumberFormat('#,##0.0');

  _UtilityTab({
    required this.bills,
    required this.analysisService,
    required this.selector,
    required this.usedSelector,
    required this.unitLabel,
    required this.title,
    required this.label,
    required this.accentColor,
    required this.costColor,
    required this.unitColor,
    this.touOffPeakColor,
    required this.currentCycle,
    this.onViewAppliances,
    this.trackAppliances = true,
    this.isTou = false,
    this.peakUsedSelector,
    this.offPeakUsedSelector,
  });

  @override
  Widget build(BuildContext context) {
    final mom = analysisService.compareMoM(bills, selector: selector);
    final yoy = analysisService.compareYoY(bills, selector: selector);
    final avg6 = analysisService.compareToAverage(bills, selector: selector);
    final forecast =
        analysisService.forecastNextMonth(bills, selector: selector);

    final insights = analysisService.generateUtilityInsights(
      label: label,
      bills: bills,
      selector: selector,
      mom: mom,
      yoy: yoy,
      forecastNextMonth: forecast,
      currentCycle: currentCycle,
      trackAppliances: trackAppliances,
    );

    // ข้อมูลน้อยกว่า 3 เดือน = แนวโน้มระยะยาวยังไม่มีความหมายทางสถิติจริงๆ
    // (linear regression บนจุดข้อมูล 1-2 จุด ก็แค่ทาบเส้นผ่านจุดที่มีเท่านั้น)
    // ใช้กำกับความมั่นใจของตัวเลข ไม่ให้ผู้ใช้เข้าใจว่าแม่นยำร้อยเปอร์เซ็นต์
    final forecastLowConfidence = bills.length < 3;

    final overviewSummary = _overviewSummary(mom, avg6);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (overviewSummary != null) ...[
          _overviewBanner(overviewSummary),
          const SizedBox(height: 16),
        ],
        if (currentCycle != null && currentCycle!.hasData) ...[
          _currentCycleCard(context),
          const SizedBox(height: 16),
        ],
        _TrendChartCard(
          bills: bills,
          title: title,
          unitLabel: unitLabel,
          costSelector: selector,
          usedSelector: usedSelector,
          accentColor: accentColor,
          costColor: costColor,
          unitColor: unitColor,
          touOffPeakColor: touOffPeakColor,
          isTou: isTou,
          peakUsedSelector: peakUsedSelector,
          offPeakUsedSelector: offPeakUsedSelector,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _comparisonCard(
                context,
                'เทียบเดือนก่อน',
                mom,
                emptyHint:
                    'ต้องมีบิลอย่างน้อย 2 เดือน (ตอนนี้มี ${bills.length} เดือน)',
                infoTitle: 'เทียบเดือนก่อนคืออะไร?',
                infoMessage:
                    'เทียบยอด$labelของเดือนล่าสุดกับเดือนก่อนหน้าเดือนเดียว '
                    'ช่วยให้เห็นการเปลี่ยนแปลงระยะสั้นแบบเดือนต่อเดือน\n\n'
                    'คำนวณอย่างไร?\n'
                    'เอายอด$labelเดือนนี้ ลบด้วยยอดเดือนก่อน แล้วหารด้วยยอด'
                    'เดือนก่อน คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง '
                    '(ถ้าเดือนก่อนเป็น 0 บาท จะโชว์เป็นส่วนต่างบาทแทน '
                    'เพราะหารด้วย 0 ไม่ได้)',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _comparisonCard(
                context,
                'เทียบปีก่อน (เดือนเดียวกัน)',
                yoy,
                emptyHint:
                    'ยังไม่มีบิลเดือนเดียวกันของปีก่อน เก็บข้อมูลต่อให้ครบ 1 ปีจะเริ่มเทียบได้',
                infoTitle: 'เทียบปีก่อนคืออะไร?',
                infoMessage:
                    'เทียบยอด$labelเดือนนี้กับเดือนเดียวกันของปีที่แล้ว '
                    'ช่วยให้เห็นแนวโน้มตามฤดูกาล เช่น หน้าร้อนมักใช้ไฟมากกว่าหน้าฝน\n\n'
                    'คำนวณอย่างไร?\n'
                    'เอายอด$labelเดือนนี้ ลบด้วยยอดเดือนเดียวกันของปีก่อน '
                    'แล้วหารด้วยยอดปีก่อน คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _comparisonCard(
          context,
          'เทียบค่าเฉลี่ย 6 เดือนล่าสุด',
          avg6,
          emptyHint:
              'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน)',
          fullWidth: true,
          infoTitle: 'เทียบค่าเฉลี่ย 6 เดือนคืออะไร?',
          infoMessage:
              'เทียบยอด$labelเดือนนี้กับค่าเฉลี่ยของ 6 เดือนก่อนหน้า '
              'ช่วยให้เห็นภาพที่นิ่งกว่าเทียบเดือนก่อนเดือนเดียว เผื่อเดือนก่อน'
              'มีอะไรผิดปกติไปเอง\n\n'
              'คำนวณอย่างไร?\n'
              'เอายอด$labelของ 6 เดือนก่อนหน้ามารวมกัน แล้วหารด้วย 6 '
              'จะได้ค่าเฉลี่ย จากนั้นเอายอดเดือนนี้ลบค่าเฉลี่ยนั้น หารด้วย'
              'ค่าเฉลี่ย คูณ 100 จะได้เป็น% ที่เพิ่มขึ้นหรือลดลง '
              '(ถ้าเดือนไหนไม่มีบิลก็จะไม่ถูกนับรวมในค่าเฉลี่ย)',
        ),
        // ไม่มีบิลเลยสักเดือน = พยากรณ์ไม่มีความหมายอะไรทั้งสิ้น (ไม่ใช่แค่
        // "ความมั่นใจต่ำ") ซ่อนการ์ดนี้ไปเลยดีกว่าโชว์ "0.00 บาท" ซึ่งดู
        // เหมือนระบบฟันธงว่าเดือนหน้าจะไม่มีค่าใช้จ่าย ทั้งที่จริงคือยังไม่มี
        // ข้อมูลให้คำนวณ — กราฟเทรนด์ด้านบนมี empty-state อธิบายเรื่องนี้
        // ให้ผู้ใช้แล้ว ไม่ต้องพูดซ้ำอีกรอบในการ์ดนี้
        if (bills.isNotEmpty) ...[
          const SizedBox(height: 10),
          _forecastCard(context, forecast,
              lowConfidence: forecastLowConfidence),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          _insightsCard(insights),
        ],
      ],
    );
  }

  // ----- ประโยคสรุปภาพรวม 1 บรรทัด รวม "เทียบเดือนก่อน" + "เทียบค่าเฉลี่ย
  // 6 เดือน" เข้าด้วยกัน เพื่อให้ผู้ใช้เห็นภาพรวมทันทีโดยไม่ต้องไล่อ่านทีละ
  // การ์ดเองว่าสรุปแล้วเดือนนี้ "ดีขึ้นจริงไหม" (เช่น ลดลงจากเดือนก่อนก็จริง
  // แต่ถ้ายังสูงกว่าค่าเฉลี่ยอยู่ ก็ยังไม่ใช่ข่าวดีทั้งหมด) -----
  String? _overviewSummary(ComparisonResult? mom, ComparisonResult? avg6) {
    if (mom == null && avg6 == null) return null;

    String momPart(ComparisonResult m) {
      if (m.isUnchanged) return '$labelเดือนนี้ไม่เปลี่ยนแปลงจากเดือนก่อน';
      final dir = m.isIncrease ? 'สูงขึ้น' : 'ลดลง';
      final pct = m.percentChange != null
          ? ' ${m.percentChange!.abs().toStringAsFixed(0)}%'
          : '';
      return '$labelเดือนนี้$dirจากเดือนก่อน$pct';
    }

    String avgPart(ComparisonResult a, {String? connector}) {
      final lead = connector ?? '';
      if (a.isUnchanged) return '$leadเท่ากับค่าเฉลี่ย 6 เดือนที่ผ่านมา';
      final dir = a.isIncrease ? 'สูงกว่า' : 'ต่ำกว่า';
      final pct = a.percentChange != null
          ? ' ${a.percentChange!.abs().toStringAsFixed(0)}%'
          : '';
      return '$lead$dirค่าเฉลี่ย 6 เดือนที่ผ่านมา$pct';
    }

    if (mom != null && avg6 != null) {
      // ถ้าทิศทางเทียบเดือนก่อน กับเทียบค่าเฉลี่ย ไปคนละทาง (เช่น ลดลงจาก
      // เดือนก่อน แต่ยังสูงกว่าค่าเฉลี่ย) ใช้ "แต่" เพื่อสื่อความขัดแย้งนั้น
      // ให้ผู้ใช้เห็นชัดว่ายังวางใจไม่ได้เต็มที่ ถ้าไปทางเดียวกันใช้ "และ"
      final sameDirection = mom.isIncrease == avg6.isIncrease;
      final connector = sameDirection ? ' และ' : ' แต่';
      return '${momPart(mom)}$connector${avgPart(avg6, connector: '')}';
    } else if (mom != null) {
      return momPart(mom);
    } else {
      return '$labelเดือนนี้${avgPart(avg6!)}';
    }
  }

  Widget _overviewBanner(String summary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 16, color: _green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B5E20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- การ์ดพยากรณ์ยอดบิลรอบปัจจุบัน (Moving Average ถึงวันตัดรอบ) -----
  Widget _currentCycleCard(BuildContext context) {
    final c = currentCycle!;
    final progressPercent = (c.progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse, color: _green, size: 18),
              const SizedBox(width: 6),
              const Text('พยากรณ์ยอดบิลรอบนี้',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('ผ่านมาแล้ว $progressPercent%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message: 'คำนวณจากค่าใช้จ่ายเฉลี่ยต่อวันตั้งแต่ต้นรอบถึง'
                      'วันนี้ คูณด้วยจำนวนวันที่เหลือในรอบ แล้วบวกกับยอดที่'
                      'ใช้จริงไปแล้ว\n\n'
                      'หากใช้งานไม่สม่ำเสมอมาก (เช่น ต้นเดือนใช้น้อย ปลายเดือน'
                      'ใช้พุ่ง) ตัวเลขอาจคลาดเคลื่อนได้บ้าง',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.12),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: c.progress,
              minHeight: 6,
              backgroundColor: _green.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(_green),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _cycleStat(
                    'ใช้ไปแล้ว', '${_fmt.format(c.currentCost)} บาท'),
              ),
              Expanded(
                child: _cycleStat(
                    'คาดว่าจะจบรอบที่', '${_fmt.format(c.forecastCost)} บาท',
                    highlight: true),
              ),
              Expanded(
                child: _cycleStat('เหลืออีก', '${c.remainingDays} วัน'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.speed, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ใช้ไป ${_fmtUnit.format(c.currentUnits)} $unitLabel '
                    '• คาดว่าจะใช้ทั้งสิ้น ${_fmtUnit.format(c.forecastUnits)} $unitLabel',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cycleStat(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 15 : 13,
              color: highlight ? _green : Colors.black87,
            )),
      ],
    );
  }

  Widget _comparisonCard(
    BuildContext context,
    String label,
    ComparisonResult? r, {
    String emptyHint = 'ไม่มีข้อมูลพอเทียบ',
    bool fullWidth = false,
    required String infoTitle,
    required String infoMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
              // ปุ่ม (i) ใช้ showInfoDialog ตัวเดียวกับที่ใช้ทั่วแอป (ดู
              // การ์ดพยากรณ์รอบปัจจุบันด้านบน) ใส่ให้ครบทุกการ์ดเทียบเพื่อ
              // ความสม่ำเสมอ แทนที่จะมีแค่การ์ดเดียวที่อธิบายวิธีคำนวณ
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: infoTitle,
                  message: infoMessage,
                ),
                child: Icon(Icons.info_outline,
                    size: 14, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r == null)
            // โชว์ "progress" ว่าต้องเก็บข้อมูลเพิ่มอีกแค่ไหนถึงจะเทียบได้
            // แทนข้อความเฉยๆ ว่าไม่มีข้อมูล ให้ผู้ใช้ใหม่รู้ว่าต้องรออะไร
            Text(emptyHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: r.isUnchanged
                      ? const Row(
                          children: [
                            Icon(Icons.remove, size: 16, color: Colors.grey),
                            SizedBox(width: 4),
                            Text('ไม่เปลี่ยนแปลง',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.grey)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  r.isIncrease
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 16,
                                  color: r.isIncrease
                                      ? DashboardStyles.spikeUp
                                      : DashboardStyles.spikeDown,
                                ),
                                const SizedBox(width: 4),
                                // ตัวเลขหลัก: % ถ้าคำนวณได้ ไม่งั้นค่อย fallback
                                // เป็นบาท (กรณีค่าที่เทียบเป็น 0 หารไม่ได้)
                                Text(
                                  r.percentChange == null
                                      ? '${_fmt.format(r.diff.abs())} บาท'
                                      : '${r.percentChange!.abs().toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: r.isIncrease
                                        ? DashboardStyles.spikeUp
                                        : DashboardStyles.spikeDown,
                                  ),
                                ),
                              ],
                            ),
                            // โชว์ผลต่างเป็นบาทควบคู่ไปด้วยเสมอ (ไม่ใช่แค่ %)
                            // ยกเว้นตอนที่ % คำนวณไม่ได้อยู่แล้วซึ่งบาทถูก
                            // โชว์เป็นตัวหลักไปแล้วด้านบน ไม่ต้องซ้ำ ใช้สี
                            // เดียวกับลูกศร/ตัวเลข % เพื่อให้อ่านเป็นชุดเดียวกัน
                            if (r.percentChange != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${r.isIncrease ? '+' : '-'}'
                                  '${_fmt.format(r.diff.abs())} บาท',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: r.isIncrease
                                        ? DashboardStyles.spikeUp
                                        : DashboardStyles.spikeDown,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (fullWidth)
                  Text('เฉลี่ย ${_fmt.format(r.previousValue)} บาท',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
              ],
            ),
        ],
      ),
    );
  }

  // ----- การ์ดพยากรณ์ "เดือนถัดไป" ด้วย Linear Regression จากบิลย้อนหลัง
  // ทั้งหมด (ชื่อเทคนิคเก็บไว้แค่ในคอมเมนต์นี้กับ thesis report เท่านั้น —
  // ฝั่ง UI ใช้ภาษาคนล้วน ให้ผู้ใช้ทั่วไปเข้าใจได้โดยไม่ต้องรู้จักศัพท์สถิติ) -----
  Widget _forecastCard(
    BuildContext context,
    double forecast, {
    required bool lowConfidence,
  }) {
    // เทียบกับยอดบิลจริงเดือนล่าสุด เพื่อบอกเป็นประโยคปกติว่าเดือนหน้า
    // "คาดว่าจะสูง/ต่ำกว่าเดือนนี้" แทนที่จะโชว์ตัวเลขลอยๆ ให้ผู้ใช้ไปตีความเอง
    final comparedToLastBill =
        bills.isNotEmpty ? selector(bills.last) : null;
    final comparison = comparedToLastBill != null && comparedToLastBill > 0
        ? ComparisonResult(
            currentValue: forecast, previousValue: comparedToLastBill)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: _green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('คาดการณ์เดือนหน้า',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${_fmt.format(forecast)} บาท',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _green)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => showInfoDialog(
                  context,
                  title: 'ตัวเลขนี้คำนวณอย่างไร?',
                  message:
                      'ประมาณแนวโน้มจากยอด$labelย้อนหลังทั้งหมดที่บันทึกไว้ '
                      'แล้วลากเส้นแนวโน้มนั้นต่อไปยังเดือนถัดไป\n\n'
                      'ยิ่งมีข้อมูลสะสมหลายเดือน ตัวเลขนี้จะยิ่งแม่นยำขึ้น',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.15),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          if (comparison != null && !comparison.isUnchanged) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  comparison.isIncrease
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 14,
                  color: comparison.isIncrease
                      ? DashboardStyles.spikeUp
                      : DashboardStyles.spikeDown,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${comparison.isIncrease ? 'สูงกว่า' : 'ต่ำกว่า'}เดือนนี้ประมาณ '
                    '${comparison.percentChange != null ? '${comparison.percentChange!.abs().toStringAsFixed(0)}% ' : ''}'
                    '(${comparison.isIncrease ? '+' : '-'}${_fmt.format(comparison.diff.abs())} บาท)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: comparison.isIncrease
                          ? DashboardStyles.spikeUp
                          : DashboardStyles.spikeDown,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (lowConfidence) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (มีข้อมูล ${bills.length} เดือน)',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----- การ์ดข้อสังเกต/คำแนะนำที่วิเคราะห์มาจากข้อมูลจริง -----
  Widget _insightsCard(List<AnalysisInsight> insights) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: _green),
              SizedBox(width: 6),
              Text('ข้อสังเกต',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _insightIcon(i.level),
                      size: 16,
                      color: _insightColor(i.level),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.text,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.4)),
                          if (i.showApplianceCta &&
                              onViewAppliances != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GestureDetector(
                                onTap: onViewAppliances,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('ดูอุปกรณ์ที่ใช้ไฟมากสุด',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: _green)),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.arrow_forward_ios,
                                        size: 10, color: _green),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  IconData _insightIcon(InsightLevel level) {
    switch (level) {
      case InsightLevel.good:
        return Icons.check_circle;
      case InsightLevel.warning:
        return Icons.warning_amber_rounded;
      case InsightLevel.neutral:
        return Icons.info_outline;
    }
  }

  Color _insightColor(InsightLevel level) {
    switch (level) {
      case InsightLevel.good:
        return _green;
      case InsightLevel.warning:
        return Colors.orange.shade800;
      case InsightLevel.neutral:
        return Colors.grey.shade600;
    }
  }
}

// =====================================================================
// การ์ดกราฟเทรนด์ — สลับมุมมองระหว่าง "ค่าใช้จ่าย" กับ "หน่วยที่ใช้" ได้ใน
// การ์ดเดียว ด้วยปุ่มเลือกแบบ radio มุมขวาบน (ตามดีไซน์ที่ขอมา คล้ายแอป
// การไฟฟ้า/ประปา) แทนที่จะแยกเป็น 2 กราฟเรียงต่อกันแบบเดิม — ต้องเป็น
// StatefulWidget แยกออกมาจาก _UtilityTab (ซึ่งเป็น StatelessWidget) เพราะ
// ต้องจำสถานะว่าผู้ใช้เลือกดูมุมมองไหนอยู่ระหว่างที่ widget อื่นๆ ใน
// หน้าเดียวกัน rebuild (เช่น ตอนเลื่อนหน้าจอ)
class _TrendChartCard extends StatefulWidget {
  final List<BillModel> bills;
  final String title; // 'ค่าไฟฟ้า' / 'ค่าน้ำ' ใช้ตั้งชื่อกราฟฝั่งค่าใช้จ่าย
  final String unitLabel; // 'หน่วย' / 'ลบ.ม.' ใช้เป็น label ปุ่มฝั่งหน่วย
  final double Function(BillModel) costSelector;
  final double Function(BillModel) usedSelector;
  final Color accentColor;
  // สีแท่งกราฟจริง แยกตามโหมด "ค่าใช้จ่าย" กับ "หน่วย/ลบ.ม." — รับเฉดจาก
  // พาเลตที่เลือกไว้ต่อยูทิลิตี้ตรงๆ (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน)
  // แทนการไล่เฉดอัตโนมัติจาก accentColor เดิม ให้คุมสีได้แม่นยำตามที่เลือก
  final Color costColor;
  final Color unitColor;
  // TOU เท่านั้น — สี Off-Peak ของแท่งซ้อน ถ้าไม่ส่งมาจะ fallback เป็นเฉด
  // อ่อนของ unitColor แทน
  final Color? touOffPeakColor;
  // TOU เท่านั้น — ดู _UtilityTab ด้านบนสำหรับที่มา
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;

  const _TrendChartCard({
    required this.bills,
    required this.title,
    required this.unitLabel,
    required this.costSelector,
    required this.usedSelector,
    required this.accentColor,
    required this.costColor,
    required this.unitColor,
    this.touOffPeakColor,
    this.isTou = false,
    this.peakUsedSelector,
    this.offPeakUsedSelector,
  });

  @override
  State<_TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<_TrendChartCard> {
  // true = โชว์กราฟค่าใช้จ่าย (บาท), false = โชว์กราฟหน่วยที่ใช้ — เริ่มที่
  // ค่าใช้จ่ายเป็นค่าเริ่มต้นเสมอ เพราะเป็นข้อมูลที่มีครบทุกเดือนแน่นอนกว่า
  // (หน่วยอาจเป็น 0 ในเดือนแรกสุดที่ไม่มี record ก่อนหน้าให้คำนวณ delta)
  bool _showCost = true;

  String _emptyMessage(String subject) {
    if (widget.bills.isEmpty) {
      return 'ยังไม่มีข้อมูลบิลของ$subject เลย\nบันทึกบิลเดือนแรกที่หน้าตั้งค่า เพื่อเริ่มเก็บข้อมูล';
    }
    final needed = 2 - widget.bills.length;
    return 'มีข้อมูลแล้ว ${widget.bills.length} เดือน\nบันทึกอีก $needed เดือน จะเริ่มเห็นกราฟแนวโน้มได้';
  }

  Widget _radioOption(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 15,
              color: selected ? widget.accentColor : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? widget.accentColor : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bills = widget.bills;
    final values = bills
        .map(_showCost ? widget.costSelector : widget.usedSelector)
        .toList();

    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final minVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxY = maxVal <= 0 ? 8.0 : maxVal * 1.25;
    final interval = maxY / 4;

    // ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
    // เดือนผิดปกติได้ทันทีโดยไม่ต้องไล่อ่านตัวเลขทีละแท่ง
    final hasVariation = values.length >= 2 && maxVal != minVal;
    final peakIndex = hasVariation ? values.indexOf(maxVal) : -1;
    final lowIndex = hasVariation ? values.indexOf(minVal) : -1;
    // สีสดใสแบบมินิมอล — ไฮไลต์เดือนสูงสุด/ต่ำสุดของทุกยูทิลิตี้ (แยกจาก
    // พาเลตสีประจำยูทิลิตี้ ให้ยังโดดเด่นเห็นชัดไม่ว่าจะเป็นแท็บไหน)
    // เดือนต่ำสุดใช้สีเขียวหลักของแบรนด์ (สื่อว่า "ใช้น้อย = ดี" ตรงกับ
    // ความหมายสีเขียวที่ใช้ทั้งแอป) เดือนสูงสุดใช้ส้มอิฐอุ่นๆ แทนสีแดงสด
    // เดิมที่ปะทะกับพาเลตอุ่นของกราฟมากไป
    const peakColor = Color(0xFFE2673F); // ส้มอิฐ — เดือนใช้สูงสุด
    const lowColor = Color(0xFF2E7D32); // เขียวหลักของแบรนด์ — เดือนใช้ต่ำสุด

    // สีแท่งกราฟจริงตามโหมดที่กำลังดู — ใช้เฉดตรงจากพาเลตที่เลือกไว้
    // (ไฟฟ้า = แดง/เหลือง, น้ำ = น้ำเงิน) ไม่ผ่านการไล่เฉดอัตโนมัติ เพื่อให้
    // สีตรงตาม swatch ที่เลือกเป๊ะๆ
    final modeAccent = _showCost ? widget.costColor : widget.unitColor;

    // TOU + กำลังดูมุมมอง "หน่วยที่ใช้" (ไม่ใช่ค่าใช้จ่าย) → แท่งซ้อน
    // On-Peak/Off-Peak แทนแท่งทึบสีเดียว ฝั่งค่าใช้จ่ายไม่แยก เพราะ
    // electricityCost เก็บเป็นยอดเดียว ไม่มีราคาแยกตามช่วงเวลาให้ซ้อน
    final showStacked = !_showCost &&
        widget.isTou &&
        widget.peakUsedSelector != null &&
        widget.offPeakUsedSelector != null;
    // Off-Peak ใช้สีที่เลือกไว้เฉพาะ (เช่น เหลืองอ่อนคู่กับเหลืองเข้มของ
    // On-Peak) ถ้าไม่ได้ส่งมา fallback เป็นเฉดอ่อนของ unitColor แทน
    final touPeakColor = widget.unitColor;
    final touOffPeakColor =
        widget.touOffPeakColor ?? Color.lerp(widget.unitColor, Colors.white, 0.3)!;


    final chartTitle = _showCost
        ? 'เทรนด์${widget.title} (${bills.length} เดือนล่าสุด)'
        : 'เทรนด์${widget.unitLabel}ที่ใช้${widget.title} '
            '(${bills.length} เดือนล่าสุด)';
    final emptyMessage = _showCost
        ? _emptyMessage(widget.title)
        : _emptyMessage('${widget.unitLabel}ที่ใช้${widget.title}');
    final tooltipSuffix = _showCost ? '' : ' ${widget.unitLabel}';

    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('ประวัติการใช้${widget.title}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              _radioOption('ค่าใช้จ่าย', _showCost,
                  () => setState(() => _showCost = true)),
              const SizedBox(width: 10),
              _radioOption(widget.unitLabel, !_showCost,
                  () => setState(() => _showCost = false)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(chartTitle,
                    style: TextStyle(
                        fontSize: 10.5, color: Colors.grey.shade500)),
              ),
              if (showStacked) ...[
                _legendDot(touPeakColor, 'On-Peak'),
                const SizedBox(width: 10),
                _legendDot(touOffPeakColor, 'Off-Peak'),
              ] else if (hasVariation) ...[
                _legendDot(peakColor, 'สูงสุด'),
                const SizedBox(width: 10),
                _legendDot(lowColor, 'ต่ำสุด'),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: values.length < 2
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: BarChart(
                            BarChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              barTouchData: BarTouchData(enabled: false),
                              maxY: 8,
                              barGroups: List.generate(6, (i) {
                                const demo = [3.0, 5.0, 3.5, 6.0, 4.5, 6.5];
                                return BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: demo[i],
                                    color: Colors.grey.shade300,
                                    width: 18,
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                  ),
                                ]);
                              }),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                    ],
                  )
                : BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval == 0 ? 1 : interval,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: interval == 0 ? 1 : interval,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey.shade500),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= bills.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                    '${bills[i].month}/${bills[i].year % 100}',
                                    style: const TextStyle(fontSize: 9)),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (showStacked) {
                              final peak =
                                  widget.peakUsedSelector!(bills[groupIndex]);
                              final offPeak = widget
                                  .offPeakUsedSelector!(bills[groupIndex]);
                              final hasSplit = peak > 0 || offPeak > 0;
                              final text = hasSplit
                                  ? 'รวม ${rod.toY.toStringAsFixed(1)}$tooltipSuffix\n'
                                      'On-Peak ${peak.toStringAsFixed(1)} · '
                                      'Off-Peak ${offPeak.toStringAsFixed(1)}'
                                  : '${rod.toY.toStringAsFixed(1)}$tooltipSuffix';
                              return BarTooltipItem(
                                text,
                                const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              );
                            }
                            return BarTooltipItem(
                              '${rod.toY.toStringAsFixed(1)}$tooltipSuffix',
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ),
                      barGroups: List.generate(values.length, (i) {
                        if (showStacked) {
                          final peak = widget.peakUsedSelector!(bills[i]);
                          final offPeak =
                              widget.offPeakUsedSelector!(bills[i]);
                          final hasSplit = peak > 0 || offPeak > 0;
                          if (hasSplit) {
                            return BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: peak + offPeak,
                                rodStackItems: [
                                  BarChartRodStackItem(0, peak, touPeakColor),
                                  BarChartRodStackItem(peak, peak + offPeak,
                                      touOffPeakColor),
                                ],
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ]);
                          }
                          // บิลเก่าก่อนมีฟิลด์แยก peak/offpeak (หรือมิเตอร์
                          // เพิ่งสลับมาเป็น TOU) — ไม่มีข้อมูลให้ซ้อน แต่ยัง
                          // มียอดรวม โชว์เป็นแท่งทึบสีเทาแทนการปล่อยให้เดือน
                          // นั้นหายไปจากกราฟเงียบๆ
                          return BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: values[i],
                              color: Colors.grey.shade400,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ]);
                        }
                        final barColor = i == peakIndex
                            ? peakColor
                            : i == lowIndex
                                ? lowColor
                                : modeAccent;
                        return BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: values[i],
                            color: barColor,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ]);
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
      ],
    );
  }
}

// ==================== Tab อุปกรณ์ ====================
class _ApplianceTab extends StatelessWidget {
  final List<ApplianceModel> appliances;
  final AnalysisService analysisService;

  static const _green = Color(0xFF2E7D32);
  final _fmt = NumberFormat('#,##0.00');

  _ApplianceTab({required this.appliances, required this.analysisService});

  @override
  Widget build(BuildContext context) {
    final breakdown = analysisService.applianceBreakdown(appliances);

    if (breakdown.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 160,
                      width: 160,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // โดนัทจำลองจางๆ ให้เห็นรูปทรงว่าพอมีข้อมูลแล้วจะเป็นแบบนี้
                          PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 46,
                              sections: [
                                PieChartSectionData(
                                  value: 40,
                                  color: Colors.grey.shade200,
                                  showTitle: false,
                                  radius: 34,
                                ),
                                PieChartSectionData(
                                  value: 25,
                                  color: Colors.grey.shade100,
                                  showTitle: false,
                                  radius: 34,
                                ),
                                PieChartSectionData(
                                  value: 35,
                                  color: Colors.grey.shade200,
                                  showTitle: false,
                                  radius: 34,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.devices_other,
                              size: 36, color: Colors.grey.shade300),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('ยังไม่มีอุปกรณ์ที่ตั้งตารางการใช้งาน',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final insights = analysisService.generateApplianceInsights(breakdown);

    // พาเลตใหม่: ยึดโทนเขียวของแบรนด์เป็นหลัก ไล่เฉดเขียวอ่อน-เข้ม สลับกับ
    // สีอุ่นคู่ตรงข้าม (ทอง/ส้ม/น้ำตาล) แทนพาเลตเดิมที่ผสมสีสดจัดหลายโทน
    // ปะปนกัน (ม่วง/ฟ้าสด/ชมพู) ซึ่งดูไม่เป็นชุดเดียวกับสีเขียวหลักของแอป
    // เรียงให้ชิ้นพายที่อยู่ติดกันสลับอุ่น-เย็นชัดเจน แยกออกจากกันง่าย
    final colors = [
      _green, // เขียวหลักของแบรนด์
      const Color(0xFFFFA726), // ส้มทอง
      const Color(0xFF26A69A), // เขียวอมฟ้า (teal)
      const Color(0xFFFFCA28), // เหลืองทอง
      const Color(0xFF8D6E63), // น้ำตาลอบอุ่น
      const Color(0xFF66BB6A), // เขียวอ่อน
      const Color(0xFFD98E5B), // ส้มดิน
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('สัดส่วนการใช้พลังงาน (kWh/เดือน, ประมาณการ)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              // วงกลม + ป้ายชื่อรายการรอบวง — ป้ายวางด้วย Alignment (ไม่ใช่
              // Positioned ตำแหน่งตายตัว) เพราะไม่รู้ขนาดจริงของป้ายแต่ละ
              // อันล่วงหน้า (ความยาวชื่ออุปกรณ์ไม่เท่ากัน) Alignment ยึด
              // "จุดกึ่งกลาง" ของป้ายที่ตำแหน่งเปอร์เซ็นต์ของกรอบสี่เหลี่ยม
              // ให้เอง ไม่ต้องคำนวณขนาดป้ายเอง
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        // มุมเริ่มที่ 12 นาฬิกา (-90 องศา) ให้คำนวณตำแหน่ง
                        // ป้ายรอบวงตรงกับชิ้นพายจริงเป๊ะๆ
                        startDegreeOffset: -90,
                        sections: List.generate(breakdown.length, (i) {
                          final u = breakdown[i];
                          // ซ่อนตัวเลข % บนชิ้นที่เล็กเกินไป (ไม่งั้นตัวหนังสือ
                          // จะเบียดกันเองหรือล้นออกนอกชิ้นพาย) ไปดู % แทนได้
                          // จากป้ายรอบวง/ตารางอันดับด้านล่าง
                          final showTitle = u.percentOfTotal >= 8;
                          return PieChartSectionData(
                            value: u.kWh,
                            color: colors[i % colors.length],
                            title: showTitle
                                ? '${u.percentOfTotal.toStringAsFixed(0)}%'
                                : '',
                            radius: 56,
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          );
                        }),
                      ),
                    ),
                    ..._pieLabelPills(breakdown, colors),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('อันดับอุปกรณ์กินไฟ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        // แสดง top 3 ก่อนเสมอ ถ้ามีมากกว่านั้นค่อยกดขยายดูที่เหลือ
        // (ใช้ widget แยกเพราะ _ApplianceTab เป็น StatelessWidget
        // ไม่มี setState ให้ toggle เอง)
        _ApplianceRankingList(breakdown: breakdown, colors: colors, fmt: _fmt),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => showApplianceEstimateInfoDialog(context),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'เป็นค่าประมาณการ ไม่ใช่ค่าจากมิเตอร์จริง — แตะเพื่อดูรายละเอียด',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 6)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: _green),
                    SizedBox(width: 6),
                    Text('ข้อสังเกต',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                ...insights.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            i.level == InsightLevel.warning
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                            size: 16,
                            color: i.level == InsightLevel.warning
                                ? Colors.orange.shade800
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(i.text,
                                style: const TextStyle(
                                    fontSize: 12.5, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // สร้างป้ายชื่อรายการ (ไอคอนจุดสี + ชื่ออุปกรณ์) วางรอบวงกลม โดยอิง
  // ตำแหน่งมุมกึ่งกลางของแต่ละชิ้นพายจริง (คำนวณจาก percentOfTotal
  // สะสมของแต่ละรายการ ตรงกับ startDegreeOffset: -90 ที่ตั้งไว้ในกราฟ)
  // ใช้ Alignment แทน Positioned เพราะไม่ต้องรู้ขนาดป้ายล่วงหน้า — ซ่อน
  // ป้ายของชิ้นที่เล็กเกินไป (<4%) กันป้ายเบียดกันเองรอบวงเวลามีอุปกรณ์
  // เยอะ (ชิ้นเล็กๆ พวกนี้ยังดูรายละเอียดได้จากตารางอันดับด้านล่าง)
  List<Widget> _pieLabelPills(
      List<ApplianceUsage> breakdown, List<Color> colors) {
    const minPercentToLabel = 4.0;
    const radiusFactor = 0.86; // ระยะห่างจากจุดกึ่งกลางออกไปรอบขอบกรอบ
    double cumulative = 0;
    final widgets = <Widget>[];

    for (var i = 0; i < breakdown.length; i++) {
      final u = breakdown[i];
      final sweep = u.percentOfTotal * 3.6;
      if (u.percentOfTotal >= minPercentToLabel) {
        final midAngleDeg = -90 + cumulative * 3.6 + sweep / 2;
        final midAngleRad = midAngleDeg * math.pi / 180;
        widgets.add(
          Align(
            alignment: Alignment(
              math.cos(midAngleRad) * radiusFactor,
              math.sin(midAngleRad) * radiusFactor,
            ),
            child: _PieLabelPill(
              color: colors[i % colors.length],
              label: u.appliance.name,
            ),
          ),
        );
      }
      cumulative += u.percentOfTotal;
    }
    return widgets;
  }
}

// ป้ายชื่อรายการรอบวงกลม — จุดสีตรงกับสีชิ้นพาย + ชื่ออุปกรณ์ ในกล่องมน
// ขอบขาว มีเงาบางๆ (ตาม ref ที่แนบมา) ตัดชื่อที่ยาวเกินด้วย ... กันป้ายเบียด
// ป้ายอื่นหรือล้นออกนอกการ์ด
class _PieLabelPill extends StatelessWidget {
  final Color color;
  final String label;

  const _PieLabelPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE4F2E4),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.18), blurRadius: 5)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// รายการอันดับอุปกรณ์กินไฟ — โชว์แค่ top 3 ก่อนเสมอ (กันไม่ให้ยาวเกินไป
// ถ้ามีอุปกรณ์เยอะ) มีปุ่ม "ดูทั้งหมด" ให้กดขยายดูที่เหลือได้ ถ้ามี ≤ 3
// ตัวอยู่แล้วจะโชว์ครบโดยไม่มีปุ่มเลย
// =====================================================================
class _ApplianceRankingList extends StatefulWidget {
  final List<ApplianceUsage> breakdown;
  final List<Color> colors;
  final NumberFormat fmt;

  const _ApplianceRankingList({
    required this.breakdown,
    required this.colors,
    required this.fmt,
  });

  @override
  State<_ApplianceRankingList> createState() => _ApplianceRankingListState();
}

class _ApplianceRankingListState extends State<_ApplianceRankingList> {
  static const _green = Color(0xFF2E7D32);
  static const _collapsedCount = 3;

  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.breakdown;
    final hasMore = breakdown.length > _collapsedCount;
    final visibleCount =
        _showAll || !hasMore ? breakdown.length : _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: Colors.grey.withValues(alpha: 0.06), blurRadius: 4)
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(0.9),
              3: FlexColumnWidth(1.3),
            },
            children: [
              // ---- หัวตาราง ----
              TableRow(
                decoration: const BoxDecoration(color: _green),
                children: [
                  _headerCell('อุปกรณ์', alignLeft: true),
                  _headerCell('kWh'),
                  _headerCell('%'),
                  _headerCell('บาท', alignRight: true),
                ],
              ),
              // ---- แถวข้อมูล (แถวสุดท้ายไม่มีเส้นคั่นด้านล่าง) ----
              ...List.generate(visibleCount, (i) {
                final u = breakdown[i];
                final isLast = i == visibleCount - 1;
                return TableRow(
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  children: [
                    _nameCell(u.appliance.name,
                        widget.colors[i % widget.colors.length], i),
                    _dataCell(u.kWh.toStringAsFixed(1)),
                    _dataCell('${u.percentOfTotal.toStringAsFixed(0)}%',
                        bold: true, color: _green),
                    _dataCell(widget.fmt.format(u.cost), alignRight: true),
                  ],
                );
              }),
            ],
          ),
        ),
        if (hasMore)
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Text(
                _showAll ? 'ย่อรายการ' : 'ดูทั้งหมด (${breakdown.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: _green,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // หัวคอลัมน์ — ตัวหนังสือเทาเล็ก จัดตำแหน่งตามคอลัมน์ (ชื่ออุปกรณ์ชิดซ้าย,
  // บาทชิดขวา, ที่เหลือกึ่งกลาง) ตาม ref
  Widget _headerCell(String label,
      {bool alignLeft = false, bool alignRight = false}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          label,
          textAlign: alignLeft
              ? TextAlign.left
              : (alignRight ? TextAlign.right : TextAlign.center),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // คอลัมน์ชื่ออุปกรณ์ — คงวงกลมสีลำดับ (1,2,3...) แบบเดิมไว้ด้วยกัน แค่ย่อ
  // ขนาดให้พอดีคอลัมน์ตาราง แทนที่จะเป็นการ์ดแยกบรรทัดแบบเดิม
  Widget _nameCell(String name, Color rankColor, int index) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: rankColor.withValues(alpha: 0.15),
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // คอลัมน์ตัวเลข (kWh / % / บาท) — กึ่งกลางเป็นค่าเริ่มต้น ยกเว้นคอลัมน์
  // "บาท" ที่ชิดขวาตาม ref, สีเข้ม/หนาได้ถ้าระบุมา (ใช้กับคอลัมน์ %)
  Widget _dataCell(String text, {bool alignRight = false, bool bold = false, Color? color}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          textAlign: alignRight ? TextAlign.right : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.grey.shade800,
          ),
        ),
      ),
    );
  }
}