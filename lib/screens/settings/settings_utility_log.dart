part of 'settings_screen.dart';

// เปิดหน้าประวัติการบันทึกมิเตอร์จากนอกหน้าตั้งค่า (เช่น หน้าบันทึกมิเตอร์
// ตอนเลขที่กรอกต่ำกว่าครั้งล่าสุด) — initialTab 0 = ไฟฟ้า, 1 = ประปา
Future<void> openUtilityHistory(
  BuildContext context,
  String uid,
  FirestoreService firestoreService, {
  int initialTab = 0,
}) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => _UtilityHistoryScreen(
        uid: uid,
        firestoreService: firestoreService,
        initialTab: initialTab,
      ),
    ),
  );
}

// ==================== ประวัติการบันทึกมิเตอร์: ไฟฟ้า / ประปา ====================
class _UtilityHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final int initialTab; // 0 = ไฟฟ้า, 1 = ประปา

  const _UtilityHistoryScreen({
    required this.uid,
    required this.firestoreService,
    this.initialTab = 0,
  });

  @override
  State<_UtilityHistoryScreen> createState() => _UtilityHistoryScreenState();
}

class _UtilityHistoryScreenState extends State<_UtilityHistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

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
            Tab(text: 'ไฟฟ้า'),
            Tab(text: 'ประปา'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LogHistoryTab(uid: widget.uid, firestoreService: widget.firestoreService, isWater: false),
          _LogHistoryTab(uid: widget.uid, firestoreService: widget.firestoreService, isWater: true),
        ],
      ),
    );
  }
}

// รายการบันทึก 1 ครั้ง ในรูปกลางที่ใช้ได้ทั้งไฟฟ้าและน้ำ (ElectricityLogModel/
// WaterLogModel มีฟิลด์คนละชุด) — usedFromStart/cost เป็นยอดสะสมตั้งแต่ต้นรอบ
class _LogEntry {
  final String id;
  final String uid;
  final DateTime date;
  final double reading; // เลขมิเตอร์ที่จด (ไฟปกติ/น้ำ)
  final double? peakReading; // TOU: เลขที่จดจริงของ On-Peak/Off-Peak
  final double? offPeakReading;
  final double usedFromLast;
  final double usedFromStart;
  final double cost;

  const _LogEntry({
    required this.id,
    required this.uid,
    required this.date,
    required this.reading,
    this.peakReading,
    this.offPeakReading,
    required this.usedFromLast,
    required this.usedFromStart,
    required this.cost,
  });
}

// รอบบิล 1 รอบ: เดือนของใบแจ้งหนี้ (key) + ช่วงวันของรอบ + รายการในรอบนั้น
class _LogCycle {
  final DateTime billMonth;
  final DateTime start;
  final DateTime end; // วันตัดรอบถัดไป (ไม่รวมวันนี้)
  final List<_LogEntry> entries; // เรียงใหม่ → เก่า

  _LogCycle(this.billMonth, this.start, this.end, this.entries);

  // ยอดของรอบ = ค่าของรายการล่าสุด (usedFromStart/cost สะสมตั้งแต่ต้นรอบ ห้ามบวกกัน)
  _LogEntry get latest => entries.first;
}

// จัดกลุ่มรายการตามรอบบิล — ขอบเขตรอบมาจาก EnergyForecaster เท่านั้น เดือนของ
// ใบแจ้งหนี้ = เดือนของวันตัดรอบที่ปิดรอบนั้น (เดียวกับ year/month ของบิล)
List<_LogCycle> _groupByCycle(List<_LogEntry> entries, int billingDay) {
  final grouped = <DateTime, List<_LogEntry>>{};
  for (final e in entries) {
    final start = EnergyForecaster.getCycleStart(e.date, billingDay);
    grouped.putIfAbsent(start, () => []).add(e);
  }
  final cycles = [
    for (final g in grouped.entries)
      () {
        final end = EnergyForecaster.getCycleEnd(g.key, billingDay);
        final list = g.value..sort((a, b) => b.date.compareTo(a.date));
        return _LogCycle(DateTime(end.year, end.month, 1), g.key, end, list);
      }(),
  ];
  cycles.sort((a, b) => b.start.compareTo(a.start));
  return cycles;
}

// ==================== แท็บประวัติ (ไฟฟ้า หรือ น้ำ) ====================
class _LogHistoryTab extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final bool isWater;

  const _LogHistoryTab({required this.uid, required this.firestoreService, required this.isWater});

  @override
  State<_LogHistoryTab> createState() => _LogHistoryTabState();
}

class _LogHistoryTabState extends State<_LogHistoryTab> {
  List<_LogEntry> _entries = [];
  bool _isLoading = true;
  int _billingDay = 30;
  bool _isTou = false;
  late DateTime _currentCycleStart;

