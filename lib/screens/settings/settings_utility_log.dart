part of 'settings_screen.dart';

// ==================== บันทึกย้อนหลัง: ไฟฟ้า / ประปา ====================
// เดิมแยกเป็น 2 หน้า (ไฟฟ้า, น้ำ) คนละปุ่มในหน้าตั้งค่า รวมเป็นหน้าเดียวที่มี
// TabBar ด้านบนแทน — ใช้ลายเดียวกับ TabBar "ไฟฟ้า/น้ำ/อุปกรณ์" ในหน้า
// วิเคราะห์ (analysis_screen.dart) เพื่อให้ทั้งแอปดู consistent กัน
class _UtilityHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _UtilityHistoryScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_UtilityHistoryScreen> createState() => _UtilityHistoryScreenState();
}

class _UtilityHistoryScreenState extends State<_UtilityHistoryScreen>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF2E7D32);
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('ประวัติมิเตอร์ไฟฟ้า / ประปา'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _green,
          tabs: const [
            Tab(icon: Icon(Icons.bolt), text: 'ไฟฟ้า'),
            Tab(icon: Icon(Icons.water_drop), text: 'ประปา'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ElectricityLogTab(
              uid: widget.uid, firestoreService: widget.firestoreService),
          _WaterLogTab(
              uid: widget.uid, firestoreService: widget.firestoreService),
        ],
      ),
    );
  }
}

// แถบสรุปด้านบนของแต่ละแท็บ — โชว์จำนวนรายการ + ยอดรวมค่าใช้จ่ายในช่วงที่ดึงมา
// ใช้ร่วมกันได้ทั้งแท็บไฟฟ้าและน้ำ แค่เปลี่ยนสี/ไอคอน/label
Widget _utilitySummaryBar({
  required Color color,
  required IconData icon,
  required int count,
  required double totalCost,
  required NumberFormat formatter,
}) {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Text(
          '$count รายการ',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const Spacer(),
        Text(
          'รวม ${formatter.format(totalCost)} บาท',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    ),
  );
}

