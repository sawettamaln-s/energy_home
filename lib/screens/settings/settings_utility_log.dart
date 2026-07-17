part of 'settings_screen.dart';

// ==================== บันทึกย้อนหลัง: ไฟฟ้า / ประปา ====================
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

// แถบสรุปด้านบนของแต่ละแท็บ — โชว์จำนวนรายการ + ยอดรวมค่าใช้จ่าย "เฉพาะรอบบิลที่กำลังสะสมยอด"
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
        const SizedBox(height: 6),
        Text(
          'ยอดประมาณการของรอบบิลถัดไป — ระบบจะสะสมหน่วยไปจนกว่าจะถึงวันตัดรอบบิลของคุณ',
          style: TextStyle(
              color: color.withValues(alpha: 0.85), fontSize: 11, height: 1.4),
        ),
      ],
    ),
  );
}

// การ์ดพับ/กางได้ของประวัติแต่ละเดือน (1 การ์ด = 1 รอบบิล)
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
                                    'กำลังสะสมยอด',
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
                            widget.isCurrent
                                ? '${widget.count} รายการที่บันทึกแล้ว' // รอบปัจจุบันโชว์แค่จำนวนรายการพอ ไม่ต้องโชว์บาทซ้ำ
                                : '${widget.count} รายการ · สรุปยอดรวม ${widget.formatter.format(widget.totalCost)} บาท', // รอบเก่าโชว์ยอดเงินจริง
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

// จัดกลุ่ม log ตามรอบบิลจริง โดยปรับขยับคีย์ขึ้นเป็นของเดือนใบแจ้งหนี้รอบถัดไปอัตโนมัติ
// เพื่อให้ได้โครงสร้างกลุ่มชื่อรอบบิลที่ถูกต้องแม่นยำ
List<MapEntry<DateTime, List<T>>> _groupLogsByCycle<T>(
  List<T> logs,
  DateTime Function(T) dateOf,
  int billingDay,
) {
  final grouped = <DateTime, List<T>>{};
  for (final log in logs) {
    final logDate = dateOf(log);
    final baseCycleStart = EnergyForecaster.getCycleStart(logDate, billingDay);

    // Logic ปัดเดือนประวัติให้สอดคล้องกัน: ถ้าวันที่ของ Log ชิ้นนั้นเลยวันตัดรอบบิลมาแล้ว
    // ให้ปัดกลุ่ม Key ของก้อนนี้ขึ้นหน้าเป็นเดือนของใบแจ้งหนี้ถัดไปล่วงหน้าทันที
    DateTime billingCycleKey;
    if (logDate.day >= billingDay) {
      billingCycleKey =
          DateTime(baseCycleStart.year, baseCycleStart.month + 1, billingDay);
    } else {
      billingCycleKey =
          DateTime(baseCycleStart.year, baseCycleStart.month, billingDay);
    }

    grouped.putIfAbsent(billingCycleKey, () => []).add(log);
  }
  final entries = grouped.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return entries;
}