  bool _newestFirst = true;
  // รอบที่กางอยู่ (key = วันเริ่มรอบ) — null = ยังไม่เคยแตะ ใช้ค่าเริ่มต้นคือกางรอบล่าสุด
  Set<DateTime>? _expanded;

  static final _fmt = NumberFormat('#,##0.##');
  static final _bahtFmt = NumberFormat('#,##0.00');

  Color get _accent => widget.isWater ? AppColors.waterBorder : AppColors.electricityBorder;
  String get _unit => widget.isWater ? 'ลบ.ม.' : 'หน่วย';
  String get _costLabel => widget.isWater ? 'ค่าน้ำ' : 'ค่าไฟ';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startDate = DateTime(now.year - 1, now.month, 1);
    final endDate = DateTime(now.year + 1, now.month, 1);
    final user = await widget.firestoreService.getUser(widget.uid);
    _billingDay = user?.billingDay ?? 30;
    _isTou = !widget.isWater && user?.meterType == 'tou';
    _currentCycleStart = EnergyForecaster.getCycleStart(now, _billingDay);

    if (widget.isWater) {
      final logs = await widget.firestoreService.getCurrentMonthWaterLogs(widget.uid, startDate, endDate);
      _entries = [
        for (final l in logs)
          _LogEntry(
            id: l.id,
            uid: l.uid,
            date: l.date,
            reading: l.meterValue,
            usedFromLast: l.usedFromLast,
            usedFromStart: l.usedFromStart,
            cost: l.cost,
          ),
      ];
    } else {
      final logs = await widget.firestoreService.getCurrentMonthElectricityLogs(widget.uid, startDate, endDate);
      _entries = [
        for (final l in logs)
          _LogEntry(
            id: l.id,
            uid: l.uid,
            date: l.date,
            reading: l.meterValue,
            peakReading: l.peakMeterValue,
            offPeakReading: l.offPeakMeterValue,
            usedFromLast: l.usedFromLast,
            usedFromStart: l.usedFromStart,
            cost: l.cost,
          ),
      ];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ลบได้เฉพาะรายการในรอบปัจจุบัน — รอบที่ปิดแล้วถูกใช้คำนวณบิลไปแล้ว
  bool _isEditable(_LogEntry e) => !e.date.isBefore(_currentCycleStart);

  Future<void> _confirmDelete(_LogEntry e) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล',
      content: 'ต้องการลบข้อมูลนี้ใช่ไหมคะ?',
    );
    if (confirm != true) return;
    if (widget.isWater) {
      await widget.firestoreService.deleteWaterLog(e.uid, e.id);
    } else {
      await widget.firestoreService.deleteElectricityLog(e.uid, e.id);
    }
    await _load();
  }

  String _shortDate(DateTime d) => '${d.day} ${thaiMonthsShort[d.month - 1]}';

  String _range(_LogCycle c) {
    final last = c.end.subtract(const Duration(days: 1));
    return '${_shortDate(c.start)} – ${_shortDate(last)} ${(last.year + 543) % 100}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final cycles = _groupByCycle(_entries, _billingDay);
    final current = cycles.where((c) => c.start == _currentCycleStart).firstOrNull;
    final ordered = _newestFirst ? cycles : cycles.reversed.toList();
    final expanded = _expanded ?? {if (cycles.isNotEmpty) cycles.first.start};

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
      children: [
        FadeSlideIn(child: _buildCurrentCard(current)),
        const SizedBox(height: AppSpacing.v24),
        Row(
          children: [
            const Expanded(child: Text('ประวัติตามรอบบิล', style: DashboardStyles.sectionTitle)),
            if (cycles.length > 1)
              TextButton.icon(
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
                ),
                icon: Icon(_newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 16),
                label: Text(_newestFirst ? 'ใหม่ → เก่า' : 'เก่า → ใหม่'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.v8),
        if (cycles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.v24),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: AppSpacing.v8),
                Text('ยังไม่มีประวัติการบันทึก',
                    style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600)),
              ],
            ),
          )
        else
          for (final c in ordered) ...[
            _cycleHeader(c, isOpen: expanded.contains(c.start), onTap: () {
              setState(() {
                final next = {...expanded};
                if (!next.remove(c.start)) next.add(c.start);
                _expanded = next;
              });
            }),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !expanded.contains(c.start)
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.v4, bottom: AppSpacing.v8),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        // รอบที่ปิดไปแล้วใช้พื้นจาง ให้รอบปัจจุบันเด่นกว่า
                        color: c.start == _currentCycleStart ? Colors.white : AppColors.closedSurface,
                        borderColor: c.start == _currentCycleStart ? null : AppColors.closedBorder,
                        child: Column(
                          children: [
                            _tableHeader(),
                            for (final e in c.entries) ...[
                              const Divider(),
                              _tableRow(e),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.v6),
          ],
      ],
    );
  }

  // ---- รอบปัจจุบัน ----------------------------------------------------------

  Widget _buildCurrentCard(_LogCycle? current) {
    final end = EnergyForecaster.getCycleEnd(_currentCycleStart, _billingDay);
    final billMonth = DateTime(end.year, end.month, 1);
    final rangeText = _range(_LogCycle(billMonth, _currentCycleStart, end, const []));
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                icon: widget.isWater ? Icons.water_drop_rounded : Icons.bolt_rounded,
                color: _accent,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('รอบปัจจุบัน · บิล ${_monthYearLabel(billMonth.month, billMonth.year)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Text(rangeText, style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v14),
          if (current == null)
            Text('รอบนี้ยังไม่ได้บันทึกมิเตอร์ค่ะ',
                style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600))
          else
            Row(
              children: [
                Expanded(child: _stat('ใช้ไปแล้ว', '${_fmt.format(current.latest.usedFromStart)} $_unit')),
                Expanded(child: _stat('$_costLabelสะสม', '${_bahtFmt.format(current.latest.cost)} บาท')),
                Expanded(child: _stat('บันทึกแล้ว', '${current.entries.length} ครั้ง')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
        const SizedBox(height: AppSpacing.v2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: const TextStyle(
                  fontSize: AppTypography.s15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ],
    );
  }

  // ---- หัวรอบ (กดเพื่อพับ/กาง) ---------------------------------------------

  Widget _cycleHeader(_LogCycle c, {required bool isOpen, required VoidCallback onTap}) {
    final isCurrent = c.start == _currentCycleStart;
    return Material(
      color: isOpen ? Colors.transparent : (isCurrent ? Colors.white : AppColors.closedSurface),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v8, AppSpacing.v10, AppSpacing.v12, AppSpacing.v10),
          child: Row(
            children: [
              AnimatedRotation(
                turns: isOpen ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade700),
              ),
              const SizedBox(width: AppSpacing.v4),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('บิล ${_monthYearLabel(c.billMonth.month, c.billMonth.year)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppTypography.s14_5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: AppSpacing.v2),
                    Row(
                      children: [
                        // จุดเขียว = รอบปัจจุบัน, แม่กุญแจ = ปิดรอบแล้ว (รายการในรอบลบไม่ได้)
                        if (isCurrent)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.primaryGreen, shape: BoxShape.circle),
                          )
                        else
                          Icon(Icons.lock_outline_rounded, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: AppSpacing.v6),
                        Flexible(
                          child: Text(_range(c),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.v8),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_fmt.format(c.latest.usedFromStart)} $_unit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppTypography.s13,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      Text('${c.entries.length} ครั้ง · ${NumberFormat('#,##0').format(c.latest.cost)} บาท',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- ตาราง ---------------------------------------------------------------

  static const double _dateColWidth = 64;
  static const double _usedColWidth = 112;

  Widget _tableHeader() {
    final style = TextStyle(fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, 36, AppSpacing.v10),
      child: Row(
        children: [
          SizedBox(width: _dateColWidth, child: Text('วันที่', style: style)),
          Expanded(child: Text('เลขที่จด', style: style)),
          SizedBox(width: _usedColWidth, child: Text('ใช้เพิ่ม / สะสม', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }

  Widget _tableRow(_LogEntry e) {
    final editable = _isEditable(e);
    const number = TextStyle(
        fontSize: AppTypography.s14,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
        fontFeatures: [FontFeature.tabularFigures()]);
    final reading = _isTou
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On ${_fmt.format(e.peakReading ?? 0)}', style: number.copyWith(fontSize: AppTypography.s13)),
              Text('Off ${_fmt.format(e.offPeakReading ?? 0)}', style: number.copyWith(fontSize: AppTypography.s13)),
            ],
          )
        : Text(_fmt.format(e.reading), style: number);
    final hh = e.date.hour.toString().padLeft(2, '0');
    final mm = e.date.minute.toString().padLeft(2, '0');

    return InkWell(
      onTap: () => showTableRowActions(
        context,
        title: '${_shortDate(e.date)} ${(e.date.year + 543) % 100}',
        subtitle: 'บันทึกเมื่อ $hh:$mm น.',
        locked: !editable,
        onDelete: () => _confirmDelete(e),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
        child: Row(
          children: [
            SizedBox(
              width: _dateColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_shortDate(e.date),
                      style: const TextStyle(
                          fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  Text('$hh:$mm น.', style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Expanded(child: reading),
            SizedBox(
              width: _usedColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+${_fmt.format(e.usedFromLast)} $_unit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTypography.s13_5,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  // ย่อตัวอักษรแทนการตัดท้าย ยอดเงินหลักพันจะได้ไม่ขึ้นเป็น "฿1,000.…"
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('สะสม ${_fmt.format(e.usedFromStart)} · ฿${_bahtFmt.format(e.cost)}',
                        maxLines: 1,
                        style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 28,
              child: Icon(
                editable ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
                size: editable ? 20 : 15,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
