import 'dart:async';

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
import '../../services/google_auth_service.dart';
import '../../services/notification_service.dart';
import '../../utils/calculator.dart';
import '../../utils/forecaster.dart';
import '../../utils/tariff_advisor.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/bill_mockup_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/excel_style_table.dart';
import '../../widgets/info_dialog.dart';
import '../../widgets/start_meter_fields.dart';
import '../../widgets/tab_chip.dart';
import '../auth/auth_gate.dart';
import '../dashboard/dashboard_styles.dart';

// แยกเป็นไฟล์ย่อยตามหน้าที่ด้วย part/part of แทนคลาส public เพราะเป็น
// implementation detail ของหน้า Settings ล้วนๆ ไม่มีที่อื่นเรียกใช้ตรงๆ
part 'settings_account.dart'; // ลบบัญชีและข้อมูลทั้งหมด (PDPA)
part 'settings_bill_form.dart'; // ฟอร์มเพิ่ม/แก้ไขบิลเดือนเก่า
part 'settings_bill_history.dart'; // หน้ารายการบิลเดือนเก่า
part 'settings_billing_day.dart'; // หน้าต่างเลือกวันตัดรอบบิล
part 'settings_cost_autofill.dart'; // คำนวณค่าใช้จ่ายอัตโนมัติขณะพิมพ์ (ใช้ร่วม 2 ฟอร์ม)
part 'settings_fixed_cost.dart'; // รายการค่าใช้จ่ายคงที่
part 'settings_rate_explanation.dart'; // อธิบายอัตราค่าไฟฟ้า/น้ำ (ไฟฟ้า+น้ำ)
part 'settings_start_meter.dart'; // ฟอร์มตั้งเลขมิเตอร์ต้นรอบ
part 'settings_start_meter_history.dart'; // หน้าประวัติเลขมิเตอร์ต้นรอบ
part 'settings_tariff.dart'; // ประเภทอัตราค่าไฟ + popup แนะนำให้ตรวจประเภท
part 'settings_utility_log.dart'; // ประวัติมิเตอร์ไฟฟ้า/น้ำที่บันทึกแต่ละวัน

// ทางลัดเปิดหน้าย่อยทันทีตอนเข้าหน้าตั้งค่า — billingDay = เปิด dialog เลือก
// วันตัดรอบบิล (ใช้จากแบนเนอร์บนแดชบอร์ด และลิงก์ในฟอร์มตั้งเลขมิเตอร์ต้นรอบ)
enum SettingsQuickAction { billingDay }

class SettingsScreen extends StatefulWidget {
  // callback จาก MainShell สำหรับสลับแท็บแบบ IndexedStack (ไม่โหลดหน้าใหม่)
  final ValueChanged<int>? onNavTap;

  // true = เปิดหน้านี้แล้วพาไปหน้า Fixed Cost ทันที (ใช้ตอนกดการ์ด
  // "Fixed Cost ประจำเดือน" จากหน้าหลัก ไม่ต้องมาเจอหน้าตั้งค่าก่อน)
  final bool openFixedCostOnStart;

  // ทางลัดอื่นๆ นอกจาก Fixed Cost — ดู SettingsQuickAction ด้านบน
  final SettingsQuickAction? quickAction;

  const SettingsScreen({
    super.key,
    this.onNavTap,
    this.openFixedCostOnStart = false,
    this.quickAction,
  });

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

  // สีของหน้าตั้งค่า — เขียวเดียวกันทุกหมวด เก็บเป็น constant จุดเดียวเผื่อเปลี่ยนทีหลัง
  static const Color _sectionColor = DashboardStyles.primaryGreen;

  // กันไม่ให้ auto-open หน้า Fixed Cost ซ้ำ ถ้า _loadUser ถูกเรียกอีกครั้ง
  // (เช่น pull-to-refresh หรือ reload หลังปิดหน้า Fixed Cost กลับมา)
  bool _fixedCostAutoOpened = false;

  // กันไม่ให้ widget.quickAction เปิดซ้ำเหมือนกัน (เหตุผลเดียวกับด้านบน)
  bool _quickActionOpened = false;

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

