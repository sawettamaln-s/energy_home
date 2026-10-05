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
import '../../widgets/ui/animated_amount.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/fade_slide_in.dart';
import '../../widgets/ui/icon_badge.dart';
import '../dashboard/dashboard_styles.dart';

part 'appliance_form_sheet.dart'; // ฟอร์มเพิ่ม/แก้ไขเครื่องใช้ไฟฟ้า

// แปลง DefaultAppliance.icon (key ที่เก็บไว้ในโมเดล เช่น 'shower', 'iron') เป็น
// IconData — ใช้ทั้งในตารางเลือกอุปกรณ์และรายการที่บันทึกแล้ว key ที่ไม่รู้จัก
// (อุปกรณ์ที่เพิ่มเอง) ใช้ไอคอนปลั๊กไฟ
IconData _defaultApplianceIcon(String key) {
  switch (key) {
    case 'shower':
      return Icons.shower_rounded;
    case 'iron':
      return Icons.iron_rounded;
    case 'hair_dryer':
      return Icons.dry_rounded;
    case 'ac_unit':
      return Icons.ac_unit_rounded;
    case 'local_laundry_service':
      return Icons.local_laundry_service_rounded;
    case 'kitchen':
      return Icons.kitchen_rounded;
    case 'rice_bowl':
      return Icons.rice_bowl_rounded;
    case 'microwave':
      return Icons.microwave_rounded;
    case 'mode_fan_off':
      return Icons.air_rounded;
    default:
      return Icons.electrical_services_rounded;
  }
}

// รายการสามัญประจำบ้านที่ชื่อตรงกับ [name] (ไม่เจอ = null)
DefaultAppliance? _defaultForName(String name) {
  for (final d in DefaultAppliances.list) {
    if (d.name == name) return d;
  }
  return null;
}

// key ไอคอนของรายการสามัญประจำบ้านที่ชื่อตรงกับ [name] (ไม่เจอ = null)
String? _defaultIconKeyForName(String name) => _defaultForName(name)?.icon;

// ไอคอนของเครื่องใช้ไฟฟ้าที่บันทึกแล้ว: ใช้ iconKey ที่เก็บไว้ตอนเลือก (เปลี่ยนชื่อ
// ทีหลังไอคอนก็ยังเดิม) ข้อมูลเก่าที่ยังไม่มี iconKey ลองจับคู่จากชื่อ
IconData _applianceIcon(ApplianceModel a) =>
    _defaultApplianceIcon(a.iconKey ?? _defaultIconKeyForName(a.name) ?? '');

// ยอดเงินในหน้านี้เป็นค่าประมาณทั้งหมด แสดงเป็นบาทเต็ม
final _bahtFmt = NumberFormat('#,##0');
final _wattFmt = NumberFormat('#,##0');

// แปลงชั่วโมงแบบทศนิยมเป็นข้อความ เช่น 0.25 -> '15 นาที', 1.5 -> '1 ชม. 30 นาที'
String _durationLabel(double hours) {
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  if (h == 0) return '$m นาที';
  if (m == 0) return '$h ชม.';
  return '$h ชม. $m นาที';
}

// วันที่ใช้งาน เช่น 'ทุกวัน', 'จ–ศ', 'ส–อา', 'จ พ ศ'
String _daysLabel(Iterable<int> days) {
  final set = days.toSet();
  if (set.length >= 7) return 'ทุกวัน';
  if (set.length == 5 && set.containsAll(const [0, 1, 2, 3, 4])) return 'จ–ศ';
  if (set.length == 2 && set.containsAll(const [5, 6])) return 'ส–อา';
  final sorted = set.toList()..sort();
  return sorted.map((d) => thaiWeekdaysShort[d % 7]).join(' ');
}

class ApplianceScreen extends StatefulWidget {
  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  final ValueChanged<int>? onNavTap;
  // ฉีดของปลอมได้ในเทส — ไม่ส่ง = ใช้ instance จริงของ Firebase
  final FirestoreService? firestoreService;
  final FirebaseAuth? auth;

  const ApplianceScreen({super.key, this.onNavTap, this.firestoreService, this.auth});

  @override
  State<ApplianceScreen> createState() => _ApplianceScreenState();
}

