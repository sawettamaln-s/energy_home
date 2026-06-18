import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/calculator.dart';
import '../../utils/forecaster.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _electricityController = TextEditingController(); // normal
  final _electricityPeakController = TextEditingController(); // TOU peak
  final _electricityOffPeakController = TextEditingController(); // TOU off-peak
  final _waterController = TextEditingController();

  int _currentIndex = 0;

  UserModel? _user;
  ElectricityLogModel? _latestElectricityLog;
  WaterLogModel? _latestWaterLog;
  List<ElectricityLogModel> _electricityLogs = [];
  List<WaterLogModel> _waterLogs = [];

  double _currentElectricityFromStart = 0;
  double _currentWaterFromStart = 0;
  double _currentElectricityCost = 0;
  double _currentWaterCost = 0;
  double _forecastTotal = 0;

  bool _isLoading = true;
  bool _isSavingElectricity = false;
  bool _isSavingWater = false;
  String _electricityError = '';
  String _waterError = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _electricityController.dispose();
    _electricityPeakController.dispose();
    _electricityOffPeakController.dispose();
    _waterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      _user = await _firestoreService.getUser(uid);

      _latestElectricityLog =
          await _firestoreService.getLatestElectricityLog(uid);
      _latestWaterLog = await _firestoreService.getLatestWaterLog(uid);

      final now = DateTime.now();
      final billingDay = _user?.billingDay ?? 30;
      DateTime startDate;
      DateTime endDate;

      if (now.day >= billingDay) {
        startDate = DateTime(now.year, now.month, billingDay);
        endDate = DateTime(now.year, now.month + 1, billingDay);
      } else {
        startDate = DateTime(now.year, now.month - 1, billingDay);
        endDate = DateTime(now.year, now.month, billingDay);
      }

      _electricityLogs = await _firestoreService.getCurrentMonthElectricityLogs(
          uid, startDate, endDate);
      _waterLogs = await _firestoreService.getCurrentMonthWaterLogs(
          uid, startDate, endDate);

      await _calculateCurrentMonth();
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateCurrentMonth() async {
    if (_electricityLogs.isNotEmpty) {
      final latest = _electricityLogs.first;
      _currentElectricityFromStart = latest.usedFromStart;
      _currentElectricityCost = latest.cost;
    } else {
      _currentElectricityFromStart = 0;
      _currentElectricityCost = 0;
    }

    if (_waterLogs.isNotEmpty) {
      final latest = _waterLogs.first;
      _currentWaterFromStart = latest.usedFromStart;
      _currentWaterCost = latest.cost;
    } else {
      _currentWaterFromStart = 0;
      _currentWaterCost = 0;
    }

    final now = DateTime.now();
    final remainingDays =
        EnergyForecaster.getRemainingDays(now, _user?.billingDay ?? 30);

    final dailyElectricity = _electricityLogs
        .map((l) => l.usedFromLast)
        .where((v) => v > 0)
        .toList();
    final dailyWater =
        _waterLogs.map((l) => l.usedFromLast).where((v) => v > 0).toList();

    final forecast = EnergyForecaster.forecastCurrentMonth(
      dailyElectricityUsage: dailyElectricity,
      dailyWaterUsage: dailyWater,
      currentElectricityCost: _currentElectricityCost,
      currentWaterCost: _currentWaterCost,
      remainingDays: remainingDays,
    );
    _forecastTotal = forecast['total'] ?? 0;
  }

  // บันทึกค่ามิเตอร์ไฟฟ้า
  Future<void> _saveElectricityLog() async {
    final isTOU = _user?.meterType == 'tou';

    if (isTOU) {
      if (_electricityPeakController.text.isEmpty ||
          _electricityOffPeakController.text.isEmpty) {
        setState(() => _electricityError = 'กรุณากรอกหน่วย Peak และ Off-Peak');
        return;
      }
    } else {
      if (_electricityController.text.isEmpty) {
        setState(() => _electricityError = 'กรุณากรอกค่ามิเตอร์ไฟฟ้า');
        return;
      }
    }

    double value = 0;
    double peakUnits = 0;
    double offPeakUnits = 0;

    try {
      if (isTOU) {
        peakUnits = double.parse(_electricityPeakController.text);
        offPeakUnits = double.parse(_electricityOffPeakController.text);
        value = peakUnits + offPeakUnits; // รวมทั้งหมด
      } else {
        value = double.parse(_electricityController.text);
      }
    } catch (e) {
      setState(() => _electricityError = 'กรุณากรอกตัวเลขเท่านั้น');
      return;
    }

    final startE = _user?.startElectricityValue ?? 0;
    final lastE = _latestElectricityLog?.meterValue ?? startE;

    if (value < startE) {
      setState(
          () => _electricityError = 'ต้องไม่น้อยกว่าหน่วยต้นรอบ ($startE)');
      return;
    }
    if (value < lastE) {
      setState(() => _electricityError = 'ต้องไม่น้อยกว่าครั้งล่าสุด ($lastE)');
      return;
    }

    setState(() {
      _electricityError = '';
      _isSavingElectricity = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final usedFromStart = value - startE;
      final usedFromLast = value - lastE;

      final cost = await EnergyCalculator.calculateElectricityByType(
        units: usedFromStart,
        meterType: _user?.meterType ?? 'normal',
        area: _user?.area ?? 'bangkok',
        meterSize: _user?.meterSize ?? '15a',
        peakUnits: peakUnits,
        offPeakUnits: offPeakUnits,
      );

      final log = ElectricityLogModel(
        id: const Uuid().v4(),
        uid: uid,
        date: DateTime.now(),
        meterValue: value,
        usedFromStart: usedFromStart,
        usedFromLast: usedFromLast,
        cost: cost,
      );

      await _firestoreService.saveElectricityLog(log);
      _electricityController.clear();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกค่ามิเตอร์ไฟฟ้าเรียบร้อยแล้ว'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _electricityError = 'เกิดข้อผิดพลาด กรุณาลองใหม่');
    } finally {
      setState(() => _isSavingElectricity = false);
    }
  }

  // บันทึกค่ามิเตอร์น้ำ
  Future<void> _saveWaterLog() async {
    if (_waterController.text.isEmpty) {
      setState(() => _waterError = 'กรุณากรอกค่ามิเตอร์น้ำ');
      return;
    }

    double value;
    try {
      value = double.parse(_waterController.text);
    } catch (e) {
      setState(() => _waterError = 'กรุณากรอกตัวเลขเท่านั้น');
      return;
    }

    final startW = _user?.startWaterValue ?? 0;
    final lastW = _latestWaterLog?.meterValue ?? startW;

    if (value < startW) {
      setState(() => _waterError = 'ต้องไม่น้อยกว่าหน่วยต้นรอบ ($startW)');
      return;
    }
    if (value < lastW) {
      setState(() => _waterError = 'ต้องไม่น้อยกว่าครั้งล่าสุด ($lastW)');
      return;
    }

    setState(() {
      _waterError = '';
      _isSavingWater = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final usedFromStart = value - startW;
      final usedFromLast = value - lastW;

      final cost = EnergyCalculator.calculateWater(
        usedFromStart,
        _user?.area ?? 'bangkok',
      );

      final log = WaterLogModel(
        id: const Uuid().v4(),
        uid: uid,
        date: DateTime.now(),
        meterValue: value,
        usedFromStart: usedFromStart,
        usedFromLast: usedFromLast,
        cost: cost,
      );

      await _firestoreService.saveWaterLog(log);
      _waterController.clear();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกค่ามิเตอร์น้ำเรียบร้อยแล้ว'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      setState(() => _waterError = 'เกิดข้อผิดพลาด กรุณาลองใหม่');
    } finally {
      setState(() => _isSavingWater = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final billingDay = _user?.billingDay ?? 30;
    final remainingDays = EnergyForecaster.getRemainingDays(now, billingDay);
    final daysElapsed = EnergyForecaster.getDaysElapsed(now, billingDay);
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: const Color(0xFF2E7D32),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'สวัสดี, ${_user?.name ?? 'ผู้ใช้'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'ผ่านมา $daysElapsed วัน • เหลืออีก $remainingDays วัน',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout),
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // การ์ดค่าใช้จ่าย
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ค่าใช้จ่ายเดือนนี้',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCostCard(
                                    icon: Icons.bolt,
                                    label: 'ค่าไฟฟ้า',
                                    amount:
                                        '฿${formatter.format(_currentElectricityCost)}',
                                    sub:
                                        '${_currentElectricityFromStart.toStringAsFixed(1)} หน่วย',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildCostCard(
                                    icon: Icons.water_drop,
                                    label: 'ค่าน้ำ',
                                    amount:
                                        '฿${formatter.format(_currentWaterCost)}',
                                    sub:
                                        '${_currentWaterFromStart.toStringAsFixed(1)} ลบ.ม.',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.trending_up,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ยอดคาดการณ์สิ้นเดือน: ฿${formatter.format(_forecastTotal)}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // บันทึกไฟฟ้า
                      if (_user?.meterType == 'tou')
                        _buildTOUMeterCard()
                      else
                        _buildMeterCard(
                          title: 'บันทึกค่ามิเตอร์ไฟฟ้า',
                          icon: Icons.bolt,
                          color: const Color(0xFFFFF3E0),
                          iconColor: Colors.orange,
                          controller: _electricityController,
                          hint: 'หน่วยสะสมปัจจุบัน เช่น 14052',
                          lastValue: _latestElectricityLog?.meterValue ??
                              _user?.startElectricityValue,
                          startValue: _user?.startElectricityValue,
                          error: _electricityError,
                          isSaving: _isSavingElectricity,
                          onSave: _saveElectricityLog,
                          unit: 'หน่วย',
                        ),

                      const SizedBox(height: 12),

                      // บันทึกน้ำ
                      _buildMeterCard(
                        title: 'บันทึกค่ามิเตอร์น้ำ',
                        icon: Icons.water_drop,
                        color: const Color(0xFFE3F2FD),
                        iconColor: Colors.blue,
                        controller: _waterController,
                        hint: 'หน่วยสะสมปัจจุบัน เช่น 178',
                        lastValue: _latestWaterLog?.meterValue ??
                            _user?.startWaterValue,
                        startValue: _user?.startWaterValue,
                        error: _waterError,
                        isSaving: _isSavingWater,
                        onSave: _saveWaterLog,
                        unit: 'ลบ.ม.',
                      ),

                      const SizedBox(height: 16),

                      // ยอดรวม
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ยอดรวมค่าใช้จ่ายทั้งสิ้น',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const Divider(height: 20),
                            _buildSummaryRow(
                              'ค่าไฟ + ค่าน้ำ',
                              '฿${formatter.format(_currentElectricityCost + _currentWaterCost)}',
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'Fixed Cost',
                              '฿${formatter.format(_user?.fixedCost ?? 0)}',
                            ),
                            const Divider(height: 20),
                            _buildSummaryRow(
                              'รวมทั้งสิ้น',
                              '฿${formatter.format((_currentElectricityCost + _currentWaterCost) + (_user?.fixedCost ?? 0))}',
                              isBold: true,
                              color: const Color(0xFF2E7D32),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SettingsScreen(),
              ),
            );
          } else {
            setState(() => _currentIndex = index);
          }
        },
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'หน้าหลัก'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'วิเคราะห์'),
          BottomNavigationBarItem(
              icon: Icon(Icons.electrical_services), label: 'อุปกรณ์'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
        ],
      ),
    );
  }

  Widget _buildMeterCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required TextEditingController controller,
    required String hint,
    required String error,
    required bool isSaving,
    required VoidCallback onSave,
    required String unit,
    double? lastValue,
    double? startValue,
  }) {
    final formatter = NumberFormat('#,##0.##');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (lastValue != null)
                Text(
                  'ล่าสุด: ${formatter.format(lastValue)} $unit',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              if (lastValue != null && startValue != null)
                const Text('  •  ', style: TextStyle(color: Colors.grey)),
              if (startValue != null)
                Text(
                  'ต้นรอบ: ${formatter.format(startValue)} $unit',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: hint,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: isSaving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('บันทึก'),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildCostCard({
    required IconData icon,
    required String label,
    required String amount,
    required String sub,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            )),
        Text(value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: isBold ? 16 : 14,
            )),
      ],
    );
  }

  Widget _buildTOUMeterCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text('บันทึกค่ามิเตอร์ไฟฟ้า (TOU)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'On-Peak: จ-ศ 09:00-22:00 | Off-Peak: จ-ศ 22:00-09:00 + วันหยุด',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // On-Peak
          const Text('หน่วย On-Peak',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _electricityPeakController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 100',
                    suffixText: 'หน่วย',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Off-Peak
          const Text('หน่วย Off-Peak',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _electricityOffPeakController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 200',
                    suffixText: 'หน่วย',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_electricityError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_electricityError,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSavingElectricity ? null : _saveElectricityLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSavingElectricity
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('บันทึก'),
            ),
          ),
        ],
      ),
    );
  }
}
