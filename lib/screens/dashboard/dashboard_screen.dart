import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/meter_log_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/calculator.dart';
import '../../utils/forecaster.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _electricityController = TextEditingController();
  final _waterController = TextEditingController();

  int _currentIndex = 0;

  UserModel? _user;
  MeterLogModel? _latestLog;
  List<MeterLogModel> _currentMonthLogs = [];

  // ยอดคำนวณเดือนปัจจุบัน
  double _currentElectricityFromStart = 0; // หน่วยรวมจากต้นรอบ
  double _currentWaterFromStart = 0;
  double _currentElectricityCost = 0;
  double _currentWaterCost = 0;
  double _forecastTotal = 0;

  bool _isLoading = true;
  bool _isSaving = false;
  String _inputError = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _electricityController.dispose();
    _waterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      _user = await _firestoreService.getUser(uid);
      _latestLog = await _firestoreService.getLatestMeterLog(uid);

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

      _currentMonthLogs = await _firestoreService.getCurrentMonthLogs(
          uid, startDate, endDate);

      _calculateCurrentMonth();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _calculateCurrentMonth() {
    // ถ้ามี log เดือนนี้ ให้ใช้ค่าล่าสุด
    if (_currentMonthLogs.isNotEmpty) {
      // เรียงตามวันที่ล่าสุด
      _currentMonthLogs.sort((a, b) => b.date.compareTo(a.date));
      final latestLog = _currentMonthLogs.first;

      _currentElectricityFromStart = latestLog.electricityFromStart;
      _currentWaterFromStart = latestLog.waterFromStart;
      _currentElectricityCost = latestLog.electricityCost;
      _currentWaterCost = latestLog.waterCost;
    } else {
      _currentElectricityFromStart = 0;
      _currentWaterFromStart = 0;
      _currentElectricityCost = 0;
      _currentWaterCost = 0;
    }

    // พยากรณ์ยอดสิ้นเดือน
    final now = DateTime.now();
    final remainingDays = EnergyForecaster.getRemainingDays(
        now, _user?.billingDay ?? 30);

    List<double> dailyElectricity = _currentMonthLogs
        .map((log) => log.electricityIncrease)
        .where((v) => v > 0)
        .toList();

    List<double> dailyWater = _currentMonthLogs
        .map((log) => log.waterIncrease)
        .where((v) => v > 0)
        .toList();

    final forecast = EnergyForecaster.forecastCurrentMonth(
      dailyElectricityUsage: dailyElectricity,
      dailyWaterUsage: dailyWater,
      currentElectricityCost: _currentElectricityCost,
      currentWaterCost: _currentWaterCost,
      remainingDays: remainingDays,
    );

    _forecastTotal = forecast['total'] ?? 0;
  }

  // validate ค่าที่กรอก
  bool _validateInput(double electricityValue, double waterValue) {
    final startE = _user?.startElectricityValue ?? 0;
    final startW = _user?.startWaterValue ?? 0;
    final lastE = _latestLog?.electricityValue ?? startE;
    final lastW = _latestLog?.waterValue ?? startW;

    if (electricityValue < startE) {
      setState(() => _inputError =
          'ค่ามิเตอร์ไฟฟ้าต้องไม่น้อยกว่าหน่วยต้นรอบ ($startE)');
      return false;
    }
    if (waterValue < startW) {
      setState(() => _inputError =
          'ค่ามิเตอร์น้ำต้องไม่น้อยกว่าหน่วยต้นรอบ ($startW)');
      return false;
    }
    if (electricityValue < lastE) {
      setState(() => _inputError =
          'ค่ามิเตอร์ไฟฟ้าต้องไม่น้อยกว่าครั้งล่าสุด ($lastE)');
      return false;
    }
    if (waterValue < lastW) {
      setState(() => _inputError =
          'ค่ามิเตอร์น้ำต้องไม่น้อยกว่าครั้งล่าสุด ($lastW)');
      return false;
    }

    setState(() => _inputError = '');
    return true;
  }

  Future<void> _saveMeterLog() async {
    if (_electricityController.text.isEmpty ||
        _waterController.text.isEmpty) {
      setState(
          () => _inputError = 'กรุณากรอกค่ามิเตอร์ให้ครบทั้งไฟฟ้าและน้ำ');
      return;
    }

    double electricityValue;
    double waterValue;

    try {
      electricityValue = double.parse(_electricityController.text);
      waterValue = double.parse(_waterController.text);
    } catch (e) {
      setState(() => _inputError = 'กรุณากรอกตัวเลขเท่านั้น');
      return;
    }

    if (!_validateInput(electricityValue, waterValue)) return;

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();

      // หน่วยต้นรอบบิล
      final startE = _user?.startElectricityValue ?? 0;
      final startW = _user?.startWaterValue ?? 0;

      // หน่วยล่าสุดที่บันทึก
      final lastE = _latestLog?.electricityValue ?? startE;
      final lastW = _latestLog?.waterValue ?? startW;

      // คำนวณหน่วยรวมจากต้นรอบบิล
      double electricityFromStart = electricityValue - startE;
      double waterFromStart = waterValue - startW;

      // คำนวณหน่วยที่เพิ่มจากครั้งล่าสุด
      double electricityIncrease = electricityValue - lastE;
      double waterIncrease = waterValue - lastW;

      // คำนวณค่าใช้จ่ายจากหน่วยรวมทั้งเดือน
      double electricityCost = EnergyCalculator.calculateElectricityByType(
        units: electricityFromStart,
        meterType: _user?.meterType ?? 'normal',
      );
      double waterCost = EnergyCalculator.calculateWater(
        waterFromStart,
        _user?.area ?? 'bangkok',
      );

      final log = MeterLogModel(
        id: const Uuid().v4(),
        uid: uid,
        date: now,
        electricityValue: electricityValue,
        waterValue: waterValue,
        electricityFromStart: electricityFromStart,
        waterFromStart: waterFromStart,
        electricityIncrease: electricityIncrease,
        waterIncrease: waterIncrease,
        electricityCost: electricityCost,
        waterCost: waterCost,
      );

      await _firestoreService.saveMeterLog(log);

      _electricityController.clear();
      _waterController.clear();

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกค่ามิเตอร์เรียบร้อยแล้ว'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final billingDay = _user?.billingDay ?? 30;
    final remainingDays =
        EnergyForecaster.getRemainingDays(now, billingDay);
    final daysElapsed =
        EnergyForecaster.getDaysElapsed(now, billingDay);
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF2E7D32)))
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
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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

                      // การ์ดค่าใช้จ่ายเดือนปัจจุบัน
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
                            const Text(
                              'ค่าใช้จ่ายเดือนนี้',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
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
                                        '${_currentWaterFromStart.toStringAsFixed(1)} หน่วย',
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
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ช่องกรอกค่ามิเตอร์
                      const Text(
                        'บันทึกค่ามิเตอร์วันนี้',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'กรอกหน่วยสะสมตามมิเตอร์จริง',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _buildMeterInput(
                              controller: _electricityController,
                              icon: Icons.bolt,
                              label: 'ไฟฟ้า',
                              hint: 'เช่น 14052',
                              color: const Color(0xFFFFF3E0),
                              iconColor: Colors.orange,
                              lastValue: _latestLog?.electricityValue ??
                                  _user?.startElectricityValue,
                              startValue: _user?.startElectricityValue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMeterInput(
                              controller: _waterController,
                              icon: Icons.water_drop,
                              label: 'น้ำ',
                              hint: 'เช่น 178',
                              color: const Color(0xFFE3F2FD),
                              iconColor: Colors.blue,
                              lastValue: _latestLog?.waterValue ??
                                  _user?.startWaterValue,
                              startValue: _user?.startWaterValue,
                            ),
                          ),
                        ],
                      ),

                      // แสดง error
                      if (_inputError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _inputError,
                            style: const TextStyle(color: Colors.red,
                                fontSize: 12),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // ปุ่มบันทึก
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveMeterLog,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(_isSaving
                              ? 'กำลังบันทึก...'
                              : 'บันทึกค่ามิเตอร์'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ประวัติการบันทึก
                      if (_currentMonthLogs.isNotEmpty) ...[
                        const Text(
                          'ประวัติการบันทึกเดือนนี้',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ..._currentMonthLogs.map(
                            (log) => _buildLogCard(log, formatter)),
                        const SizedBox(height: 16),
                      ],

                      // ยอดรวมทั้งสิ้น
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
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
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
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'หน้าหลัก',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'วิเคราะห์',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.electrical_services),
            label: 'อุปกรณ์',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'ตั้งค่า',
          ),
        ],
      ),
    );
  }

  // การ์ดประวัติการบันทึก
  Widget _buildLogCard(MeterLogModel log, NumberFormat formatter) {
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm').format(log.date);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // วันที่และปุ่มลบ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(log),
              ),
            ],
          ),
          const Divider(height: 12),

          // ไฟฟ้า
          Row(
            children: [
              const Icon(Icons.bolt, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'ไฟฟ้า: ${log.electricityValue.toStringAsFixed(0)} หน่วย '
                  '(ใช้ไป ${log.electricityFromStart.toStringAsFixed(0)} หน่วย'
                  '${log.electricityIncrease > 0 ? ' +${log.electricityIncrease.toStringAsFixed(0)}' : ''})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                '฿${formatter.format(log.electricityCost)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.orange),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // น้ำ
          Row(
            children: [
              const Icon(Icons.water_drop,
                  color: Colors.blue, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'น้ำ: ${log.waterValue.toStringAsFixed(0)} หน่วย '
                  '(ใช้ไป ${log.waterFromStart.toStringAsFixed(0)} หน่วย'
                  '${log.waterIncrease > 0 ? ' +${log.waterIncrease.toStringAsFixed(0)}' : ''})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                '฿${formatter.format(log.waterCost)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.blue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ยืนยันก่อนลบ
  Future<void> _confirmDelete(MeterLogModel log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อมูล'),
        content: const Text('ต้องการลบข้อมูลการบันทึกนี้ใช่ไหม?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deleteMeterLog(log.uid, log.id);
      await _loadData();
    }
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
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(sub,
            style: const TextStyle(
                color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildMeterInput({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    required Color color,
    required Color iconColor,
    double? lastValue,
    double? startValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          if (lastValue != null)
            Text(
              'ล่าสุด: ${lastValue.toStringAsFixed(0)}',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600),
            ),
          if (startValue != null)
            Text(
              'ต้นรอบ: ${startValue.toStringAsFixed(0)}',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade500),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontWeight:
                  isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            )),
        Text(value,
            style: TextStyle(
              fontWeight:
                  isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: isBold ? 16 : 14,
            )),
      ],
    );
  }
}