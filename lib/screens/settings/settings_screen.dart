import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../utils/calculator.dart';
import '../../utils/forecaster.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/excel_style_table.dart';
import '../../widgets/info_dialog.dart';
import '../../widgets/start_meter_fields.dart';
import '../auth/auth_gate.dart';

// ไฟล์นี้เดิมยาว 4,633 บรรทัด รวม 12 คลาสไว้ในไฟล์เดียว (settings หลัก,
// ประวัติบิลย้อนหลัง, ประวัติไฟฟ้า/น้ำ, ประวัติมิเตอร์ต้นรอบ, Fixed Cost,
// หน้าอธิบายอัตราค่าไฟ/น้ำ) แก้ไข/หาอะไรทีต้องเลื่อนหาเป็นพันบรรทัด
//
// แยกออกเป็นไฟล์ย่อยตามหน้าที่ด้วย part/part of (ไม่ใช้ export คลาสเป็น
// public เพราะคลาสพวกนี้เป็น implementation detail ของหน้า Settings ล้วนๆ
// ไม่มีที่อื่นในแอปเรียกใช้ตรงๆ — part ทำให้ยังอ้างอิงกันเหมือนอยู่ไฟล์
// เดียวได้ปกติ ไม่ต้องเปลี่ยนชื่อคลาสเป็น public หรือ import ซ้ำในแต่ละไฟล์)
part 'settings_bill_history.dart'; // เพิ่ม/แก้ไข/ดูรายการบิลย้อนหลัง
part 'settings_fixed_cost.dart'; // รายการค่าใช้จ่ายคงที่
part 'settings_rate_explanation.dart'; // อธิบายอัตราค่าไฟฟ้า/น้ำ (ไฟฟ้า+น้ำ)
part 'settings_start_meter.dart'; // บันทึก + ประวัติมิเตอร์ต้นรอบ
part 'settings_utility_log.dart'; // ประวัติมิเตอร์ไฟฟ้า/น้ำที่บันทึกแต่ละวัน

