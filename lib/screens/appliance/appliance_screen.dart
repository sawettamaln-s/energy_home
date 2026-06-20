import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/appliance_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/default_appliances.dart';

class ApplianceScreen extends StatefulWidget {
  const ApplianceScreen({super.key});

  @override
  State<ApplianceScreen> createState() => _ApplianceScreenState();
}

class _ApplianceScreenState extends State<ApplianceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<ApplianceModel> _appliances = [];
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _user = await _firestoreService.getUser(uid);
    _firestoreService.getAppliances(uid).listen((data) {
      setState(() {
        _appliances = data;
        _isLoading = false;
      });
    });
  }

  // คำนวณค่าไฟ/เดือนของอุปกรณ์ (ประมาณการแบบง่าย ไม่อิงขั้นบันได)
  double _estimateMonthlyCost(double watt, double hoursPerDay) {
    double kWhPerDay = (watt * hoursPerDay) / 1000;
    double kWhPerMonth = kWhPerDay * 30;
    // ใช้อัตราเฉลี่ยประมาณการ 4.5 บาท/หน่วย (รวม Ft + VAT คร่าวๆ)
    return kWhPerMonth * 4.5;
  }

  double get _totalMonthlyCost {
    double total = 0;
    for (var a in _appliances) {
      if (a.isActive && a.schedules.isNotEmpty) {
        double hours = a.schedules.fold(0.0, (sum, s) => sum + s.hoursPerDay);
        total += _estimateMonthlyCost(a.watt, hours);
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('อุปกรณ์',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2E7D32),
        onPressed: _showAddApplianceSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // สรุปยอดรวม
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ประมาณการค่าไฟต่อเดือน',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '฿${formatter.format(_totalMonthlyCost)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'จากอุปกรณ์ ${_appliances.length} ชิ้น',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // รายการอุปกรณ์
                Expanded(
                  child: _appliances.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.devices_other,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text('ยังไม่มีเครื่องใช้ไฟฟ้า',
                                  style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 4),
                              const Text('กดปุ่ม + เพื่อเพิ่มรายการ',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _appliances.length,
                          itemBuilder: (context, index) {
                            final a = _appliances[index];
                            double hours = a.schedules
                                .fold(0.0, (sum, s) => sum + s.hoursPerDay);
                            double monthlyCost =
                                _estimateMonthlyCost(a.watt, hours);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.08),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.electrical_services,
                                        color: Color(0xFF2E7D32)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(a.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        Text(
                                          '${a.watt.toStringAsFixed(0)} วัตต์ • ${hours.toStringAsFixed(1)} ชม./วัน',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '฿${formatter.format(monthlyCost)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2E7D32)),
                                      ),
                                      const Text('/เดือน',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () => _confirmDelete(a),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        selectedItemColor: const Color(0xFF2E7D32),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index != 2) Navigator.pop(context);
        },
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

  Future<void> _confirmDelete(ApplianceModel a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบอุปกรณ์'),
        content: Text('ต้องการลบ "${a.name}" ใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _firestoreService.deleteAppliance(a.uid, a.id);
    }
  }

  // Bottom sheet เลือกเพิ่มอุปกรณ์
  void _showAddApplianceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddApplianceSheet(
        firestoreService: _firestoreService,
        onAdded: _loadData,
      ),
    );
  }
}

// ==================== Bottom Sheet เพิ่มอุปกรณ์ ====================
class _AddApplianceSheet extends StatefulWidget {
  final FirestoreService firestoreService;
  final VoidCallback onAdded;

  const _AddApplianceSheet({
    required this.firestoreService,
    required this.onAdded,
  });

  @override
  State<_AddApplianceSheet> createState() => _AddApplianceSheetState();
}

class _AddApplianceSheetState extends State<_AddApplianceSheet> {
  final _nameController = TextEditingController();
  final _wattController = TextEditingController();
  final _hoursController = TextEditingController(text: '1');
  bool _isCustom = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _wattController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  void _selectDefault(DefaultAppliance d) {
    setState(() {
      _nameController.text = d.name;
      _wattController.text = d.defaultWatt.toStringAsFixed(0);
      _isCustom = true;
    });
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty ||
        _wattController.text.isEmpty ||
        _hoursController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบ')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final watt = double.parse(_wattController.text);
      final hours = double.parse(_hoursController.text);

      final appliance = ApplianceModel(
        id: const Uuid().v4(),
        uid: uid,
        name: _nameController.text,
        watt: watt,
        schedules: [
          ScheduleModel(
            days: [0, 1, 2, 3, 4, 5, 6], // ทุกวัน
            startTime: '00:00',
            endTime: _hoursToTimeString(hours),
          ),
        ],
      );

      await widget.firestoreService.saveAppliance(appliance);
      widget.onAdded();

      if (mounted) Navigator.pop(context);
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

  String _hoursToTimeString(double hours) {
    int h = hours.floor();
    int m = ((hours - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
                const Text('เพิ่มเครื่องใช้ไฟฟ้า',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
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
                  if (!_isCustom) ...[
                    const Text('เลือกจากรายการสามัญประจำบ้าน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...DefaultAppliances.list.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            tileColor: Colors.grey.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            leading: const Icon(Icons.electrical_services,
                                color: Color(0xFF2E7D32)),
                            title: Text(d.name,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                                '${d.minWatt.toStringAsFixed(0)}-${d.maxWatt.toStringAsFixed(0)} วัตต์',
                                style: const TextStyle(fontSize: 11)),
                            onTap: () => _selectDefault(d),
                          ),
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isCustom = true),
                      icon: const Icon(Icons.add),
                      label: const Text('เพิ่มเครื่องใช้ไฟฟ้าอื่น'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, size: 18),
                          onPressed: () => setState(() => _isCustom = false),
                        ),
                        const Text('กรอกข้อมูลอุปกรณ์',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('ชื่ออุปกรณ์',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'เช่น แอร์ห้องนอน',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('กำลังไฟ (วัตต์)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _wattController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'เช่น 1200',
                        suffixText: 'วัตต์',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('ใช้งานประมาณกี่ชั่วโมง/วัน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _hoursController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: 'เช่น 8',
                        suffixText: 'ชม./วัน',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    _buildEstimateCard(),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateCard() {
    double watt = double.tryParse(_wattController.text) ?? 0;
    double hours = double.tryParse(_hoursController.text) ?? 0;

    double kWhPerDay = (watt * hours) / 1000;
    double costPerDay = kWhPerDay * 4.5; // อัตราเฉลี่ยประมาณการ
    double costPerMonth = costPerDay * 30;
    double costPerYear = costPerDay * 365;

    final formatter = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ประมาณการค่าไฟ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/วัน', '฿${formatter.format(costPerDay)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/เดือน', '฿${formatter.format(costPerMonth)}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/ปี', '฿${formatter.format(costPerYear)}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _estimateBox(
                    'พลังงาน/วัน', '${kWhPerDay.toStringAsFixed(2)} kWh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estimateBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}
