import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/info_dialog.dart';
import 'setup_complete_screen.dart';

class SetupScreen extends StatefulWidget {
  // รับ firestoreService แบบ optional เพื่อให้ AuthGate ส่ง instance ปลอมมา
  // ตอนเทสได้ (เดิม _SetupScreenState สร้าง FirestoreService() ของจริงเอง
  // ตรงๆ ใน field initializer ทำให้ crash ตั้งแต่ก่อน initState ด้วยซ้ำ
  // เวลาเทสโดยไม่มี Firebase.initializeApp())
  const SetupScreen({super.key, FirestoreService? firestoreService})
      : _firestoreService = firestoreService;

  final FirestoreService? _firestoreService;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final FirestoreService _firestoreService =
      widget._firestoreService ?? FirestoreService();

  int _currentStep = 0;
  // คงที่ 2 ขั้นตอนเสมอ: พื้นที่+อธิบายสูตรคำนวณ (รวมเป็นขั้นเดียว) /
  // ประเภทมิเตอร์ (เดิมพื้นที่กับอธิบายสูตรคำนวณแยกกัน 2 ขั้น ตอนนี้รวมเป็น
  // ขั้นเดียวแบบส่วนที่ 1 / ส่วนที่ 2 ในหน้าเดียว)
  //
  // ตัดขั้น "วันตัดรอบบิล" กับ "ค่ามิเตอร์ตามใบแจ้งหนี้" ออกจากเซตอัพแล้ว
  // (ย้ายไปกรอกที่หน้าตั้งค่าแทน) เพราะสองขั้นนั้นเป็น optional อยู่แล้วใน
  // ทางปฏิบัติ (ข้ามได้เสมอ) แถมพอเลือกวันตัดรอบบิลไปแล้วแต่เดือนของใบแจ้ง
  // หนี้ยังต้องมาเดา/แก้เองอีกที ก็ยังรู้สึกไม่ match กับรอบจริงอยู่ดี — ให้
  // ผู้ใช้ทุกคนเข้าหน้าหลักได้เร็วขึ้น แล้วมีการ์ด/แจ้งเตือนจูงไปตั้งค่า
  // ทีหลังแทน ตัวแปรสองชุดนี้จึงเหลือไว้เป็นค่าเริ่มต้น (billingDay = null
  // → fallback 30, start meter = ยังไม่ตั้ง) เหมือน path "ข้ามทุกอย่าง" เดิม
  static const int _totalSteps = 2;
  String _selectedArea = 'bangkok';
  String _selectedMeterType = 'normal';
  final int? _selectedBillingDay = null;
  final int _selectedStartMonth = DateTime.now().month;
  final int _selectedStartYear = DateTime.now().year;

  bool _isLoading = false;

  Future<void> _saveSetup() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // ตัดขั้นวันตัดรอบบิล/ค่ามิเตอร์ตามใบแจ้งหนี้ออกจากเซตอัพแล้ว —
      // ทุกบัญชีใหม่จึงเริ่มแบบ "ยังไม่ตั้ง" เหมือน path เดิมตอนกดข้ามทั้งคู่
      // เสมอ (billingDay fallback 30, start meter ว่าง) ไปกรอกจริงที่หน้า
      // ตั้งค่าแทน ไม่มีการสร้าง StartMeterRecordModel/BillModel ย้อนหลัง
      // ในขั้นตอนนี้อีกต่อไป
      final userModel = UserModel(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        area: _selectedArea,
        meterType: _selectedMeterType,
        billingDay: _selectedBillingDay ?? 30,
        startElectricityValue: 0,
        startWaterValue: 0,
        startPeakValue: 0,
        startOffPeakValue: 0,
        startMeterConfigured: false,
        electricityStartConfigured: false,
        waterStartConfigured: false,
        // ขั้นเลือกวันตัดรอบบิลถูกตัดออกจากเซตอัพแล้ว (ดูคอมเมนต์ด้านบน)
        // _selectedBillingDay เลยเป็น null เสมอในตอนนี้ ทำให้ค่านี้เป็น false
        // เสมอด้วย — คงเงื่อนไขไว้แบบนี้ (ไม่ hardcode false ตรงๆ) เผื่อมีการ
        // เอาขั้นเลือกวันตัดรอบบิลกลับมาใส่ในเซตอัพอีกทีในอนาคต
        billingDayConfigured: _selectedBillingDay != null,
        startBillingMonth: _selectedStartMonth,
        startBillingYear: _selectedStartYear,
      );