// ทางลัดเปิดหน้าย่อยทันทีตอนเข้าหน้าตั้งค่า (ใช้จากหน้าเช็คลิสหลัง setup —
// setup_complete_screen.dart — เพื่อให้แตะรายการแล้วพาไปตั้งค่าเรื่องนั้นๆ
// ตรงๆ แทนที่จะต้องมาไล่หาเองในหน้าตั้งค่า)
enum SettingsQuickAction { billingDay, startMeter, historicalBills }

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

  // -------------------------------------------------------------------
  // สีของหน้าตั้งค่า — ใช้เขียวเดียวกันทุกหมวดเหมือนเดิม (ลองแยกสีตาม
  // หมวดไปแล้วแต่พอดีอยากได้เขียวเหมือนเดิมมากกว่า) เก็บเป็น constant
  // ไว้จุดเดียวเผื่ออยากเปลี่ยนสีทีหลัง ไม่ต้องไล่แก้ทีละจุด
  // -------------------------------------------------------------------
  static const Color _sectionColor = Color(0xFF2E7D32);

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
            _showEditBillingDay();
            break;
          case SettingsQuickAction.startMeter:
            _showStartMeterHistory();
            break;
          case SettingsQuickAction.historicalBills:
            _showHistoricalBillList();
            break;
        }
      });
    }
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

  // ==================== ลบบัญชี + ข้อมูลทั้งหมด (PDPA) ====================
  // ลำดับขั้นตอนตั้งใจเรียงแบบนี้:
  // 1) ยืนยันครั้งแรก อธิบายผลที่จะเกิดขึ้นให้ชัดว่าลบอะไรบ้าง กู้คืนไม่ได้
  // 2) ขอรหัสผ่าน reauthenticate — Firebase บังคับ requires-recent-login
  //    สำหรับ operation อ่อนไหวแบบลบบัญชีอยู่แล้ว ถ้า session login ค้างไว้
  //    นานจะโดน FirebaseAuthException 'requires-recent-login' ทันทีถ้าข้าม
  //    ขั้นตอนนี้ไป
  // 3) ลบข้อมูลใน Firestore ก่อน แล้วค่อยลบบัญชี Auth เป็นลำดับสุดท้าย
  //    (ถ้าลบบัญชี Auth ก่อนแล้วลบ Firestore ไม่สำเร็จ จะไม่มีทาง sign-in
  //    กลับมาลบข้อมูลที่เหลือได้อีก เพราะบัญชีหายไปแล้ว กลายเป็นข้อมูล
  //    กำพร้าค้างอยู่ถาวร)
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'ลบบัญชีและข้อมูลทั้งหมด?',
      content: 'การลบบัญชีจะลบข้อมูลทั้งหมดถาวร ได้แก่ ประวัติมิเตอร์ไฟ/น้ำ, '
          'บิลย้อนหลังทั้งหมด, เครื่องใช้ไฟฟ้าที่บันทึกไว้, ค่าใช้จ่ายคงที่ '
          'รายเดือน และการตั้งค่าบัญชีทั้งหมด — กู้คืนไม่ได้ไม่ว่ากรณีใดค่ะ',
      confirmLabel: 'ลบถาวร',
    );
    if (!confirmed) return;
    if (!mounted) return;

    final password = await _askPasswordForDeletion();
    if (password == null || password.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);

      await _firestoreService.deleteAllUserData(user.uid);
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String message = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้งค่ะ';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'รหัสผ่านไม่ถูกต้องค่ะ';
      } else if (e.code == 'too-many-requests') {
        message = 'ลองผิดหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่ค่ะ';
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ลบบัญชีไม่สำเร็จ กรุณาลองใหม่อีกครั้งค่ะ')),
      );
    }
  }

  // ขอรหัสผ่านก่อนลบบัญชี — คืนค่า null ถ้ากดยกเลิก
  Future<String?> _askPasswordForDeletion() {
    final ctrl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('ยืนยันตัวตนก่อนลบบัญชี',
              style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กรอกรหัสผ่านของบัญชีนี้อีกครั้งเพื่อยืนยันว่าเป็นคุณเอง',
                style: TextStyle(fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'รหัสผ่าน',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon:
                        Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('ยืนยัน', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text(
          'ตั้งค่า',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
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

                  // โซนอันตราย — ลบบัญชี+ข้อมูลทั้งหมดถาวร (PDPA: สิทธิ
                  // ขอให้ลบข้อมูลส่วนบุคคล) แยกเป็นการ์ดขอบแดงต่างหาก
                  // ไม่ปนกับหมวดอื่น กันกดโดนโดยไม่ตั้งใจ
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
              color: color.withValues(alpha: 0.12),
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
    final initials = _getInitials(_user?.name ?? '');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
                    fontSize: 15,
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
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user?.email ?? '-',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // แก้ได้เฉพาะชื่อเหมือนเดิม — อีเมลไม่มีปุ่มแก้ไข
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
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
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
        borderRadius: BorderRadius.circular(12),
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
            title: 'เลขมิเตอร์ต้นรอบ',
            subtitle: 'บันทึกเลขใหม่ และดูประวัติที่เคยตั้งไว้ทั้งหมด',
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
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _sectionColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.notifications_active_outlined,
                  color: _sectionColor, size: 20),
            ),
            title: const Text(
              'การแจ้งเตือนทั้งหมด',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              granted ? 'เปิดอยู่' : 'ปิดอยู่',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            title: 'ใกล้วันตัดรอบบิล',
            subtitle: 'เตือนล่วงหน้าก่อนถึงวันตัดรอบบิลของคุณ',
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
            subtitle: 'แจ้งสรุปค่าใช้จ่ายทันทีที่จบรอบบิลแต่ละเดือน',
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
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (enabled ? _sectionColor : Colors.grey).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 20,
                color: enabled ? _sectionColor : Colors.grey.shade400),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: enabled ? Colors.black87 : Colors.grey.shade400,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
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
        borderRadius: BorderRadius.circular(12),
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
            title: 'ประวัติมิเตอร์ไฟฟ้า / ประปา',
            subtitle: 'ดูและลบประวัติการบันทึก แยกแท็บไฟฟ้า-น้ำ',
            color: _sectionColor,
            onTap: () => _showUtilityHistory(),
          ),
          const Divider(height: 1, indent: 56),
          // ให้ผู้ใช้เข้าใจว่าตัวเลขในบิลที่แอปคำนวณให้มาจากไหน — โชว์
          // ตารางอัตราขั้นบันได/TOU และคำอธิบาย Ft/VAT/ค่าน้ำขั้นต่ำแบบ
          // อ่านง่าย ตามเกณฑ์ (พื้นที่ + ประเภทมิเตอร์) ที่ผู้ใช้ตั้งไว้จริง
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

  // โซนอันตราย: ลบบัญชี + ข้อมูลทั้งหมดถาวร
  // ทำเป็นการ์ดขอบแดงแยกจาก _buildDataCard ตั้งใจ — ไม่ให้ปุ่มทำลายล้าง
  // แบบนี้ไปปนกับ tile ธรรมดาที่กดแล้วแค่เปิดดูข้อมูล ลดโอกาสกดพลาด
  Widget _buildDangerZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
        onTap: () => _confirmDeleteAccount(),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
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
              if (context.mounted) Navigator.pop(context);
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
    showInfoDialog(context, title: title, message: message);
  }

  // วันที่ "ยอดนิยม" ที่ให้ป้ายกำกับในปฏิทินเลือกวันตัดรอบบิล — เป็นชุดคงที่
  // สำหรับความสวยงามของ UI เท่านั้น (แอปยังไม่ได้เก็บสถิติวันที่ผู้ใช้เลือกจริง)
  static const Set<int> _popularBillingDays = {1, 15, 20, 25, 30};

  // ช่องวันที่หนึ่งช่องในปฏิทินเลือกวันตัดรอบบิล (ไม่มีเดือน มีแค่เลข 1-31
  // เพราะวันตัดรอบบิลซ้ำทุกเดือนอยู่แล้ว ไม่ต้องให้เลือกเดือน)
  Widget _buildBillingDayCell({
    required int day,
    required bool isSelected,
    required bool isPopular,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            if (isPopular)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'ยอดนิยม',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.green.shade700,
                  ),
                ),
              ),
          ],
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      icon: const Icon(Icons.info_outline,
                          color: Color(0xFF2E7D32), size: 20),
                      onPressed: () => _showInfoPopup(
                        'วันตัดรอบบิลคืออะไร?',
                        'เลือกวันตัดรอบบิลตามวันที่ใบแจ้งหนี้ค่าไฟหรือค่าน้ำ'
                            'มาถึงบ้าน ระบบจะใช้วันนี้แจ้งเตือนเมื่อใกล้ถึง'
                            'รอบชำระเงิน และเตือนให้บันทึกเลขมิเตอร์ต้นรอบ '
                            'เพื่อตั้งเป็นค่าเริ่มต้นของรอบบิลเดือนถัดไปโดยอัตโนมัติ',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'แตะที่วันบนใบแจ้งหนี้ล่าสุดของคุณ',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                // ปฏิทินเลือกวัน 1-31 แบบกริด 7 คอลัมน์ — mainAxisExtent คงที่
                // เพื่อให้ช่องที่มีป้าย "ยอดนิยม" กับช่องปกติสูงเท่ากัน
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 6,
                    mainAxisExtent: 46,
                  ),
                  // +1 ช่องแรกเป็นช่องว่าง เพื่อให้เลข 1 เริ่มเยื้องคอลัมน์ที่ 2
                  // ตามแพทเทิร์นเลย์เอาต์ปฏิทินที่อ้างอิงมา
                  itemCount: 32,
                  itemBuilder: (context, i) {
                    if (i == 0) return const SizedBox.shrink();
                    final day = i;
                    return _buildBillingDayCell(
                      day: day,
                      isSelected: day == selectedDay,
                      isPopular: _popularBillingDays.contains(day),
                      onTap: () => setDialogState(() => selectedDay = day),
                    );
                  },
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
                          if (context.mounted) Navigator.pop(context);
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

  void _showRateExplanation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _RateExplanationScreen(
          area: _user?.area ?? 'bangkok',
          meterType: _user?.meterType ?? 'normal',
        ),
      ),
    );
  }
}