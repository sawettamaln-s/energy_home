import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/appliance_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/appliance_rate.dart';
import '../../utils/data_refresh_bus.dart';
import '../../utils/default_appliances.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_dialog.dart';
import '../dashboard/dashboard_styles.dart';

part 'appliance_form_sheet.dart'; // ฟอร์มเพิ่ม/แก้ไขเครื่องใช้ไฟฟ้า

// แปลง DefaultAppliance.icon (string ที่เก็บไว้ในโมเดล เช่น 'shower', 'iron')
// เป็น IconData จริงเพื่อใช้ในลิสต์ "เลือกจากรายการสามัญประจำบ้าน" ให้แยก
// เครื่องใช้ไฟฟ้าแต่ละชนิดออกจากกันได้จากไอคอน ไม่ต้องอ่านชื่ออย่างเดียว
//
// เลือกแมปเฉพาะ key ที่มั่นใจว่ามีไอคอนนี้จริงในชุด Icons มาตรฐานของ Flutter
// เท่านั้น — 'hair_dryer' ยังไม่แมป (ไม่มั่นใจว่ามีไอคอนนี้แน่ๆ ในทุกเวอร์ชัน
// SDK) เลยปล่อยให้ตกไปใช้ default ด้านล่างแทนการเดาชื่อ Icons.* ที่อาจไม่มี
// จริงแล้วคอมไพล์ไม่ผ่าน
IconData _defaultApplianceIcon(String key) {
  switch (key) {
    case 'shower':
      return Icons.shower;
    case 'iron':
      return Icons.iron;
    case 'ac_unit':
      return Icons.ac_unit;
    case 'local_laundry_service':
      return Icons.local_laundry_service;
    case 'kitchen':
      return Icons.kitchen;
    case 'rice_bowl':
      return Icons.rice_bowl;
    case 'microwave':
      return Icons.microwave;
    case 'mode_fan_off':
      return Icons.mode_fan_off;
    default:
      return Icons.electrical_services;
  }
}

// key ไอคอนของรายการสามัญประจำบ้านที่ชื่อตรงกับ [name] (ไม่เจอ = null)
String? _defaultIconKeyForName(String name) {
  for (final d in DefaultAppliances.list) {
    if (d.name == name) return d.icon;
  }
  return null;
}

// ไอคอนของเครื่องใช้ไฟฟ้าที่บันทึกแล้วในลิสต์ — ใช้ชุดเดียวกับหน้าเลือกจากรายการ
// สามัญประจำบ้าน: ใช้ iconKey ที่เก็บไว้ตอนเลือก (เปลี่ยนชื่อทีหลังไอคอนก็ยังเดิม)
// ข้อมูลเก่าที่ยังไม่มี iconKey ลองจับคู่จากชื่อ ส่วนอุปกรณ์ที่เพิ่มเอง
// ตกไปใช้ไอคอนเริ่มต้น
IconData _applianceIcon(ApplianceModel a) =>
    _defaultApplianceIcon(a.iconKey ?? _defaultIconKeyForName(a.name) ?? '');

class ApplianceScreen extends StatefulWidget {
  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  final ValueChanged<int>? onNavTap;

  const ApplianceScreen({super.key, this.onNavTap});

  @override
  State<ApplianceScreen> createState() => _ApplianceScreenState();
}

class _ApplianceScreenState extends State<ApplianceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<ApplianceModel> _appliances = [];
  bool _isLoading = true;
  // อัตราค่าไฟต่อหน่วยที่ใช้ประมาณค่าไฟของอุปกรณ์ — จากบิลล่าสุดของผู้ใช้
  // (ดู ApplianceRate) โหลดใหม่เมื่อบิลเปลี่ยนผ่าน DataRefreshBus
  ApplianceRate _rate = ApplianceRate.fallback;

