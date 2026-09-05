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
  static const _green = DashboardStyles.primaryGreen;
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
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'ประวัติการบันทึกมิเตอร์',
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
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

// แถวสถิติด้านบนของแต่ละแท็บ — การ์ด 2 ช่อง "รอบปัจจุบัน" กับ "รวมทั้งหมดที่มี"
// แทนแถบสรุปยาวๆ แบบเดิม อ่านค่าได้เร็วกว่าแบบ dashboard
Widget _historyStatCards({
  required Color accent,
  required double currentCycleCost,
  required double allTimeCost,
  required NumberFormat formatter,
}) {
  Widget statCard({
    required IconData icon,
    required String label,
    required double value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 1),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: formatter.format(value),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  TextSpan(
                    text: ' บาท',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    child: Row(
      children: [
        statCard(
          icon: Icons.schedule,
          label: 'รอบปัจจุบัน',
          value: currentCycleCost,
        ),
        const SizedBox(width: 10),
        statCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'รวมทั้งหมดที่มี',
          value: allTimeCost,
        ),
      ],
    ),
  );
}

// ตัวเลือกปี (พ.ศ.) + เดือน — แทนการเลื่อนหาการ์ดเดือนทีละใบ ปีค่าเริ่มต้น
// เป็นปีปัจจุบันเสมอ ส่วนเดือนจะกรองให้เหลือแค่เดือนที่มีข้อมูลจริงของปีนั้น
class _YearMonthPicker extends StatelessWidget {
  final Color accent;
  final List<int> years;
  final List<int> months;
  final int selectedYear;
  final int selectedMonth;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int> onMonthChanged;

