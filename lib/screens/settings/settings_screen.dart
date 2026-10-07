import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../models/bill_model.dart';
import '../../models/fixed_cost_item_model.dart';
import '../../models/start_meter_record_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/notification_service.dart';
import '../../utils/calculator.dart';
import '../../utils/forecaster.dart';
import '../../utils/tariff_tables.dart';
import '../../utils/tariff_advisor.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/bill_mockup_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_dialog.dart';
import '../../widgets/start_meter_fields.dart';
import '../../widgets/table_row_actions.dart';
import '../../widgets/tab_chip.dart';
import '../../widgets/ui/animated_amount.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/fade_slide_in.dart';
import '../../widgets/ui/icon_badge.dart';
import '../auth/auth_gate.dart';
import '../dashboard/dashboard_styles.dart';

// แยกเป็นไฟล์ย่อยตามหน้าที่ด้วย part/part of แทนคลาส public เพราะเป็น
// implementation detail ของหน้า Settings ล้วนๆ ไม่มีที่อื่นเรียกใช้ตรงๆ
part 'settings_account.dart'; // ลบบัญชีและข้อมูลทั้งหมด (PDPA)
part 'settings_bill_form.dart'; // ฟอร์มเพิ่ม/แก้ไขบิลเดือนเก่า
part 'settings_billing_day.dart'; // หน้าต่างเลือกวันตัดรอบบิล
part 'settings_cost_autofill.dart'; // คำนวณค่าใช้จ่ายอัตโนมัติขณะพิมพ์ (ใช้ร่วม 2 ฟอร์ม)
part 'settings_fixed_cost.dart'; // รายการค่าใช้จ่ายคงที่
part 'settings_invoices.dart'; // หน้าเลขมิเตอร์จากใบแจ้งหนี้ (ใบล่าสุด + บิลย้อนหลัง + ตารางรายเดือน)
part 'settings_rate_explanation.dart'; // อธิบายอัตราค่าไฟฟ้า/น้ำ (ไฟฟ้า+น้ำ)
part 'settings_start_meter.dart'; // ฟอร์มตั้งเลขมิเตอร์ต้นรอบ
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

  // ฉีดของปลอมได้ในเทส — ไม่ส่ง = ใช้ instance จริงของ Firebase
  final FirestoreService? firestoreService;
  final FirebaseAuth? auth;

  const SettingsScreen({
    super.key,
    this.onNavTap,
    this.openFixedCostOnStart = false,
    this.quickAction,
    this.firestoreService,
    this.auth,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final FirestoreService _firestoreService = widget.firestoreService ?? FirestoreService();
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
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
    try {
      final status = await Permission.notification.status;
      if (mounted) setState(() => _notificationStatus = status);
    } catch (_) {
      // อ่านสถานะสิทธิ์ไม่ได้ (เช่น แพลตฟอร์มที่ไม่มีปลั๊กอิน) ถือว่ายังไม่ได้อนุญาต
    }
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
    final uid = _auth.currentUser!.uid;
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

    await NotificationService.instance.cancelScheduledForSignOut();
    await _auth.signOut();
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
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
              children: [
                FadeSlideIn(child: _buildProfileCard()),

                // ค่าที่ตั้งครั้งเดียวแล้วนานๆ เปลี่ยน
                _sectionLabel('รอบบิลและค่าใช้จ่าย'),
                FadeSlideIn(delay: const Duration(milliseconds: 60), child: _buildSettingsGroup()),

                // ข้อมูลที่กรอก/ดูตามรอบบิล เรียงตามลำดับใช้งาน: เลขจากใบแจ้งหนี้ →
                // ประวัติบันทึกมิเตอร์ → บิลเดือนเก่า → อัตราที่ใช้คิดเงิน
                _sectionLabel('ข้อมูลมิเตอร์และบิล'),
                FadeSlideIn(delay: const Duration(milliseconds: 120), child: _buildDataGroup()),

                _sectionLabel('การแจ้งเตือน'),
                FadeSlideIn(delay: const Duration(milliseconds: 180), child: _buildNotificationCard()),

                // ออกจากระบบ + ลบบัญชี (PDPA: สิทธิขอให้ลบข้อมูลส่วนบุคคล) อยู่ท้ายสุด
                // แยกจากเมนูอื่น ลบบัญชีเป็นแถวสีแดงและต้องยืนยันก่อนเสมอ
                _sectionLabel('บัญชี'),
                _buildAccountGroup(),
              ],
            ),
      // ผ่าน MainShell บาร์ล่างอยู่ที่ shell ตัวเดียว (แคปซูลเลื่อนระหว่างแท็บได้)
      bottomNavigationBar: widget.onNavTap == null ? const AppBottomNavBar(currentIndex: 3) : null,
    );
  }

  // หัวกลุ่มเมนู — ตัวหนังสือเล็กสีเทาเหนือการ์ด
  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v4, AppSpacing.v24, AppSpacing.v4, AppSpacing.v8),
      child: Text(
        title,
        style: TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
      ),
    );
  }

  // การ์ดรวมแถวเมนูหลายแถว คั่นด้วยเส้นบางที่เริ่มหลังไอคอน
  Widget _group(List<Widget> tiles) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const Divider(indent: 66),
            tile,
          ],
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final user = _user;
    final isBangkok = user?.area == 'bangkok';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: _sectionColor.withValues(alpha: 0.12),
                child: Text(
                  _getInitials(user?.name ?? ''),
                  style: const TextStyle(
                      color: _sectionColor, fontWeight: FontWeight.w700, fontSize: AppTypography.s16),
                ),
              ),
              const SizedBox(width: AppSpacing.v14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: AppTypography.s16, color: AppColors.textDark),
                    ),
                    const SizedBox(height: AppSpacing.v2),
                    Text(
                      user?.email ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              // แก้ได้เฉพาะชื่อ — อีเมลไม่มีปุ่มแก้ไข
              IconButton(
                tooltip: 'แก้ไขชื่อ',
                icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade600),
                onPressed: _showEditName,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v12),
          Wrap(
            spacing: AppSpacing.v8,
            runSpacing: AppSpacing.v6,
            children: [
              _infoChip(Icons.location_on_outlined, isBangkok ? 'กรุงเทพและปริมณฑล' : 'ต่างจังหวัด'),
              _infoChip(Icons.electric_meter_outlined, user?.meterType == 'tou' ? 'มิเตอร์ TOU' : 'มิเตอร์ปกติ'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v5),
      decoration: BoxDecoration(
        color: DashboardStyles.background,
        borderRadius: BorderRadius.circular(AppSpacing.v20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: AppSpacing.v4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  // ตัวอักษรย่อสำหรับ avatar — ชื่อเดียวเอา 2 ตัวแรก, ชื่อ+นามสกุลเอาตัวแรกของแต่ละ
  // คำ (เช่น "kidsnoi" → "KI", "สมชาย ใจดี" → "สจ") ภาษาไทยข้ามสระที่เขียนหน้า
  // พยัญชนะ (เ แ โ ใ ไ) ให้ได้ตัวพยัญชนะ
  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    String firstLetter(String word) =>
        word.characters.firstWhere((c) => !'เแโใไ'.contains(c), orElse: () => word.characters.first);
    if (parts.length == 1) {
      final letters = parts[0].characters.where((c) => !'เแโใไ'.contains(c)).take(2).join();
      return (letters.isEmpty ? parts[0].characters.first : letters).toUpperCase();
    }
    return (firstLetter(parts[0]) + firstLetter(parts[1])).toUpperCase();
  }

  // ค่าที่ตั้งครั้งเดียวแล้วนานๆ เปลี่ยน (วันตัดรอบ, ประเภทอัตรา, รายจ่ายประจำ)
  // แต่ละแถวแสดงค่าปัจจุบันไว้ด้านขวา ไม่ต้องกดเข้าไปดู
  Widget _buildSettingsGroup() {
    final user = _user;
    final fixedCost = user?.fixedCost ?? 0;
    return _group([
      _buildSettingsTile(
        icon: Icons.event_repeat_rounded,
        title: 'วันตัดรอบบิล',
        subtitle: 'วันแรกของรอบบิลใหม่ ดูได้จากใบแจ้งหนี้',
        value: user == null || !user.billingDayConfigured ? 'ยังไม่ได้ตั้ง' : 'วันที่ ${user.billingDay}',
        onTap: () => _showBillingDayDialog(
          context,
          user: _user,
          firestoreService: _firestoreService,
          onSaved: _loadUser,
        ),
      ),
      // ประเภทอัตราใช้กับมิเตอร์ปกติเท่านั้น (TOU มีอัตราของตัวเอง)
      if (user != null && user.meterType != 'tou')
        _buildSettingsTile(
          icon: Icons.receipt_outlined,
          title: 'ประเภทอัตราค่าไฟ',
          subtitle: 'ดูได้จากใบแจ้งหนี้ค่าไฟ',
          value: tariffLabel(user.electricityTariff, user.area),
          onTap: () => showElectricityTariffDialog(
            context,
            user: user,
            firestoreService: _firestoreService,
            onSaved: _loadUser,
          ),
        ),
      _buildSettingsTile(
        icon: Icons.payments_outlined,
        title: 'รายจ่ายประจำ',
        subtitle: 'ค่าใช้จ่ายที่จ่ายทุกเดือน เช่น อินเทอร์เน็ต ค่าส่วนกลาง',
        value: fixedCost > 0 ? 'เดือนนี้ ${NumberFormat('#,##0').format(fixedCost)} บาท' : 'ยังไม่มี',
        onTap: () => _showEditFixedCost(),
      ),
    ]);
  }

  Widget _buildDataGroup() {
    return _group([
      // หน้าเดียวรวมใบแจ้งหนี้ล่าสุด (ตั้งต้นรอบ) กับบิลย้อนหลัง
      _buildSettingsTile(
        icon: Icons.receipt_long_outlined,
        title: 'เลขมิเตอร์จากใบแจ้งหนี้',
        subtitle: 'กรอกทุกครั้งที่ได้ใบใหม่ และเพิ่มบิลย้อนหลัง',
        onTap: () => _showInvoices(),
      ),
      _buildSettingsTile(
        icon: Icons.history_rounded,
        title: 'ประวัติการบันทึกมิเตอร์',
        subtitle: 'ดูและลบรายการที่บันทึกไว้ ทั้งไฟฟ้าและน้ำ',
        onTap: () => _showUtilityHistory(),
      ),
      // ตารางอัตราขั้นบันได/TOU และคำอธิบายประเภทอัตรา/Ft/VAT/ค่าบริการน้ำ
      // ตามเกณฑ์ที่ผู้ใช้ตั้งไว้จริง
      _buildSettingsTile(
        icon: Icons.calculate_outlined,
        title: 'อัตราค่าไฟฟ้าและค่าน้ำ',
        subtitle: 'ตารางอัตราและวิธีคิดบิลที่แอปใช้',
        onTap: () => _showRateExplanation(),
      ),
    ]);
  }

  Widget _buildAccountGroup() {
    return _group([
      _buildSettingsTile(
        icon: Icons.logout_rounded,
        title: 'ออกจากระบบ',
        color: Colors.grey.shade700,
        showChevron: false,
        onTap: _confirmSignOut,
      ),
      _buildSettingsTile(
        icon: Icons.delete_forever_outlined,
        title: 'ลบบัญชีและข้อมูลทั้งหมด',
        subtitle: 'ลบถาวร กู้คืนไม่ได้ (ตามสิทธิ PDPA)',
        color: Colors.red.shade700,
        titleColor: Colors.red.shade700,
        showChevron: false,
        onTap: () => _confirmDeleteAccount(
          context,
          firestoreService: _firestoreService,
          setBusy: (busy) {
            if (mounted) setState(() => _isLoading = busy);
          },
        ),
      ),
    ]);
  }

  // การ์ดการแจ้งเตือน — สวิตช์บนสุดคุมสิทธิ์แจ้งเตือนของเครื่องทั้งหมด ส่วน 4
  // สวิตช์ย่อยคุมประเภทที่อยากรับ แสดงเมื่อได้รับสิทธิ์แล้วเท่านั้น
  Widget _buildNotificationCard() {
    final granted = _notificationStatus == PermissionStatus.granted;
    return _group([
      _switchTile(
        icon: Icons.notifications_active_outlined,
        title: 'การแจ้งเตือนของแอป',
        subtitle: granted
            ? 'เปิดอยู่ เลือกประเภทที่อยากรับได้ด้านล่าง'
            : 'ปิดอยู่ เปิดเพื่อรับการแจ้งเตือนวันตัดรอบบิล การจดมิเตอร์ และสรุปค่าใช้จ่ายค่ะ',
        value: granted,
        onChanged: (val) => _toggleNotification(val),
      ),
      // ยังไม่ได้รับสิทธิ์ ประเภทย่อยไม่มีผล จึงซ่อนไว้จนกว่าจะเปิดสวิตช์บน
      if (granted) ..._notifTypeToggles(),
    ]);
  }

  List<Widget> _notifTypeToggles() {
    return [
      _notifTypeToggle(
        icon: Icons.event_available_outlined,
        title: 'ถึงวันตัดรอบบิล',
        subtitle: 'เตือนเช้าวันตัดรอบ ให้บันทึกเลขมิเตอร์จากใบแจ้งหนี้ใหม่',
        type: 'billing',
      ),
      _notifTypeToggle(
        icon: Icons.speed_outlined,
        title: 'ยังไม่บันทึกมิเตอร์',
        subtitle: 'เตือนเมื่อถึงเวลาแล้วแต่ยังไม่ได้จดมิเตอร์',
        type: 'meter',
      ),
      _notifTypeToggle(
        icon: Icons.trending_up_rounded,
        title: 'ใช้ไฟ/น้ำพุ่งขึ้นผิดปกติ',
        subtitle: 'เตือนเมื่อค่าไฟหรือค่าน้ำสูงผิดปกติจากที่ผ่านมา',
        type: 'spike',
      ),
      _notifTypeToggle(
        icon: Icons.summarize_outlined,
        title: 'สรุปยอดท้ายรอบบิล',
        subtitle: 'สรุปค่าใช้จ่ายเมื่อจบรอบบิล แนะนำเมื่อควรตรวจประเภทอัตราค่าไฟ และแจ้งเมื่อค่า Ft งวดใหม่มีผล',
        type: 'summary',
      ),
    ];
  }

  Widget _notifTypeToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
  }) {
    return _switchTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: _notifPrefs[type] ?? true,
      onChanged: (val) => _setNotifPref(type, val),
    );
  }

  // แถวที่มีสวิตช์ — กดได้ทั้งแถว ไม่ต้องเล็งโดนตัวสวิตช์ ([onChanged] null = ปิดใช้งาน)
  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v10, AppSpacing.v12),
        child: Row(
          children: [
            IconBadge(icon: icon, color: enabled ? _sectionColor : Colors.grey.shade400, size: 38),
            const SizedBox(width: AppSpacing.v12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTypography.s14,
                          color: enabled ? AppColors.textDark : Colors.grey.shade500)),
                  const SizedBox(height: AppSpacing.v2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: AppTypography.s12,
                          height: 1.4,
                          color: enabled ? Colors.grey.shade600 : Colors.grey.shade400)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.v4),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  // แถวเมนู: ไอคอน + ชื่อ + คำอธิบาย + ค่าปัจจุบัน ([value]) + ลูกศร
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    required VoidCallback onTap,
    Color color = _sectionColor,
    Color titleColor = AppColors.textDark,
    bool showChevron = true,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v12, AppSpacing.v12),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38),
            const SizedBox(width: AppSpacing.v12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s14, color: titleColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.v2),
                    Text(subtitle,
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade600)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppSpacing.v8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: _sectionColor)),
              ),
            ],
            if (showChevron) Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 22),
          ],
        ),
      ),
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
              await _auth.currentUser?.updateDisplayName(newName);
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
        builder: (context) => FixedCostScreen(
          uid: _user!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
    await _loadUser();
  }

  void _showInvoices() => openInvoiceScreen(context, _user!.uid, _firestoreService);

  void _showUtilityHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _UtilityHistoryScreen(
          uid: _auth.currentUser!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }

  void _showRateExplanation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RateExplanationScreen(
          area: _user?.area ?? 'bangkok',
          meterType: _user?.meterType ?? 'normal',
          tariff: _user?.electricityTariff ?? EnergyCalculator.tariffStandard,
        ),
      ),
    );
  }
}