// เก็บ subscription ของ stream อุปกรณ์ไว้ เพื่อ cancel ตอน dispose
// ป้องกัน setState หลัง widget dispose ไปแล้ว (memory leak / error ตอนสลับแท็บบ่อยๆ)
  StreamSubscription<List<ApplianceModel>>? _applianceSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadRate();
    DataRefreshBus.instance.version.addListener(_loadRate);
  }

  @override
  void dispose() {
    DataRefreshBus.instance.version.removeListener(_loadRate);
    _applianceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final bills = await _firestoreService.getBills(uid);
      if (mounted) setState(() => _rate = ApplianceRate.fromBills(bills));
    } catch (_) {
      // โหลดบิลไม่ได้ ใช้อัตราเดิมต่อไป (ค่าเริ่มต้นคือค่าเฉลี่ยประมาณการ)
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _applianceSub?.cancel();
    _applianceSub = _firestoreService.getAppliances(uid).listen((data) {
      if (!mounted) return;
      setState(() {
        _appliances = data;
        _isLoading = false;
      });
    });
  }

  // คำนวณ kWh รวมของอุปกรณ์ในช่วง totalDaysInPeriod วัน (30 = เดือน, 365 = ปี)
  // คิดตามจำนวนวัน/สัปดาห์ที่ตั้งไว้จริงในแต่ละ schedule (ไม่ใช่ทุกวันเสมอ)
  double _kWhForPeriod(ApplianceModel a, int totalDaysInPeriod) {
    double kWh = 0;
    for (final s in a.schedules) {
      final activeDays = (s.days.length / 7) * totalDaysInPeriod;
      kWh += (a.watt * s.hoursPerDay / 1000) * activeDays;
    }
    return kWh;
  }

  // ค่าไฟเฉพาะวันที่ใช้งานจริง (ไม่เฉลี่ยรวมวันที่ไม่ได้ใช้)
  double _costPerActiveDay(ApplianceModel a) {
    double kWh = 0;
    for (final s in a.schedules) {
      kWh += (a.watt * s.hoursPerDay) / 1000;
    }
    return kWh * _rate.perUnit;
  }

  // ทุกตัวเลขในไฟล์ใช้อัตราเดียวกัน (_rate) — ดู ApplianceRate
  double _estimateApplianceMonthlyCost(ApplianceModel a) =>
      _kWhForPeriod(a, 30) * _rate.perUnit;

  double _estimateApplianceYearlyCost(ApplianceModel a) =>
      _kWhForPeriod(a, 365) * _rate.perUnit;

  double get _totalMonthlyCost {
    double total = 0;
    for (var a in _appliances) {
      if (a.schedules.isNotEmpty) {
        total += _estimateApplianceMonthlyCost(a);
      }
    }
    return total;
  }

  // ค่าเฉลี่ยชั่วโมงการใช้งานต่อวัน (เฉลี่ยจาก hoursPerDay ของทุกอุปกรณ์)
  double get _avgHoursPerDay {
    if (_appliances.isEmpty) return 0;
    final total = _appliances.fold<double>(
      0,
      (sum, a) =>
          sum + (a.schedules.isNotEmpty ? a.schedules.first.hoursPerDay : 0),
    );
    return total / _appliances.length;
  }

  // สีของแถบตารางการใช้งาน ไล่ตามชั่วโมง/วันที่ใช้จริง เพื่อให้เห็นความ
  // หนักเบาของแต่ละอุปกรณ์ได้ไวๆ โดยไม่ต้องอ่านตัวเลข
  // <=5 ชม. เขียว (เบา) | <=10 ชม. เหลือง | <=15 ชม. ส้ม | >15 ชม. แดง (หนัก)
  Color _scheduleBgColor(double hoursPerDay) {
    if (hoursPerDay <= 5) return AppColors.softGreenBg;
    if (hoursPerDay <= 10) return AppColors.softAmberBg;
    if (hoursPerDay <= 15) return AppColors.softOrangeBg;
    return AppColors.softRedBg;
  }

  Color _scheduleFgColor(double hoursPerDay) {
    if (hoursPerDay <= 5) return DashboardStyles.primaryGreen;
    if (hoursPerDay <= 10) return AppColors.levelMedium;
    if (hoursPerDay <= 15) return AppColors.levelHigh;
    return AppColors.levelVeryHigh;
  }

  // สรุปตารางการใช้งานเป็นข้อความสั้นๆ จากข้อมูลที่มีจริง (days + จำนวนชม./วัน)
  // หมายเหตุ: ฟอร์มเพิ่ม/แก้ไขอุปกรณ์ไม่มีช่องกรอก "เวลาเริ่มใช้งาน" จึงไม่แสดง
  // เป็นช่วงเวลา (เช่น 00:00-08:00) เพราะนั่นจะเป็นข้อมูลที่ผู้ใช้ไม่ได้กรอกจริง
  String _scheduleSummary(ApplianceModel a) {
    if (a.schedules.isEmpty) return 'ยังไม่ได้ตั้งตารางการใช้งาน';
    final s = a.schedules.first;
    final daysLabel = _daysLabel(s.days);
    return '$daysLabel ใช้วันละ ${_durationLabel(s.hoursPerDay)}';
  }

  // แปลงชั่วโมงแบบทศนิยม (เช่น 0.25) ให้เป็นข้อความที่อ่านง่าย
  // เช่น 0.25 ชม. -> '15 นาที', 1.5 ชม. -> '1 ชม. 30 นาที'
  String _durationLabel(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h == 0) return '$m นาที';
    if (m == 0) return '$h ชม.';
    return '$h ชม. $m นาที';
  }

  String _daysLabel(List<int> days) {
    if (days.length >= 7) return 'ทุกวัน';
    final sorted = [...days]..sort();
    return sorted.map((d) => thaiWeekdaysShort[d % 7]).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'อุปกรณ์', showBack: false),
      floatingActionButton: FloatingActionButton(
        backgroundColor: DashboardStyles.primaryGreen,
        onPressed: _showAddApplianceSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DashboardStyles.primaryGreen))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: DashboardStyles.primaryGreen,
              child: Column(
              children: [
                // ---- สรุปยอด 3 ช่อง ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _summaryBox(
                          label: 'อุปกรณ์ทั้งหมด',
                          value: '${_appliances.length} ชิ้น',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryBox(
                          label: 'เฉลี่ย ชม./วัน',
                          value: _durationLabel(_avgHoursPerDay),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryBox(
                          label: 'ค่าไฟ/เดือน',
                          value: '${formatter.format(_totalMonthlyCost)} บาท',
                          valueColor: DashboardStyles.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),

                // ---- อัตราที่ใช้คำนวณ (กดดูที่มาได้) ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.v16, 0, AppSpacing.v16, AppSpacing.v8),
                  child: InkWell(
                    onTap: () =>
                        showApplianceEstimateInfoDialog(context, rate: _rate),
                    borderRadius: BorderRadius.circular(AppSpacing.v8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _rate.isFromBill
                                ? 'คิดจากอัตราเฉลี่ยบิลล่าสุดของคุณ '
                                    '${_rate.perUnit.toStringAsFixed(2)} บาท/หน่วย'
                                : 'คิดจากอัตราเฉลี่ยประมาณการ '
                                    '${_rate.perUnit.toStringAsFixed(2)} บาท/หน่วย',
                            style: TextStyle(
                                fontSize: AppTypography.s11_5,
                                color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- รายการอุปกรณ์ ----
                Expanded(
                  child: _appliances.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.devices_other,
                                          size: 64,
                                          color: Colors.grey.shade300),
                                      const SizedBox(height: 12),
                                      const Text('ยังไม่มีเครื่องใช้ไฟฟ้า',
                                          style:
                                              TextStyle(color: Colors.grey)),
                                      const SizedBox(height: 4),
                                      const Text('กดปุ่ม + เพื่อเพิ่มรายการ',
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: AppTypography.s12)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v4, AppSpacing.v16, AppSpacing.v16),
                          itemCount: _appliances.length,
                          itemBuilder: (context, index) {
                            final a = _appliances[index];
                            double monthlyCost =
                                _estimateApplianceMonthlyCost(a);
                            final hasSchedule = a.schedules.isNotEmpty;

                            return Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.v12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppSpacing.v14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withValues(alpha: 0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(AppSpacing.v14),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(AppSpacing.v10),
                                          decoration: BoxDecoration(
                                            color: DashboardStyles.primaryGreen
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(AppSpacing.v10),
                                          ),
                                          child: Icon(_applianceIcon(a),
                                              color: DashboardStyles.primaryGreen),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(a.name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: AppTypography.s15)),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${a.watt.toStringAsFixed(0)} วัตต์ • ${formatter.format(monthlyCost)} บาท/เดือน',
                                                style: TextStyle(
                                                    fontSize: AppTypography.s12,
                                                    color:
                                                        Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.red, size: 20),
                                          onPressed: () => _confirmDelete(a),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.v14, vertical: AppSpacing.v8),
                                    decoration: BoxDecoration(
                                      color: hasSchedule
                                          ? _scheduleBgColor(
                                              a.schedules.first.hoursPerDay)
                                          : Colors.grey.shade100,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasSchedule
                                              ? Icons.schedule
                                              : Icons.schedule_outlined,
                                          size: 14,
                                          color: hasSchedule
                                              ? _scheduleFgColor(
                                                  a.schedules.first.hoursPerDay)
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _scheduleSummary(a),
                                            style: TextStyle(
                                              fontSize: AppTypography.s11,
                                              color: hasSchedule
                                                  ? _scheduleFgColor(a
                                                      .schedules
                                                      .first
                                                      .hoursPerDay)
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(AppSpacing.v14)),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _showDetailSheet(a),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: AppSpacing.v11),
                                              child: Center(
                                                child: Text(
                                                  'ดูข้อมูล',
                                                  style: TextStyle(
                                                    fontSize: AppTypography.s12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.textDark,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 20,
                                          color: Colors.grey.shade200,
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                _showEditApplianceSheet(a),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: AppSpacing.v11),
                                              child: Center(
                                                child: Text(
                                                  'แก้ไข',
                                                  style: TextStyle(
                                                    fontSize: AppTypography.s12,
                                                    fontWeight: FontWeight.w600,
                                                    color: DashboardStyles.primaryGreen,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            ),
      bottomNavigationBar:
          AppBottomNavBar(currentIndex: 2, onTap: widget.onNavTap),
    );
  }

Widget _summaryBox({
  required String label,
  required String value,
  Color? valueColor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.v12, horizontal: AppSpacing.v8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.v12),
      border: Border.all(
        color: DashboardStyles.primaryGreen.withValues(alpha: 0.25),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTypography.s15,
            color: valueColor ?? AppColors.textDark,
          ),
        ),
      ],
    ),
  );
}
 
Future<void> _confirmDelete(ApplianceModel a) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'ลบอุปกรณ์',
      content: 'ต้องการลบ "${a.name}" ใช่ไหมคะ',
    );
    if (confirm == true) {
      await _firestoreService.deleteAppliance(a.uid, a.id);
    }
  }

  // Bottom sheet เลือกเพิ่มอุปกรณ์
  void _showAddApplianceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddApplianceSheet(
        firestoreService: _firestoreService,
        onAdded: _loadData,
        rate: _rate,
      ),
    );
  }

  // Bottom sheet แก้ไขอุปกรณ์ที่มีอยู่แล้ว (ใช้ชีตเดียวกัน ส่ง existing ไปพรีฟิล)
  void _showEditApplianceSheet(ApplianceModel a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddApplianceSheet(
        firestoreService: _firestoreService,
        onAdded: _loadData,
        rate: _rate,
        existing: a,
      ),
    );
  }

  // Bottom sheet ดูข้อมูล/รายละเอียดค่าไฟของอุปกรณ์ (ต่อวัน/เดือน/ปี/เฉลี่ย)
  void _showDetailSheet(ApplianceModel a) {
    final formatter = NumberFormat('#,##0.00');
    final hasSchedule = a.schedules.isNotEmpty;
    final costPerActiveDay = _costPerActiveDay(a);
    final costPerMonth = _estimateApplianceMonthlyCost(a);
    final costPerYear = _estimateApplianceYearlyCost(a);
    final avgCostPerDay = costPerMonth / 30;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppSpacing.v20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.v20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.v16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(AppSpacing.v2),
                ),
              ),
            ),
            Text(a.name,
                style:
                    const TextStyle(fontSize: AppTypography.s18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              '${a.watt.toStringAsFixed(0)} วัตต์'
              '${hasSchedule ? ' • ${_scheduleSummary(a)}' : ''}',
              style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (!hasSchedule)
              Text(
                'อุปกรณ์นี้ยังไม่ได้ตั้งตารางการใช้งาน จึงยังไม่มีตัวเลขประมาณการค่าไฟ',
                style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _detailBox('ต่อวันที่ใช้งาน',
                        '${formatter.format(costPerActiveDay)} บาท'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _detailBox('เฉลี่ย/วัน (ทั้งเดือน)',
                        '${formatter.format(avgCostPerDay)} บาท'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _detailBox(
                        'ต่อเดือน', '${formatter.format(costPerMonth)} บาท'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _detailBox(
                        'ต่อปี', '${formatter.format(costPerYear)} บาท'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: AppColors.softGreenBg,
        borderRadius: BorderRadius.circular(AppSpacing.v10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTypography.s15,
                  color: DashboardStyles.primaryGreen)),
        ],
      ),
    );
  }
}