String _cycleMonthLabel(DateTime cycleMonth) {
  return '${thaiMonths[cycleMonth.month - 1]} ${cycleMonth.year + 543}';
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
  DateTime? _cycleStart;
  DateTime? _billingCycleKey;
  // ใช้ตัดสินว่าตารางควรโชว์คอลัมน์ On-Peak/Off-Peak แยกไหม (เดิมข้อมูลนี้
  // โชว์ได้แค่ตอนแตะแถวดู detail เฉยๆ ทั้งที่เป็นตัวเลขที่ TOU ใช้ตัดสินใจ
  // บ่อย เลยยกขึ้นมาเป็นคอลัมน์ในตารางหลักด้วย)
  bool _isTou = false;
  // เลขมิเตอร์ต้นรอบ (peak/offpeak) ของแต่ละรอบบิล — ใช้คำนวณ "ที่ใช้ไป"
  // แยกตามประเภทจาก log.peakMeterValue/offPeakMeterValue ที่เป็นเลขสะสม
  // ล้วนๆ (ไม่ใช้ user.startPeakValue ตัวเดียวเพราะรอบเก่าที่ปิดไปแล้วมี
  // ต้นรอบคนละค่ากับรอบปัจจุบัน — ต้องอิงประวัติจริงของรอบนั้นๆ)
  List<StartMeterRecordModel> _startHistory = [];

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
    _isTou = user?.meterType == 'tou';
    if (_isTou) {
      _startHistory = await widget.firestoreService.getStartMeterHistory(widget.uid);
    }
    _cycleStart = EnergyForecaster.getCycleStart(now, _billingDay);

    // ตั้งค่าคีย์ระบุกลุ่มของรอบปัจจุบันที่ผ่าน Logic ปัดรอบบิลเรียบร้อยแล้ว
    if (now.day >= _billingDay) {
      _billingCycleKey =
          DateTime(_cycleStart!.year, _cycleStart!.month + 1, _billingDay);
    } else {
      _billingCycleKey =
          DateTime(_cycleStart!.year, _cycleStart!.month, _billingDay);
    }

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

  // หาเลขต้นรอบ (peak/offpeak) ของรอบบิลที่ cycleKey นี้ตรงกับ — ใช้ month/
  // year เดียวกับที่ StartMeterRecordModel เก็บไว้ (r.billingMonth/Year)
  // คืน null ถ้าไม่เจอ record ของรอบนั้นเลย (เช่น log เก่าก่อนเคยตั้ง TOU)
  (double peak, double offPeak)? _startValuesFor(DateTime cycleKey) {
    final match = _startHistory.where((r) =>
        r.billingMonth == cycleKey.month && r.billingYear == cycleKey.year);
    if (match.isEmpty) return null;
    final r = match.first;
    if (r.peakValue <= 0 && r.offPeakValue <= 0) return null;
    return (r.peakValue, r.offPeakValue);
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
              final isCurrent = group.key == _billingCycleKey;
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
                  // TOU: เพิ่มคอลัมน์ On-Peak/Off-Peak "ที่ใช้ไป" (ไม่ใช่เลข
                  // มิเตอร์สะสม) เข้าไปในตารางหลักเลย เดิมมีแต่เลขสะสมโชว์
                  // ตอนแตะแถวดู detail เท่านั้น ไม่มีตัวเลข "ใช้ไปเท่าไหร่"
                  // แยกประเภทให้ดูตรงๆ
                  columns: _isTou
                      ? const [
                          ExcelTableColumn('วันที่',
                              align: TextAlign.left, flex: 3),
                          ExcelTableColumn('On-Peak', flex: 2),
                          ExcelTableColumn('Off-Peak', flex: 2),
                          ExcelTableColumn('รวม', flex: 2),
                          ExcelTableColumn('ค่าไฟ', flex: 2),
                        ]
                      : const [
                          ExcelTableColumn('วันที่',
                              align: TextAlign.left, flex: 3),
                          ExcelTableColumn('หน่วยที่ใช้', flex: 2),
                          ExcelTableColumn('ค่าไฟ', flex: 2),
                        ],
                  rowCount: groupLogs.length,
                  isLatest: (row) => groupIndex == 0 && row == 0,
                  isLocked: (row) => !_isEditable(groupLogs[row]),
                  cellText: (row, col) {
                    final log = groupLogs[row];
                    if (_isTou) {
                      final start = _startValuesFor(group.key);
                      switch (col) {
                        case 0:
                          return DateFormat('dd/MM/yy').format(log.date);
                        case 1:
                          if (start == null) return '-';
                          final peakUsed =
                              (log.peakMeterValue ?? 0) - start.$1;
                          return peakUsed.toStringAsFixed(0);
                        case 2:
                          if (start == null) return '-';
                          final offPeakUsed =
                              (log.offPeakMeterValue ?? 0) - start.$2;
                          return offPeakUsed.toStringAsFixed(0);
                        case 3:
                          return log.usedFromStart.toStringAsFixed(0);
                        default:
                          return formatter.format(log.cost);
                      }
                    }
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
  DateTime? _billingCycleKey;

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

    // ตั้งค่าคีย์ระบุกลุ่มของรอบปัจจุบันที่ผ่าน Logic ปัดรอบบิลเรียบร้อยแล้ว
    if (now.day >= _billingDay) {
      _billingCycleKey =
          DateTime(_cycleStart!.year, _cycleStart!.month + 1, _billingDay);
    } else {
      _billingCycleKey =
          DateTime(_cycleStart!.year, _cycleStart!.month, _billingDay);
    }

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
              final isCurrent = group.key == _billingCycleKey;
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
                      subtitle:
                          'มิเตอร์ ${log.meterValue.toStringAsFixed(0)} · '
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