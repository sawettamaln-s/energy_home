import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/bill_model.dart';
import '../../models/electricity_log_model.dart';
import '../../models/fixed_cost_item_model.dart';
import '../../models/start_meter_record_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/thai_date_utils.dart';
import '../analysis/analysis_screen.dart';
import '../appliance/appliance_screen.dart';
import '../auth/auth_gate.dart';
import '../dashboard/dashboard_screen.dart';
import '../../widgets/confirm_dialog.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _user = await _firestoreService.getUser(uid);
    setState(() => _isLoading = false);
  }

  // เหตุที่ "ออกจากระบบ" เดิมกดแล้วไม่ออก: main.dart มี StreamBuilder
  // ฟัง authStateChanges() อยู่ที่ root แต่พอเรา Navigator.pushReplacement
  // ไปหน้าอื่นๆ (Dashboard/Settings/...) มันไปแทนที่ตัว StreamBuilder นั้น
  // ในสแต็กเลย ทำให้ไม่มีอะไรเหลือคอยฟังว่า user ออกจากระบบแล้ว
  // วิธีแก้: หลัง signOut ให้ push ไปหน้า Login ตรงๆ พร้อมเคลียร์
  // ประวัติหน้าจอเก่าทั้งหมดทิ้ง (pushAndRemoveUntil)
  //
  // อัปเดต: เดิม push ไปแค่ LoginScreen() เปล่าๆ ทำให้หลัง login ใหม่
  // ไม่มีตัวฟัง auth state เหลืออยู่เลย (เพราะ push ไปแทนที่ StreamBuilder
  // จนหลุดจาก tree ไปแล้วตั้งแต่ตอนสลับแท็บ) เป็นเหตุให้ login ใหม่ไม่
  // พาไป Dashboard ให้ ค้างอยู่หน้า Login เฉยๆ — ต้อง push ไปที่ AuthGate()
  // แทน เพราะ AuthGate มี StreamBuilder ของตัวเองสดๆติดไปด้วยทุกครั้ง
  Future<void> _confirmSignOut() async {
 final confirmed = await showConfirmDialog(
      context,
      title: 'ออกจากระบบ',
      content: 'ต้องการออกจากระบบใช่ไหมคะ?',
      confirmLabel: 'ออกจากระบบ',
    );
    if (confirmed != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthGate()),
      (route) => false, // ทิ้งทุกหน้าก่อนหน้าออกจากสแต็ก กันกดย้อนกลับเข้ามาได้
    );
  }

