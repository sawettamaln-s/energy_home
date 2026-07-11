import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../utils/thai_date_utils.dart';
import '../../widgets/info_dialog.dart';
import '../main_shell.dart';
import 'setup_complete_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  int _currentStep = 0;
  // คงที่ 4 ขั้นตอนเสมอ: พื้นที่+อธิบายสูตรคำนวณ (รวมเป็นขั้นเดียว) /
  // ประเภทมิเตอร์ / วันตัดรอบบิล / บิลตั้งต้น
  // (เดิมพื้นที่กับอธิบายสูตรคำนวณแยกกัน 2 ขั้น ตอนนี้รวมเป็นขั้นเดียวแบบ
  // ส่วนที่ 1 / ส่วนที่ 2 ในหน้าเดียว)
  static const int _totalSteps = 4;
  String _selectedArea = 'bangkok';
  String _selectedMeterType = 'normal';
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

      if (!mounted) return;

      // ถ้ากรอกครบทุกอย่างไม่มีการข้าม ไม่ต้องแวะหน้าสรุป เข้า Dashboard ได้เลย
      // แต่ถ้าข้ามวันตัดรอบบิลหรือบิลตั้งต้นไปข้อใดข้อหนึ่ง ให้แวะหน้าสรุป
      // ก่อน เพื่อเตือนว่ายังมีอะไรค้างอยู่บ้าง
      final skippedSomething =
          _selectedBillingDay == null || _startMeterSkipped;

      if (!skippedSomething) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (context) =>
                  const MainShell(justCompletedSetup: true)),
          (route) => false,
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => SetupCompleteScreen(
            billingDayConfigured: _selectedBillingDay != null,
            startMeterConfigured: !_startMeterSkipped,
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
    switch (step) {
      case 0:
        return _buildAreaAndRateExplanationStep();
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

  Widget _buildBillingDayStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            icon: Icons.calendar_month_rounded,
            title: 'วันตัดรอบบิล',
            subtitle: 'ดูได้จากใบแจ้งหนี้ค่าไฟหรือค่าน้ำของคุณ',
            helpTitle: 'วันตัดรอบบิลคืออะไร?',
            helpMessage: 'เลือกวันตัดรอบบิลตามวันที่ใบแจ้งหนี้ค่าไฟหรือค่าน้ำ'
                'มาถึงบ้าน ระบบจะใช้วันนี้แจ้งเตือนเมื่อใกล้ถึงรอบชำระเงิน '
                'และเตือนให้บันทึกค่ามิเตอร์ต้นรอบ เพื่อตั้งเป็นค่าเริ่มต้น'
                'ของรอบบิลเดือนถัดไปโดยอัตโนมัติ',
          ),
          const SizedBox(height: 28),

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
                      'ข้ามขั้นตอนนี้ไปก่อนได้ ระบบจะใช้วันที่ 30 เป็น'
                      'ค่าเริ่มต้นไปก่อน แล้วมาตั้งวันที่ถูกต้องได้'
                      'ภายหลังที่หน้าตั้งค่า',
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
                      icon: const Icon(Icons.info_outline,
                          color: Color(0xFF2E7D32), size: 20),
                      onPressed: () => _showInfoPopup(
                        'วันตัดรอบบิลคืออะไร?',
                        'เลือกวันตัดรอบบิลตามวันที่ใบแจ้งหนี้ค่าไฟหรือค่าน้ำ'
                            'มาถึงบ้าน ระบบจะใช้วันนี้แจ้งเตือนเมื่อใกล้ถึง'
                            'รอบชำระเงิน และเตือนให้บันทึกค่ามิเตอร์ต้นรอบ '
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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                      isSelected: day == tempSelected,
                      isPopular: _popularBillingDays.contains(day),
                      onTap: () => setDialogState(() => tempSelected = day),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    tempSelected != null
                        ? 'วันที่เลือก: ทุกวันที่ $tempSelected ของเดือน'
                        : 'ยังไม่ได้เลือกวัน',
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

  // วันที่ "ยอดนิยม" ที่ให้ป้ายกำกับในปฏิทินเลือกวันตัดรอบบิล — เป็นชุดคงที่
  // สำหรับความสวยงามของ UI เท่านั้น (ดีไซน์เดียวกับหน้าตั้งค่า)
  static const Set<int> _popularBillingDays = {1, 15, 20, 25, 30};

  // ช่องวันที่หนึ่งช่องในปฏิทินเลือกวันตัดรอบบิล (ดีไซน์เดียวกับหน้าตั้งค่า)
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
            color:
                isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
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

  // popup อธิบายข้อมูล — ใช้ widget กลาง showInfoDialog (เดิมมีโค้ดซ้ำในนี้)
  void _showInfoPopup(String title, String message) {
    showInfoDialog(context, title: title, message: message);
  }


  Widget _buildStartMeterStep() {
    const green = Color(0xFF2E7D32);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            icon: Icons.receipt_long_outlined,
            title: 'ค่ามิเตอร์ตามใบแจ้งหนี้',
            subtitle: 'กรอกค่ามิเตอร์จากใบแจ้งหนี้ล่าสุด เพื่อใช้เป็น'
                'หน่วยตั้งต้นในการคำนวณค่าไฟ-น้ำของคุณ',
            helpTitle: 'ทำไมต้องกรอกค่ามิเตอร์ตั้งต้น?',
            helpMessage: 'ระบบใช้ค่านี้เทียบกับค่ามิเตอร์ที่บันทึกครั้ง'
                'ถัดไป เพื่อคำนวณหน่วยไฟ/น้ำที่ใช้ในรอบบิลนี้ '
                'หากข้ามขั้นตอนนี้ ระบบจะยังคำนวณหน่วยที่ใช้ให้ไม่ได้'
                'จนกว่าจะกรอกค่านี้ภายหลังที่หน้าตั้งค่า',
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
              'ไม่บังคับ กรอกภายหลังได้ที่หน้าตั้งค่า > '
              'ค่ามิเตอร์ตั้งต้น ระหว่างนี้ระบบจะยังคำนวณหน่วยที่ใช้'
              'ให้ไม่ได้จนกว่าจะกรอกค่าเริ่มต้น',
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

  // หัวข้อของแต่ละ step — ใช้โครงเดียวกันทั้ง 4 หน้า: ไอคอนกล่องสีเขียว +
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
            color: green.withOpacity(0.1),
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