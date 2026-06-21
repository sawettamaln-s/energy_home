import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/appliance_model.dart';
import '../../models/bill_model.dart';
import '../../services/analysis_service.dart';
import '../../services/firestore_service.dart';
import '../appliance/appliance_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';

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
  bool _isLoading = true;

  static const _green = Color(0xFF2E7D32);
  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

Future<void> _loadData() async {
  setState(() => _isLoading = true);
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    debugPrint('🔵 uid: $uid');

    final bills = await _analysisService.fetchBills(uid);
    debugPrint('🔵 bills: ${bills.length}');
    
    _firestoreService.getAppliances(uid).listen((data) {
      setState(() => _appliances = data);
    });

    setState(() {
      _bills = bills;
      _isLoading = false;
    });
  } catch (e) {
    debugPrint('🔴 ERROR: $e');
    setState(() => _isLoading = false);
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
          : _bills.isEmpty
              ? _emptyState('ยังไม่มีข้อมูลบิลให้วิเคราะห์')
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _UtilityTab(
                      bills: _bills,
                      analysisService: _analysisService,
                      selector: (b) => b.electricityCost,
                      unitSelector: (b) => b.electricityUsed,
                      unitLabel: 'หน่วย',
                      title: 'ค่าไฟฟ้า',
                    ),
                    _UtilityTab(
                      bills: _bills,
                      analysisService: _analysisService,
                      selector: (b) => b.waterCost,
                      unitSelector: (b) => b.waterUsed,
                      unitLabel: 'หน่วย',
                      title: 'ค่าน้ำ',
                    ),
                    _ApplianceTab(
                      appliances: _appliances,
                      analysisService: _analysisService,
                    ),
                  ],
                ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: _green,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 1) return;
          if (index == 0) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()));
          } else if (index == 2) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const ApplianceScreen()));
          } else if (index == 3) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'หน้าหลัก'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'วิเคราะห์'),
          BottomNavigationBarItem(
              icon: Icon(Icons.electrical_services), label: 'อุปกรณ์'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
        ],
      ),
    );
  }

  Widget _emptyState(String text) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}

// ==================== Tab ไฟฟ้า / น้ำ ====================
class _UtilityTab extends StatelessWidget {
  final List<BillModel> bills;
  final AnalysisService analysisService;
  final double Function(BillModel) selector; // ค่าใช้จ่าย (บาท)
  final double Function(BillModel) unitSelector; // หน่วยที่ใช้
  final String unitLabel;
  final String title;

  static const _green = Color(0xFF2E7D32);
  final _fmt = NumberFormat('#,##0.00');

  _UtilityTab({
    required this.bills,
    required this.analysisService,
    required this.selector,
    required this.unitSelector,
    required this.unitLabel,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final mom = analysisService.compareMoM(bills, selector: selector);
    final yoy = analysisService.compareYoY(bills, selector: selector);
    final forecast =
        analysisService.forecastNextMonth(bills, selector: selector);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _trendChart(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _comparisonCard('เทียบเดือนก่อน', mom)),
            const SizedBox(width: 10),
            Expanded(child: _comparisonCard('เทียบปีก่อน (เดือนเดียวกัน)', yoy)),
          ],
        ),
        const SizedBox(height: 10),
        _forecastCard(forecast),
      ],
    );
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          Expanded(
            child: spots.length < 2
                ? const Center(
                    child: Text('ข้อมูลยังไม่พอแสดงกราฟ (ต้องมีอย่างน้อย 2 เดือน)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)))
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
                              return Text('${bills[i].month}/${bills[i].year % 100}',
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

  Widget _comparisonCard(String label, ComparisonResult? r) {
    final hasData = r != null;
    final isUp = hasData && r.isIncrease;
    final pct = hasData ? r.percentChange : null;

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
          if (!hasData)
            const Text('ไม่มีข้อมูลพอเทียบ',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            Row(
              children: [
                Icon(
                  isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isUp ? Colors.red : _green,
                ),
                const SizedBox(width: 4),
                Text(
                  pct == null ? '฿${_fmt.format(r.diff.abs())}' : '${pct.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isUp ? Colors.red : _green,
                  ),
                ),
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
                const Text('คาดการณ์เดือนถัดไป',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('฿${_fmt.format(forecast)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18, color: _green)),
              ],
            ),
          ),
          const Text('(เฉลี่ย 3 เดือนล่าสุด)',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
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
                          '${u.kWh.toStringAsFixed(1)} kWh • ฿${_fmt.format(u.cost)}',
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
          '* เป็นค่าประมาณการจากกำลังไฟ (วัตต์) × ชั่วโมงที่ตั้งไว้ ไม่ใช่ค่าจากมิเตอร์จริงรายอุปกรณ์',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}