void _handleBottomNavTap(int index) {
  if (index == 3) return; // Already on Settings
  
  if (index == 0) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  } else if (index == 1) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AnalysisScreen()),
    );
  } else if (index == 2) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ApplianceScreen()),
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
        title: const Text(
          'ตั้งค่า',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ข้อมูลผู้ใช้
                  _buildSectionHeader('บัญชีผู้ใช้'),
                  _buildUserCard(),
                  const SizedBox(height: 24),

                  // ตั้งค่าระบบ
                  _buildSectionHeader('ตั้งค่าระบบ'),
                  _buildSettingsCard(),
                  const SizedBox(height: 24),

                  // ข้อมูลและบิล
                  _buildSectionHeader('ข้อมูลและบิล'),
                  _buildDataCard(),
                  const SizedBox(height: 24),

                  // ออกจากระบบ
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmSignOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('ออกจากระบบ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavBar(
        currentIndex: 3,
        onTap: _handleBottomNavTap,
      ),
    );
  }

  // -------------------------------------------------------------------
  // บาร์ล่างแบบ floating pill — เหมือนกันทุกหน้า (วางโค้ดนี้ก๊อปไว้ทุกไฟล์)
  // -------------------------------------------------------------------
  Widget _buildBottomNavBar({
    required int currentIndex,
    required void Function(int) onTap,
  }) {
    final items = [
      (icon: Icons.dashboard_rounded, label: 'หน้าหลัก'),
      (icon: Icons.bar_chart_rounded, label: 'วิเคราะห์'),
      (icon: Icons.electrical_services, label: 'อุปกรณ์'),
      (icon: Icons.settings_rounded, label: 'ตั้งค่า'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(items.length, (index) {
          final isSelected = index == currentIndex;
          final item = items[index];
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2E7D32).withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 22,
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ชื่อ — กดแก้ไขได้
          _buildInfoRow(
            Icons.person,
            'ชื่อ',
            _user?.name ?? '-',
            onEdit: _showEditName,
          ),
          const Divider(height: 16),
          _buildInfoRow(
            Icons.email,
            'อีเมล',
            _user?.email ?? '-',
          ),
          const Divider(height: 16),
          _buildInfoRow(
            Icons.location_on,
            'พื้นที่',
            _user?.area == 'bangkok'
                ? 'กรุงเทพและปริมณฑล'
                : 'ต่างจังหวัด',
          ),
          const Divider(height: 16),
          _buildInfoRow(
            Icons.electric_meter,
            'ประเภทมิเตอร์',
            _user?.meterType == 'tou' ? 'TOU' : 'ปกติ',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.calendar_today,
            title: 'วันตัดรอบบิล',
            subtitle: 'วันที่ ${_user?.billingDay ?? 30} ของทุกเดือน',
            onTap: () => _showEditBillingDay(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.attach_money,
            title: 'Fixed Cost',
            subtitle:
                '฿${NumberFormat('#,##0.00').format(_user?.fixedCost ?? 0)} / เดือน',
            onTap: () => _showEditFixedCost(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.history,
            title: 'บันทึกค่ามิเตอร์ต้นรอบ',
            subtitle: 'กรอกหน่วยจากใบแจ้งหนี้ล่าสุด',
            onTap: () => _showEditStartMeter(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.manage_history,
            title: 'ประวัติค่ามิเตอร์ต้นรอบ',
            subtitle: 'ดูค่าที่เคยตั้ง/แก้ไขไว้ทั้งหมด',
            onTap: () => _showStartMeterHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.bolt,
            title: 'ประวัติมิเตอร์ไฟฟ้า / ประปา',
            subtitle: 'ดูและลบประวัติการบันทึก แยกแท็บไฟฟ้า-น้ำ',
            onTap: () => _showUtilityHistory(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.receipt_long,
            title: 'บันทึกบิลย้อนหลัง',
            subtitle: 'เพิ่ม แก้ไข หรือลบบิลที่กรอกย้อนหลัง',
            onTap: () => _showHistoricalBillList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onEdit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: Colors.grey),
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  // -------------------------------------------------------------------
  // แก้ไขชื่อ — ง่าย แก้ตรงๆใน Firestore ได้เลย ไม่กระทบ Auth
  // -------------------------------------------------------------------
  void _showEditName() {
    final controller = TextEditingController(text: _user?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขชื่อ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'ชื่อของคุณ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              await _firestoreService.updateUser(_user!.uid, {'name': newName});
              // อัปเดต displayName ของ Firebase Auth ด้วย ให้ข้อมูลตรงกันทั้งสองที่
              await FirebaseAuth.instance.currentUser
                  ?.updateDisplayName(newName);
              await _loadUser();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // popup อธิบายสั้นๆ แบบ "ห้อย" ใต้หัวข้อ — ใช้ซ้ำได้กับ popup อื่นที่ต้อง
  // มีคำอธิบายประกอบ (เช่น Fixed Cost ในอนาคต) เลยแยกเป็นฟังก์ชันกลางไว้
  // -------------------------------------------------------------------
  void _showInfoPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: const Color(0xFF2E7D32), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('เข้าใจแล้วค่ะ'),
          ),
        ],
      ),
    );
  }

  // ช่องวันที่หนึ่งช่องในปฏิทินเลือกวันตัดรอบบิล (ไม่มีเดือน มีแค่เลข 1-31
  // เพราะวันตัดรอบบิลซ้ำทุกเดือนอยู่แล้ว ไม่ต้องให้เลือกเดือน)
  Widget _buildBillingDayCell({
    required int day,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2E7D32)
                : Colors.grey.shade200,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  void _showEditBillingDay() {
    int selectedDay = _user?.billingDay ?? 30;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // หัวเรื่อง + ปุ่ม info ห้อยอธิบายว่าวันตัดรอบบิลคืออะไร
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'เลือกวันตัดรอบบิล',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.help_outline,
                          color: Color(0xFF2E7D32), size: 20),
                      onPressed: () => _showInfoPopup(
                        'วันตัดรอบบิลคืออะไร?',
                        'เลือกวันตัดรอบบิลตามวันที่ใบแจ้งหนี้ค่าไฟหรือค่าน้ำ'
                            'มาถึงบ้านของคุณค่ะ ระบบจะใช้วันนี้แจ้งเตือนเมื่อ'
                            'ใกล้ถึงรอบชำระเงิน และเตือนให้มาบันทึกค่ามิเตอร์'
                            'ต้นรอบ เพื่อตั้งเป็นค่าเริ่มต้นของรอบบิลเดือน'
                            'ถัดไปให้โดยอัตโนมัติค่ะ',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'แตะที่วันบนใบแจ้งหนี้ล่าสุดของคุณได้เลยค่ะ',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // ปฏิทินเลือกวัน 1-31 แบบกริด 7 คอลัมน์
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: List.generate(31, (i) {
                    final day = i + 1;
                    return _buildBillingDayCell(
                      day: day,
                      isSelected: day == selectedDay,
                      onTap: () => setDialogState(() => selectedDay = day),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'วันที่เลือก: ทุกวันที่ $selectedDay ของเดือน',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await _firestoreService.updateUser(
                            _user!.uid,
                            {'billingDay': selectedDay},
                          );
                          await _loadUser();
                          if (mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('บันทึก'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // เดิม Fixed Cost เป็นแค่ช่องกรอกยอดเดียว เปลี่ยนเป็นหน้าแยกที่บันทึก
  // เป็นรายการย่อยได้ (ค่าแก๊ส, อินเทอร์เน็ต ฯลฯ) — ดู _FixedCostScreen
  // ด้านล่างของไฟล์ ส่วนยอดรวมยังถูก sync เข้า _user.fixedCost เหมือนเดิม
  // เลย reload _loadUser() ทุกครั้งที่กลับจากหน้านั้น เพื่อให้ subtitle ในการ์ด
  // ตั้งค่าอัปเดตตามยอดล่าสุด
  Future<void> _showEditFixedCost() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FixedCostScreen(
          uid: _user!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
    await _loadUser();
  }

  void _showEditStartMeter() {
    final eController = TextEditingController(
      text: (_user?.startElectricityValue ?? 0).toString(),
    );
    final wController = TextEditingController(
      text: (_user?.startWaterValue ?? 0).toString(),
    );
    int selectedMonth = _user?.startBillingMonth ?? DateTime.now().month;
    int selectedYear = _user?.startBillingYear ?? DateTime.now().year;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ค่ามิเตอร์ต้นรอบบิล'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'เดือนของใบแจ้งหนี้',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: selectedMonth,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: List.generate(12, (i) {
                          return DropdownMenuItem(
                            value: i + 1,
                            child: Text(
                              thaiMonths[i],
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }),
                        onChanged: (val) =>
                            setDialogState(() => selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          DateTime.now().year - 1,
                          DateTime.now().year,
                        ].map((year) {
                          return DropdownMenuItem(
                            value: year,
                            child: Text(
                              '$year',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedYear = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'หน่วยไฟฟ้า',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: eController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 14009',
                    suffixText: 'หน่วย',
                    prefixIcon: const Icon(
                      Icons.bolt,
                      color: Colors.orange,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'หน่วยน้ำประปา',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: wController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 148',
                    suffixText: 'ลบ.ม.',
                    prefixIcon: const Icon(
                      Icons.water_drop,
                      color: Colors.blue,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final eVal = double.tryParse(eController.text) ?? 0;
                final wVal = double.tryParse(wController.text) ?? 0;
                await _firestoreService.updateUser(_user!.uid, {
                  'startElectricityValue': eVal,
                  'startWaterValue': wVal,
                  'startBillingMonth': selectedMonth,
                  'startBillingYear': selectedYear,
                });
                // เก็บ snapshot ไว้ในประวัติ เผื่อย้อนดูทีหลังว่าเคยตั้งค่าอะไรไว้
                await _firestoreService.saveStartMeterRecord(
                  StartMeterRecordModel(
                    id: const Uuid().v4(),
                    uid: _user!.uid,
                    electricityValue: eVal,
                    waterValue: wVal,
                    peakValue: _user?.startPeakValue ?? 0,
                    offPeakValue: _user?.startOffPeakValue ?? 0,
                    billingMonth: selectedMonth,
                    billingYear: selectedYear,
                    recordedAt: DateTime.now(),
                  ),
                );
                await _loadUser();
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStartMeterHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _StartMeterHistoryScreen(
          uid: _user!.uid,
          firestoreService: _firestoreService,
          isTou: _user?.meterType == 'tou',
        ),
      ),
    );
  }

  void _showUtilityHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _UtilityHistoryScreen(
          uid: FirebaseAuth.instance.currentUser!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }

  void _showHistoricalBillList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _HistoricalBillListScreen(
          uid: _user!.uid,
          defaultFixedCost: _user?.fixedCost ?? 0,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }
}

// ==================== เพิ่ม/แก้ไขบันทึกบิลย้อนหลัง ====================
// ไม่บังคับ • สูงสุด 6 เดือน — ใช้ให้หน้าวิเคราะห์มีข้อมูลตั้งแต่วันแรก
class _AddHistoricalBillSheet extends StatefulWidget {
  final String uid;
  final double defaultFixedCost;
  final FirestoreService firestoreService;
  final BillModel? existingBill; // null = เพิ่มใหม่, ไม่ null = แก้ไขของเดิม

  const _AddHistoricalBillSheet({
    required this.uid,
    required this.defaultFixedCost,
    required this.firestoreService,
    this.existingBill,
  });

  @override
  State<_AddHistoricalBillSheet> createState() =>
      _AddHistoricalBillSheetState();
}

class _AddHistoricalBillSheetState extends State<_AddHistoricalBillSheet> {
  late final List<DateTime> _monthOptions;
  late DateTime _selectedMonth;
  Set<String> _takenMonths = {}; // เก็บ 'year-month' ของเดือนที่มีบิลแล้ว
  bool _isLoadingTaken = true;
  bool _isSaving = false;

  final _eUsedCtrl = TextEditingController();
  final _eCostCtrl = TextEditingController();
  final _wUsedCtrl = TextEditingController();
  final _wCostCtrl = TextEditingController();
  late final TextEditingController _fixedCtrl;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingBill;
    final now = DateTime.now();
    _monthOptions = List.generate(
      6,
      (i) => DateTime(now.year, now.month - (i + 1), 1),
    );
    // ถ้าแก้ไขบิลที่เดือนอยู่นอกช่วง 6 เดือนล่าสุด ให้เพิ่มเดือนนั้นเข้าไปในตัวเลือกด้วย
    if (existing != null &&
        !_monthOptions.any(
            (m) => m.year == existing.year && m.month == existing.month)) {
      _monthOptions.add(DateTime(existing.year, existing.month, 1));
    }
    _selectedMonth = existing != null
        ? DateTime(existing.year, existing.month, 1)
        : _monthOptions.first;
    _fixedCtrl = TextEditingController(
        text: (existing?.fixedCost ?? widget.defaultFixedCost)
            .toStringAsFixed(0));
    if (existing != null) {
      _eUsedCtrl.text = existing.electricityUsed == 0
          ? ''
          : existing.electricityUsed.toStringAsFixed(2);
      _eCostCtrl.text =
          existing.electricityCost == 0 ? '' : existing.electricityCost.toStringAsFixed(2);
      _wUsedCtrl.text =
          existing.waterUsed == 0 ? '' : existing.waterUsed.toStringAsFixed(2);
      _wCostCtrl.text =
          existing.waterCost == 0 ? '' : existing.waterCost.toStringAsFixed(2);
    }
    _loadTakenMonths();

    for (final c in [_eUsedCtrl, _eCostCtrl, _wUsedCtrl, _wCostCtrl, _fixedCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _eUsedCtrl.dispose();
    _eCostCtrl.dispose();
    _wUsedCtrl.dispose();
    _wCostCtrl.dispose();
    _fixedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTakenMonths() async {
    final bills = await widget.firestoreService.getBills(widget.uid);
    final taken = bills.map((b) => '${b.year}-${b.month}').toSet();
    // กำลังแก้ไขบิลเดือนนี้อยู่ → ไม่ถือว่าเดือนนี้ "ถูกจองแล้ว" สำหรับตัวมันเอง
    final existing = widget.existingBill;
    if (existing != null) {
      taken.remove('${existing.year}-${existing.month}');
    }

    // ถ้าเดือนแรก (ใหม่สุด) มีบิลแล้ว ให้เลื่อนไปเลือกเดือนแรกที่ยังว่างแทน
    // (เฉพาะตอนเพิ่มใหม่ — ตอนแก้ไขให้คงเดือนเดิมของบิลไว้)
    DateTime initialSelection = _selectedMonth;
    if (existing == null) {
      for (final m in _monthOptions) {
        if (!taken.contains('${m.year}-${m.month}')) {
          initialSelection = m;
          break;
        }
      }
    }

    if (mounted) {
      setState(() {
        _takenMonths = taken;
        _selectedMonth = initialSelection;
        _isLoadingTaken = false;
      });
    }
  }

  double get _eCost => double.tryParse(_eCostCtrl.text) ?? 0;
  double get _wCost => double.tryParse(_wCostCtrl.text) ?? 0;
  double get _fixed => double.tryParse(_fixedCtrl.text) ?? 0;
  double get _total => _eCost + _wCost + _fixed;

  bool get _isSelectedMonthTaken =>
      _takenMonths.contains('${_selectedMonth.year}-${_selectedMonth.month}');

  Future<void> _save() async {
    final isEditing = widget.existingBill != null;
    if (_isSelectedMonthTaken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เดือนนี้มีบิลบันทึกไว้แล้วค่ะ')),
      );
      return;
    }
    if (_total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกยอดค่าไฟหรือค่าน้ำอย่างน้อย 1 ช่องค่ะ')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final bill = BillModel(
        id: isEditing ? widget.existingBill!.id : const Uuid().v4(),
        uid: widget.uid,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
        electricityUsed: double.tryParse(_eUsedCtrl.text) ?? 0,
        waterUsed: double.tryParse(_wUsedCtrl.text) ?? 0,
        electricityCost: _eCost,
        waterCost: _wCost,
        fixedCost: _fixed,
        totalCost: _total,
        // บิลย้อนหลังคือของจริงที่เกิดขึ้นแล้ว ไม่ใช่ค่าพยากรณ์
        forecastElectricity: _eCost,
        forecastWater: _wCost,
        forecastTotal: _total,
        isComplete: true,
        source: 'imported',
      );
      await widget.firestoreService.saveBill(bill);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  InputDecoration _fieldDecoration({String? hint, String? suffixText}) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existingBill != null
                      ? 'แก้ไขบันทึกบิลย้อนหลัง'
                      : 'เพิ่มบันทึกบิลย้อนหลัง',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ไม่บังคับ • สูงสุด 6 เดือน • ช่วยให้หน้าวิเคราะห์มีข้อมูลตั้งแต่วันแรก',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('เดือน'),
                  _isLoadingTaken
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : DropdownButtonFormField<DateTime>(
                          value: _selectedMonth,
                          decoration: _fieldDecoration(),
                          items: _monthOptions.map((d) {
                            final taken =
                                _takenMonths.contains('${d.year}-${d.month}');
                            return DropdownMenuItem(
                              value: d,
                              enabled: !taken,
                              child: Text(
                                taken
                                    ? '${thaiMonths[d.month - 1]} ${d.year} (มีบิลแล้ว)'
                                    : '${thaiMonths[d.month - 1]} ${d.year}',
                                style: TextStyle(
                                  color: taken ? Colors.grey.shade400 : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _selectedMonth = val!),
                        ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('หน่วยไฟที่ใช้'),
                            TextField(
                              controller: _eUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'หน่วย'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('ค่าไฟ'),
                            TextField(
                              controller: _eCostCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: '฿'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('หน่วยน้ำที่ใช้'),
                            TextField(
                              controller: _wUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'หน่วย'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('ค่าน้ำ'),
                            TextField(
                              controller: _wCostCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: '฿'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label('Fixed Cost'),
                  TextField(
                    controller: _fixedCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _fieldDecoration(hint: '0', suffixText: '฿'),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ยอดรวมเดือนนี้',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '฿${formatter.format(_total)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _isSelectedMonthTaken)
                          ? null
                          : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(widget.existingBill != null ? 'บันทึกการแก้ไข' : 'บันทึก'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== รายการบิลย้อนหลัง (แก้ไข/ลบได้) ====================
class _HistoricalBillListScreen extends StatefulWidget {
  final String uid;
  final double defaultFixedCost;
  final FirestoreService firestoreService;

  const _HistoricalBillListScreen({
    required this.uid,
    required this.defaultFixedCost,
    required this.firestoreService,
  });

  @override
  State<_HistoricalBillListScreen> createState() =>
      _HistoricalBillListScreenState();
}

class _HistoricalBillListScreenState
    extends State<_HistoricalBillListScreen> {
  List<BillModel> _bills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final all = await widget.firestoreService.getBills(widget.uid);
    // เฉพาะบิลที่กรอกย้อนหลังเอง (ไม่ใช่บิลที่ระบบสรุปจาก log อัตโนมัติ)
    final imported = all.where((b) => b.source == 'imported').toList();
    if (mounted) {
      setState(() {
        _bills = imported;
        _isLoading = false;
      });
    }
  }

  Future<void> _openSheet({BillModel? existingBill}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddHistoricalBillSheet(
        uid: widget.uid,
        defaultFixedCost: widget.defaultFixedCost,
        firestoreService: widget.firestoreService,
        existingBill: existingBill,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(BillModel bill) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบบิลนี้?',
      content: 'ต้องการลบบันทึกบิลของเดือน ${thaiMonths[bill.month - 1]} ${bill.year} ใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteBill(widget.uid, bill.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกบิลย้อนหลัง')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'ยังไม่มีบิลย้อนหลัง\nกดปุ่ม + เพื่อเพิ่มบิลของเดือนก่อนๆ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final bill = _bills[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                            '${thaiMonths[bill.month - 1]} ${bill.year}'),
                        subtitle:
                            Text('ยอดรวม ฿${formatter.format(bill.totalCost)}'),
                        onTap: () => _openSheet(existingBill: bill),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _openSheet(existingBill: bill),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              onPressed: () => _confirmDelete(bill),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(),
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ==================== บันทึกย้อนหลัง: ไฟฟ้า / ประปา ====================
// เดิมแยกเป็น 2 หน้า (ไฟฟ้า, น้ำ) คนละปุ่มในหน้าตั้งค่า รวมเป็นหน้าเดียวที่มี
// TabBar ด้านบนแทน — ใช้ลายเดียวกับ TabBar "ไฟฟ้า/น้ำ/อุปกรณ์" ในหน้า
// วิเคราะห์ (analysis_screen.dart) เพื่อให้ทั้งแอปดู consistent กัน
class _UtilityHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _UtilityHistoryScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_UtilityHistoryScreen> createState() => _UtilityHistoryScreenState();
}

class _UtilityHistoryScreenState extends State<_UtilityHistoryScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF2E7D32);
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('บันทึกย้อนหลัง'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _green,
          tabs: const [
            Tab(icon: Icon(Icons.bolt), text: 'ไฟฟ้า'),
            Tab(icon: Icon(Icons.water_drop), text: 'ประปา'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ElectricityLogTab(
              uid: widget.uid, firestoreService: widget.firestoreService),
          _WaterLogTab(
              uid: widget.uid, firestoreService: widget.firestoreService),
        ],
      ),
    );
  }
}

// แถบสรุปด้านบนของแต่ละแท็บ — โชว์จำนวนรายการ + ยอดรวมค่าใช้จ่ายในช่วงที่ดึงมา
// ใช้ร่วมกันได้ทั้งแท็บไฟฟ้าและน้ำ แค่เปลี่ยนสี/ไอคอน/label
Widget _utilitySummaryBar({
  required Color color,
  required IconData icon,
  required int count,
  required double totalCost,
  required NumberFormat formatter,
}) {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(
          '$count รายการ',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const Spacer(),
        Text(
          'รวม ฿${formatter.format(totalCost)}',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    ),
  );
}

// ==================== แท็บประวัติไฟฟ้า ====================
class _ElectricityLogTab extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _ElectricityLogTab({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_ElectricityLogTab> createState() => _ElectricityLogTabState();
}

class _ElectricityLogTabState extends State<_ElectricityLogTab> {
  List<ElectricityLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, 1);
    final endDate = DateTime(now.year + 1, now.month, 1);
    _logs = await widget.firestoreService.getCurrentMonthElectricityLogs(
      widget.uid,
      startDate,
      endDate,
    );
    setState(() => _isLoading = false);
  }

  Future<void> _confirmDelete(ElectricityLogModel log) async {
final confirm = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล',
      content: 'ต้องการลบข้อมูลนี้ใช่ไหมคะ?',
    );
    if (confirm == true) {
      await widget.firestoreService.deleteElectricityLog(log.uid, log.id);
      await _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('ยังไม่มีประวัติการบันทึก',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);

    return Column(
      children: [
        _utilitySummaryBar(
          color: Colors.orange,
          icon: Icons.bolt,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bolt,
                          color: Colors.orange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(log.date),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'มิเตอร์: ${log.meterValue.toStringAsFixed(0)} • '
                            'ใช้ไป: ${log.usedFromStart.toStringAsFixed(0)} หน่วย',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '฿${formatter.format(log.cost)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDelete(log),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ==================== แท็บประวัติน้ำ ====================
class _WaterLogTab extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _WaterLogTab({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_WaterLogTab> createState() => _WaterLogTabState();
}

class _WaterLogTabState extends State<_WaterLogTab> {
  List<WaterLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, 1);
    final endDate = DateTime(now.year + 1, now.month, 1);
    _logs = await widget.firestoreService.getCurrentMonthWaterLogs(
      widget.uid,
      startDate,
      endDate,
    );
    setState(() => _isLoading = false);
  }

  Future<void> _confirmDelete(WaterLogModel log) async {
final confirm = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล',
      content: 'ต้องการลบข้อมูลนี้ใช่ไหมคะ?',
    );
    if (confirm == true) {
      await widget.firestoreService.deleteWaterLog(log.uid, log.id);
      await _loadLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('ยังไม่มีประวัติการบันทึก',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);

    return Column(
      children: [
        _utilitySummaryBar(
          color: Colors.blue,
          icon: Icons.water_drop,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.water_drop,
                          color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(log.date),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'มิเตอร์: ${log.meterValue.toStringAsFixed(0)} • '
                            'ใช้ไป: ${log.usedFromStart.toStringAsFixed(0)} ลบ.ม.',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '฿${formatter.format(log.cost)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDelete(log),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


// ==================== ประวัติค่ามิเตอร์ต้นรอบ ====================
class _StartMeterHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final bool isTou; // true = มิเตอร์ TOU ต้องโชว์ peak/off-peak ด้วย

  const _StartMeterHistoryScreen({
    required this.uid,
    required this.firestoreService,
    this.isTou = false,
  });

  @override
  State<_StartMeterHistoryScreen> createState() =>
      _StartMeterHistoryScreenState();
}

class _StartMeterHistoryScreenState extends State<_StartMeterHistoryScreen> {
  List<StartMeterRecordModel> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final records = await widget.firestoreService.getStartMeterHistory(widget.uid);
    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDelete(StartMeterRecordModel record) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบรายการนี้?',
      content: 'ต้องการลบประวัติการตั้งค่ามิเตอร์ต้นรอบรายการนี้ใช่ไหมคะ',
      borderRadius: 16,
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteStartMeterRecord(widget.uid, record.id);
      _load();
    }
  }

  // ก้อนตัวเลข + ไอคอนเล็กๆ ใช้ทั้งใน timeline และอาจเอาไปใช้ที่อื่นได้
  Widget _valueChip(IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd/MM/yyyy, HH:mm');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('ประวัติค่ามิเตอร์ต้นรอบ')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — บอกว่ามีกี่รอบ แล้วรอบล่าสุดคือเดือนไหน
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.white, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'บันทึกค่ามิเตอร์ต้นรอบทั้งหมด',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_records.length} รอบบิล',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_records.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ล่าสุด ${thaiMonths[_records.first.billingMonth - 1]}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),

                // Timeline ของแต่ละรอบ
                Expanded(
                  child: _records.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.speed_outlined,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีประวัติการตั้งค่ามิเตอร์ต้นรอบ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final r = _records[index];
                            final isLatest = index == 0;
                            final isLast = index == _records.length - 1;

                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // เส้น timeline + จุดด้านซ้าย
                                  Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isLatest
                                              ? const Color(0xFF2E7D32)
                                              : Colors.grey.shade300,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: isLatest
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF2E7D32)
                                                        .withOpacity(0.4),
                                                    blurRadius: 6,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                      if (!isLast)
                                        Expanded(
                                          child: Container(
                                            width: 2,
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // การ์ดข้อมูลของรอบนั้น
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: isLatest
                                              ? Border.all(
                                                  color: const Color(0xFF2E7D32)
                                                      .withOpacity(0.3),
                                                )
                                              : null,
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
                                                Expanded(
                                                  child: Text(
                                                    'ต้นรอบ ${thaiMonths[r.billingMonth - 1]} ${r.billingYear}',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14.5,
                                                    ),
                                                  ),
                                                ),
                                                if (isLatest)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF2E7D32)
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(20),
                                                    ),
                                                    child: const Text(
                                                      'ปัจจุบัน',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF2E7D32),
                                                      ),
                                                    ),
                                                  ),
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  icon: Icon(Icons.delete_outline,
                                                      size: 19, color: Colors.red.shade300),
                                                  onPressed: () => _confirmDelete(r),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'บันทึกเมื่อ ${dateFormatter.format(r.recordedAt)}',
                                              style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.grey.shade500),
                                            ),
                                            const SizedBox(height: 10),

                                            // ค่ามิเตอร์ — โชว์ peak/off-peak แทนค่าไฟปกติถ้าเป็น TOU
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: widget.isTou
                                                  ? [
                                                      _valueChip(
                                                        Icons.bolt,
                                                        Colors.orange.shade700,
                                                        'On-Peak',
                                                        '${formatter.format(r.peakValue)} หน่วย',
                                                      ),
                                                      _valueChip(
                                                        Icons.bolt_outlined,
                                                        Colors.blueGrey,
                                                        'Off-Peak',
                                                        '${formatter.format(r.offPeakValue)} หน่วย',
                                                      ),
                                                      _valueChip(
                                                        Icons.water_drop,
                                                        Colors.blue,
                                                        'น้ำ',
                                                        '${formatter.format(r.waterValue)} ลบ.ม.',
                                                      ),
                                                    ]
                                                  : [
                                                      _valueChip(
                                                        Icons.bolt,
                                                        const Color(0xFF2E7D32),
                                                        'ไฟ',
                                                        '${formatter.format(r.electricityValue)} หน่วย',
                                                      ),
                                                      _valueChip(
                                                        Icons.water_drop,
                                                        Colors.blue,
                                                        'น้ำ',
                                                        '${formatter.format(r.waterValue)} ลบ.ม.',
                                                      ),
                                                    ],
                                            ),
                                          ],
                                        ),
                                      ),
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
    );
  }
}

// ==================== Fixed Cost (รายการแยก) ====================
// รายการตัวเลือกหมวดหมู่ค่าใช้จ่ายคงที่ที่พบบ่อย — เลือกแล้วชื่อ/ไอคอนจะเติม
// ให้อัตโนมัติ แต่ผู้ใช้ยังแก้ชื่อเองได้เสมอ (เผื่อมีรายการที่ไม่ตรงกับหมวดนี้)
const List<({String key, String label, IconData icon})> _fixedCostCategories =
    [
  (key: 'gas', label: 'ค่าแก๊สหุงต้ม', icon: Icons.local_fire_department),
  (key: 'internet', label: 'ค่าอินเทอร์เน็ตบ้าน', icon: Icons.wifi),
  (
    key: 'maintenance',
    label: 'ค่าส่วนกลาง/นิติบุคคล',
    icon: Icons.apartment
  ),
  (key: 'insurance', label: 'ค่าประกัน', icon: Icons.shield_outlined),
  (
    key: 'subscription',
    label: 'ค่าสมาชิก/บริการรายเดือน',
    icon: Icons.subscriptions_outlined
  ),
  (key: 'other', label: 'อื่นๆ', icon: Icons.receipt_long),
];

IconData _iconForFixedCostCategory(String key) {
  for (final c in _fixedCostCategories) {
    if (c.key == key) return c.icon;
  }
  return Icons.receipt_long;
}

String _labelForFixedCostCategory(String key) {
  for (final c in _fixedCostCategories) {
    if (c.key == key) return c.label;
  }
  return 'อื่นๆ';
}

class _FixedCostScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _FixedCostScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_FixedCostScreen> createState() => _FixedCostScreenState();
}

class _FixedCostScreenState extends State<_FixedCostScreen> {
  List<FixedCostItemModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await widget.firestoreService.getFixedCostItems(widget.uid);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  double get _total => _items.fold(0, (sum, item) => sum + item.amount);

  // เปิด popup เพิ่ม/แก้ไขรายการ — ถ้าส่ง existing มาคือแก้ไข ไม่ส่งคือเพิ่มใหม่
  Future<void> _showAddEditItem({FixedCostItemModel? existing}) async {
    String selectedCategory = existing?.category ?? _fixedCostCategories.first.key;
    final nameController =
        TextEditingController(text: existing?.name ?? _fixedCostCategories.first.label);
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    String? errorText;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'เพิ่มรายการ Fixed Cost' : 'แก้ไขรายการ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('หมวดหมู่',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _fixedCostCategories.map((c) {
                    final selected = c.key == selectedCategory;
                    return ChoiceChip(
                      label: Text(c.label, style: const TextStyle(fontSize: 12)),
                      avatar: Icon(c.icon,
                          size: 16,
                          color: selected ? Colors.white : const Color(0xFF2E7D32)),
                      selected: selected,
                      selectedColor: const Color(0xFF2E7D32),
                      labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87),
                      onSelected: (_) => setDialogState(() {
                        selectedCategory = c.key;
                        // เปลี่ยนหมวดแล้วเติมชื่ออัตโนมัติให้ ถ้า user ยังไม่ได้
                        // พิมพ์ชื่อเองมาก่อน (กันเขียนทับชื่อที่ user ตั้งเองไว้)
                        if (nameController.text.isEmpty ||
                            _fixedCostCategories
                                .map((e) => e.label)
                                .contains(nameController.text)) {
                          nameController.text = c.label;
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'ชื่อรายการ',
                    hintText: 'เช่น ค่าแก๊สหุงต้ม',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'ยอดต่อเดือน',
                    prefixText: '฿ ',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = double.tryParse(amountController.text);
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'กรอกชื่อรายการด้วยค่ะ');
                  return;
                }
                if (amount == null || amount <= 0) {
                  setDialogState(() => errorText = 'กรอกยอดเงินให้ถูกต้องด้วยค่ะ');
                  return;
                }

                final item = FixedCostItemModel(
                  id: existing?.id ?? const Uuid().v4(),
                  uid: widget.uid,
                  name: name,
                  category: selectedCategory,
                  amount: amount,
                  createdAt: existing?.createdAt ?? DateTime.now(),
                );
                await widget.firestoreService.saveFixedCostItem(item);
                if (mounted) Navigator.pop(context);
                await _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FixedCostItemModel item) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบรายการนี้?',
      content: 'ต้องการลบ "${item.name}" ออกจาก Fixed Cost ใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteFixedCostItem(widget.uid, item.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0');
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('Fixed Cost รายเดือน')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปยอดรวมด้านบน
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.summarize_outlined,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'รวม Fixed Cost ต่อเดือน',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '฿${formatter.format(_total)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_items.length} รายการ',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // รายการ Fixed Cost
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีรายการ Fixed Cost\nกดปุ่ม + เพื่อเพิ่มรายการแรกได้เลยค่ะ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _iconForFixedCostCategory(item.category),
                                      color: const Color(0xFF2E7D32),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _labelForFixedCostCategory(item.category),
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '฿${formatter.format(item.amount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert,
                                        size: 18, color: Colors.grey.shade500),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showAddEditItem(existing: item);
                                      } else if (value == 'delete') {
                                        _confirmDelete(item);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('แก้ไข'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('ลบ',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditItem(),
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}