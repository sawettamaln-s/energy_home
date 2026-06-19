import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/electricity_log_model.dart';
import '../../models/user_model.dart';
import '../../models/water_log_model.dart';
import '../../services/firestore_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _user = await _firestoreService.getUser(uid);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('ตั้งค่า',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ข้อมูลผู้ใช้
                  _buildSectionHeader('บัญชีผู้ใช้'),
                  _buildUserCard(),

                  const SizedBox(height: 16),

                  // ตั้งค่าระบบ
                  _buildSectionHeader('ตั้งค่าระบบ'),
                  _buildSettingsCard(),

                  const SizedBox(height: 16),

                  // ข้อมูลและบิล
                  _buildSectionHeader('ข้อมูลและบิล'),
                  _buildDataCard(),

                  const SizedBox(height: 16),

                  // ออกจากระบบ
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('ออกจากระบบ',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.grey)),
    );
  }

  // การ์ดข้อมูลผู้ใช้
  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildInfoRow(
              Icons.person, 'ชื่อ', _user?.name ?? '-'),
          const Divider(height: 16),
          _buildInfoRow(
              Icons.email, 'อีเมล', _user?.email ?? '-'),
          const Divider(height: 16),
          _buildInfoRow(
              Icons.location_on,
              'พื้นที่',
              _user?.area == 'bangkok'
                  ? 'กรุงเทพและปริมณฑล'
                  : 'ต่างจังหวัด'),
          const Divider(height: 16),
          _buildInfoRow(
              Icons.electric_meter,
              'ประเภทมิเตอร์',
              _user?.meterType == 'tou' ? 'TOU' : 'ปกติ'),
          const Divider(height: 16),
        ],
      ),
    );
  }

  // การ์ดตั้งค่าระบบ
  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.calendar_today,
            title: 'วันตัดรอบบิล',
            subtitle: 'วันที่ ${_user?.billingDay ?? 30} ของทุกเดือน',
            onTap: () => _showEditBillingDay(),
          ),
          const Divider(height: 1),
          _buildSettingsTile(
            icon: Icons.attach_money,
            title: 'Fixed Cost',
            subtitle:
                '฿${NumberFormat('#,##0.00').format(_user?.fixedCost ?? 0)} / เดือน',
            onTap: () => _showEditFixedCost(),
          ),
          const Divider(height: 1),
          _buildSettingsTile(
            icon: Icons.history,
            title: 'บันทึกค่ามิเตอร์ต้นรอบ',
            subtitle: 'กรอกหน่วยจากใบแจ้งหนี้ล่าสุด',
            onTap: () => _showEditStartMeter(),
          ),
        ],
      ),
    );
  }

  // การ์ดข้อมูลและบิล
  Widget _buildDataCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.bolt,
            title: 'ประวัติมิเตอร์ไฟฟ้า',
            subtitle: 'ดูและลบประวัติการบันทึก',
            onTap: () => _showElectricityHistory(),
          ),
          const Divider(height: 1),
          _buildSettingsTile(
            icon: Icons.water_drop,
            title: 'ประวัติมิเตอร์น้ำ',
            subtitle: 'ดูและลบประวัติการบันทึก',
            onTap: () => _showWaterHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF2E7D32), size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // แก้ไขวันตัดรอบบิล
  void _showEditBillingDay() {
    int selectedDay = _user?.billingDay ?? 30;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('วันตัดรอบบิล'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedDay,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: List.generate(31, (i) {
                  return DropdownMenuItem(
                    value: i + 1,
                    child: Text('วันที่ ${i + 1}'),
                  );
                }),
                onChanged: (val) =>
                    setDialogState(() => selectedDay = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _firestoreService.updateUser(
                    _user!.uid, {'billingDay': selectedDay});
                await _loadUser();
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  // แก้ไข Fixed Cost
  void _showEditFixedCost() {
    final controller = TextEditingController(
        text: (_user?.fixedCost ?? 0).toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fixed Cost รายเดือน'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'เช่น 500',
            prefixText: '฿ ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final value =
                  double.tryParse(controller.text) ?? 0;
              await _firestoreService.updateUser(
                  _user!.uid, {'fixedCost': value});
              await _loadUser();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  // แก้ไขค่ามิเตอร์ต้นรอบ
  void _showEditStartMeter() {
    final eController = TextEditingController(
        text: (_user?.startElectricityValue ?? 0).toString());
    final wController = TextEditingController(
        text: (_user?.startWaterValue ?? 0).toString());
    int selectedMonth = _user?.startBillingMonth ??
        DateTime.now().month;
    int selectedYear =
        _user?.startBillingYear ?? DateTime.now().year;

    final List<String> thaiMonths = [
      'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน',
      'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม',
      'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ค่ามิเตอร์ต้นรอบบิล'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('เดือนของใบแจ้งหนี้',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: selectedMonth,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                        ),
                        items: List.generate(12, (i) {
                          return DropdownMenuItem(
                            value: i + 1,
                            child: Text(thaiMonths[i],
                                style:
                                    const TextStyle(fontSize: 13)),
                          );
                        }),
                        onChanged: (val) => setDialogState(
                            () => selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedYear,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                        ),
                        items: [
                          DateTime.now().year - 1,
                          DateTime.now().year,
                        ].map((year) {
                          return DropdownMenuItem(
                            value: year,
                            child: Text('$year',
                                style:
                                    const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(
                            () => selectedYear = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('หน่วยไฟฟ้า',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: eController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 14009',
                    suffixText: 'หน่วย',
                    prefixIcon: const Icon(Icons.bolt,
                        color: Colors.orange),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('หน่วยน้ำประปา',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: wController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  decoration: InputDecoration(
                    hintText: 'เช่น 148',
                    suffixText: 'ลบ.ม.',
                    prefixIcon: const Icon(Icons.water_drop,
                        color: Colors.blue),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final eVal =
                    double.tryParse(eController.text) ?? 0;
                final wVal =
                    double.tryParse(wController.text) ?? 0;
                await _firestoreService.updateUser(_user!.uid, {
                  'startElectricityValue': eVal,
                  'startWaterValue': wVal,
                  'startBillingMonth': selectedMonth,
                  'startBillingYear': selectedYear,
                });
                await _loadUser();
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  // ประวัติมิเตอร์ไฟฟ้า
  void _showElectricityHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ElectricityHistoryScreen(
          uid: FirebaseAuth.instance.currentUser!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }

  // ประวัติมิเตอร์น้ำ
  void _showWaterHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _WaterHistoryScreen(
          uid: FirebaseAuth.instance.currentUser!.uid,
          firestoreService: _firestoreService,
        ),
      ),
    );
  }
}

// ==================== ประวัติไฟฟ้า ====================
class _ElectricityHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _ElectricityHistoryScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_ElectricityHistoryScreen> createState() =>
      _ElectricityHistoryScreenState();
}

class _ElectricityHistoryScreenState
    extends State<_ElectricityHistoryScreen> {
  List<ElectricityLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, 1);
    final endDate = DateTime(now.year + 1, now.month, 1);
    _logs = await widget.firestoreService
        .getCurrentMonthElectricityLogs(
            widget.uid, startDate, endDate);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติมิเตอร์ไฟฟ้า'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('ยังไม่มีประวัติการบันทึก'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFF3E0),
                          child: Icon(Icons.bolt,
                              color: Colors.orange),
                        ),
                        title: Text(
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(log.date),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                        subtitle: Text(
                          'มิเตอร์: ${log.meterValue.toStringAsFixed(0)} • '
                          'ใช้ไป: ${log.usedFromStart.toStringAsFixed(0)} หน่วย'
                          '${log.usedFromLast > 0 ? ' (+${log.usedFromLast.toStringAsFixed(0)})' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              '฿${formatter.format(log.cost)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange),
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _confirmDelete(log),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _confirmDelete(ElectricityLogModel log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อมูล'),
        content: const Text('ต้องการลบข้อมูลนี้ใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.firestoreService
          .deleteElectricityLog(log.uid, log.id);
      await _loadLogs();
    }
  }
}

// ==================== ประวัติน้ำ ====================
class _WaterHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _WaterHistoryScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_WaterHistoryScreen> createState() =>
      _WaterHistoryScreenState();
}

class _WaterHistoryScreenState
    extends State<_WaterHistoryScreen> {
  List<WaterLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, 1);
    final endDate = DateTime(now.year + 1, now.month, 1);
    _logs = await widget.firestoreService
        .getCurrentMonthWaterLogs(
            widget.uid, startDate, endDate);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติมิเตอร์น้ำ'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('ยังไม่มีประวัติการบันทึก'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE3F2FD),
                          child: Icon(Icons.water_drop,
                              color: Colors.blue),
                        ),
                        title: Text(
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(log.date),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                        subtitle: Text(
                          'มิเตอร์: ${log.meterValue.toStringAsFixed(0)} • '
                          'ใช้ไป: ${log.usedFromStart.toStringAsFixed(0)} ลบ.ม.'
                          '${log.usedFromLast > 0 ? ' (+${log.usedFromLast.toStringAsFixed(0)})' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              '฿${formatter.format(log.cost)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue),
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _confirmDelete(log),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _confirmDelete(WaterLogModel log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อมูล'),
        content: const Text('ต้องการลบข้อมูลนี้ใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ลบ',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.firestoreService
          .deleteWaterLog(log.uid, log.id);
      await _loadLogs();
    }
  }
}