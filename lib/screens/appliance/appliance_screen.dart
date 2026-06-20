import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/appliance_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/default_appliances.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';

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

  // คำนวณ kWh รวมของอุปกรณ์ในช่วง totalDaysInPeriod วัน (30 = เดือน, 365 = ปี)
  // คิดตามจำนวนวัน/สัปดาห์ที่ตั้งไว้จริงในแต่ละ schedule (ไม่ใช่ทุกวันเสมอ)
  double _kWhForPeriod(ApplianceModel a, int totalDaysInPeriod) {
    double kWh = 0;
    for (final s in a.schedules) {
      final activeDays = (s.days.length / 7) * totalDaysInPeriod;
      kWh += (a.watt * s.hoursPerDay / 1000) * activeDays;
    }
    return kWh;
  }

  // ค่าไฟเฉพาะวันที่ใช้งานจริง (ไม่เฉลี่ยรวมวันที่ไม่ได้ใช้)
  double _costPerActiveDay(ApplianceModel a) {
    double kWh = 0;
    for (final s in a.schedules) {
      kWh += (a.watt * s.hoursPerDay) / 1000;
    }
    return kWh * 4.5;
  }

  // ใช้อัตราเฉลี่ยประมาณการ 4.5 บาท/หน่วย (รวม Ft + VAT คร่าวๆ) ตลอดทั้งไฟล์
  double _estimateApplianceMonthlyCost(ApplianceModel a) =>
      _kWhForPeriod(a, 30) * 4.5;

  double _estimateApplianceYearlyCost(ApplianceModel a) =>
      _kWhForPeriod(a, 365) * 4.5;

  double get _totalMonthlyCost {
    double total = 0;
    for (var a in _appliances) {
      if (a.isActive && a.schedules.isNotEmpty) {
        total += _estimateApplianceMonthlyCost(a);
      }
    }
    return total;
  }

  int get _scheduledCount =>
      _appliances.where((a) => a.schedules.isNotEmpty).length;

  // สรุปตารางการใช้งานเป็นข้อความสั้นๆ จากข้อมูลที่มีจริง (days + จำนวนชม./วัน)
  // หมายเหตุ: ฟอร์มเพิ่ม/แก้ไขอุปกรณ์ไม่มีช่องกรอก "เวลาเริ่มใช้งาน" จึงไม่แสดง
  // เป็นช่วงเวลา (เช่น 00:00-08:00) เพราะนั่นจะเป็นข้อมูลที่ผู้ใช้ไม่ได้กรอกจริง
  String _scheduleSummary(ApplianceModel a) {
    if (a.schedules.isEmpty) return 'ยังไม่ได้ตั้งตารางการใช้งาน';
    final s = a.schedules.first;
    final daysLabel = _daysLabel(s.days);
    final hoursLabel = s.hoursPerDay % 1 == 0
        ? s.hoursPerDay.toStringAsFixed(0)
        : s.hoursPerDay.toStringAsFixed(1);
    return '$daysLabel ใช้วันละ $hoursLabel ชม.';
  }

  String _daysLabel(List<int> days) {
    const names = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    if (days.length >= 7) return 'ทุกวัน';
    final sorted = [...days]..sort();
    return sorted.map((d) => names[d % 7]).join(' ');
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
                // ---- สรุปยอด 3 ช่อง ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _summaryBox(
                          label: 'อุปกรณ์ทั้งหมด',
                          value: '${_appliances.length} ชิ้น',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryBox(
                          label: 'ตารางใช้งาน',
                          value: '$_scheduledCount ชิ้น',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryBox(
                          label: 'ค่าไฟ/เดือน',
                          value: '฿${formatter.format(_totalMonthlyCost)}',
                          valueColor: const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---- รายการอุปกรณ์ ----
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
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _appliances.length,
                          itemBuilder: (context, index) {
                            final a = _appliances[index];
                            double monthlyCost =
                                _estimateApplianceMonthlyCost(a);
                            final hasSchedule = a.schedules.isNotEmpty;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                              Icons.electrical_services,
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
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15)),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${a.watt.toStringAsFixed(0)} วัตต์ • ฿${formatter.format(monthlyCost)}/เดือน',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20),
                                          onPressed: () => _confirmDelete(a),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: hasSchedule
                                          ? const Color(0xFFE8F5E9)
                                          : Colors.grey.shade100,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasSchedule
                                              ? Icons.schedule
                                              : Icons.schedule_outlined,
                                          size: 14,
                                          color: hasSchedule
                                              ? const Color(0xFF2E7D32)
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _scheduleSummary(a),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: hasSchedule
                                                  ? const Color(0xFF2E7D32)
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ClipRRect(
                                    borderRadius:
                                        const BorderRadius.vertical(
                                            bottom: Radius.circular(14)),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                _showDetailSheet(a),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 11),
                                              child: Center(
                                                child: Text(
                                                  'ดูข้อมูล',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: Color(0xFF333333),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 20,
                                          color: Colors.grey.shade200,
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                _showEditApplianceSheet(a),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 11),
                                              child: Center(
                                                child: Text(
                                                  'แก้ไข',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: Color(0xFF2E7D32),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
          if (index == 2) return;

          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
          } else if (index == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          }
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

  Widget _summaryBox({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: valueColor ?? const Color(0xFF333333),
            ),
          ),
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

  // Bottom sheet แก้ไขอุปกรณ์ที่มีอยู่แล้ว (ใช้ชีตเดียวกัน ส่ง existing ไปพรีฟิล)
  void _showEditApplianceSheet(ApplianceModel a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddApplianceSheet(
        firestoreService: _firestoreService,
        onAdded: _loadData,
        existing: a,
      ),
    );
  }

  // Bottom sheet ดูข้อมูล/รายละเอียดค่าไฟของอุปกรณ์ (ต่อวัน/เดือน/ปี/เฉลี่ย)
  void _showDetailSheet(ApplianceModel a) {
    final formatter = NumberFormat('#,##0.00');
    final hasSchedule = a.schedules.isNotEmpty;
    final costPerActiveDay = _costPerActiveDay(a);
    final costPerMonth = _estimateApplianceMonthlyCost(a);
    final costPerYear = _estimateApplianceYearlyCost(a);
    final avgCostPerDay = costPerMonth / 30;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(a.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              '${a.watt.toStringAsFixed(0)} วัตต์'
              '${hasSchedule ? ' • ${_scheduleSummary(a)}' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (!hasSchedule)
              Text(
                'อุปกรณ์นี้ยังไม่ได้ตั้งตารางการใช้งาน จึงยังไม่มีตัวเลขประมาณการค่าไฟ',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _detailBox(
                        'ต่อวันที่ใช้งาน',
                        '฿${formatter.format(costPerActiveDay)}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _detailBox('เฉลี่ย/วัน (ทั้งเดือน)',
                        '฿${formatter.format(avgCostPerDay)}'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _detailBox(
                        'ต่อเดือน', '฿${formatter.format(costPerMonth)}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _detailBox(
                        'ต่อปี', '฿${formatter.format(costPerYear)}'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ปิด'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
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

// ==================== Bottom Sheet เพิ่ม/แก้ไขอุปกรณ์ ====================
class _AddApplianceSheet extends StatefulWidget {
  final FirestoreService firestoreService;
  final VoidCallback onAdded;
  final ApplianceModel? existing;

  const _AddApplianceSheet({
    required this.firestoreService,
    required this.onAdded,
    this.existing,
  });

  @override
  State<_AddApplianceSheet> createState() => _AddApplianceSheetState();
}

class _AddApplianceSheetState extends State<_AddApplianceSheet> {
  final _nameController = TextEditingController();
  final _wattController = TextEditingController();
  final _hoursController = TextEditingController(text: '1');
  final _minutesController = TextEditingController(text: '0');
  Set<int> _selectedDays = {0, 1, 2, 3, 4, 5, 6}; // ทุกวันเป็นค่าเริ่มต้น
  bool _isCustom = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _isCustom = true; // แก้ไข: ข้ามหน้าเลือกรายการสามัญ เข้าฟอร์มตรง
      _nameController.text = existing.name;
      _wattController.text = existing.watt.toStringAsFixed(0);
      if (existing.schedules.isNotEmpty) {
        final s = existing.schedules.first;
        final h = s.hoursPerDay.floor();
        final m = ((s.hoursPerDay - h) * 60).round();
        _hoursController.text = h.toString();
        _minutesController.text = m.toString();
        _selectedDays = s.days.toSet();
      } else {
        _selectedDays = {};
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wattController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
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
    if (_nameController.text.isEmpty || _wattController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบ')),
      );
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกวันที่ใช้งานอย่างน้อย 1 วัน')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final watt = double.parse(_wattController.text);
      final hours = _totalHours;

      final appliance = ApplianceModel(
        id: widget.existing?.id ?? const Uuid().v4(),
        uid: uid,
        name: _nameController.text,
        watt: watt,
        schedules: [
          ScheduleModel(
            days: _selectedDays.toList()..sort(),
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

  double get _totalHours {
    final h = double.tryParse(_hoursController.text) ?? 0;
    final m = double.tryParse(_minutesController.text) ?? 0;
    return h + (m / 60);
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
                Text(_isEditing ? 'แก้ไขเครื่องใช้ไฟฟ้า' : 'เพิ่มเครื่องใช้ไฟฟ้า',
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        if (!_isEditing)
                          IconButton(
                            icon: const Icon(Icons.arrow_back, size: 18),
                            onPressed: () => setState(() => _isCustom = false),
                          ),
                        Text(
                            _isEditing ? 'แก้ไขข้อมูลอุปกรณ์' : 'กรอกข้อมูลอุปกรณ์',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 8',
                              suffixText: 'ชม.',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _minutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 30',
                              suffixText: 'นาที',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('วันที่ใช้งาน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _buildDaySelector(),
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
                            : Text(_isEditing ? 'บันทึกการแก้ไข' : 'บันทึก'),
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

  Widget _buildDaySelector() {
    const labels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (index) {
          final selected = _selectedDays.contains(index);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedDays.remove(index);
                } else {
                  _selectedDays.add(index);
                }
              });
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? const Color(0xFF2E7D32) : Colors.white,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF2E7D32)
                      : Colors.grey.shade300,
                ),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEstimateCard() {
    double watt = double.tryParse(_wattController.text) ?? 0;
    double hours = _totalHours;
    final activeDaysPerWeek = _selectedDays.isEmpty ? 7 : _selectedDays.length;

    double kWhPerDay = (watt * hours) / 1000;
    double costPerDay = kWhPerDay * 4.5; // อัตราเฉลี่ยประมาณการ (เฉพาะวันที่ใช้)
    double costPerMonth = costPerDay * (activeDaysPerWeek / 7) * 30;
    double costPerYear = costPerDay * (activeDaysPerWeek / 7) * 365;

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