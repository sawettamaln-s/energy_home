part of 'settings_screen.dart';

// ==================== บันทึกย้อนหลัง: ไฟฟ้า / ประปา ====================
// เดิมแยกเป็น 2 หน้า (ไฟฟ้า, น้ำ) คนละปุ่มในหน้าตั้งค่า รวมเป็นหน้าเดียวที่มี
// TabBar ด้านบนแทน — ใช้ลายเดียวกับ TabBar "ไฟฟ้า/น้ำ/อุปกรณ์" ในหน้า
// วิเคราะห์ (analysis_screen.dart) เพื่อให้ทั้งแอปดู consistent กัน
//
// แถบสรุปด้านบน (_utilitySummaryBar) ตอนนี้ผูกกับ "รอบบิลปัจจุบัน" เท่านั้น
// (log ที่ date >= cycleStart) พอบันทึกเลขมิเตอร์ต้นรอบขึ้นรอบใหม่ ตัวเลขจะ
// รีเซ็ตเป็น 0 รายการ/0 บาทให้เองตามธรรมชาติ โดยไม่ต้องลบข้อมูลเก่าทิ้ง —
// ประวัติของรอบก่อนๆ ถูกจัดกลุ่มเป็นการ์ดแยกตามเดือน/ปีของรอบบิล (ดู
// _MonthGroupCard) พับเก็บได้ทีละการ์ด รองรับกรณีมีประวัติสะสมหลายเดือน/ปี
// โดยไม่ทำให้หน้ายาวเกินไป
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

// แถบสรุปด้านบนของแต่ละแท็บ — โชว์จำนวนรายการ + ยอดรวมค่าใช้จ่าย "เฉพาะรอบ
// บิลปัจจุบัน" เท่านั้น (ไม่ใช่ทั้งหมดที่ดึงมา) ใช้ร่วมกันได้ทั้งแท็บไฟฟ้า
// และน้ำ แค่เปลี่ยนสี/ไอคอน/label
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        const SizedBox(height: 4),
        Text(
          'นับเฉพาะรอบบิลปัจจุบัน — พอขึ้นเลขมิเตอร์ต้นรอบใหม่ ตัวเลขนี้จะ'
          'เริ่มนับใหม่ ส่วนประวัติเดือนก่อนๆ ยังดูได้ด้านล่าง',
          style: TextStyle(
              color: color.withValues(alpha: 0.85), fontSize: 11, height: 1.3),
        ),
      ],
    ),
  );
}

// การ์ดพับ/กางได้ของประวัติแต่ละเดือน (1 การ์ด = 1 รอบบิล) ใช้ร่วมกันได้ทั้ง
// แท็บไฟฟ้าและน้ำ — ค่าเริ่มต้นรอบปัจจุบันกางไว้ ส่วนรอบเก่าพับเก็บ ให้หน้า
// ไม่ยาวเกินไปแม้ประวัติจะสะสมมาหลายเดือน/หลายปีในอนาคต
class _MonthGroupCard extends StatefulWidget {
  final String monthLabel;
  final bool isCurrent;
  final int count;
  final double totalCost;
  final Color accent;
  final NumberFormat formatter;
  final Widget table;
  final bool initiallyExpanded;

  const _MonthGroupCard({
    required this.monthLabel,
    required this.isCurrent,
    required this.count,
    required this.totalCost,
    required this.accent,
    required this.formatter,
    required this.table,
    this.initiallyExpanded = false,
  });

  @override
  State<_MonthGroupCard> createState() => _MonthGroupCardState();
}

class _MonthGroupCardState extends State<_MonthGroupCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isCurrent
              ? accent.withValues(alpha: 0.35)
              : Colors.grey.shade200,
          width: widget.isCurrent ? 1.3 : 1,
        ),
        boxShadow: widget.isCurrent
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                color: widget.isCurrent
                    ? accent.withValues(alpha: 0.07)
                    : Colors.grey.shade50,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: accent.withValues(
                            alpha: widget.isCurrent ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(Icons.calendar_month, size: 18, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.monthLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (widget.isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'รอบปัจจุบัน',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.count} รายการ · '
                            '${widget.formatter.format(widget.totalCost)} บาท',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down,
                          color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: widget.table,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }
}

