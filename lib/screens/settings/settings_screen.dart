import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../models/bill_model.dart';
import '../../models/electricity_log_model.dart';
import '../../models/fixed_cost_item_model.dart';
import '../../models/start_meter_record_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../auth/auth_gate.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  UserModel? _user;
  bool _isLoading = true;

  // สถานะสิทธิ์แจ้งเตือนของเครื่อง — เก็บแยกจาก _isLoading เพราะโหลดเสร็จ
  // ไม่พร้อมกัน (ไม่อยากให้การ์ดอื่นรอสถานะแจ้งเตือนก่อนโชว์)
  PermissionStatus? _notificationStatus;

  // preference เปิด/ปิดแจ้งเตือนแยกตามประเภท (billing/meter/spike/summary)
  // ค่าเริ่มต้น true ทั้งหมดไว้ก่อนโหลดเสร็จ กัน UI กระพริบตอนเปิดหน้า
  Map<String, bool> _notifPrefs = {
    for (final t in NotificationService.notificationTypes) t: true,
  };

  // -------------------------------------------------------------------
  // สีของหน้าตั้งค่า — ใช้เขียวเดียวกันทุกหมวดเหมือนเดิม (ลองแยกสีตาม
  // หมวดไปแล้วแต่พอดีอยากได้เขียวเหมือนเดิมมากกว่า) เก็บเป็น constant
  // ไว้จุดเดียวเผื่ออยากเปลี่ยนสีทีหลัง ไม่ต้องไล่แก้ทีละจุด
  // -------------------------------------------------------------------
  static const Color _sectionColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadNotificationStatus();
    _loadNotifPrefs();
  }

  Future<void> _loadNotifPrefs() async {
    final prefs = await NotificationService.instance.getAllTypePreferences();
    if (mounted) setState(() => _notifPrefs = prefs);
  }

  Future<void> _setNotifPref(String type, bool value) async {
    setState(() => _notifPrefs[type] = value); // อัปเดต UI ทันทีไม่ต้องรอ
    await NotificationService.instance.setTypeEnabled(type, value);
  }

  Future<void> _loadNotificationStatus() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _notificationStatus = status);
  }

  // เปิด: ถ้ายังไม่เคยขอสิทธิ์มาก่อนขอผ่าน dialog ของระบบได้เลย แต่ถ้าเคย
  // กดปฏิเสธถาวรไปแล้ว (permanentlyDenied) ระบบจะไม่ยอมเด้ง dialog ขอซ้ำ
  // ให้อีก ต้องพาไปหน้าตั้งค่าเครื่องเพื่อเปิดเอง
  // ปิด: iOS/Android ไม่มี API ให้แอปถอนสิทธิ์ตัวเองได้ ต้องพาไปหน้าตั้งค่า
  // เครื่องเหมือนกัน (อธิบายให้ผู้ใช้เข้าใจก่อนผ่าน popup กันงง)
  Future<void> _toggleNotification(bool turnOn) async {
    if (turnOn && _notificationStatus != PermissionStatus.permanentlyDenied) {
      await NotificationService.instance.requestPermission();
      await _loadNotificationStatus();
      return;
    }

    // เปิดไม่ได้จากในแอปแล้ว (เคยปฏิเสธถาวร) หรือกำลังจะปิด — ทั้งสองกรณี
    // ต้องพาไปหน้าตั้งค่าเครื่องเท่านั้น เลยรวม popup ไว้ด้วยกัน แค่เปลี่ยน
    // ข้อความอธิบายตามบริบท
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(turnOn ? 'เปิดแจ้งเตือนไม่ได้จากในแอป' : 'ปิดแจ้งเตือน'),
        content: Text(
          turnOn
              ? 'คุณเคยปิดสิทธิ์แจ้งเตือนของแอปนี้ไว้ค่ะ กรุณาไปเปิดเองที่'
                  'หน้าตั้งค่าเครื่อง > แอป > Energy Home > การแจ้งเตือน'
              : 'ระบบมือถือไม่อนุญาตให้แอปปิดสิทธิ์แจ้งเตือนเองได้ค่ะ กรุณา'
                  'ไปปิดที่หน้าตั้งค่าเครื่อง > แอป > Energy Home > '
                  'การแจ้งเตือน',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            child: const Text('ไปที่ตั้งค่าเครื่อง'),
          ),
        ],
      ),
    );
    await _loadNotificationStatus();
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
                  _buildSectionHeader('บัญชีผู้ใช้',
                      icon: Icons.person_rounded, color: _sectionColor),
                  _buildUserCard(),
                  const SizedBox(height: 24),

                  // ตั้งค่าระบบ
                  _buildSectionHeader('ตั้งค่าระบบ',
                      icon: Icons.tune_rounded, color: _sectionColor),
                  _buildSettingsCard(),
                  const SizedBox(height: 24),

                  // ข้อมูลและบิล
                  _buildSectionHeader('ข้อมูลและบิล',
                      icon: Icons.receipt_long_rounded, color: _sectionColor),
                  _buildDataCard(),
                  const SizedBox(height: 24),

                  // การแจ้งเตือน — เดิมฝังอยู่ท้าย "ตั้งค่าระบบ" ย้ายออกมา
                  // เป็นหมวดแยกตามที่ขอ เพราะเป็นเรื่องคนละประเภทกับการตั้งค่า
                  // ตัวเลข/รอบบิล
                  _buildSectionHeader('การแจ้งเตือน',
                      icon: Icons.notifications_active_rounded,
                      color: _sectionColor),
                  _buildNotificationCard(),
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
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
    );
  }

  // -------------------------------------------------------------------
  // บาร์ล่างแบบ floating pill — เหมือนกันทุกหน้า (วางโค้ดนี้ก๊อปไว้ทุกไฟล์)
  // -------------------------------------------------------------------
  // แต่ละหมวดมีไอคอน + สีประจำหมวดของตัวเอง (เดิมเป็นตัวหนังสือสีเทาล้วน
  // ทุกหมวดเหมือนกันหมด ดูเรียบไป) สีที่เลือกให้ไปในทิศทางเดียวกับสีที่
  // ใช้อยู่แล้วในแอป: เขียว = สีหลักของระบบ, ส้ม = โทนเดียวกับมิเตอร์ไฟฟ้า,
  // ฟ้า = โทนเดียวกับมิเตอร์น้ำ, ม่วง = สีใหม่สำหรับหมวดบัญชีผู้ใช้
  Widget _buildSectionHeader(
    String title, {
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              color: color,
            ),
          ),
        ],
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
            color: _sectionColor,
            onEdit: _showEditName,
          ),
          const Divider(height: 16),
          _buildInfoRow(
            Icons.email,
            'อีเมล',
            _user?.email ?? '-',
            color: _sectionColor,
          ),
          const Divider(height: 16),
          // รวม "พื้นที่" กับ "ประเภทมิเตอร์" เป็นแถวเดียว — ตามที่ขอ
          // เพราะสองอย่างนี้เป็นข้อมูลตั้งค่ามิเตอร์เหมือนกัน ไม่จำเป็นต้อง
          // แยกแถว ใช้จุด (·) คั่นกลาง อ่านง่ายกว่าขึ้นบรรทัดใหม่
          _buildInfoRow(
            Icons.electric_meter,
            'พื้นที่ / ประเภทมิเตอร์',
            '${_user?.area == 'bangkok' ? 'กรุงเทพและปริมณฑล' : 'ต่างจังหวัด'}'
                ' · ${_user?.meterType == 'tou' ? 'TOU' : 'ปกติ'}',
            color: _sectionColor,
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
            icon: Icons.attach_money,
            title: 'Fixed Cost',
            subtitle:
                '${NumberFormat('#,##0.00').format(_user?.fixedCost ?? 0)} บาท / เดือน',
            color: _sectionColor,
            onTap: () => _showEditFixedCost(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.calendar_today,
            title: 'วันตัดรอบบิล',
            subtitle: 'วันที่ ${_user?.billingDay ?? 30} ของทุกเดือน',
            color: _sectionColor,
            onTap: () => _showEditBillingDay(),
          ),
          const Divider(height: 1, indent: 56),
          // เดิมกดแล้วเด้ง dialog กรอกค่าอย่างเดียว ตอนนี้รวมกับหน้าประวัติ
          // เป็นหน้าเดียวแล้ว (มีปุ่ม + ในหน้านั้นสำหรับเพิ่มค่าใหม่)
          _buildSettingsTile(
            icon: Icons.history,
            title: 'ค่ามิเตอร์ต้นรอบ',
            subtitle: 'บันทึกค่าใหม่ และดูประวัติที่เคยตั้งไว้ทั้งหมด',
            color: _sectionColor,
            onTap: () => _showStartMeterHistory(),
          ),
          const Divider(height: 1, indent: 56),
          // ย้ายมาจากหมวด "ข้อมูลและบิล" — สลับที่กับ "ประวัติค่ามิเตอร์
          // ต้นรอบ" ที่ย้ายไปอยู่หมวดนั้นแทน
          _buildSettingsTile(
            icon: Icons.receipt_long,
            title: 'บันทึกบิลย้อนหลัง',
            subtitle: 'เพิ่ม แก้ไข หรือลบบิลที่กรอกย้อนหลัง',
            color: _sectionColor,
            onTap: () => _showHistoricalBillList(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // การ์ดการแจ้งเตือน — แยกออกมาจาก _buildSettingsCard เดิม (ก่อนหน้านี้
  // ฝังเป็น ListTile สุดท้ายของหมวด "ตั้งค่าระบบ") ให้เป็นหมวดของตัวเอง
  // เพราะเป็นเรื่องสิทธิ์การแจ้งเตือนของเครื่อง คนละประเภทกับตัวเลข/รอบบิล
  //
  // สวิตช์บนสุดคุม "สิทธิ์แจ้งเตือนของเครื่อง" (ทั้งหมด) ส่วน 4 toggle ย่อย
  // ด้านล่างคุมว่าอยากรับแจ้งเตือน "ประเภทไหนบ้าง" — ถ้าสวิตช์บนปิดอยู่
  // toggle ย่อยจะกดไม่ได้ (เพราะไม่มีสิทธิ์แจ้งเตือนอยู่แล้วไม่ว่าจะตั้ง
  // ประเภทไหนไว้ก็ไม่มีผล) ให้ดูจางลงกันสับสน
  // -------------------------------------------------------------------
  Widget _buildNotificationCard() {
    final granted = _notificationStatus == PermissionStatus.granted;
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
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _sectionColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.notifications_active_outlined,
                  color: _sectionColor, size: 20),
            ),
            title: const Text(
              'แจ้งเตือนบิลและมิเตอร์',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              granted ? 'เปิดอยู่' : 'ปิดอยู่',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: Switch(
              value: granted,
              activeColor: _sectionColor,
              onChanged: (val) => _toggleNotification(val),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _notifTypeToggle(
            icon: Icons.event_available_outlined,
            title: 'ใกล้วันตัดรอบบิล',
            type: 'billing',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.speed_outlined,
            title: 'ยังไม่บันทึกมิเตอร์',
            type: 'meter',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.trending_up_rounded,
            title: 'ใช้ไฟ/น้ำพุ่งขึ้นผิดปกติ',
            type: 'spike',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.summarize_outlined,
            title: 'สรุปยอดท้ายรอบบิล',
            type: 'summary',
            enabled: granted,
            isLast: true,
          ),
        ],
      ),
    );
  }

  // toggle ย่อยแต่ละประเภท — ใช้ SwitchListTile แทน ListTile+Switch แยกกัน
  // เพราะกดได้ทั้งแถว ไม่ต้องเล็งโดนตัวสวิตช์เป๊ะๆ
  Widget _notifTypeToggle({
    required IconData icon,
    required String title,
    required String type,
    required bool enabled,
    bool isLast = false,
  }) {
    final value = _notifPrefs[type] ?? true;
    return Column(
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          dense: true,
          secondary: Icon(icon,
              size: 19,
              color: enabled ? Colors.grey.shade600 : Colors.grey.shade300),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: enabled ? Colors.black87 : Colors.grey.shade400,
            ),
          ),
          value: value,
          activeColor: _sectionColor,
          onChanged: enabled ? (val) => _setNotifPref(type, val) : null,
        ),
        if (!isLast) const Divider(height: 1, indent: 56),
      ],
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
            color: _sectionColor,
            onTap: () => _showUtilityHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color color = _sectionColor,
    VoidCallback? onEdit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
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
    Color color = _sectionColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
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
          title: Row(
            children: [
              const Expanded(child: Text('ค่ามิเตอร์ต้นรอบบิล')),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.help_outline,
                    color: Color(0xFF2E7D32), size: 20),
                onPressed: () => _showInfoPopup(
                  'กรอกเลขจากบิลตรงไหน?',
                  'เปิดใบแจ้งหนี้ค่าไฟ/ค่าน้ำเดือนล่าสุดของคุณ แล้วมองหาช่อง'
                      '"เลขอ่านครั้งหลัง" หรือภาษาอังกฤษว่า "Last Meter '
                      'Reading" ค่ะ — คือเลขที่มิเตอร์อ่านได้ล่าสุดตอนที่'
                      'เจ้าหน้าที่มาจดในรอบบิลนั้น เอาตัวเลขนี้มากรอกตรงนี้'
                      'ได้เลย (ไม่ใช่เลข "เลขอ่านครั้งก่อน" ที่อยู่คู่กัน '
                      'เพราะอันนั้นเป็นเลขของรอบก่อนหน้า)\n\n'
                      'ระบบจะใช้เลขนี้เป็นจุดเริ่มต้นของรอบบิลถัดไป '
                      'เพื่อคำนวณว่าคุณใช้ไปกี่หน่วยเมื่อเทียบกับเลขที่คุณ'
                      'บันทึกในแอปครั้งถัดไปค่ะ',
                ),
              ),
            ],
          ),
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
  final FirestoreService firestoreService;
  final BillModel? existingBill; // null = เพิ่มใหม่, ไม่ null = แก้ไขของเดิม

  const _AddHistoricalBillSheet({
    required this.uid,
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

    for (final c in [_eUsedCtrl, _eCostCtrl, _wUsedCtrl, _wCostCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _eUsedCtrl.dispose();
    _eCostCtrl.dispose();
    _wUsedCtrl.dispose();
    _wCostCtrl.dispose();
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
  // ตัด Fixed Cost ออกจากฟีเจอร์นี้ทั้งหมดตามที่ขอ — บันทึกบิลย้อนหลัง
  // เก็บแค่เรื่องบิลไฟ/น้ำล้วนๆ ไม่ปนกับค่าใช้จ่ายคงที่รายเดือนแล้ว
  double get _total => _eCost + _wCost;

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

  Widget _label(String text, {VoidCallback? onInfoTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (onInfoTap != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onInfoTap,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2E7D32).withOpacity(0.12),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32))),
                ),
              ),
            ],
          ],
        ),
      );

  // อธิบายว่าช่อง "หน่วยที่ใช้" ต้องกรอกอะไร — ปัญหาที่เจอบ่อยคือคนกรอก
  // "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) มาใส่แทนที่จะเป็นยอดหน่วยที่ใช้
  // จริงของเดือนนั้น ซึ่งฟอร์มนี้ไม่ได้เอาเลขมิเตอร์ของ 2 เดือนมาลบกันให้
  // (ต่างจากหน้าบันทึกมิเตอร์ปกติที่ระบบลบให้อัตโนมัติ) เพราะบิลย้อนหลัง
  // แต่ละเดือนไม่ได้ต่อเนื่องกันเสมอไป จึงให้กรอกยอดหน่วยที่ใช้ตรงๆ จากบิล
  void _showUsageInfoPopup(String utilityLabel, String unitLabel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('กรอก "$utilityLabel" ตรงไหนของบิล?',
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          'เปิดบิลเดือนที่จะบันทึกย้อนหลัง แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
          'หรือ "$unitLabel" ตรงๆ เอาตัวเลขนั้นมากรอกในช่องนี้ได้เลยค่ะ\n\n'
          '⚠️ ไม่ต้องเอา "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) มากรอกนะคะ '
          'เพราะฟอร์มนี้ไม่ได้เอาเลขมิเตอร์ของแต่ละเดือนมาลบกันให้เหมือนหน้า'
          'บันทึกมิเตอร์ปกติ — ระบบจะเก็บแค่ยอดหน่วยที่ใช้จริงของเดือนนั้น'
          'ไปวิเคราะห์ตรงๆ ถ้ากรอกเลขมิเตอร์สะสมมาแทน ตัวเลขในหน้าวิเคราะห์'
          'จะเพี้ยนไปเยอะเลยค่ะ',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
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
                            _label('หน่วยไฟที่ใช้',
                                onInfoTap: () =>
                                    _showUsageInfoPopup('หน่วยไฟที่ใช้', 'kWh')),
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
                                  _fieldDecoration(hint: '0', suffixText: 'บาท'),
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
                            _label('หน่วยน้ำที่ใช้',
                                onInfoTap: () => _showUsageInfoPopup(
                                    'หน่วยน้ำที่ใช้', 'ลบ.ม.')),
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
                                  _fieldDecoration(hint: '0', suffixText: 'บาท'),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          '${formatter.format(_total)} บาท',
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
// อธิบายภาพรวมของหน้า "บันทึกบิลย้อนหลัง" ไว้ที่ AppBar ของหน้ารายการเลย
// (ไม่ใช่แค่ในฟอร์มเพิ่ม/แก้ไข) เพราะเดิมผู้ใช้ต้องกดปุ่ม + ก่อนถึงจะเห็น
// คำอธิบาย ถ้ายังไม่เคยกรอกมาก่อนจะไม่รู้เลยว่าต้องกรอกอะไร
void _showHistoricalBillInfoPopup(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text('หน้านี้ใช้ทำอะไร?', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: const Text(
        'สำหรับเพิ่มบิลของเดือนก่อนๆ ที่ไม่ได้บันทึกผ่านแอปตั้งแต่แรก '
        'เพื่อให้หน้าวิเคราะห์มีข้อมูลย้อนหลังไปเปรียบเทียบได้ (สูงสุด 6 เดือน)\n\n'
        '📋 กรอกยังไง\n'
        'เปิดบิลค่าไฟ/ค่าน้ำเดือนนั้น แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
        '(kWh หรือ ลบ.ม.) กับ "ยอดเงิน" เอาตัวเลขทั้งสองมากรอกตรงๆ ได้เลยค่ะ\n\n'
        '⚠️ ข้อควรระวัง\n'
        'อย่ากรอก "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) มาแทนนะคะ '
        'เพราะแต่ละเดือนที่กรอกในหน้านี้ไม่ได้ต่อเนื่องกัน ระบบจึงไม่เอาเลข'
        'มิเตอร์ของ 2 เดือนมาลบกันให้เหมือนหน้าบันทึกมิเตอร์ปกติ '
        'ต้องเป็นยอดหน่วยที่ใช้จริงของเดือนนั้นเดือนเดียวเท่านั้นค่ะ',
        style: TextStyle(fontSize: 13.5, height: 1.6),
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

class _HistoricalBillListScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _HistoricalBillListScreen({
    required this.uid,
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

  // ก้อนตัวเลข + ไอคอนเล็กๆ ในการ์ดแต่ละบิล — ดีไซน์เดียวกับ _valueChip ใน
  // หน้าประวัติค่ามิเตอร์ต้นรอบ ให้ทั้งแอปดู consistent กัน
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('บันทึกบิลย้อนหลัง'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHistoricalBillInfoPopup(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — สไตล์เดียวกับหน้าประวัติค่ามิเตอร์ต้นรอบ
                // เดิมหน้านี้ไม่มีการ์ดสรุป ดูจืดกว่าหน้าอื่นในแอป
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
                      const Icon(Icons.receipt_long,
                          color: Colors.white, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'บันทึกบิลย้อนหลังทั้งหมด',
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_bills.length} เดือน',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // รายการบิลแต่ละเดือน
                Expanded(
                  child: _bills.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีบิลย้อนหลัง\nกดปุ่ม + เพื่อเพิ่มบิลของเดือนก่อนๆ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _bills.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final bill = _bills[index];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
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
                                      // จุดสีเขียวเล็กๆ หน้าหัวข้อ — ให้ฟีลเดียว
                                      // กับการ์ดในหน้าประวัติมิเตอร์ต้นรอบ
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF2E7D32),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${thaiMonths[bill.month - 1]} ${bill.year}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${formatter.format(bill.totalCost)} บาท',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          color: Color(0xFF2E7D32),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 19, color: Colors.grey),
                                        onPressed: () =>
                                            _openSheet(existingBill: bill),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(Icons.delete_outline,
                                            size: 19,
                                            color: Colors.red.shade300),
                                        onPressed: () => _confirmDelete(bill),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // แสดงเฉพาะรายการที่มีค่า (บางเดือนอาจกรอก
                                  // แค่ค่าไฟ หรือแค่ค่าน้ำ ไม่จำเป็นต้องครบ)
                                  // เอา Fixed Cost ออกแล้ว เหลือแค่ไฟ/น้ำที่
                                  // เกี่ยวกับตัวบิลจริงๆ ตามที่ขอ
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (bill.electricityCost > 0)
                                        _valueChip(
                                          Icons.bolt,
                                          Colors.orange.shade700,
                                          'ไฟ',
                                          '${formatter.format(bill.electricityCost)} บาท',
                                        ),
                                      if (bill.waterCost > 0)
                                        _valueChip(
                                          Icons.water_drop,
                                          Colors.blue,
                                          'น้ำ',
                                          '${formatter.format(bill.waterCost)} บาท',
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
          'รวม ${formatter.format(totalCost)} บาท',
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
                          '${formatter.format(log.cost)} บาท',
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
                          '${formatter.format(log.cost)} บาท',
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


// ==================== บันทึกค่ามิเตอร์ต้นรอบ (bottom sheet) ====================
// เดิมเป็น AlertDialog แยกอยู่คนละหน้ากับ "ประวัติค่ามิเตอร์ต้นรอบ" — ย้ายมา
// เป็น bottom sheet แบบเดียวกับ _AddHistoricalBillSheet แล้วรวมเข้ากับหน้า
// ประวัติผ่านปุ่ม FAB "+" แทน ตามที่ขอ (กดดูประวัติ + เพิ่มค่าใหม่ได้ในหน้า
// เดียวกันเลย ไม่ต้องสลับไปมา 2 หน้าเหมือนก่อน)
class _AddStartMeterSheet extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final bool isTou;

  const _AddStartMeterSheet({
    required this.uid,
    required this.firestoreService,
    this.isTou = false,
  });

  @override
  State<_AddStartMeterSheet> createState() => _AddStartMeterSheetState();
}

class _AddStartMeterSheetState extends State<_AddStartMeterSheet> {
  bool _isLoading = true;
  final _eCtrl = TextEditingController();
  final _peakCtrl = TextEditingController();
  final _offPeakCtrl = TextEditingController();
  final _wCtrl = TextEditingController();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  // ดึงค่าปัจจุบันของ user มาตั้งเป็นค่าเริ่มต้นในฟอร์ม (เผื่อแค่มาแก้ไข
  // ไม่ใช่ตั้งใหม่ทั้งหมด) ไม่ได้รับ UserModel มาจากหน้าก่อนหน้าตรงๆ เพื่อให้
  // widget นี้ใช้งานได้เองอิสระ ไม่ผูกกับ state ของหน้าตั้งค่า
  Future<void> _loadCurrent() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    if (user != null && mounted) {
      _eCtrl.text = user.startElectricityValue == 0
          ? ''
          : user.startElectricityValue.toString();
      _peakCtrl.text =
          user.startPeakValue == 0 ? '' : user.startPeakValue.toString();
      _offPeakCtrl.text = user.startOffPeakValue == 0
          ? ''
          : user.startOffPeakValue.toString();
      _wCtrl.text =
          user.startWaterValue == 0 ? '' : user.startWaterValue.toString();
      _selectedMonth = user.startBillingMonth == 0
          ? DateTime.now().month
          : user.startBillingMonth;
      _selectedYear = user.startBillingYear == 0
          ? DateTime.now().year
          : user.startBillingYear;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _eCtrl.dispose();
    _peakCtrl.dispose();
    _offPeakCtrl.dispose();
    _wCtrl.dispose();
    super.dispose();
  }

  void _showInfoPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('กรอกเลขจากบิลตรงไหน?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'เปิดใบแจ้งหนี้ค่าไฟ/ค่าน้ำเดือนล่าสุดของคุณ แล้วมองหาช่อง'
          '"เลขอ่านครั้งหลัง" หรือภาษาอังกฤษว่า "Last Meter '
          'Reading" ค่ะ — คือเลขที่มิเตอร์อ่านได้ล่าสุดตอนที่'
          'เจ้าหน้าที่มาจดในรอบบิลนั้น เอาตัวเลขนี้มากรอกตรงนี้'
          'ได้เลย (ไม่ใช่เลข "เลขอ่านครั้งก่อน" ที่อยู่คู่กัน '
          'เพราะอันนั้นเป็นเลขของรอบก่อนหน้า)\n\n'
          'ระบบจะใช้เลขนี้เป็นจุดเริ่มต้นของรอบบิลถัดไป '
          'เพื่อคำนวณว่าคุณใช้ไปกี่หน่วยเมื่อเทียบกับเลขที่คุณ'
          'บันทึกในแอปครั้งถัดไปค่ะ',
          style: TextStyle(fontSize: 13.5, height: 1.6),
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

  InputDecoration _fieldDecoration({
    required String hint,
    required String suffixText,
    required IconData icon,
    required Color iconColor,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: Icon(icon, color: iconColor),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final eVal = double.tryParse(_eCtrl.text) ?? 0;
      final peakVal = double.tryParse(_peakCtrl.text) ?? 0;
      final offPeakVal = double.tryParse(_offPeakCtrl.text) ?? 0;
      final wVal = double.tryParse(_wCtrl.text) ?? 0;

      await widget.firestoreService.updateUser(widget.uid, {
        'startElectricityValue': eVal,
        'startPeakValue': peakVal,
        'startOffPeakValue': offPeakVal,
        'startWaterValue': wVal,
        'startBillingMonth': _selectedMonth,
        'startBillingYear': _selectedYear,
      });
      // เก็บ snapshot ไว้ในประวัติ เผื่อย้อนดูทีหลังว่าเคยตั้งค่าอะไรไว้
      await widget.firestoreService.saveStartMeterRecord(
        StartMeterRecordModel(
          id: const Uuid().v4(),
          uid: widget.uid,
          electricityValue: eVal,
          waterValue: wVal,
          peakValue: peakVal,
          offPeakValue: offPeakVal,
          billingMonth: _selectedMonth,
          billingYear: _selectedYear,
          recordedAt: DateTime.now(),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
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
                      const Text(
                        'บันทึกค่ามิเตอร์ต้นรอบ',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.help_outline,
                                color: Color(0xFF2E7D32)),
                            onPressed: _showInfoPopup,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'เดือนของใบแจ้งหนี้',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: _selectedMonth,
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
                                    setState(() => _selectedMonth = val!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedYear,
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
                                    setState(() => _selectedYear = val!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ไฟฟ้า — ถ้าเป็น TOU แยก On-Peak/Off-Peak สองช่อง
                        // ถ้าปกติใช้ช่องเดียว (ตรงกับที่หน้าประวัติแสดงผล)
                        if (widget.isTou) ...[
                          const Text(
                            'หน่วยไฟฟ้า On-Peak',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _peakCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _fieldDecoration(
                              hint: 'เช่น 8500',
                              suffixText: 'หน่วย',
                              icon: Icons.bolt,
                              iconColor: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'หน่วยไฟฟ้า Off-Peak',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _offPeakCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _fieldDecoration(
                              hint: 'เช่น 5500',
                              suffixText: 'หน่วย',
                              icon: Icons.bolt_outlined,
                              iconColor: Colors.blueGrey,
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'หน่วยไฟฟ้า',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _eCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _fieldDecoration(
                              hint: 'เช่น 14009',
                              suffixText: 'หน่วย',
                              icon: Icons.bolt,
                              iconColor: Colors.orange,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'หน่วยน้ำประปา',
                          style:
                              TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _wCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _fieldDecoration(
                            hint: 'เช่น 148',
                            suffixText: 'ลบ.ม.',
                            icon: Icons.water_drop,
                            iconColor: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const Text('บันทึก'),
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

  // เปิด bottom sheet บันทึกค่ามิเตอร์ต้นรอบ — เดิมเป็นปุ่มแยกอยู่คนละหน้า
  // ในหมวด "ตั้งค่าระบบ" ย้ายมารวมกับหน้าประวัติผ่านปุ่ม FAB นี้แทน
  Future<void> _openSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddStartMeterSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        isTou: widget.isTou,
      ),
    );
    if (saved == true) _load();
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
      appBar: AppBar(title: const Text('ค่ามิเตอร์ต้นรอบ')),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openSheet,
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
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

// อธิบายว่า Fixed Cost คืออะไร ทำไมต้องแยกเป็นรายการย่อยแทนยอดเดียว
void _showFixedCostInfoPopup(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text('Fixed Cost คืออะไร?', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: const Text(
        'Fixed Cost คือค่าใช้จ่ายประจำที่ไม่ใช่ค่าไฟหรือค่าน้ำ แต่จ่ายทุกเดือน '
        'ในจำนวนที่ค่อนข้างคงที่ เช่น ค่าแก๊สหุงต้ม ค่าอินเทอร์เน็ต '
        'ค่าส่วนกลางหมู่บ้าน/คอนโด เพื่อให้เห็น "ยอดค่าใช้จ่ายเดือนนี้" '
        'ที่ตรงกับความเป็นจริงมากขึ้น ไม่ใช่แค่ค่าไฟ-น้ำอย่างเดียว\n\n'
        'ทำไมต้องแยกเป็นรายการย่อย: เพราะแต่ละรายการเปลี่ยนแปลงไม่พร้อมกัน '
        '(เช่น เดือนนี้ค่าแก๊สขึ้น แต่ค่าอินเทอร์เน็ตเท่าเดิม) การแยกรายการ '
        'ทำให้แก้ไขหรือลบทีละรายการได้ง่าย โดยระบบจะรวมยอดทั้งหมดให้อัตโนมัติ '
        'แล้วนำไปบวกกับค่าไฟ-น้ำในหน้าหลักและหน้าวิเคราะห์ค่ะ',
        style: TextStyle(fontSize: 13.5, height: 1.6),
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
                    suffixText: ' บาท',
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
      appBar: AppBar(
        title: const Text('Fixed Cost รายเดือน'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFixedCostInfoPopup(context),
          ),
        ],
      ),
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
                              '${formatter.format(_total)} บาท',
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
                                    '${formatter.format(item.amount)} บาท',
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