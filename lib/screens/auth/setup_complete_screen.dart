import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../appliance/appliance_screen.dart';
import '../main_shell.dart';
import '../settings/settings_screen.dart';

/// หน้าสรุปหลังทำ setup wizard เสร็จ — โชว์เฉพาะกรณีที่ผู้ใช้ข้ามบางขั้นตอน
/// ไป (วันตัดรอบบิล หรือ บิลตั้งต้น) เพื่อเตือนว่ายังมีอะไรค้างอยู่บ้าง
/// ก่อนเข้าใช้งานจริง ถ้ากรอกครบหมดแล้ว setup_screen.dart จะข้ามหน้านี้ไปเลย
///
/// ดีไซน์ใหม่ (โทนมืด) — แต่ละรายการในเช็คลิสตอนนี้แตะได้จริง พาไปหน้า
/// ตั้งค่าเรื่องนั้นๆ ตรงๆ ผ่าน SettingsQuickAction (ดู settings_screen.dart)
/// แทนที่จะพาไปหน้าตั้งค่าเฉยๆ แล้วให้ผู้ใช้ไปหาเอง กลับมาหน้านี้อีกที
/// ระบบจะรีเฟรชสถานะ "ตั้งค่าแล้วหรือยัง" ให้อัตโนมัติ
class SetupCompleteScreen extends StatefulWidget {
  final bool billingDayConfigured;
  final bool startMeterConfigured;
  final double startElectricityValue;

  const SetupCompleteScreen({
    super.key,
    required this.billingDayConfigured,
    required this.startMeterConfigured,
    required this.startElectricityValue,
  });

  @override
  State<SetupCompleteScreen> createState() => _SetupCompleteScreenState();
}

class _SetupCompleteScreenState extends State<SetupCompleteScreen> {
  static const _green = Color(0xFF2E7D32);
  static const _bg = Colors.white;
  static const _card = Colors.white;
  static final _border = Colors.grey.shade200;

  final FirestoreService _firestoreService = FirestoreService();