// จัดกลุ่ม log ตามรอบบิลที่ log แต่ละตัวสังกัดอยู่ (ใช้ logic เดียวกับ
// EnergyForecaster.getCycleStart) แล้ว sort คีย์จากใหม่ไปเก่า — ใช้ร่วมกันได้
// ทั้ง ElectricityLogModel และ WaterLogModel เพราะรับแค่ตัว getวันที่เข้ามา
List<MapEntry<DateTime, List<T>>> _groupLogsByCycle<T>(
  List<T> logs,
  DateTime Function(T) dateOf,
  int billingDay,
) {
  final grouped = <DateTime, List<T>>{};
  for (final log in logs) {
    final key = EnergyForecaster.getCycleStart(dateOf(log), billingDay);
    grouped.putIfAbsent(key, () => []).add(log);
  }
  final entries = grouped.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return entries;
}

String _cycleMonthLabel(DateTime cycleStart) {
  return '${thaiMonths[cycleStart.month - 1]} ${cycleStart.year + 543}';
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
  int _billingDay = 30;
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
    _billingDay = user?.billingDay ?? 30;
    _cycleStart = EnergyForecaster.getCycleStart(now, _billingDay);
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

    const accent = Colors.orange;
    final currentCycleLogs =
        _logs.where((l) => !l.date.isBefore(_cycleStart!)).toList();
    final currentCycleCost =
        currentCycleLogs.fold<double>(0, (sum, l) => sum + l.cost);
    final groups = _groupLogsByCycle<ElectricityLogModel>(
        _logs, (l) => l.date, _billingDay);

    return Column(
      children: [
        _utilitySummaryBar(
          color: accent,
          icon: Icons.bolt,
          count: currentCycleLogs.length,
          totalCost: currentCycleCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: groups.length,
            itemBuilder: (context, groupIndex) {
              final group = groups[groupIndex];
              final groupLogs = group.value;
              final isCurrent = group.key == _cycleStart;
              final groupCost =
                  groupLogs.fold<double>(0, (sum, l) => sum + l.cost);

              return _MonthGroupCard(
                monthLabel: _cycleMonthLabel(group.key),
                isCurrent: isCurrent,
                count: groupLogs.length,
                totalCost: groupCost,
                accent: accent,
                formatter: formatter,
                initiallyExpanded: groupIndex == 0,
                table: ExcelStyleTable(
                  accent: accent,
                  columns: const [
                    ExcelTableColumn('วันที่', align: TextAlign.left, flex: 3),
                    ExcelTableColumn('หน่วยที่ใช้', flex: 2),
                    ExcelTableColumn('ค่าไฟ', flex: 2),
                  ],
                  rowCount: groupLogs.length,
                  isLatest: (row) => groupIndex == 0 && row == 0,
                  isLocked: (row) => !_isEditable(groupLogs[row]),
                  cellText: (row, col) {
                    final log = groupLogs[row];
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
                    final log = groupLogs[row];
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
  int _billingDay = 30;
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
    _billingDay = user?.billingDay ?? 30;
    _cycleStart = EnergyForecaster.getCycleStart(now, _billingDay);
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

    const accent = Colors.blue;
    final currentCycleLogs =
        _logs.where((l) => !l.date.isBefore(_cycleStart!)).toList();
    final currentCycleCost =
        currentCycleLogs.fold<double>(0, (sum, l) => sum + l.cost);
    final groups =
        _groupLogsByCycle<WaterLogModel>(_logs, (l) => l.date, _billingDay);

    return Column(
      children: [
        _utilitySummaryBar(
          color: accent,
          icon: Icons.water_drop,
          count: currentCycleLogs.length,
          totalCost: currentCycleCost,
          formatter: formatter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: groups.length,
            itemBuilder: (context, groupIndex) {
              final group = groups[groupIndex];
              final groupLogs = group.value;
              final isCurrent = group.key == _cycleStart;
              final groupCost =
                  groupLogs.fold<double>(0, (sum, l) => sum + l.cost);

              return _MonthGroupCard(
                monthLabel: _cycleMonthLabel(group.key),
                isCurrent: isCurrent,
                count: groupLogs.length,
                totalCost: groupCost,
                accent: accent,
                formatter: formatter,
                initiallyExpanded: groupIndex == 0,
                table: ExcelStyleTable(
                  accent: accent,
                  columns: const [
                    ExcelTableColumn('วันที่', align: TextAlign.left, flex: 3),
                    ExcelTableColumn('หน่วยที่ใช้', flex: 2),
                    ExcelTableColumn('ค่าน้ำ', flex: 2),
                  ],
                  rowCount: groupLogs.length,
                  isLatest: (row) => groupIndex == 0 && row == 0,
                  isLocked: (row) => !_isEditable(groupLogs[row]),
                  cellText: (row, col) {
                    final log = groupLogs[row];
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
                    final log = groupLogs[row];
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
              );
            },
          ),
        ),
      ],
    );
  }
}