import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/thai_date_utils.dart';
import '../dashboard/dashboard_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  int _currentStep = 0;
  int get _totalSteps => 4;
  String _selectedArea = 'bangkok';
  String _selectedMeterType = 'normal';
  String _selectedMeterSize = '15a';
  // null = ยังไม่ได้เลือกวันตัดรอบบิล (ผู้ใช้กดข้ามไปก่อนได้ ไปตั้งทีหลังที่
  // หน้าตั้งค่าได้) ตอนบันทึกจริงถ้ายังเป็น null จะ fallback เป็นวันที่ 30
  // ตาม default ของ UserModel
  int? _selectedBillingDay;

  final _electricityStartController = TextEditingController();
  final _peakStartController = TextEditingController();
  final _offPeakStartController = TextEditingController();
  final _waterStartController = TextEditingController();
  int _selectedStartMonth = DateTime.now().month;
  int _selectedStartYear = DateTime.now().year;
  String _startMeterError = '';
  // ผู้ใช้กดข้ามขั้นตอนนี้ไปก่อน (ยังไม่มีใบแจ้งหนี้ตอนสมัคร) ไปกรอกทีหลัง
  // ได้ที่หน้าตั้งค่า ตอนข้ามจะไม่บังคับกรอกและตั้งค่าตั้งต้นเป็น 0 ไปก่อน
  bool _startMeterSkipped = false;

  bool _isLoading = false;

  @override
  void dispose() {
    _electricityStartController.dispose();
    _waterStartController.dispose();
    _peakStartController.dispose();
    _offPeakStartController.dispose();
    super.dispose();
  }

  bool _validateStartMeter() {
    // กดข้ามไปก่อนแล้ว ไม่ต้องเช็คอะไรเลย ปล่อยผ่านได้ทันที
    if (_startMeterSkipped) {
      setState(() => _startMeterError = '');
      return true;
    }

    if (_waterStartController.text.isEmpty) {
      setState(() => _startMeterError = 'กรุณากรอกค่ามิเตอร์น้ำ');
      return false;
    }

    if (_selectedMeterType == 'tou') {
      if (_peakStartController.text.isEmpty ||
          _offPeakStartController.text.isEmpty) {
        setState(() =>
            _startMeterError = 'กรุณากรอกหน่วย On-Peak และ Off-Peak ให้ครบ');
        return false;
      }
      try {
        double.parse(_peakStartController.text);
        double.parse(_offPeakStartController.text);
        double.parse(_waterStartController.text);
      } catch (e) {
        setState(() => _startMeterError = 'กรุณากรอกตัวเลขเท่านั้น');
        return false;
      }
    } else {
      if (_electricityStartController.text.isEmpty) {
        setState(() => _startMeterError = 'กรุณากรอกค่ามิเตอร์ไฟฟ้า');
        return false;
      }
      try {
        double.parse(_electricityStartController.text);
        double.parse(_waterStartController.text);
      } catch (e) {
        setState(() => _startMeterError = 'กรุณากรอกตัวเลขเท่านั้น');
        return false;
      }
    }

    setState(() => _startMeterError = '');
    return true;
  }

  Future<void> _saveSetup() async {
    if (!_validateStartMeter()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userModel = UserModel(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        area: _selectedArea,
        meterType: _selectedMeterType,
        meterSize: _selectedMeterSize,
        billingDay: _selectedBillingDay ?? 30,
        startElectricityValue:
            (_startMeterSkipped || _selectedMeterType == 'tou')
                ? 0
                : (double.tryParse(_electricityStartController.text) ?? 0),
        startWaterValue: _startMeterSkipped
            ? 0
            : (double.tryParse(_waterStartController.text) ?? 0),
        startPeakValue: (!_startMeterSkipped && _selectedMeterType == 'tou')
            ? (double.tryParse(_peakStartController.text) ?? 0)
            : 0,
        startOffPeakValue:
            (!_startMeterSkipped && _selectedMeterType == 'tou')
                ? (double.tryParse(_offPeakStartController.text) ?? 0)
                : 0,
        startMeterConfigured: !_startMeterSkipped,
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

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
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
                                if (_validateStartMeter()) {
                                  await _saveSetup();
                                }
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
    // ทุกเส้นทางมี 4 ขั้นตอนเสมอ (ขั้น 0 รวมพื้นที่ + ขนาดมิเตอร์ไว้ด้วยกัน
    // ขนาดมิเตอร์จะโชว์เป็นส่วนที่ 2 เฉพาะกรณี กทม. + มิเตอร์ปกติเท่านั้น)
    switch (step) {
      case 0:
        return _buildAreaAndMeterSizeStep();
      case 1:
        return _buildMeterTypeStep();
      case 2:
        return _buildBillingDayStep();
      case 3:
        return _buildStartMeterStep();
      default:
        return const SizedBox();
    }
  }

  // ขั้นรวม: ส่วนที่ 1 เลือกพื้นที่ + ส่วนที่ 2 เลือกขนาดมิเตอร์ไฟฟ้า
  // (ส่วนที่ 2 โชว์เฉพาะ กทม. + มิเตอร์ปกติ เหมือนเงื่อนไขเดิมของ
  // _buildMeterSizeStep ก่อนแยกเป็นขั้นตอนต่างหาก)
  Widget _buildAreaAndMeterSizeStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTag('ส่วนที่ 1'),
          const SizedBox(height: 10),
          const Text(
            'คุณอยู่ในพื้นที่ไหน?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'เพื่อคำนวณค่าน้ำให้ถูกต้องตามพื้นที่ของคุณ',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          _buildSelectionCard(
            title: 'กรุงเทพและปริมณฑล',
            subtitle: 'ใช้อัตราค่าน้ำ MWA',
            icon: Icons.location_city,
            isSelected: _selectedArea == 'bangkok',
            onTap: () => setState(() => _selectedArea = 'bangkok'),
          ),
          const SizedBox(height: 12),
          _buildSelectionCard(
            title: 'ต่างจังหวัด',
            subtitle: 'ใช้อัตราค่าน้ำ PWA',
            icon: Icons.nature,
            isSelected: _selectedArea == 'province',
            onTap: () => setState(() => _selectedArea = 'province'),
          ),

          // ส่วนที่ 2 โชว์เฉพาะ กทม. + มิเตอร์ปกติ (ระบบคิดค่าไฟตามขนาดมิเตอร์
          // มีผลเฉพาะอัตรา MEA ประเภท 1.1/1.2 เท่านั้น)
          if (_selectedArea == 'bangkok' && _selectedMeterType == 'normal') ...[
            const SizedBox(height: 28),
            Divider(color: Colors.grey.shade200, thickness: 1),
            const SizedBox(height: 20),
            _buildSectionTag('ส่วนที่ 2'),
            const SizedBox(height: 10),
            _buildMeterSizeStep(),
          ],
        ],
      ),
    );
  }

  // ป้าย "ส่วนที่ N" ใช้ร่วมกันสำหรับ step ที่มีหลาย section ในหน้าเดียว
  Widget _buildSectionTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2E7D32),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMeterTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ประเภทมิเตอร์ไฟฟ้า',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'ดูได้จากใบแจ้งหนี้ค่าไฟของคุณ',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        _buildSelectionCard(
          title: 'มิเตอร์ปกติ',
          subtitle: 'คิดค่าไฟตามอัตราขั้นบันได\nเหมาะสำหรับบ้านทั่วไป',
          icon: Icons.electric_meter,
          isSelected: _selectedMeterType == 'normal',
          onTap: () => setState(() => _selectedMeterType = 'normal'),
        ),
        const SizedBox(height: 12),
        _buildSelectionCard(
          title: 'มิเตอร์ TOU',
          subtitle:
              'คิดค่าไฟแยก Peak/Off-Peak\nเหมาะสำหรับบ้านที่ใช้ไฟช่วงกลางคืน',
          icon: Icons.access_time,
          isSelected: _selectedMeterType == 'tou',
          onTap: () => setState(() => _selectedMeterType = 'tou'),
        ),
      ],
    );
  }

  // ขั้นเพิ่มเติม (เฉพาะกรุงเทพ): เลือกขนาดมิเตอร์
  Widget _buildMeterSizeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ขนาดมิเตอร์ไฟฟ้า',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'ดูได้จากตัวเลขบนมิเตอร์หรือใบแจ้งหนี้ค่าไฟ MEA',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        _buildSelectionCard(
          title: 'มิเตอร์ปกติ เกิน 5(15)A',
          subtitle:
              'บ้านเดี่ยว ทาวน์เฮาส์ คอนโดทั่วไป\nคิดอัตราประเภท 1.2 เสมอ',
          icon: Icons.electric_meter,
          isSelected: _selectedMeterSize == '15a',
          onTap: () => setState(() => _selectedMeterSize = '15a'),
        ),
        const SizedBox(height: 12),
        _buildSelectionCard(
          title: 'มิเตอร์เล็ก 5(15)A',
          subtitle:
              'ห้องเช่า บ้านเก่าขนาดเล็ก\nคิดอัตราประเภท 1.1 ถ้าใช้ไม่เกิน 150 หน่วย',
          icon: Icons.electric_meter_outlined,
          isSelected: _selectedMeterSize == '5a',
          onTap: () => setState(() => _selectedMeterSize = '5a'),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'วิธีเช็คขนาดมิเตอร์',
                    style: TextStyle(
                        color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                '1. ดูตัวเลขบนมิเตอร์ เช่น "5(15)A" หรือ "15(45)A"\n'
                '2. หรือดูจากใบแจ้งหนี้ค่าไฟ MEA\n'
                '3. ถ้าไม่แน่ใจ เลือก "เกิน 5(15)A" ไว้ก่อนได้เลยค่ะ',
                style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBillingDayStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'วันตัดรอบบิล',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.help_outline,
                    color: Color(0xFF2E7D32), size: 22),
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
            'ดูได้จากใบแจ้งหนี้ค่าไฟหรือค่าน้ำของคุณ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // ฟิลด์กดเปิดปฏิทินเลือกวัน — แทนกริด 31 ช่องเต็มหน้าจอที่กินพื้นที่
          // เกินไปบนมือถือ คงรูปแบบฟิลด์ให้เหมือน DropdownButtonFormField เดิม
          // (กรอบ, padding, มุมโค้ง) เพื่อความสอดคล้องกับฟิลด์อื่นในวิซาร์ดนี้
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _openBillingDayPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: _selectedBillingDay != null
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade400,
                      size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedBillingDay != null
                          ? 'วันที่ $_selectedBillingDay ของทุกเดือน'
                          : 'แตะเพื่อเลือกวันตัดรอบบิล',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _selectedBillingDay != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: _selectedBillingDay != null
                            ? Colors.black87
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ข้ามไปก่อนได้ — เผื่อตอนสมัครยังไม่มีใบแจ้งหนี้ติดตัวอยู่
          // มาตั้งค่าทีหลังได้ที่เมนูตั้งค่า > วันตัดรอบบิล
          if (_selectedBillingDay != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedBillingDay = null),
                icon: Icon(Icons.skip_next_rounded,
                    size: 18, color: Colors.grey.shade600),
                label: Text(
                  'ยังไม่รู้วันตัดรอบบิล ข้ามไปก่อน',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.grey.shade600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ข้ามขั้นตอนนี้ไปก่อนได้ค่ะ ระบบจะใช้วันที่ 30 เป็น'
                      'ค่าเริ่มต้นไปก่อน แล้วค่อยมาตั้งวันที่ถูกต้องได้'
                      'ทีหลังที่หน้าตั้งค่า',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // dialog ปฏิทินเลือกวันตัดรอบบิล — เปิดจากฟิลด์ด้านบน (ดีไซน์เดียวกับ
  // หน้าตั้งค่า แต่ทำงานกับตัวแปร temp ในนี้ก่อน ค่อยยืนยันลง state จริง
  // ตอนกด "ยืนยัน" กันเผลอกดวันแล้วเปลี่ยนใจ ปิด dialog ทิ้งได้แบบไม่บันทึก)
  void _openBillingDayPicker() {
    int? tempSelected = _selectedBillingDay;
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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'เลือกวันตัดรอบบิล',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
                      isSelected: day == tempSelected,
                      onTap: () => setDialogState(() => tempSelected = day),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    tempSelected != null
                        ? 'วันที่เลือก: ทุกวันที่ $tempSelected ของเดือน'
                        : 'ยังไม่ได้เลือกวันค่ะ',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tempSelected != null
                          ? const Color(0xFF2E7D32)
                          : Colors.grey.shade500,
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
                        onPressed: tempSelected == null
                            ? null
                            : () {
                                setState(
                                    () => _selectedBillingDay = tempSelected);
                                Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('ยืนยัน'),
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

  // ช่องวันที่หนึ่งช่องในปฏิทินเลือกวันตัดรอบบิล (ดีไซน์เดียวกับหน้าตั้งค่า)
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
            color:
                isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
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

  // popup อธิบายข้อมูล (ดีไซน์เดียวกับหน้าตั้งค่า)
  void _showInfoPopup(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF2E7D32), size: 20),
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

  Widget _buildStartMeterStep() {
    const green = Color(0xFF2E7D32);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // หัวข้อ + คำอธิบาย — แยกออกจากสวิตช์ข้าม เพื่อไม่ให้ปนกัน
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: green),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ค่ามิเตอร์ตามใบแจ้งหนี้',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'กรอกค่ามิเตอร์จากใบแจ้งหนี้ล่าสุด เพื่อใช้เป็น'
                      'หน่วยตั้งต้นในการคำนวณค่าไฟ-น้ำของคุณ',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // การ์ดสวิตช์ "ข้ามไปก่อน" — มีข้อความบอกความหมายตรงๆ ในตัว
          // ไม่ใช่แค่ไอคอนสวิตช์ลอยๆ ที่ต้องกด tooltip ดู (ซึ่งบนมือถือ
          // โดยเฉพาะ iOS ไม่มีทาง long-press เจอ tooltip อยู่แล้ว)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                setState(() => _startMeterSkipped = !_startMeterSkipped),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _startMeterSkipped
                    ? green.withOpacity(0.08)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _startMeterSkipped
                      ? green.withOpacity(0.4)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ยังไม่มีใบแจ้งหนี้ตอนนี้?',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _startMeterSkipped
                                ? green
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _startMeterSkipped
                              ? 'ข้ามไปก่อน — ไปกรอกทีหลังได้ที่หน้าตั้งค่า'
                              : 'ข้ามขั้นตอนนี้ไปก่อนได้ กรอกทีหลังได้ที่หน้าตั้งค่า',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _startMeterSkipped,
                    activeColor: green,
                    onChanged: (val) =>
                        setState(() => _startMeterSkipped = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (_startMeterSkipped)
            _buildInfoBanner(
              'ไม่บังคับค่ะ มากรอกทีหลังก็ได้ที่หน้าตั้งค่า > '
              'ค่ามิเตอร์ตั้งต้น ระหว่างนี้ระบบจะยังคำนวณหน่วยที่ใช้'
              'ให้ไม่ได้จนกว่าจะกรอกค่าเริ่มต้นค่ะ',
              green: green,
            )
          else ...[
            _buildFieldGroupLabel('ใบแจ้งหนี้เดือน', Icons.event_outlined),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _selectedStartMonth,
                    decoration: _dropdownDecoration(),
                    items: List.generate(12, (i) {
                      return DropdownMenuItem(
                        value: i + 1,
                        child: Text(thaiMonths[i]),
                      );
                    }),
                    onChanged: (val) =>
                        setState(() => _selectedStartMonth = val!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedStartYear,
                    decoration: _dropdownDecoration(),
                    items: [
                      DateTime.now().year - 1,
                      DateTime.now().year,
                    ].map((year) {
                      return DropdownMenuItem(
                        value: year,
                        child: Text('$year'),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _selectedStartYear = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildFieldGroupLabel(
                'หน่วยมิเตอร์ตามใบแจ้งหนี้', Icons.speed_outlined),
            const SizedBox(height: 12),
            if (_selectedMeterType == 'tou') ...[
              // กรอกแยก Peak/Off-Peak สำหรับ TOU
              _buildMeterField(
                label: 'หน่วย On-Peak',
                controller: _peakStartController,
                hint: 'เช่น 1200',
                icon: Icons.bolt,
                color: Colors.orange,
              ),
              const SizedBox(height: 14),
              _buildMeterField(
                label: 'หน่วย Off-Peak',
                controller: _offPeakStartController,
                hint: 'เช่น 3500',
                icon: Icons.bolt,
                color: Colors.deepOrange,
              ),
            ] else ...[
              // กรอกแบบปกติ
              _buildMeterField(
                label: 'หน่วยไฟฟ้า',
                controller: _electricityStartController,
                hint: 'เช่น 14009',
                icon: Icons.bolt,
                color: Colors.orange,
              ),
            ],
            const SizedBox(height: 14),
            _buildMeterField(
              label: 'หน่วยน้ำประปา',
              controller: _waterStartController,
              hint: 'เช่น 148',
              icon: Icons.water_drop,
              color: Colors.blue,
            ),
            if (_startMeterError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _startMeterError,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            _buildInfoBanner(
              'กรอกหน่วยสะสมทั้งหมดตามมิเตอร์จริง ไม่ใช่หน่วยที่ใช้ในเดือนนั้น\n'
              'เช่น ถ้ามิเตอร์แสดง 14009 ก็กรอก 14009',
              green: green,
            ),
          ], // ปิด else ของ if (_startMeterSkipped)
        ],
      ),
    );
  }

  // ป้ายชื่อหัวข้อกลุ่มฟิลด์ — ใช้ร่วมกันทุกกลุ่ม ให้ดูเป็นโครงเดียวกัน
  Widget _buildFieldGroupLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
      ),
    );
  }

  // ฟิลด์กรอกหน่วยมิเตอร์ — ไอคอนเป็นชิปสีในกรอบ ดูเป็นมือชั้นมือ
  // กว่า prefixIcon ลอยๆ แบบเดิม และ label คงที่ ไม่ใช้ placeholder ลวง
  Widget _buildMeterField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontWeight: FontWeight.normal),
            filled: true,
            fillColor: Colors.grey.shade50,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
            ),
            suffixText: 'หน่วย',
            suffixStyle:
                TextStyle(color: Colors.grey.shade500, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: color, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // กล่องข้อความแจ้งเตือน/คำอธิบาย สีเขียวอ่อน ใช้ร่วมกันทุกจุดในหน้านี้
  Widget _buildInfoBanner(String text, {required Color green}) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: green, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
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
              ? const Color(0xFF2E7D32).withOpacity(0.1)
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