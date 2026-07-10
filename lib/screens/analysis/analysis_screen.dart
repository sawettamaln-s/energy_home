import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/appliance_model.dart';
import '../../models/bill_model.dart';
import '../../services/analysis_service.dart';
import '../../services/firestore_service.dart';
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
  }

  @override
  void dispose() {
    _applianceSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // ต้องดึง user มาก่อน เพื่อเอา billingDay ไปคำนวณขอบเขตรอบบิลปัจจุบัน
      final user = await _firestoreService.getUser(uid);
      final billingDay = user?.billingDay ?? 30;

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
                    unitLabel: 'หน่วย',
                    title: 'ค่าไฟฟ้า',
                    label: 'ค่าไฟ',
                    currentCycle: _currentCycle?['electricity'],
                    onViewAppliances: () => _tabController.animateTo(2),
                  ),
                  _UtilityTab(
                    bills: _bills,
                    analysisService: _analysisService,
                    selector: (b) => b.waterCost,
                    unitLabel: 'หน่วย',
                    title: 'ค่าน้ำ',
                    label: 'ค่าน้ำ',
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
  final String unitLabel; // หน่วยที่ใช้ เช่น 'หน่วย'
  final String title; // หัวข้อยาว เช่น 'ค่าไฟฟ้า' ใช้ในกราฟเทรนด์
  final String label; // หัวข้อสั้น เช่น 'ค่าไฟ' ใช้ในข้อความ insight
  final CurrentCycleForecast? currentCycle;

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
    required this.unitLabel,
    required this.title,
    required this.label,
    required this.currentCycle,
    this.onViewAppliances,
    this.trackAppliances = true,
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
        _trendChart(),
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
                    'ช่วยให้เห็นการเปลี่ยนแปลงระยะสั้นแบบเดือนต่อเดือน',
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
                    'ช่วยให้เห็นแนวโน้มตามฤดูกาล เช่น หน้าร้อนมักใช้ไฟมากกว่าหน้าฝน '
                    'ซึ่งการเทียบเดือนก่อนเดือนเดียวจะไม่เห็นภาพนี้',
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
              'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน) — '
              'ช่วยให้เห็นภาพที่นิ่งกว่าเทียบเดือนก่อนเดือนเดียว',
          fullWidth: true,
          infoTitle: 'เทียบค่าเฉลี่ย 6 เดือนคืออะไร?',
          infoMessage:
              'เทียบยอด$labelเดือนนี้กับค่าเฉลี่ยของ 6 เดือนก่อนหน้า (ไม่รวมเดือนนี้) '
              'ช่วยให้เห็นภาพที่นิ่งกว่าการเทียบเดือนก่อนเดือนเดียว เผื่อเดือนก่อน '
              'มีอะไรผิดปกติไปเอง (เช่น ไปต่างจังหวัดทั้งเดือน) ก็จะไม่ทำให้เดือนนี้ดูเหมือนพุ่งทั้งที่จริงแค่กลับสู่ปกติ',
        ),
        const SizedBox(height: 10),
        _forecastCard(context, forecast, lowConfidence: forecastLowConfidence),
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
      if (a.isUnchanged) return '${lead}เท่ากับค่าเฉลี่ย 6 เดือนที่ผ่านมา';
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
        color: _green.withOpacity(0.08),
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
          BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
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
                  message: 'ใช้วิธีค่าเฉลี่ยเคลื่อนที่ คำนวณจากค่าใช้จ่ายเฉลี่ย'
                      'ต่อวันตั้งแต่ต้นรอบบิลถึงวันนี้ คูณด้วยจำนวนวันที่เหลือ'
                      'ในรอบ แล้วบวกกับยอดที่ใช้จริงไปแล้ว โดยสมมติว่าช่วงที่'
                      'เหลือของเดือนใช้ในอัตราเดิมต่อเนื่อง\n\n'
                      'วิธีนี้ไม่ต้องรอสะสมข้อมูลหลายเดือน คำนวณได้ทันทีจาก'
                      'พฤติกรรมการใช้จริงในรอบปัจจุบัน หากใช้งานไม่สม่ำเสมอมาก '
                      '(เช่น ต้นเดือนใช้น้อย ปลายเดือนใช้พุ่ง) ตัวเลขอาจ'
                      'คลาดเคลื่อนได้บ้าง',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withOpacity(0.12),
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
              backgroundColor: _green.withOpacity(0.12),
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

  // ----- ข้อความ empty state ของกราฟเทรนด์ บอก progress ตามจำนวนบิลจริง -----
  // เดิมเขียนตายตัวว่า "ข้อมูลยังไม่พอ (ต้องมีอย่างน้อย 2 เดือน)" ผู้ใช้ใหม่
  // จะไม่รู้ว่าตอนนี้มีกี่เดือนแล้ว ต้องรออีกกี่เดือนถึงจะเริ่มเห็นกราฟ
  String _trendEmptyMessage() {
    if (bills.isEmpty) {
      return 'ยังไม่มีข้อมูลบิลของ$title เลย\nบันทึกบิลเดือนแรกที่หน้าตั้งค่า เพื่อเริ่มเก็บข้อมูล';
    }
    final needed = 2 - bills.length;
    return 'มีข้อมูลแล้ว ${bills.length} เดือน\nบันทึกอีก $needed เดือน จะเริ่มเห็นกราฟแนวโน้มได้';
  }

  Widget _trendChart() {
    final values = <double>[];
    for (int i = 0; i < bills.length; i++) {
      values.add(selector(bills[i]));
    }
    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final minVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    // เผื่อหัวกราฟด้านบน 25% กันแท่งสูงสุดชนขอบพอดี
    final maxY = maxVal <= 0 ? 8.0 : maxVal * 1.25;
    final interval = maxY / 4;

    // ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
    // เดือนผิดปกติได้ทันทีโดยไม่ต้องไล่อ่านตัวเลขทีละแท่ง — ใช้ indexOf ตัว
    // แรกที่เจอถ้ามีหลายเดือนเท่ากันพอดี (เคสหายากในทางปฏิบัติ ไม่ซับซ้อนเกิน
    // ความจำเป็น) ข้ามการไฮไลต์ถ้าทุกเดือนเท่ากันหมดเป๊ะ (maxVal == minVal)
    // เพราะแบบนั้นไม่มี "เดือนที่โดดเด่น" ให้ชี้จริงๆ
    final hasVariation = values.length >= 2 && maxVal != minVal;
    final peakIndex = hasVariation ? values.indexOf(maxVal) : -1;
    final lowIndex = hasVariation ? values.indexOf(minVal) : -1;
    const peakColor = Color(0xFFE53935); // แดง — เดือนใช้สูงสุด
    const lowColor = Color(0xFF00897B); // เขียวอมฟ้า — เดือนใช้ต่ำสุด

    return Container(
      height: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('เทรนด์$title (${bills.length} เดือนล่าสุด)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              // คำอธิบายสีสั้นๆ กันผู้ใช้เข้าใจผิดว่าสีที่ต่างกันเป็น bug
              // (โชว์เฉพาะตอนมีการไฮไลต์จริง)
              if (hasVariation) ...[
                _trendLegendDot(peakColor, 'สูงสุด'),
                const SizedBox(width: 10),
                _trendLegendDot(lowColor, 'ต่ำสุด'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: values.length < 2
                ? Stack(
                    children: [
                      // กราฟจำลองจางๆ ให้เห็นรูปทรงว่าพอมีข้อมูลแล้วจะเป็นแบบนี้
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
                                    borderRadius: BorderRadius.circular(4),
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
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _trendEmptyMessage(),
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
                            return BarTooltipItem(
                              rod.toY.toStringAsFixed(1),
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                      ),
                      barGroups: List.generate(values.length, (i) {
                        final barColor = i == peakIndex
                            ? peakColor
                            : i == lowIndex
                                ? lowColor
                                : _green;
                        return BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: values[i],
                            color: barColor,
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
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

  Widget _trendLegendDot(Color color, String label) {
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
          BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
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
        color: _green.withOpacity(0.08),
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
                      'โดยดูว่าตัวเลขแต่ละเดือนขยับขึ้นหรือลงตามแนวทางไหน '
                      'แล้วลากเส้นแนวโน้มนั้นต่อไปยังเดือนถัดไป\n\n'
                      'ยิ่งมีข้อมูลสะสมหลายเดือน เส้นแนวโน้มจะยิ่งนิ่งและแม่นยำขึ้น '
                      'ถ้ามีข้อมูลน้อยตัวเลขนี้จะเป็นแค่การประมาณการเบื้องต้นเท่านั้น',
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withOpacity(0.15),
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
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ประมาณการเบื้องต้น (ข้อมูลยังน้อย — มี ${bills.length} เดือน '
                'ยิ่งบันทึกบิลสะสมมากขึ้น ตัวเลขนี้จะยิ่งแม่นยำขึ้น)',
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
          BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('ดูอุปกรณ์ที่ใช้ไฟมากสุด',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: _green)),
                                    const SizedBox(width: 2),
                                    Icon(Icons.arrow_forward_ios,
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

    final colors = [
      _green,
      Colors.orange,
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.brown,
      Colors.pink,
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
              BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('สัดส่วนการใช้พลังงาน (kWh/เดือน, ประมาณการ)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                height: 190,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: List.generate(breakdown.length, (i) {
                      final u = breakdown[i];
                      // ซ่อนตัวเลข % บนชิ้นที่เล็กเกินไป (ไม่งั้นตัวหนังสือ
                      // จะเบียดกันเองหรือล้นออกนอกชิ้นพาย) ไปดู % แทนได้
                      // จาก legend ด้านล่างซึ่งมีพื้นที่พอสำหรับทุกชิ้น
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
                BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6)
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
        ...List.generate(visibleCount, (i) {
          final u = breakdown[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 4)
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      widget.colors[i % widget.colors.length].withOpacity(0.15),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: widget.colors[i % widget.colors.length],
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.appliance.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                          '${u.kWh.toStringAsFixed(1)} kWh • '
                          '${widget.fmt.format(u.cost)} บาท',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Text('${u.percentOfTotal.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _green)),
              ],
            ),
          );
        }),
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
}