      await _firestoreService.createUser(userModel);

      // แจ้งเตือนต้อนรับ — ย้ายมาไว้ตรงนี้แทน Dashboard.initState()
      // เพราะ _saveSetup() รันแค่ครั้งเดียวจริงๆ ต่อบัญชี (เฉพาะตอนบัญชีใหม่
      // ทำ setup เสร็จครั้งแรก ปุ่มกดถูก disable ระหว่าง _isLoading กันกด
      // ซ้ำอยู่แล้ว) ไม่ต้องพึ่ง flag เครื่องแบบเดิมที่ผูกผิดกับ device
      // ไม่ใช่บัญชี
      await NotificationService.instance.notifyWelcome();

      if (!mounted) return;

      // เซตอัพจบแค่ 2 ขั้นตอนนี้เสมอ วันตัดรอบบิล/ค่ามิเตอร์ยังไม่ตั้งทุก
      // บัญชี → แวะหน้าสรุปเพื่อจูงไปตั้งค่าต่อเสมอ (เหมือน path เดิมตอน
      // กดข้ามทั้งคู่)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => SetupCompleteScreen(
            billingDayConfigured: _selectedBillingDay != null,
            startMeterConfigured: userModel.startMeterConfigured,
            startElectricityValue: userModel.startElectricityValue,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(
                children: List.generate(_totalSteps, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: index <= _currentStep
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'ขั้นตอนที่ ${_currentStep + 1} จาก $_totalSteps',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              Expanded(child: _buildStep(_currentStep)),
              Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _currentStep--),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('ย้อนกลับ'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (_currentStep == _totalSteps - 1) {
                                await _saveSetup();
                              } else {
                                setState(() => _currentStep++);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              _currentStep < _totalSteps - 1
                                  ? 'ถัดไป'
                                  : 'เริ่มใช้งาน',
                              style: const TextStyle(fontSize: 16),
                            ),
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

  Widget _buildStep(int step) {
    switch (step) {
      case 0:
        return _buildAreaAndRateExplanationStep();
      case 1:
        return _buildMeterTypeStep();
      default:
        return const SizedBox();
    }
  }

  // ขั้นรวม: ส่วนที่ 1 เลือกพื้นที่ + ส่วนที่ 2 อธิบายสูตรคำนวณแบบภาพรวม
  // (ไม่ลงรายละเอียดปกติ/TOU ตรงนี้ เพราะยังไม่เลือกในขั้นตอนนี้ — รายละเอียด
  // แยกตามประเภทมิเตอร์ย้ายไปอยู่ในหน้าเลือกประเภทมิเตอร์แทนแล้ว)
  Widget _buildAreaAndRateExplanationStep() {
    final isBangkok = _selectedArea == 'bangkok';

    final electricityLine = isBangkok
        ? '• ค่าไฟ (MEA): คิดขั้นบันไดตามหน่วยที่ใช้ บวกค่า Ft และค่าบริการ'
            'รายเดือน'
        : '• ค่าไฟ (PEA): คิดขั้นบันไดเช่นกัน แต่เลือกอัตราให้อัตโนมัติตาม'
            'หน่วยที่ใช้จริงแต่ละเดือน';
    final waterLine = isBangkok
        ? '• ค่าน้ำ (MWA): คิดขั้นบันไดตามหน่วยที่ใช้ บวกค่าบริการรายเดือน'
            'และค่าน้ำดิบเล็กน้อย'
        : '• ค่าน้ำ (PWA): คิดขั้นบันไดตามหน่วยที่ใช้ บวกค่าบริการรายเดือน';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            icon: Icons.location_city,
            title: 'คุณอยู่ในพื้นที่ไหน?',
            subtitle: 'เพื่อคำนวณค่าไฟและค่าน้ำให้ถูกต้องตามพื้นที่ของคุณ',
            helpTitle: 'ค่าไฟและค่าน้ำคิดยังไง?',
            helpMessage: '$electricityLine\n\n$waterLine',
          ),
          const SizedBox(height: 28),
          _buildSelectionCard(
            title: 'กรุงเทพและปริมณฑล',
            subtitle: 'ไฟฟ้านครหลวง (MEA) • ประปานครหลวง (MWA)',
            icon: Icons.location_city,
            isSelected: _selectedArea == 'bangkok',
            onTap: () => setState(() => _selectedArea = 'bangkok'),
          ),
          const SizedBox(height: 12),
          _buildSelectionCard(
            title: 'ส่วนภูมิภาค',
            subtitle: 'ไฟฟ้าส่วนภูมิภาค (PEA) • ประปาส่วนภูมิภาค (PWA)',
            icon: Icons.nature,
            isSelected: _selectedArea == 'province',
            onTap: () => setState(() => _selectedArea = 'province'),
          ),
        ],
      ),
    );
  }

  Widget _buildMeterTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          icon: Icons.electric_meter,
          title: 'ประเภทมิเตอร์ไฟฟ้า',
          subtitle: 'เลือกตามที่ระบุในใบแจ้งหนี้ค่าไฟของคุณ',
          helpTitle: 'ปกติ vs TOU ต่างกันยังไง?',
          helpMessage:
              '• มิเตอร์ปกติ: คิดอัตราขั้นบันไดตามหน่วยรวมทั้งเดือน ระบบ'
              'ล็อกเป็นประเภท 1.2 (มิเตอร์เกิน 5(15)A) ให้อัตโนมัติ '
              'เพราะเป็นขนาดที่บ้านทั่วไปใช้กันอยู่แล้ว และเกณฑ์แยกขนาด'
              'มิเตอร์ของ MEA เองก็ปรับเปลี่ยนได้ไม่ตายตัว\n\n'
              '• มิเตอร์ TOU: คิดแยกช่วงเวลา กลางวัน (On-Peak) แพงกว่า '
              'กลางคืน/วันหยุด (Off-Peak) ถูกกว่า เหมาะกับบ้านที่ใช้ไฟ'
              'ช่วงกลางคืนเยอะ เช่น เปิดแอร์นอน',
        ),
        const SizedBox(height: 28),
        _buildSelectionCard(
          title: 'มิเตอร์ปกติ',
          subtitle: 'คิดอัตราขั้นบันได เหมาะสำหรับบ้านทั่วไป',
          icon: Icons.electric_meter,
          isSelected: _selectedMeterType == 'normal',
          onTap: () => setState(() => _selectedMeterType = 'normal'),
        ),
        const SizedBox(height: 12),
        _buildSelectionCard(
          title: 'มิเตอร์ TOU',
          subtitle: 'คิดแยก Peak/Off-Peak เหมาะกับบ้านที่ใช้ไฟกลางคืนเยอะ',
          icon: Icons.access_time,
          isSelected: _selectedMeterType == 'tou',
          onTap: () => setState(() => _selectedMeterType = 'tou'),
        ),
      ],
    );
  }


  // popup อธิบายข้อมูล — ใช้ widget กลาง showInfoDialog (เดิมมีโค้ดซ้ำในนี้)
  void _showInfoPopup(String title, String message) {
    showInfoDialog(context, title: title, message: message);
  }

  // หัวข้อของแต่ละ step — ใช้โครงเดียวกันทั้ง 2 หน้า: ไอคอนกล่องสีเขียว +
  // หัวข้อ + คำอธิบายสั้น 1 บรรทัด + ปุ่ม "?" (ถ้ามีอะไรอธิบายเพิ่ม เปิด
  // popup เดียวกับที่ใช้ในหน้าตั้งค่า) แทนที่จะโชว์คำอธิบายยาวเต็มหน้าแบบ
  // เดิมที่แต่ละ step ทำคนละสไตล์กัน
  Widget _buildStepHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    String? helpTitle,
    String? helpMessage,
  }) {
    const green = Color(0xFF2E7D32);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (helpMessage != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.info_outline,
                          color: green, size: 22),
                      onPressed: () =>
                          _showInfoPopup(helpTitle ?? title, helpMessage),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          isSelected ? const Color(0xFF2E7D32) : Colors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
          ],
        ),
      ),
    );
  }
}