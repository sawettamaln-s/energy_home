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

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return excelTableEmptyState(
        icon: Icons.bolt,
        message: 'ยังไม่มีประวัติการบันทึก',
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);
    const accent = Colors.orange;

    return Column(
      children: [
        _utilitySummaryBar(
          color: accent,
          icon: Icons.bolt,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ExcelStyleTable(
              accent: accent,
              columns: const [
                ExcelTableColumn('วันที่', align: TextAlign.left, flex: 3),
                ExcelTableColumn('ใช้ไป', flex: 2),
                ExcelTableColumn('ค่าไฟ', flex: 2),
              ],
              rowCount: _logs.length,
              isLatest: (row) => row == 0,
              isLocked: (row) => !_isEditable(_logs[row]),
              cellText: (row, col) {
                final log = _logs[row];
                switch (col) {
                  case 0:
                    return DateFormat('dd/MM/yy').format(log.date);
                  case 1:
                    return log.usedFromStart.toStringAsFixed(0);
                  default:
                    return formatter.format(log.cost);
                }
              },
              onRowTap: (row) {
                final log = _logs[row];
                final isTou = log.peakMeterValue != null;
                showTableRowActions(
                  context,
                  title: DateFormat('dd/MM/yyyy').format(log.date),
                  subtitle: isTou
                      ? 'On-Peak ${log.peakMeterValue!.toStringAsFixed(0)} · '
                          'Off-Peak ${log.offPeakMeterValue!.toStringAsFixed(0)} · '
                          'ใช้ไป ${log.usedFromStart.toStringAsFixed(0)} หน่วย · '
                          '${formatter.format(log.cost)} บาท'
                      : 'มิเตอร์ ${log.meterValue.toStringAsFixed(0)} · '
                          'ใช้ไป ${log.usedFromStart.toStringAsFixed(0)} หน่วย · '
                          '${formatter.format(log.cost)} บาท',
                  locked: !_isEditable(log),
                  onDelete: () => _confirmDelete(log),
                );
              },
            ),
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

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    }
    if (_logs.isEmpty) {
      return excelTableEmptyState(
        icon: Icons.water_drop,
        message: 'ยังไม่มีประวัติการบันทึก',
      );
    }

    final totalCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);
    const accent = Colors.blue;

    return Column(
      children: [
        _utilitySummaryBar(
          color: accent,
          icon: Icons.water_drop,
          count: _logs.length,
          totalCost: totalCost,
          formatter: formatter,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ExcelStyleTable(
              accent: accent,
              columns: const [
                ExcelTableColumn('วันที่', align: TextAlign.left, flex: 3),
                ExcelTableColumn('ใช้ไป', flex: 2),
                ExcelTableColumn('ค่าน้ำ', flex: 2),
              ],
              rowCount: _logs.length,
              isLatest: (row) => row == 0,
              isLocked: (row) => !_isEditable(_logs[row]),
              cellText: (row, col) {
                final log = _logs[row];
                switch (col) {
                  case 0:
                    return DateFormat('dd/MM/yy').format(log.date);
                  case 1:
                    return log.usedFromStart.toStringAsFixed(0);
                  default:
                    return formatter.format(log.cost);
                }
              },
              onRowTap: (row) {
                final log = _logs[row];
                showTableRowActions(
                  context,
                  title: DateFormat('dd/MM/yyyy').format(log.date),
                  subtitle: 'มิเตอร์ ${log.meterValue.toStringAsFixed(0)} · '
                      'ใช้ไป ${log.usedFromStart.toStringAsFixed(0)} ลบ.ม. · '
                      '${formatter.format(log.cost)} บาท',
                  locked: !_isEditable(log),
                  onDelete: () => _confirmDelete(log),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

}