  const _YearMonthPicker({
    required this.accent,
    required this.years,
    required this.months,
    required this.selectedYear,
    required this.selectedMonth,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  InputDecoration _decoration() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFAF9F4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFD8D5C8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFD8D5C8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5, left: 2),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('ปี (พ.ศ.)'),
                DropdownButtonFormField<int>(
                  key: ValueKey('year-$selectedYear'),
                  initialValue: selectedYear,
                  isDense: true,
                  dropdownColor: Colors.white,
                  icon: Icon(Icons.keyboard_arrow_down,
                      size: 18, color: Colors.grey.shade500),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  decoration: _decoration(),
                  items: [
                    for (final y in years)
                      DropdownMenuItem(value: y, child: Text('${y + 543}')),
                  ],
                  onChanged: (v) {
                    if (v != null) onYearChanged(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('เดือน'),
                DropdownButtonFormField<int>(
                  key: ValueKey('month-$selectedYear-$selectedMonth'),
                  initialValue: selectedMonth,
                  isDense: true,
                  dropdownColor: Colors.white,
                  icon: Icon(Icons.keyboard_arrow_down,
                      size: 18, color: Colors.grey.shade500),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  decoration: _decoration(),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(value: m, child: Text(thaiMonths[m - 1])),
                  ],
                  onChanged: (v) {
                    if (v != null) onMonthChanged(v);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  // ใช้ตัดสินว่าตารางควรโชว์คอลัมน์ On-Peak/Off-Peak แยกไหม (เดิมโชว์ได้แค่ตอนแตะแถวดู detail เฉยๆ)
  bool _isTou = false;
  // เลขมิเตอร์ต้นรอบ (peak/offpeak) ของแต่ละรอบบิล — อิงจาก log.peakMeterValue/
  // offPeakMeterValue ของประวัติจริงรอบนั้นๆ ไม่ใช้ user.startPeakValue ตัวเดียว
  // เพราะรอบเก่าที่ปิดไปแล้วมีต้นรอบคนละค่ากับรอบปัจจุบัน
  List<StartMeterRecordModel> _startHistory = [];
  // ค่ามิเตอร์ต้นรอบล่าสุดที่ user ตั้งไว้ — ใช้เป็น fallback เฉพาะรอบปัจจุบัน
  // ตอนยังไม่มี StartMeterRecordModel ของรอบนี้ (เช่น กรอก log ก่อนตั้งเลขต้นรอบ)
  // ไม่ให้ตารางโชว์ "-" ทั้งที่มีค่าตั้งต้นอยู่แล้ว — pattern เดียวกับ compileBill() (firestore_service.dart)
  double? _userStartPeak;
  double? _userStartOffPeak;

  // ปี/เดือนที่เลือกดูอยู่ในตัวเลือกปี-เดือน — null หมายถึงยังไม่ได้ตั้งค่า
  // เริ่มต้น จะถูกตั้งเป็นรอบปัจจุบันอัตโนมัติตอน build() ครั้งแรกที่มีข้อมูล
  int? _selYear;
  int? _selMonth;

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
      _userStartPeak = user?.startPeakValue;
      _userStartOffPeak = user?.startOffPeakValue;
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

  // หาเลขต้นรอบ (peak/offpeak) ของรอบบิลที่ cycleKey นี้ตรงกับ — ใช้ month/year
  // เดียวกับที่ StartMeterRecordModel เก็บไว้ คืน null ถ้าไม่เจอ record ของรอบนั้นเลย
  (double peak, double offPeak)? _startValuesFor(DateTime cycleKey) {
    final match = _startHistory.where((r) =>
        r.billingMonth == cycleKey.month && r.billingYear == cycleKey.year);
    if (match.isNotEmpty) {
      final r = match.first;
      if (r.peakValue > 0 || r.offPeakValue > 0) {
        return (r.peakValue, r.offPeakValue);
      }
    }
    // ไม่เจอ record ของรอบนี้เลย — ถ้าเป็นรอบปัจจุบัน fallback ไปใช้ค่าต้นรอบล่าสุด
    // ที่ user ตั้งไว้แทน (เกิดขึ้นได้ตอนกรอก log ก่อนตั้งเลขต้นรอบ) รอบเก่าไม่ fallback เพราะจะได้เลขต้นรอบผิดรอบ
    if (cycleKey == _billingCycleKey) {
      final peak = _userStartPeak;
      final offPeak = _userStartOffPeak;
      if (peak != null && offPeak != null && (peak > 0 || offPeak > 0)) {
        return (peak, offPeak);
      }
    }
    return null;
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
          child: CircularProgressIndicator(color: DashboardStyles.primaryGreen));
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
    final allTimeCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);
    final groups = _groupLogsByCycle<ElectricityLogModel>(
        _logs, (l) => l.date, _billingDay);

    // ตั้งค่าปี/เดือนเริ่มต้น = รอบปัจจุบันเสมอ ถ้ายังไม่เคยเลือก หรือค่าที่
    // เลือกไว้ไม่มีอยู่ในข้อมูลแล้ว (เช่นสลับแท็บ/โหลดข้อมูลใหม่)
    final years = groups.map((g) => g.key.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selYear == null || !years.contains(_selYear)) {
      _selYear = years.contains(_billingCycleKey!.year)
          ? _billingCycleKey!.year
          : years.first;
    }
    final monthsForYear = groups
        .where((g) => g.key.year == _selYear)
        .map((g) => g.key.month)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selMonth == null || !monthsForYear.contains(_selMonth)) {
      _selMonth = (_selYear == _billingCycleKey!.year &&
              monthsForYear.contains(_billingCycleKey!.month))
          ? _billingCycleKey!.month
          : monthsForYear.first;
    }

    final selectedGroup = groups
        .firstWhere((g) => g.key.year == _selYear && g.key.month == _selMonth);
    final selectedLogs = selectedGroup.value;
    final selectedCost = selectedLogs.fold<double>(0, (sum, l) => sum + l.cost);
    final isSelectedCurrent = selectedGroup.key == _billingCycleKey;
    final isMostRecentGroup = groups.first.key == selectedGroup.key;

    return Column(
      children: [
        _historyStatCards(
          accent: accent,
          currentCycleCost: currentCycleCost,
          allTimeCost: allTimeCost,
          formatter: formatter,
        ),
        _YearMonthPicker(
          accent: accent,
          years: years,
          months: monthsForYear,
          selectedYear: _selYear!,
          selectedMonth: _selMonth!,
          onYearChanged: (y) => setState(() {
            _selYear = y;
            _selMonth = null;
          }),
          onMonthChanged: (m) => setState(() => _selMonth = m),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _MonthGroupCard(
              monthLabel: _cycleMonthLabel(selectedGroup.key),
              isCurrent: isSelectedCurrent,
              count: selectedLogs.length,
              totalCost: selectedCost,
              accent: accent,
              formatter: formatter,
              initiallyExpanded: true,
              table: ExcelStyleTable(
                accent: accent,
                // TOU: เพิ่มคอลัมน์ On-Peak/Off-Peak "ที่ใช้ไป" เข้าตารางหลักเลย
                // (เดิมมีแต่เลขสะสม โชว์ตอนแตะแถวดู detail เท่านั้น)
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
                rowCount: selectedLogs.length,
                isLatest: (row) => isMostRecentGroup && row == 0,
                isLocked: (row) => !_isEditable(selectedLogs[row]),
                cellText: (row, col) {
                  final log = selectedLogs[row];
                  if (_isTou) {
                    final start = _startValuesFor(selectedGroup.key);
                    switch (col) {
                      case 0:
                        return DateFormat('dd/MM/yy').format(log.date);
                      case 1:
                        if (start == null) return '-';
                        final peakUsed = (log.peakMeterValue ?? 0) - start.$1;
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
                  final log = selectedLogs[row];
                  showTableRowActions(
                    context,
                    title: DateFormat('dd/MM/yyyy').format(log.date),
                    subtitle:
                        'บันทึกเมื่อ ${DateFormat('dd/MM/yyyy, HH:mm').format(log.date)}',
                    locked: !_isEditable(log),
                    onDelete: () => _confirmDelete(log),
                  );
                },
              ),
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
  int _billingDay = 30;
  DateTime? _cycleStart;
  DateTime? _billingCycleKey;

  // ปี/เดือนที่เลือกดูอยู่ในตัวเลือกปี-เดือน — null หมายถึงยังไม่ได้ตั้งค่า
  int? _selYear;
  int? _selMonth;

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
          child: CircularProgressIndicator(color: DashboardStyles.primaryGreen));
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
    final allTimeCost = _logs.fold<double>(0, (sum, l) => sum + l.cost);
    final groups =
        _groupLogsByCycle<WaterLogModel>(_logs, (l) => l.date, _billingDay);

    final years = groups.map((g) => g.key.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selYear == null || !years.contains(_selYear)) {
      _selYear = years.contains(_billingCycleKey!.year)
          ? _billingCycleKey!.year
          : years.first;
    }
    final monthsForYear = groups
        .where((g) => g.key.year == _selYear)
        .map((g) => g.key.month)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selMonth == null || !monthsForYear.contains(_selMonth)) {
      _selMonth = (_selYear == _billingCycleKey!.year &&
              monthsForYear.contains(_billingCycleKey!.month))
          ? _billingCycleKey!.month
          : monthsForYear.first;
    }

    final selectedGroup = groups
        .firstWhere((g) => g.key.year == _selYear && g.key.month == _selMonth);
    final selectedLogs = selectedGroup.value;
    final selectedCost = selectedLogs.fold<double>(0, (sum, l) => sum + l.cost);
    final isSelectedCurrent = selectedGroup.key == _billingCycleKey;
    final isMostRecentGroup = groups.first.key == selectedGroup.key;

    return Column(
      children: [
        _historyStatCards(
          accent: accent,
          currentCycleCost: currentCycleCost,
          allTimeCost: allTimeCost,
          formatter: formatter,
        ),
        _YearMonthPicker(
          accent: accent,
          years: years,
          months: monthsForYear,
          selectedYear: _selYear!,
          selectedMonth: _selMonth!,
          onYearChanged: (y) => setState(() {
            _selYear = y;
            _selMonth = null;
          }),
          onMonthChanged: (m) => setState(() => _selMonth = m),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _MonthGroupCard(
              monthLabel: _cycleMonthLabel(selectedGroup.key),
              isCurrent: isSelectedCurrent,
              count: selectedLogs.length,
              totalCost: selectedCost,
              accent: accent,
              formatter: formatter,
              initiallyExpanded: true,
              table: ExcelStyleTable(
                accent: accent,
                columns: const [
                  ExcelTableColumn('วันที่', align: TextAlign.left, flex: 3),
                  ExcelTableColumn('หน่วยที่ใช้', flex: 2),
                  ExcelTableColumn('ค่าน้ำ', flex: 2),
                ],
                rowCount: selectedLogs.length,
                isLatest: (row) => isMostRecentGroup && row == 0,
                isLocked: (row) => !_isEditable(selectedLogs[row]),
                cellText: (row, col) {
                  final log = selectedLogs[row];
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
                  final log = selectedLogs[row];
                  showTableRowActions(
                    context,
                    title: DateFormat('dd/MM/yyyy').format(log.date),
                    subtitle:
                        'บันทึกเมื่อ ${DateFormat('dd/MM/yyyy, HH:mm').format(log.date)}',
                    locked: !_isEditable(log),
                    onDelete: () => _confirmDelete(log),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}