class _ApplianceScreenState extends State<ApplianceScreen> {
  late final FirestoreService _firestoreService = widget.firestoreService ?? FirestoreService();
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  List<ApplianceModel> _appliances = [];
  bool _isLoading = true;
  // อัตราค่าไฟต่อหน่วยที่ใช้ประมาณค่าไฟของอุปกรณ์ — จากบิลล่าสุดของผู้ใช้
  // (ดู ApplianceRate) โหลดใหม่เมื่อบิลเปลี่ยนผ่าน DataRefreshBus
  ApplianceRate _rate = ApplianceRate.fallback;

  // เก็บ subscription ของ stream อุปกรณ์ไว้ cancel ตอน dispose กัน setState
  // หลัง widget ถูกถอดออก
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
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final bills = await _firestoreService.getBills(uid);
      if (mounted) setState(() => _rate = ApplianceRate.fromBills(bills));
    } catch (_) {
      // โหลดบิลไม่ได้ ใช้อัตราเดิมต่อไป (ค่าเริ่มต้นคือค่าเฉลี่ยประมาณการ)
    }
  }

  // สมัครฟัง stream อุปกรณ์ใหม่ (ตอนเปิดหน้าและตอนดึงลงเพื่อรีเฟรช) — รายการเดิม
  // ยังอยู่บนจอระหว่างรอ (วงโหลดเต็มจอมีแค่ครั้งแรก) Future จบเมื่อได้ข้อมูลชุดแรก
  // การเพิ่ม/แก้/ลบไม่ต้องเรียกซ้ำ เพราะ stream ส่งรายการใหม่มาเอง
  Future<void> _loadData() async {
    final uid = _auth.currentUser!.uid;
    final firstEvent = Completer<void>();
    await _applianceSub?.cancel();
    _applianceSub = _firestoreService.getAppliances(uid).listen((data) {
      if (!firstEvent.isCompleted) firstEvent.complete();
      if (!mounted) return;
      setState(() {
        _appliances = data;
        _isLoading = false;
      });
    }, onError: (Object _) {
      if (!firstEvent.isCompleted) firstEvent.complete();
      if (mounted) setState(() => _isLoading = false);
    });
    return firstEvent.future;
  }

  // kWh รวมของอุปกรณ์ในช่วง totalDaysInPeriod วัน (30 = เดือน, 365 = ปี)
  // คิดตามจำนวนวัน/สัปดาห์ที่ตั้งไว้จริงในแต่ละ schedule (ไม่ใช่ทุกวันเสมอ)
  double _kWhForPeriod(ApplianceModel a, int totalDaysInPeriod) {
    double kWh = 0;
    for (final s in a.schedules) {
      final activeDays = (s.days.length / 7) * totalDaysInPeriod;
      kWh += (a.watt * s.hoursPerDay / 1000) * activeDays;
    }
    return kWh;
  }

  // หน่วยที่ใช้ต่อวันที่เปิดใช้งาน (ไม่เฉลี่ยรวมวันที่ไม่ได้ใช้)
  double _kWhPerActiveDay(ApplianceModel a) {
    double kWh = 0;
    for (final s in a.schedules) {
      kWh += (a.watt * s.hoursPerDay) / 1000;
    }
    return kWh;
  }

  // ทุกตัวเลขในไฟล์ใช้อัตราเดียวกัน (_rate) — ดู ApplianceRate
  double _monthlyCost(ApplianceModel a) => _kWhForPeriod(a, 30) * _rate.perUnit;

  double _yearlyCost(ApplianceModel a) => _kWhForPeriod(a, 365) * _rate.perUnit;

  double get _totalMonthlyCost =>
      _appliances.where((a) => a.schedules.isNotEmpty).fold(0.0, (sum, a) => sum + _monthlyCost(a));

  // สีของชิปเวลาใช้งาน ไล่ตามชั่วโมง/วัน ให้เห็นความหนักเบาโดยไม่ต้องอ่านตัวเลข
  // <=5 ชม. เขียว (เบา) | <=10 ชม. เหลือง | <=15 ชม. ส้ม | >15 ชม. แดง (หนัก)
  static Color _levelColor(double hoursPerDay) {
    if (hoursPerDay <= 5) return DashboardStyles.primaryGreen;
    if (hoursPerDay <= 10) return AppColors.levelMedium;
    if (hoursPerDay <= 15) return AppColors.levelHigh;
    return AppColors.levelVeryHigh;
  }

  // สรุปตารางการใช้งานจากข้อมูลที่ผู้ใช้กรอกจริง (วัน + ชม./วัน) ฟอร์มไม่มีช่อง
  // "เวลาเริ่มใช้งาน" จึงไม่แสดงเป็นช่วงเวลา (เช่น 00:00-08:00)
  String _scheduleSummary(ApplianceModel a) {
    if (a.schedules.isEmpty) return 'ยังไม่ได้ตั้งเวลาใช้งาน';
    final s = a.schedules.first;
    return '${_daysLabel(s.days)} · วันละ ${_durationLabel(s.hoursPerDay)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'อุปกรณ์', showBack: false),
      floatingActionButton: _appliances.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddApplianceSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('เพิ่มอุปกรณ์',
                  style: TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w600)),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _appliances.isEmpty ? _buildEmptyState() : _buildList(),
            ),
      bottomNavigationBar: AppBottomNavBar(currentIndex: 2, onTap: widget.onNavTap),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.v32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconBadge(icon: Icons.electrical_services_rounded, color: AppColors.primaryGreen, size: 72),
                  const SizedBox(height: AppSpacing.v18),
                  const Text('ยังไม่มีเครื่องใช้ไฟฟ้า',
                      style: TextStyle(
                          fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: AppSpacing.v6),
                  Text(
                    'เพิ่มเครื่องใช้ไฟฟ้าและเวลาที่ใช้ เพื่อดูว่าแต่ละเครื่องกินไฟเดือนละเท่าไรค่ะ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppTypography.s13, height: 1.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: AppSpacing.v20),
                  ElevatedButton.icon(
                    onPressed: _showAddApplianceSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('เพิ่มอุปกรณ์ชิ้นแรก'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // เว้นด้านล่างให้ปุ่มเพิ่มอุปกรณ์ไม่บังการ์ดใบสุดท้าย
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, 96),
      children: [
        FadeSlideIn(child: _buildSummaryCard()),
        const SizedBox(height: AppSpacing.v20),
        Row(
          children: [
            const Flexible(
              child: Text('รายการอุปกรณ์',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: DashboardStyles.sectionTitle),
            ),
            const SizedBox(width: AppSpacing.v6),
            Text('(${_appliances.length})',
                style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: AppSpacing.v10),
        for (final (i, a) in _appliances.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.v10),
          FadeSlideIn(
            delay: Duration(milliseconds: 60 + 40 * (i < 6 ? i : 6)),
            child: _buildApplianceCard(a),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.bolt_rounded, color: AppColors.primaryGreen, size: 34),
              const SizedBox(width: AppSpacing.v10),
              const Expanded(
                child: Text('ค่าไฟจากอุปกรณ์ที่บันทึกไว้',
                    style: TextStyle(
                        fontSize: AppTypography.s14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
              IconButton(
                onPressed: () => showApplianceEstimateInfoDialog(context, rate: _rate),
                tooltip: 'คำอธิบาย',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.v4),
                child: Text('ประมาณ', style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade700)),
              ),
              const SizedBox(width: AppSpacing.v6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedAmount(
                    value: _totalMonthlyCost.roundToDouble(),
                    pattern: '#,##0',
                    suffix: ' บาท/เดือน',
                    style: const TextStyle(
                        fontSize: AppTypography.s26, fontWeight: FontWeight.w700, color: AppColors.primaryGreen),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v6),
          Text(
            '${_appliances.length} รายการ · คิดที่ ${_rate.perUnit.toStringAsFixed(2)} บาท/หน่วย '
            '${_rate.isFromBill ? '(จากบิลล่าสุดของคุณ)' : '(ค่าเฉลี่ยประมาณการ)'}',
            style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // การ์ดอุปกรณ์ 1 รายการ — กดทั้งการ์ดเพื่อดูรายละเอียด (มีปุ่มแก้ไข/ลบในนั้น)
  Widget _buildApplianceCard(ApplianceModel a) {
    final hasSchedule = a.schedules.isNotEmpty;
    final hours = hasSchedule ? a.schedules.first.hoursPerDay : 0.0;
    final level = _levelColor(hours);
    return AppCard(
      onTap: () => _showDetailSheet(a),
      padding: const EdgeInsets.all(AppSpacing.v14),
      child: Row(
        children: [
          IconBadge(icon: _applianceIcon(a), color: AppColors.primaryGreen, size: 46),
          const SizedBox(width: AppSpacing.v12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTypography.s14_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                const SizedBox(height: AppSpacing.v4),
                Wrap(
                  spacing: AppSpacing.v6,
                  runSpacing: AppSpacing.v4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _chip(
                      hasSchedule ? _scheduleSummary(a) : 'ยังไม่ได้ตั้งเวลาใช้งาน',
                      color: hasSchedule ? level : Colors.grey.shade600,
                    ),
                    Text('${_wattFmt.format(a.watt)} วัตต์',
                        style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.v10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hasSchedule ? _bahtFmt.format(_monthlyCost(a)) : '–',
                  style: const TextStyle(
                      fontSize: AppTypography.s17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Text('บาท/เดือน', style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8, vertical: AppSpacing.v2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.v20),
      ),
      child: Text(text,
          style: TextStyle(fontSize: AppTypography.s11_5, fontWeight: FontWeight.w500, color: color)),
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

  void _showAddApplianceSheet() => _openFormSheet();

  void _showEditApplianceSheet(ApplianceModel a) => _openFormSheet(existing: a);

  // ฟอร์มเพิ่ม/แก้ไขอุปกรณ์ (ชีตเดียวกัน ส่ง existing ไปพรีฟิลเมื่อแก้ไข)
  void _openFormSheet({ApplianceModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddApplianceSheet(
        uid: _auth.currentUser!.uid,
        firestoreService: _firestoreService,
        rate: _rate,
        existing: existing,
      ),
    );
  }

  // รายละเอียดค่าไฟของอุปกรณ์ (เดือน/ปี/วัน) พร้อมปุ่มแก้ไขและลบ
  void _showDetailSheet(ApplianceModel a) {
    final hasSchedule = a.schedules.isNotEmpty;
    final kWhPerActiveDay = _kWhPerActiveDay(a);
    final costPerMonth = _monthlyCost(a);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v10, AppSpacing.v20, AppSpacing.v16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: AppSpacing.v14),
              Row(
                children: [
                  IconBadge(icon: _applianceIcon(a), color: AppColors.primaryGreen, size: 48),
                  const SizedBox(width: AppSpacing.v12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                        const SizedBox(height: AppSpacing.v2),
                        Text('${_wattFmt.format(a.watt)} วัตต์ · ${_scheduleSummary(a)}',
                            style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.v16),
              if (!hasSchedule)
                Text('อุปกรณ์นี้ยังไม่ได้ตั้งเวลาใช้งาน จึงยังประมาณค่าไฟไม่ได้ กด "แก้ไข" เพื่อตั้งเวลาค่ะ',
                    style: TextStyle(fontSize: AppTypography.s13, height: 1.5, color: Colors.grey.shade600))
              else
                Container(
                  padding: const EdgeInsets.all(AppSpacing.v16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ค่าไฟโดยประมาณ',
                          style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
                      const SizedBox(height: AppSpacing.v2),
                      Text('${_bahtFmt.format(costPerMonth)} บาท/เดือน',
                          style: const TextStyle(
                              fontSize: AppTypography.s24, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
                      const SizedBox(height: AppSpacing.v12),
                      Row(
                        children: [
                          Expanded(
                              child: _detailStat(
                                  'ต่อวันที่ใช้', '${_bahtFmt.format(kWhPerActiveDay * _rate.perUnit)} บาท')),
                          Expanded(child: _detailStat('ต่อปี', '${_bahtFmt.format(_yearlyCost(a))} บาท')),
                          Expanded(
                              child: _detailStat('พลังงาน/วันที่ใช้', '${kWhPerActiveDay.toStringAsFixed(2)} หน่วย')),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.v16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _confirmDelete(a);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        minimumSize: const Size(0, 48),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text('ลบ'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.v10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showEditApplianceSheet(a);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('แก้ไข'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
        const SizedBox(height: AppSpacing.v2),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
      ],
    );
  }
}

// แถบจับด้านบนของแผ่นด้านล่าง
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(AppSpacing.v2),
        ),
      ),
    );
  }
}
