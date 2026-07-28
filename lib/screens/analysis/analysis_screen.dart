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

part 'analysis_appliance_tab.dart'; // แท็บอุปกรณ์ — พาย์ชาร์ต + อันดับอุปกรณ์กินไฟ
part 'analysis_trend_chart.dart'; // การ์ดกราฟเทรนด์ค่าใช้จ่าย/หน่วยที่ใช้ (สลับมุมมองได้)
part 'analysis_utility_tab.dart'; // แท็บไฟฟ้า/น้ำ — สรุปรอบปัจจุบัน, กราฟเทรนด์, การเปรียบเทียบ/พยากรณ์

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

  static const _green = DashboardStyles.primaryGreen;

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
      backgroundColor: DashboardStyles.background,
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