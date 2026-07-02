import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/appliance_model.dart';
import '../../models/bill_model.dart';
import '../../services/analysis_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_bottom_nav_bar.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

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
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('วิเคราะห์',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _green,
          tabs: const [
            Tab(text: 'ไฟฟ้า'),
            Tab(text: 'น้ำ'),
            Tab(text: 'อุปกรณ์'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : TabBarView(
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
                ),
                _UtilityTab(
                  bills: _bills,
                  analysisService: _analysisService,
                  selector: (b) => b.waterCost,
                  unitLabel: 'หน่วย',
                  title: 'ค่าน้ำ',
                  label: 'ค่าน้ำ',
                  currentCycle: _currentCycle?['water'],
                ),
                _ApplianceTab(
                  appliances: _appliances,
                  analysisService: _analysisService,
                ),
              ],
            ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 1),
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
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (currentCycle != null && currentCycle!.hasData) ...[
          _currentCycleCard(),
          const SizedBox(height: 16),
        ],
        _trendChart(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _comparisonCard(
                'เทียบเดือนก่อน',
                mom,
                emptyHint:
                    'ต้องมีบิลอย่างน้อย 2 เดือน (ตอนนี้มี ${bills.length} เดือน)',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _comparisonCard(
                'เทียบปีก่อน (เดือนเดียวกัน)',
                yoy,
                emptyHint:
                    'ยังไม่มีบิลเดือนเดียวกันของปีก่อน เก็บข้อมูลต่อให้ครบ 1 ปีจะเริ่มเทียบได้',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _comparisonCard(
          'เทียบค่าเฉลี่ย 6 เดือนล่าสุด',
          avg6,
          emptyHint:
              'ต้องมีบิลอย่างน้อย 3 เดือน (ตอนนี้มี ${bills.length} เดือน) — '
              'ช่วยให้เห็นภาพที่นิ่งกว่าเทียบเดือนก่อนเดือนเดียว',
          fullWidth: true,
        ),
        const SizedBox(height: 10),
        _forecastCard(forecast),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 16),
          _insightsCard(insights),
        ],
      ],
    );
  }

  // ----- การ์ดพยากรณ์ยอดบิลรอบปัจจุบัน (Moving Average ถึงวันตัดรอบ) -----
  Widget _currentCycleCard() {
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
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text('ผ่านมาแล้ว $progressPercent%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
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
    final spots = <FlSpot>[];
    for (int i = 0; i < bills.length; i++) {
      spots.add(FlSpot(i.toDouble(), selector(bills[i])));
    }

    return Container(
      height: 220,
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
          Text('เทรนด์$title (${bills.length} เดือนล่าสุด)',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          Expanded(
            child: spots.length < 2
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        _trendEmptyMessage(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= bills.length) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                  '${bills[i].month}/${bills[i].year % 100}',
                                  style: const TextStyle(fontSize: 9));
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: _green,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                              show: true, color: _green.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _comparisonCard(
    String label,
    ComparisonResult? r, {
    String emptyHint = 'ไม่มีข้อมูลพอเทียบ',
    bool fullWidth = false,
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
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (r == null)
            // โชว์ "progress" ว่าต้องเก็บข้อมูลเพิ่มอีกแค่ไหนถึงจะเทียบได้
            // แทนข้อความเฉยๆ ว่าไม่มีข้อมูล ให้ผู้ใช้ใหม่รู้ว่าต้องรออะไร
            Text(emptyHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (r.isUnchanged)
                  const Row(
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
                else
                  Row(
                    children: [
                      Icon(
                        r.isIncrease
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                        color: r.isIncrease ? Colors.red : _green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        r.percentChange == null
                            ? '${_fmt.format(r.diff.abs())} บาท'
                            : '${r.percentChange!.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: r.isIncrease ? Colors.red : _green,
                        ),
                      ),
                    ],
                  ),
                if (fullWidth) ...[
                  const Spacer(),
                  Text('เฉลี่ย ${_fmt.format(r.previousValue)} บาท',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _forecastCard(double forecast) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, color: _green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // เปลี่ยนชื่อให้ชัดว่าเป็นแนวโน้ม "ระยะยาว" (Linear Regression
                // จากบิลย้อนหลังทั้งหมด) ต่างจากการ์ดด้านบนที่พยากรณ์แค่รอบนี้
                const Text('แนวโน้มระยะยาว (เดือนถัดไป)',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('${_fmt.format(forecast)} บาท',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _green)),
              ],
            ),
          ),
          const Text('(Linear Regression\nจากบิลย้อนหลัง)',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, color: Colors.grey)),
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
                      child: Text(i.text,
                          style: const TextStyle(fontSize: 12.5, height: 1.4)),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('ยังไม่มีอุปกรณ์ที่ตั้งตารางการใช้งาน',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
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
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 220,
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
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: List.generate(breakdown.length, (i) {
                      final u = breakdown[i];
                      return PieChartSectionData(
                        value: u.kWh,
                        color: colors[i % colors.length],
                        title: '${u.percentOfTotal.toStringAsFixed(0)}%',
                        radius: 60,
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
        ...List.generate(breakdown.length, (i) {
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
                  backgroundColor: colors[i % colors.length].withOpacity(0.15),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: colors[i % colors.length],
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
                          '${u.kWh.toStringAsFixed(1)} kWh • ${_fmt.format(u.cost)} บาท',
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
        const SizedBox(height: 8),
        Text(
          '* เป็นค่าประมาณการจากกำลังไฟ (วัตต์) × ชั่วโมงที่ตั้งไว้ ไม่ใช่ค่าจากมิเตอร์จริงรายอุปกรณ์ '
          'และใช้อัตราเฉลี่ย 4.5 บาท/หน่วย จึงอาจไม่ตรงกับยอดบิลจริงที่คิดตามอัตราขั้นบันได',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
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
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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