import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../dashboard/dashboard_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  int _currentStep = 0;
  final int _totalSteps = 4;

  // ค่าที่ผู้ใช้เลือก
  String _selectedArea = 'bangkok';
  String _selectedMeterType = 'normal';
  int _selectedBillingDay = 30;

  // ค่ามิเตอร์ต้นรอบ
  final _electricityStartController = TextEditingController();
  final _waterStartController = TextEditingController();
  int _selectedStartMonth = DateTime.now().month;
  int _selectedStartYear = DateTime.now().year;
  String _startMeterError = '';

  bool _isLoading = false;

  final List<String> _thaiMonths = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
    'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
    'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
  ];

  @override
  void dispose() {
    _electricityStartController.dispose();
    _waterStartController.dispose();
    super.dispose();
  }

  // ตรวจสอบค่ามิเตอร์ต้นรอบก่อนไปขั้นถัดไป
  bool _validateStartMeter() {
    if (_electricityStartController.text.isEmpty ||
        _waterStartController.text.isEmpty) {
      setState(() => _startMeterError = 'กรุณากรอกค่ามิเตอร์ให้ครบ');
      return false;
    }
    try {
      double.parse(_electricityStartController.text);
      double.parse(_waterStartController.text);
    } catch (e) {
      setState(() => _startMeterError = 'กรุณากรอกตัวเลขเท่านั้น');
      return false;
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
        billingDay: _selectedBillingDay,
        startElectricityValue:
            double.parse(_electricityStartController.text),
        startWaterValue: double.parse(_waterStartController.text),
        startBillingMonth: _selectedStartMonth,
        startBillingYear: _selectedStartYear,
      );

      await _firestoreService.createUser(userModel);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (context) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')),
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

              // Progress indicator
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

              // ปุ่มถัดไป/เสร็จสิ้น
              Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            setState(() => _currentStep--),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
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
                              if (_currentStep == 3) {
                                // ขั้นสุดท้าย validate ก่อน save
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : Text(
                              _currentStep < 3 ? 'ถัดไป' : 'เริ่มใช้งาน',
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
        return _buildAreaStep();
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

  // ขั้นที่ 1: เลือกพื้นที่
  Widget _buildAreaStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'คุณอยู่ในพื้นที่ไหน?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'เพื่อคำนวณค่าน้ำให้ถูกต้องตามพื้นที่ของคุณ',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
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
      ],
    );
  }

  // ขั้นที่ 2: เลือกประเภทมิเตอร์
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

  // ขั้นที่ 3: เลือกวันตัดรอบบิล
  Widget _buildBillingDayStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'วันตัดรอบบิล',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'ดูได้จากใบแจ้งหนี้ค่าไฟหรือค่าน้ำของคุณ',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'วันที่ $_selectedBillingDay',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
            ),
          ),
        ),
        const Center(
          child: Text(
            'ของทุกเดือน',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 24),
        Slider(
          value: _selectedBillingDay.toDouble(),
          min: 1,
          max: 31,
          divisions: 30,
          activeColor: const Color(0xFF2E7D32),
          label: 'วันที่ $_selectedBillingDay',
          onChanged: (value) =>
              setState(() => _selectedBillingDay = value.toInt()),
        ),
        const SizedBox(height: 16),
        const Text('วันที่นิยม',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [7, 15, 20, 23, 25, 30].map((day) {
            return ChoiceChip(
              label: Text('วันที่ $day'),
              selected: _selectedBillingDay == day,
              selectedColor: const Color(0xFF2E7D32),
              labelStyle: TextStyle(
                color: _selectedBillingDay == day
                    ? Colors.white
                    : Colors.black,
              ),
              onSelected: (_) =>
                  setState(() => _selectedBillingDay = day),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ขั้นที่ 4: กรอกค่ามิเตอร์ต้นรอบ
  Widget _buildStartMeterStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ค่ามิเตอร์ตามใบแจ้งหนี้',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'กรอกค่ามิเตอร์จากใบแจ้งหนี้ล่าสุดของคุณ\nเพื่อใช้เป็นหน่วยตั้งต้นในการคำนวณ',
            style: TextStyle(color: Colors.grey),
          ),

          const SizedBox(height: 24),

          // เลือกเดือน/ปีของใบแจ้งหนี้
          const Text(
            'ใบแจ้งหนี้เดือน',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // เลือกเดือน
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: _selectedStartMonth,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  items: List.generate(12, (i) {
                    return DropdownMenuItem(
                      value: i + 1,
                      child: Text(_thaiMonths[i]),
                    );
                  }),
                  onChanged: (val) =>
                      setState(() => _selectedStartMonth = val!),
                ),
              ),
              const SizedBox(width: 8),
              // เลือกปี
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedStartYear,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
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

          const SizedBox(height: 20),

          // ช่องกรอกค่ามิเตอร์ไฟฟ้า
          const Text(
            'หน่วยไฟฟ้า (ตามใบแจ้งหนี้)',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _electricityStartController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'เช่น 14009',
              prefixIcon: const Icon(Icons.bolt, color: Colors.orange),
              suffixText: 'หน่วย',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ช่องกรอกค่ามิเตอร์น้ำ
          const Text(
            'หน่วยน้ำประปา (ตามใบแจ้งหนี้)',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _waterStartController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'เช่น 148',
              prefixIcon:
                  const Icon(Icons.water_drop, color: Colors.blue),
              suffixText: 'หน่วย',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // แสดง error ถ้ามี
          if (_startMeterError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _startMeterError,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          const SizedBox(height: 16),

          // กล่องอธิบาย
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: Color(0xFF2E7D32), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'กรอกหน่วยสะสมทั้งหมดตามมิเตอร์จริง ไม่ใช่หน่วยที่ใช้ในเดือนนั้น\nเช่น ถ้ามิเตอร์แสดง 14009 ก็กรอก 14009',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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
            color: isSelected
                ? const Color(0xFF2E7D32)
                : Colors.grey.shade200,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2E7D32)
                    : Colors.grey.shade200,
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
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
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