  // เปิด: ขอ permission dialog ได้เลยถ้ายังไม่เคยกดปฏิเสธถาวร ถ้าเคยปฏิเสธถาวร
  // (permanentlyDenied) ต้องพาไปหน้าตั้งค่าเครื่อง — ปิด: iOS/Android ไม่มี API
  // ให้แอปถอนสิทธิ์ตัวเองได้ ต้องพาไปหน้าตั้งค่าเครื่องเหมือนกัน
  Future<void> _toggleNotification(bool turnOn) async {
    if (turnOn && _notificationStatus != PermissionStatus.permanentlyDenied) {
      await NotificationService.instance.requestPermission();
      await _loadNotificationStatus();
      return;
    }

    // เปิดไม่ได้จากในแอปแล้ว หรือกำลังจะปิด — ทั้งสองกรณีต้องพาไปหน้าตั้งค่าเครื่อง
    // รวม popup ไว้ด้วยกัน แค่เปลี่ยนข้อความตามบริบท
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v16)),
        title: Text(turnOn ? 'เปิดแจ้งเตือนไม่ได้จากในแอป' : 'ปิดแจ้งเตือน'),
        content: Text(
          turnOn
              ? 'คุณเคยปิดสิทธิ์แจ้งเตือนของแอปนี้ไว้ค่ะ กรุณาไปเปิดเองที่'
                  'หน้าตั้งค่าเครื่อง > แอป > Energy Home > การแจ้งเตือน'
              : 'ระบบมือถือไม่อนุญาตให้แอปปิดสิทธิ์แจ้งเตือนเองได้ค่ะ กรุณา'
                  'ไปปิดที่หน้าตั้งค่าเครื่อง > แอป > Energy Home > '
                  'การแจ้งเตือน',
          style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.5),
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
              backgroundColor: DashboardStyles.primaryGreen,
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
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (widget.openFixedCostOnStart && _fixedCostAutoOpened == false) {
      _fixedCostAutoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditFixedCost();
      });
    }
    if (widget.quickAction != null && _quickActionOpened == false) {
      _quickActionOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.quickAction!) {
          case SettingsQuickAction.billingDay:
            _showBillingDayDialog(
              context,
              user: _user,
              firestoreService: _firestoreService,
              onSaved: _loadUser,
            );
        }
      });
    }
  }

  // ออกจากระบบด้วย push ไปที่ AuthGate() (มี StreamBuilder ฟัง authStateChanges()
  // ของตัวเอง) พร้อมเคลียร์ประวัติหน้าจอทิ้งทั้งหมด (pushAndRemoveUntil) — ไม่ใช้
  // push ไป LoginScreen() เปล่าๆ เพราะเมื่อ push ไปหน้าอื่น StreamBuilder ที่ root
  // ถูกแทนที่ในสแต็ก ทำให้ไม่มีอะไรฟัง auth state เหลืออยู่
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
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'ตั้งค่า', showBack: false),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DashboardStyles.primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.v16),
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

                  // การแจ้งเตือน — แยกเป็นหมวดของตัวเอง เพราะคนละเรื่องกับตั้งค่าตัวเลข/รอบบิล
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
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // โซนอันตราย — ลบบัญชี+ข้อมูลทั้งหมดถาวร (PDPA: สิทธิขอให้ลบข้อมูล
                  // ส่วนบุคคล) แยกเป็นการ์ดขอบแดงต่างหาก กันกดโดนโดยไม่ตั้งใจ
                  _buildSectionHeader('โซนอันตราย',
                      icon: Icons.warning_amber_rounded, color: Colors.red),
                  _buildDangerZoneCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar:
          AppBottomNavBar(currentIndex: 3, onTap: widget.onNavTap),
    );
  }

  // หัวหมวด: ไอคอนในกรอบสีจาง + ชื่อหมวด — ทุกหมวดใช้ _sectionColor (เขียว)
  // ยกเว้น "โซนอันตราย" ที่ใช้สีแดง
  Widget _buildSectionHeader(
    String title, {
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.v12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.v6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.v8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTypography.s14_5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard() {
    final initials = _getInitials(_user?.name ?? '');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _sectionColor.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: _sectionColor,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypography.s15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _user?.name ?? '-',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.s15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user?.email ?? '-',
                      style: TextStyle(
                        fontSize: AppTypography.s12_5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // แก้ได้เฉพาะชื่อ — อีเมลไม่มีปุ่มแก้ไข
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Colors.grey),
                visualDensity: VisualDensity.compact,
                onPressed: _showEditName,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              Icon(Icons.electric_meter, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_user?.area == 'bangkok' ? 'กรุงเทพและปริมณฑล' : 'ต่างจังหวัด'}'
                  ' · ${_user?.meterType == 'tou' ? 'TOU' : 'ปกติ'}',
                  style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// ตัวอักษรย่อสำหรับ avatar — ชื่อเดียวเอา 2 ตัวแรก, ชื่อ+นามสกุลเอาตัวแรก
// ของแต่ละคำ (เช่น "kidsnoi" → "KI", "สมชาย ใจดี" → "สจ")
  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
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
            title: 'รายจ่ายประจำ',
            subtitle: 'ค่าใช้จ่ายที่คงที่ทุกเดือน',
            color: _sectionColor,
            onTap: () => _showEditFixedCost(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.calendar_today,
            title: 'วันตัดรอบบิล',
            subtitle: 'รอบบิลเริ่มทุกวันที่ ${_user?.billingDay ?? 30} ของเดือน',
            color: _sectionColor,
            onTap: () => _showBillingDayDialog(
              context,
              user: _user,
              firestoreService: _firestoreService,
              onSaved: _loadUser,
            ),
          ),
          // ประเภทอัตราใช้กับมิเตอร์ปกติเท่านั้น (TOU มีอัตราของตัวเอง)
          if (_user != null && _user!.meterType != 'tou') ...[
            const Divider(height: 1, indent: 56),
            _buildSettingsTile(
              icon: Icons.receipt,
              title: 'ประเภทอัตราค่าไฟ',
              subtitle: '${tariffLabel(_user!.electricityTariff, _user!.area)} (ดูได้จากใบแจ้งหนี้)',
              color: _sectionColor,
              onTap: () => showElectricityTariffDialog(
                context,
                user: _user!,
                firestoreService: _firestoreService,
                onSaved: _loadUser,
              ),
            ),
          ],
          const Divider(height: 1, indent: 56),
          // หน้าเดียวรวมประวัติ + เพิ่มค่าใหม่ (มีปุ่ม + ในหน้านั้น)
          _buildSettingsTile(
            icon: Icons.history,
            title: 'เลขมิเตอร์จากใบแจ้งหนี้',
            subtitle: 'กรอกทุกครั้งที่ได้ใบแจ้งหนี้ใหม่ ใช้เป็นจุดเริ่มคำนวณรอบบิล',
            color: _sectionColor,
            onTap: () => _showStartMeterHistory(),
          ),
          const Divider(height: 1, indent: 56),
          _buildSettingsTile(
            icon: Icons.receipt_long,
            title: 'เพิ่มบิลเดือนเก่าเข้าระบบ',
            subtitle: 'เพิ่ม แก้ไข หรือลบบิลในอดีต',
            color: _sectionColor,
            onTap: () => _showHistoricalBillList(),
          ),
        ],
      ),
    );
  }

  // การ์ดการแจ้งเตือน — แยกเป็นหมวดของตัวเอง เพราะเป็นเรื่องสิทธิ์การแจ้งเตือน
  // ของเครื่อง คนละประเภทกับตัวเลข/รอบบิล — สวิตช์บนสุดคุมสิทธิ์แจ้งเตือนของเครื่อง
  // ทั้งหมด ส่วน 4 toggle ย่อยด้านล่างคุมประเภทที่อยากรับ ถ้าสวิตช์บนปิด toggle
  // ย่อยจะกดไม่ได้ (ไม่มีสิทธิ์แจ้งเตือนอยู่แล้วไม่ว่าตั้งประเภทไหนไว้ก็ไม่มีผล)
  Widget _buildNotificationCard() {
    final granted = _notificationStatus == PermissionStatus.granted;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
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
                const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v8),
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.v8),
              decoration: BoxDecoration(
                color: _sectionColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.v8),
              ),
              child: const Icon(Icons.notifications_active_outlined,
                  color: _sectionColor, size: 20),
            ),
            title: const Text(
              'การแจ้งเตือนทั้งหมด',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s14),
            ),
            subtitle: Text(
              granted ? 'เปิดอยู่' : 'ปิดอยู่',
              style: const TextStyle(fontSize: AppTypography.s12, color: Colors.grey),
            ),
            trailing: Switch(
              value: granted,
              activeThumbColor: _sectionColor,
              onChanged: (val) => _toggleNotification(val),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _notifTypeToggle(
            icon: Icons.event_available_outlined,
            title: 'ถึงวันตัดรอบบิล',
            subtitle: 'เตือนเช้าวันตัดรอบ ให้บันทึกเลขมิเตอร์จากใบแจ้งหนี้ใหม่',
            type: 'billing',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.speed_outlined,
            title: 'ยังไม่บันทึกมิเตอร์',
            subtitle: 'เตือนเมื่อถึงเวลาแล้วแต่ยังไม่ได้จดมิเตอร์',
            type: 'meter',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.trending_up_rounded,
            title: 'ใช้ไฟ/น้ำพุ่งขึ้นผิดปกติ',
            subtitle: 'เตือนเมื่อค่าไฟหรือค่าน้ำสูงผิดปกติจากที่ผ่านมา',
            type: 'spike',
            enabled: granted,
          ),
          _notifTypeToggle(
            icon: Icons.summarize_outlined,
            title: 'สรุปยอดท้ายรอบบิล',
            subtitle: 'แจ้งสรุปค่าใช้จ่ายทันทีที่จบรอบบิล และแนะนำเมื่อควรตรวจประเภทอัตราค่าไฟ',
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
    required String subtitle,
    required String type,
    required bool enabled,
    bool isLast = false,
  }) {
    final value = _notifPrefs[type] ?? true;
    return Column(
      children: [
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v8),
          secondary: Container(
            padding: const EdgeInsets.all(AppSpacing.v8),
            decoration: BoxDecoration(
              color: (enabled ? _sectionColor : Colors.grey).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.v8),
            ),
            child: Icon(icon,
                size: 20,
                color: enabled ? _sectionColor : Colors.grey.shade400),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: AppTypography.s14,
              color: enabled ? Colors.black87 : Colors.grey.shade400,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: AppTypography.s12,
              color: enabled ? Colors.grey : Colors.grey.shade400,
            ),
          ),
          value: value,
          activeThumbColor: _sectionColor,
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
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
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
            title: 'ประวัติการบันทึกมิเตอร์',
            subtitle: 'ดูและจัดการประวัติการบันทึก ไฟฟ้า-น้ำ',
            color: _sectionColor,
            onTap: () => _showUtilityHistory(),
          ),
          const Divider(height: 1, indent: 56),
          // ให้ผู้ใช้เข้าใจว่าตัวเลขในบิลมาจากไหน — โชว์ตารางอัตราขั้นบันได/TOU
          // และคำอธิบายประเภทอัตรา/Ft/VAT/ค่าบริการน้ำ ตามเกณฑ์ที่ผู้ใช้ตั้งไว้จริง
          _buildSettingsTile(
            icon: Icons.calculate_outlined,
            title: 'อัตราค่าไฟฟ้า / น้ำ คำนวณยังไง',
            subtitle: 'ตารางอัตราและวิธีคิดบิล อ่านเข้าใจง่าย',
            color: _sectionColor,
            onTap: () => _showRateExplanation(),
          ),
        ],
      ),
    );
  }

  // โซนอันตราย: ลบบัญชี + ข้อมูลทั้งหมดถาวร — แยกการ์ดขอบแดงจาก _buildDataCard
  // ตั้งใจ ไม่ให้ปุ่มทำลายล้างปนกับ tile ธรรมดา ลดโอกาสกดพลาด
  Widget _buildDangerZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildSettingsTile(
        icon: Icons.delete_forever_rounded,
        title: 'ลบบัญชีและข้อมูลทั้งหมด',
        subtitle: 'ลบถาวร กู้คืนไม่ได้ • ตามสิทธิ PDPA',
        color: Colors.red,
        onTap: () => _confirmDeleteAccount(
          context,
          firestoreService: _firestoreService,
          setBusy: (busy) {
            if (mounted) setState(() => _isLoading = busy);
          },
        ),
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v8),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.v8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.v8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: AppTypography.s12, color: Colors.grey),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.v12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v14),
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
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DashboardStyles.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  // Fixed Cost เป็นหน้าแยกที่บันทึกเป็นรายการย่อยได้ (ค่าแก๊ส, อินเทอร์เน็ต
  // ฯลฯ) — ดู _FixedCostScreen ยอดรวม sync เข้า _user.fixedCost อยู่แล้ว เลย
  // reload _loadUser() ทุกครั้งที่กลับจากหน้านั้น
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
        builder: (context) => HistoricalBillListScreen(
          uid: _user!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }

  void _showRateExplanation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _RateExplanationScreen(
          area: _user?.area ?? 'bangkok',
          meterType: _user?.meterType ?? 'normal',
          tariff: _user?.electricityTariff ?? EnergyCalculator.tariffStandard,
        ),
      ),
    );
  }
}