  late bool _billingDayDone = widget.billingDayConfigured;
  late bool _startMeterDone = widget.startMeterConfigured;
  late double _startElectricityValue = widget.startElectricityValue;

  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  // ดึงข้อมูลจริงจาก Firestore มาใช้กับการ์ดที่ตั้ง/ประเภทมิเตอร์ด้านบน
  // (ค่าที่ constructor ส่งมาให้มีแค่ billingDay/startMeter เท่านั้น ไม่มี
  // area/meterType) และใช้ค่ามิเตอร์ตั้งต้นล่าสุดแทนของเดิมถ้ามีอัปเดต
  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = await _firestoreService.getUser(uid);
    if (!mounted) return;
    setState(() {
      _user = user;
      if (user != null) {
        _startMeterDone = user.startMeterConfigured;
        _startElectricityValue = user.startElectricityValue;
      }
    });
  }

  int get _pendingRequiredCount =>
      (_billingDayDone ? 0 : 1) + (_startMeterDone ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    final pending = _pendingRequiredCount;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'พร้อมใช้งานแล้ว!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pending > 0
                    ? 'บัญชีถูกสร้างเรียบร้อยแล้ว เหลืออีก $pending ขั้นตอน'
                        'ก่อนเพิ่มค่าไฟได้'
                    : 'บัญชีถูกสร้างเรียบร้อยแล้ว พร้อมเริ่มบันทึกค่าไฟ/น้ำได้เลย',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _infoCard(
                      icon: Icons.location_on_outlined,
                      label: 'ที่ตั้ง',
                      value: _user?.area == 'bangkok'
                          ? 'กรุงเทพและปริมณฑล'
                          : 'ต่างจังหวัด',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _infoCard(
                      icon: Icons.bolt_rounded,
                      label: 'มิเตอร์ไฟ',
                      value: _user?.meterType == 'tou'
                          ? 'มิเตอร์ TOU'
                          : 'มิเตอร์ปกติ',
                    ),
                  ),
                ],
              ),
              if (pending > 0) ...[
                const SizedBox(height: 14),
                _warningBanner(),
              ],
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ขั้นตอนต่อไป',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _checklistItem(
                        icon: Icons.event_rounded,
                        iconBg: const Color(0xFFE8F5E9),
                        iconColor: _green,
                        title: 'วันตัดรอบบิล',
                        subtitle: _billingDayDone
                            ? 'ตั้งค่าเรียบร้อยแล้ว'
                            : 'แตะเพื่อไปตั้งค่า',
                        done: _billingDayDone,
                        onTap: _goToBillingDay,
                      ),
                      const SizedBox(height: 10),
                      _checklistItem(
                        icon: Icons.bolt_rounded,
                        iconBg: const Color(0xFFFFF3E0),
                        iconColor: Colors.orange,
                        title: 'กรอกมิเตอร์ตั้งต้น',
                        subtitle: _startMeterDone
                            ? '${fmt.format(_startElectricityValue)} หน่วย'
                            : 'แตะเพื่อไปตั้งค่า',
                        done: _startMeterDone,
                        onTap: _goToStartMeter,
                      ),
                      const SizedBox(height: 10),
                      _checklistItem(
                        icon: Icons.history_rounded,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: Colors.blue,
                        title: 'บิลย้อนหลัง',
                        subtitle: 'สูงสุด 6 เดือน',
                        done: false,
                        optional: true,
                        onTap: _goToHistoricalBills,
                      ),
                      const SizedBox(height: 10),
                      _checklistItem(
                        icon: Icons.list_alt_rounded,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: Colors.blue,
                        title: 'Fixed cost',
                        subtitle: 'ค่าใช้จ่ายประจำบ้าน',
                        done: false,
                        optional: true,
                        onTap: _goToFixedCost,
                      ),
                      const SizedBox(height: 10),
                      _checklistItem(
                        icon: Icons.power_rounded,
                        iconBg: const Color(0xFFFCE4EC),
                        iconColor: Colors.pink,
                        title: 'เพิ่มเครื่องใช้ไฟฟ้า',
                        subtitle: 'เพื่อวิเคราะห์ที่แม่นยำขึ้น',
                        done: false,
                        optional: true,
                        onTap: _goToAppliances,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goToDashboard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child:
                        const Text('เข้าใช้งาน', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _warningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFFF9A825), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ระบบยังคำนวณค่าไฟ/น้ำไม่ได้ จนกว่าจะตั้งมิเตอร์ตั้งต้นและ'
              'วันตัดรอบบิลก่อน — แตะรายการด้านล่างเพื่อไปตั้งได้เลย',
              style: TextStyle(
                color: Color(0xFF5D4A0E),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checklistItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onTap,
    bool optional = false,
  }) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(done: done, optional: optional),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip({required bool done, required bool optional}) {
    if (done) {
      return _chip(
        label: 'เสร็จแล้ว',
        bg: const Color(0xFFE8F5E9),
        fg: _green,
      );
    }
    if (optional) {
      return _chip(
        label: 'ไม่บังคับ',
        bg: Colors.grey.shade100,
        fg: Colors.grey.shade600,
      );
    }
    return _chip(
      label: 'ทำเลย',
      bg: const Color(0xFFFFF3E0),
      fg: const Color(0xFFE65100),
    );
  }

  Widget _chip({required String label, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _goToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) => const MainShell(justCompletedSetup: true)),
      (route) => false,
    );
  }

  // แตะแล้วพาไปหน้าตั้งค่า เปิดขั้นตอนนั้นๆ ให้ทันที (SettingsQuickAction)
  // กลับมาแล้ว refresh สถานะให้ใหม่ ให้เช็คลิสอัปเดตตามจริง
  Future<void> _goToBillingDay() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const SettingsScreen(quickAction: SettingsQuickAction.billingDay),
      ),
    );
    // วันตัดรอบบิลถูกบันทึกเป็นค่าเริ่มต้น (30) เสมอแม้ตอน setup จะข้ามไว้
    // จึงแยกความต่าง "ข้าม" กับ "ตั้งจริง" จาก Firestore เพียวๆ ไม่ได้ —
    // ถือว่าแตะเข้ามาหน้านี้แล้วคือถือว่าตั้งค่าแล้ว
    if (mounted) setState(() => _billingDayDone = true);
  }

  Future<void> _goToStartMeter() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const SettingsScreen(quickAction: SettingsQuickAction.startMeter),
      ),
    );
    await _loadUser();
  }

  Future<void> _goToHistoricalBills() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(
            quickAction: SettingsQuickAction.historicalBills),
      ),
    );
    if (mounted) await _loadUser();
  }

  Future<void> _goToFixedCost() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(openFixedCostOnStart: true),
      ),
    );
    if (mounted) await _loadUser();
  }

  Future<void> _goToAppliances() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ApplianceScreen()),
    );
    if (mounted) await _loadUser();
  }
}