// ==================== แท็บประวัติไฟฟ้า ====================
class _ElectricityLogTab extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _ElectricityLogTab({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_ElectricityLogTab> createState() => _ElectricityLogTabState();
}

class _ElectricityLogTabState extends State<_ElectricityLogTab> {
  List<ElectricityLogModel> _logs = [];
  bool _isLoading = true;
  // จุดเริ่มต้นของรอบบิลปัจจุบัน — log ที่เก่ากว่านี้ถือว่าอยู่ในรอบที่ปิด
  // ไปแล้ว ห้ามแก้ไข/ลบ เพราะถูกใช้คำนวณบิลที่ปิดไปแล้วแล้ว แก้ย้อนหลังจะ
  // ทำให้ตัวเลขบิลเก่ากับ log ไม่ตรงกัน
  DateTime? _cycleStart;

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
    final user = await widget.firestoreService.getUser(widget.uid);
    _cycleStart = EnergyForecaster.getCycleStart(now, user?.billingDay ?? 30);
    _logs = await widget.firestoreService.getCurrentMonthElectricityLogs(
      widget.uid,
      startDate,
      endDate,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  bool _isEditable(ElectricityLogModel log) {
    if (_cycleStart == null) return false;
    return !log.date.isBefore(_cycleStart!);
  }

  Future<void> _confirmDelete(ElectricityLogModel log) async {
final confirm = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล',
      content: 'ต้องการลบข้อมูลนี้ใช่ไหมคะ?',
    );
    if (confirm == true) {
      await widget.firestoreService.deleteElectricityLog(log.uid, log.id);
      await _loadLogs();
    }
  }

  void _showLockedNotice() {
    showInfoDialog(
      context,
      title: 'แก้ไขไม่ได้แล้ว',
      message: 'รายการนี้อยู่ในรอบบิลที่ปิดไปแล้ว ถูกใช้คำนวณบิลเดือนนั้น'
          'เรียบร้อยแล้ว จึงแก้ไข/ลบไม่ได้ เพื่อไม่ให้ตัวเลขบิลเก่ากับ'
          'ประวัติไม่ตรงกัน',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('ยังไม่มีประวัติการบันทึก',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);

    return Column(
      children: [
        _utilitySummaryBar(
          color: Colors.orange,
          icon: Icons.bolt,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              final isLatest = index == 0;
              final isLast = index == _logs.length - 1;
              const accent = Colors.orange;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // เส้น timeline + จุดด้านซ้าย
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLatest ? accent : Colors.grey.shade300,
                            border:
                                Border.all(color: Colors.white, width: 2),
                            boxShadow: isLatest
                                ? [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey.shade200,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // การ์ดข้อมูลของรายการนั้น
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isLatest
                                ? Border.all(color: accent.withValues(alpha: 0.3))
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      DateFormat('dd/MM/yyyy')
                                          .format(log.date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  if (isLatest)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'ล่าสุด',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: _isEditable(log)
                                        ? Icon(Icons.delete_outline,
                                            size: 19,
                                            color: Colors.red.shade300)
                                        : Icon(Icons.lock_outline,
                                            size: 18,
                                            color: Colors.grey.shade400),
                                    onPressed: _isEditable(log)
                                        ? () => _confirmDelete(log)
                                        : _showLockedNotice,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'บันทึกเมื่อ ${DateFormat('HH:mm น.').format(log.date)}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: log.peakMeterValue != null
                                    ? [
                                        ValueChip(
                                          icon: Icons.bolt,
                                          color: Colors.orange.shade700,
                                          label: 'On-Peak',
                                          value: '${log.peakMeterValue!.toStringAsFixed(0)} หน่วย',
                                        ),
                                        ValueChip(
                                          icon: Icons.bolt_outlined,
                                          color: Colors.blueGrey,
                                          label: 'Off-Peak',
                                          value: '${log.offPeakMeterValue!.toStringAsFixed(0)} หน่วย',
                                        ),
                                        ValueChip(
                                          icon: Icons.trending_up_rounded,
                                          color: accent,
                                          label: 'ใช้ไปรวม',
                                          value: '${log.usedFromStart.toStringAsFixed(0)} หน่วย',
                                        ),
                                        ValueChip(
                                          icon: Icons.payments_outlined,
                                          color: accent,
                                          label: 'ค่าไฟ',
                                          value: '${formatter.format(log.cost)} บาท',
                                        ),
                                      ]
                                    : [
                                        ValueChip(
                                          icon: Icons.speed_outlined,
                                          color: accent,
                                          label: 'มิเตอร์',
                                          value: log.meterValue.toStringAsFixed(0),
                                        ),
                                        ValueChip(
                                          icon: Icons.trending_up_rounded,
                                          color: accent,
                                          label: 'ใช้ไป',
                                          value: '${log.usedFromStart.toStringAsFixed(0)} หน่วย',
                                        ),
                                        ValueChip(
                                          icon: Icons.payments_outlined,
                                          color: accent,
                                          label: 'ค่าไฟ',
                                          value: '${formatter.format(log.cost)} บาท',
                                        ),
                                      ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

}

// ==================== แท็บประวัติน้ำ ====================
class _WaterLogTab extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _WaterLogTab({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_WaterLogTab> createState() => _WaterLogTabState();
}

class _WaterLogTabState extends State<_WaterLogTab> {
  List<WaterLogModel> _logs = [];
  bool _isLoading = true;
  DateTime? _cycleStart;

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
    final user = await widget.firestoreService.getUser(widget.uid);
    _cycleStart = EnergyForecaster.getCycleStart(now, user?.billingDay ?? 30);
    _logs = await widget.firestoreService.getCurrentMonthWaterLogs(
      widget.uid,
      startDate,
      endDate,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  bool _isEditable(WaterLogModel log) {
    if (_cycleStart == null) return false;
    return !log.date.isBefore(_cycleStart!);
  }

  Future<void> _confirmDelete(WaterLogModel log) async {
final confirm = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล',
      content: 'ต้องการลบข้อมูลนี้ใช่ไหมคะ?',
    );
    if (confirm == true) {
      await widget.firestoreService.deleteWaterLog(log.uid, log.id);
      await _loadLogs();
    }
  }

  void _showLockedNotice() {
    showInfoDialog(
      context,
      title: 'แก้ไขไม่ได้แล้ว',
      message: 'รายการนี้อยู่ในรอบบิลที่ปิดไปแล้ว ถูกใช้คำนวณบิลเดือนนั้น'
          'เรียบร้อยแล้ว จึงแก้ไข/ลบไม่ได้ เพื่อไม่ให้ตัวเลขบิลเก่ากับ'
          'ประวัติไม่ตรงกัน',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('ยังไม่มีประวัติการบันทึก',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);

    return Column(
      children: [
        _utilitySummaryBar(
          color: Colors.blue,
          icon: Icons.water_drop,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              final isLatest = index == 0;
              final isLast = index == _logs.length - 1;
              const accent = Colors.blue;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // เส้น timeline + จุดด้านซ้าย
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLatest ? accent : Colors.grey.shade300,
                            border:
                                Border.all(color: Colors.white, width: 2),
                            boxShadow: isLatest
                                ? [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey.shade200,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // การ์ดข้อมูลของรายการนั้น
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: isLatest
                                ? Border.all(color: accent.withValues(alpha: 0.3))
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      DateFormat('dd/MM/yyyy')
                                          .format(log.date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                  if (isLatest)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'ล่าสุด',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: _isEditable(log)
                                        ? Icon(Icons.delete_outline,
                                            size: 19,
                                            color: Colors.red.shade300)
                                        : Icon(Icons.lock_outline,
                                            size: 18,
                                            color: Colors.grey.shade400),
                                    onPressed: _isEditable(log)
                                        ? () => _confirmDelete(log)
                                        : _showLockedNotice,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'บันทึกเมื่อ ${DateFormat('HH:mm น.').format(log.date)}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ValueChip(
                                    icon: Icons.speed_outlined,
                                    color: accent,
                                    label: 'มิเตอร์',
                                    value: log.meterValue.toStringAsFixed(0),
                                  ),
                                  ValueChip(
                                    icon: Icons.trending_up_rounded,
                                    color: accent,
                                    label: 'ใช้ไป',
                                    value: '${log.usedFromStart.toStringAsFixed(0)} ลบ.ม.',
                                  ),
                                  ValueChip(
                                    icon: Icons.payments_outlined,
                                    color: accent,
                                    label: 'ค่าน้ำ',
                                    value: '${formatter.format(log.cost)} บาท',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

}