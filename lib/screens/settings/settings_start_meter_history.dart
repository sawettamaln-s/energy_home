part of 'settings_screen.dart';

// ประวัติเลขมิเตอร์ต้นรอบ — คำอธิบายภาพรวมอยู่ที่ AppBar ของหน้านี้แล้ว
Future<void> openStartMeterSetup(
  BuildContext context,
  String uid,
  FirestoreService firestoreService,
  bool isTou,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => _StartMeterHistoryScreen(
        uid: uid,
        firestoreService: firestoreService,
        isTou: isTou,
      ),
    ),
  );
}

void _showStartMeterInfoPopup(BuildContext context) {
  showInfoDialog(
    context,
    title: 'หน้านี้ใช้ทำอะไร?',
    message: 'เลขมิเตอร์ต้นรอบคือเลขที่มิเตอร์อ่านได้ตอนเริ่มรอบบิลใหม่ '
        'ระบบใช้เลขนี้เป็นจุดตั้งต้นเพื่อคำนวณว่าคุณใช้ไฟ/น้ำไปกี่หน่วย '
        'เมื่อเทียบกับเลขที่บันทึกในแอปครั้งถัดไป\n\n'
        'กดปุ่ม + เพื่อบันทึกค่าของรอบบิลใหม่ทุกครั้งที่ใบแจ้งหนี้มาถึง '
        'ส่วนรายการในหน้านี้คือประวัติค่าที่เคยตั้งไว้ในแต่ละรอบ '
        'ไว้ย้อนดูทีหลังได้ว่าเดือนไหนตั้งค่าไว้เท่าไหร่',
  );
}

class _StartMeterHistoryScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final bool isTou; // true = มิเตอร์ TOU ต้องโชว์ peak/off-peak ด้วย

  const _StartMeterHistoryScreen({
    required this.uid,
    required this.firestoreService,
    this.isTou = false,
  });

  @override
  State<_StartMeterHistoryScreen> createState() =>
      _StartMeterHistoryScreenState();
}

class _StartMeterHistoryScreenState extends State<_StartMeterHistoryScreen> {
  List<StartMeterRecordModel> _records = [];
  // ค่าไฟ/ค่าน้ำของแต่ละรอบ ดึงจาก BillModel (source: startMeter) แยกเก็บจาก StartMeterRecordModel จับคู่กันด้วยเดือน/ปี
  List<BillModel> _bills = [];
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final user = await widget.firestoreService.getUser(widget.uid);
    final records = await widget.firestoreService.getStartMeterHistory(widget.uid);
    final bills = await widget.firestoreService.getBills(widget.uid);
    if (mounted) {
      setState(() {
        _user = user;
        _records = records;
        _bills = bills;
        _isLoading = false;
      });
    }
  }

  // เช็คว่าตั้งค่าของรอบปัจจุบันครบแล้วไหม ใช้ตัวเดียวกับ _AddStartMeterSheetState
  // (ผ่าน EnergyForecaster.matchesCurrentCycle) — ใช้ซ่อนปุ่ม (+) เมื่อครบแล้ว
  bool get _currentCycleConfigured {
    final user = _user;
    if (user == null) return false;
    return user.startMeterConfigured &&
        EnergyForecaster.matchesCurrentCycle(
          billingMonth: user.startBillingMonth,
          billingYear: user.startBillingYear,
          billingDay: user.billingDay,
        );
  }

  BillModel? _billFor(int month, int year) {
    for (final b in _bills) {
      if (b.month == month && b.year == year) return b;
    }
    return null;
  }

  // เปิด bottom sheet บันทึกเลขมิเตอร์ต้นรอบ ผ่านปุ่ม FAB
  Future<void> _openSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddStartMeterSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        isTou: widget.isTou,
      ),
    );
    if (saved == true) _load();
  }

  // ลบ record หนึ่งแถว — record เก็บทั้งไฟและน้ำของเดือนนั้นรวมกัน (บิลคู่กันก็เก็บ cost รวมทั้งสอง)
  // เช็คก่อนว่าอีกยูทิลิตี้ของรอบนี้ยังมีข้อมูลอยู่ไหม: ถ้ามีให้เซฟทับด้วย field ของฝั่งที่ลบเป็น 0 (ไม่ลบทั้งแถว)
  // ถ้าไม่มี (อีกฝั่งว่างอยู่ก่อนแล้ว) ลบทั้ง record/bill ได้เลย
  // startMeterConfigured (flag รวม) จะเป็น false ก็ต่อเมื่อไม่มียูทิลิตี้ไหนตั้งค่าไว้เหลือแล้วเท่านั้น
  Future<void> _confirmDelete(
    StartMeterRecordModel record, {
    required bool isCurrentCycleRow,
    required bool isElectricity,
  }) async {
    final utilityLabel = isElectricity ? 'ไฟฟ้า' : 'น้ำ';
    final otherUtilityHasData = isElectricity
        ? record.waterValue > 0
        : (widget.isTou
            ? (record.peakValue > 0 || record.offPeakValue > 0)
            : record.electricityValue > 0);

    final confirmed = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล$utilityLabelรายการนี้?',
      content: isCurrentCycleRow
          ? 'ลบแล้วเลขมิเตอร์ต้นรอบ$utilityLabelของรอบปัจจุบันจะถูกรีเซ็ต '
              'ต้องตั้งค่าใหม่ก่อนถึงจะบันทึกมิเตอร์รายวันต่อได้ และบิลที่'
              'สร้างอัตโนมัติของรอบนี้ (ถ้ามี) จะถูกลบไปด้วย ต้องการดำเนินการ'
              'ต่อใช่ไหมคะ?'
          : 'ต้องการลบประวัติการตั้งเลขมิเตอร์ต้นรอบ$utilityLabelรายการนี้'
              'ใช่ไหมคะ (บิลที่สร้างอัตโนมัติของรอบนี้ ถ้ามี จะถูกลบไปด้วย)',
      borderRadius: 16,
    );
    if (confirmed != true) return;

    final pairedBill = _billFor(record.billingMonth, record.billingYear);

    if (otherUtilityHasData) {
      // อีกยูทิลิตี้ยังมีข้อมูลอยู่ — เก็บไว้ ล้างเฉพาะฝั่งที่กดลบ
      await widget.firestoreService.saveStartMeterRecord(
        StartMeterRecordModel(
          id: record.id,
          uid: record.uid,
          electricityValue: isElectricity ? 0 : record.electricityValue,
          waterValue: isElectricity ? record.waterValue : 0,
          peakValue: isElectricity ? 0 : record.peakValue,
          offPeakValue: isElectricity ? 0 : record.offPeakValue,
          billingMonth: record.billingMonth,
          billingYear: record.billingYear,
          recordedAt: record.recordedAt,
        ),
      );
      if (pairedBill != null && pairedBill.source == 'startMeter') {
        final remainingCost =
            isElectricity ? pairedBill.waterCost : pairedBill.electricityCost;
        await widget.firestoreService.saveBill(
          BillModel(
            id: pairedBill.id,
            uid: pairedBill.uid,
            year: pairedBill.year,
            month: pairedBill.month,
            electricityCost: isElectricity ? 0 : pairedBill.electricityCost,
            waterCost: isElectricity ? pairedBill.waterCost : 0,
            totalCost: remainingCost,
            electricityUsed: isElectricity ? 0 : pairedBill.electricityUsed,
            electricityPeakUsed:
                isElectricity ? 0 : pairedBill.electricityPeakUsed,
            electricityOffPeakUsed:
                isElectricity ? 0 : pairedBill.electricityOffPeakUsed,
            waterUsed: isElectricity ? pairedBill.waterUsed : 0,
            fixedCost: pairedBill.fixedCost,
            source: pairedBill.source,
          ),
        );
      }
    } else {
      // อีกยูทิลิตี้ไม่มีข้อมูลอยู่แล้ว — ลบทั้งแถว/บิลได้เลย
      await widget.firestoreService.deleteStartMeterRecord(widget.uid, record.id);
      if (pairedBill != null && pairedBill.source == 'startMeter') {
        await widget.firestoreService.deleteBill(widget.uid, pairedBill.id);
      }
    }

    if (isCurrentCycleRow) {
      final updates = <String, dynamic>{};
      if (isElectricity) {
        updates['startElectricityValue'] = 0;
        updates['startPeakValue'] = 0;
        updates['startOffPeakValue'] = 0;
        updates['electricityStartConfigured'] = false;
      } else {
        updates['startWaterValue'] = 0;
        updates['waterStartConfigured'] = false;
      }
      final otherStillConfigured = isElectricity
          ? (_user?.waterStartConfigured ?? false)
          : (_user?.electricityStartConfigured ?? false);
      if (!otherStillConfigured) {
        updates['startMeterConfigured'] = false;
        updates['startBillingMonth'] = 0;
        updates['startBillingYear'] = 0;
      }
      await widget.firestoreService.updateUser(widget.uid, updates);
    }

    _load();
  }

  // ---- ตัวกรอง/เรียงของรายการย้อนหลัง (UI state ล้วนๆ) ----
  bool _showWater = false; // false = ไฟฟ้า, true = น้ำ
  bool _newestFirst = true;
  // ปี (ค.ศ.) ที่กางอยู่ — null = ยังไม่เคยแตะ ใช้ค่าเริ่มต้นคือกางเฉพาะปีล่าสุด
  Set<int>? _expandedYears;

  // แถวนี้คือ record ที่ค่า start ใน user document อ้างอิงอยู่ไหม — เช็คด้วย
  // billingMonth/Year ของ record เทียบกับ user.startBillingMonth/Year ตรงๆ (ไม่ผูก
  // กับวันที่ตามปฏิทิน/billingDay) ถ้าเช็คกับ "รอบที่ควรจะเป็นตอนนี้" การรีเซ็ตค่า
  // ใน user document ตอนลบอาจถูกข้าม (เช่น billingDay เพิ่งเปลี่ยน) ทั้งที่ record
  // ถูกลบไปแล้ว เหลือ startMeterConfigured/startElectricityValue ค้างแบบไม่มี record
  bool _isCurrentCycleRow(StartMeterRecordModel r) =>
      _user != null && r.billingMonth == _user!.startBillingMonth && r.billingYear == _user!.startBillingYear;

  bool _hasElectricity(StartMeterRecordModel r) =>
      widget.isTou ? (r.peakValue > 0 || r.offPeakValue > 0) : r.electricityValue > 0;

  bool _hasData(StartMeterRecordModel r) => _showWater ? r.waterValue > 0 : _hasElectricity(r);

  double _reading(StartMeterRecordModel r) =>
      _showWater ? r.waterValue : (widget.isTou ? r.peakValue + r.offPeakValue : r.electricityValue);

  String get _unit => _showWater ? 'ลบ.ม.' : 'หน่วย';

  Color get _accent => _showWater ? AppColors.waterBorder : AppColors.electricityBorder;

  static int _monthKey(StartMeterRecordModel r) => r.billingYear * 12 + r.billingMonth;

  // หน่วยที่ใช้ของแต่ละ record ของยูทิลิตี้ที่กำลังดู = เลขรอบนี้ − เลขของรอบก่อนหน้า
  // ที่ใกล้ที่สุดซึ่งมีข้อมูล (คิดจากประวัติทั้งหมด ไม่ขึ้นกับตัวกรองปี) — null = ไม่มี
  // รอบก่อนให้เทียบ
  Map<String, double> _usedById() {
    final withData = _records.where(_hasData).toList()..sort((a, b) => _monthKey(a).compareTo(_monthKey(b)));
    final used = <String, double>{};
    for (var i = 1; i < withData.length; i++) {
      used[withData[i].id] = EnergyCalculator.calculateUsed(_reading(withData[i]), _reading(withData[i - 1]));
    }
    return used;
  }

  StartMeterRecordModel? get _currentRecord {
    for (final r in _records) {
      if (_isCurrentCycleRow(r)) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'เลขมิเตอร์จากใบแจ้งหนี้',
        actions: [
          IconButton(
            tooltip: 'หน้านี้ใช้ทำอะไร',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showStartMeterInfoPopup(context),
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
    );
  }

  Widget _buildBody() {
    final fmt = NumberFormat('#,##0.##');
    final used = _usedById();
    final sorted = [..._records]
      ..sort((a, b) => _newestFirst ? _monthKey(b).compareTo(_monthKey(a)) : _monthKey(a).compareTo(_monthKey(b)));
    // แถบปริมาณเทียบกับรอบที่ใช้มากที่สุดในประวัติทั้งหมด ทุกปีใช้สเกลเดียวกัน เทียบข้ามปีได้
    final maxUsed = sorted.map((r) => used[r.id] ?? 0).fold<double>(0, (a, b) => a > b ? a : b);

    // แบ่งเป็นกลุ่มตามปี (เรียงตามทิศทางที่เลือก) — กางเฉพาะปีที่เลือกไว้
    final groups = <int, List<StartMeterRecordModel>>{};
    for (final r in sorted) {
      groups.putIfAbsent(r.billingYear, () => []).add(r);
    }
    final expanded = _expandedYears ??
        {if (_records.isNotEmpty) _records.map((r) => r.billingYear).reduce((a, b) => a > b ? a : b)};

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
      children: [
        FadeSlideIn(child: _buildCurrentCycleCard(fmt)),
        const SizedBox(height: AppSpacing.v24),
        Row(
          children: [
            const Expanded(child: Text('ประวัติย้อนหลัง', style: DashboardStyles.sectionTitle)),
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
        _utilityToggle(),
        const SizedBox(height: AppSpacing.v12),
        if (_records.isEmpty)
          _buildEmptyState()
        else
          for (final entry in groups.entries) ...[
            _yearHeader(entry.key, entry.value, used, fmt, expanded: expanded.contains(entry.key), onTap: () {
              setState(() {
                final next = {...expanded};
                if (!next.remove(entry.key)) next.add(entry.key);
                _expandedYears = next;
              });
            }),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !expanded.contains(entry.key)
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.v4, bottom: AppSpacing.v8),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            _tableHeader(),
                            for (final r in entry.value) ...[
                              const Divider(),
                              _tableRow(r, used[r.id], maxUsed, fmt),
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

  // การ์ดบนสุด: เลขต้นรอบของรอบปัจจุบัน (สิ่งที่ผู้ใช้เข้ามาเช็คบ่อยที่สุด) พร้อมปุ่ม
  // แก้ไข/จัดการ ยังไม่ได้กรอก = ชวนกรอกพร้อมบอกเดือนของใบแจ้งหนี้ที่ต้องใช้
  Widget _buildCurrentCycleCard(NumberFormat fmt) {
    final current = _currentRecord;
    if (current == null || !_currentCycleConfigured) {
      final expected = _expectedInvoiceMonth(_user?.billingDay ?? 30);
      return AppCard(
        borderColor: AppColors.primaryGreen.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(icon: Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 40),
                const SizedBox(width: AppSpacing.v12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ยังไม่ได้กรอกเลขของรอบนี้',
                          style: TextStyle(
                              fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      Text('ใช้เลขจากใบแจ้งหนี้เดือน ${_monthYearLabel(expected.month, expected.year)}',
                          style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.v14),
            ElevatedButton.icon(
              onPressed: _openSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('กรอกเลขรอบนี้'),
            ),
          ],
        ),
      );
    }

    String eText;
    if (!_hasElectricity(current)) {
      eText = 'ไม่ได้กรอก';
    } else if (widget.isTou) {
      eText = 'On ${fmt.format(current.peakValue)} · Off ${fmt.format(current.offPeakValue)}';
    } else {
      eText = fmt.format(current.electricityValue);
    }
    return AppCard(
      onTap: () => _showRecordActions(current),
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('รอบปัจจุบัน', style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                    Text(_monthYearLabel(current.billingMonth, current.billingYear),
                        style: const TextStyle(
                            fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showRecordActions(current),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('จัดการ'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v12),
          Row(
            children: [
              Expanded(
                child: _currentValue(Icons.bolt_rounded, AppColors.electricityBorder, 'เลขมิเตอร์ไฟฟ้า', eText,
                    _hasElectricity(current)),
              ),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: _currentValue(
                    Icons.water_drop_rounded,
                    AppColors.waterBorder,
                    'เลขมิเตอร์น้ำ',
                    current.waterValue > 0 ? fmt.format(current.waterValue) : 'ไม่ได้กรอก',
                    current.waterValue > 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currentValue(IconData icon, Color color, String label, String value, bool filled) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.07) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: filled ? color : Colors.grey.shade400),
              const SizedBox(width: AppSpacing.v4),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: filled ? AppTypography.s16 : AppTypography.s13,
                    fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
                    color: filled ? AppColors.textDark : Colors.grey.shade500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }

  // ---- ตัวกรอง --------------------------------------------------------------

  Widget _utilityToggle() {
    Widget option(String label, IconData icon, bool water) {
      final selected = _showWater == water;
      final color = water ? AppColors.waterBorder : AppColors.electricityBorder;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showWater = water),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.v8),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm - 2),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? color : Colors.grey.shade500),
                const SizedBox(width: AppSpacing.v4),
                Text(label,
                    style: TextStyle(
                        fontSize: AppTypography.s13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? color : Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          option('ไฟฟ้า', Icons.bolt_rounded, false),
          option('น้ำ', Icons.water_drop_rounded, true),
        ],
      ),
    );
  }

  // ---- ตาราง ---------------------------------------------------------------

  // หัวกลุ่มปี (กดเพื่อพับ/กาง) + สรุปของปีนั้น: จำนวนรอบ ใช้รวม เฉลี่ยต่อรอบ
  Widget _yearHeader(
    int year,
    List<StartMeterRecordModel> rows,
    Map<String, double> used,
    NumberFormat fmt, {
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final usedValues = [for (final r in rows) if (used[r.id] != null) used[r.id]!];
    final total = usedValues.fold<double>(0, (a, b) => a + b);
    final summary = usedValues.isEmpty
        ? '${rows.length} รอบ'
        : '${rows.length} รอบ · ใช้รวม ${fmt.format(total)} $_unit';
    final average = usedValues.isEmpty
        ? null
        : 'เฉลี่ย ${NumberFormat('#,##0').format(total / usedValues.length)} $_unit/รอบ';
    return Material(
      color: expanded ? Colors.transparent : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v8, AppSpacing.v10, AppSpacing.v12, AppSpacing.v10),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade700),
              ),
              const SizedBox(width: AppSpacing.v4),
              Text('พ.ศ. ${year + 543}',
                  style: const TextStyle(
                      fontSize: AppTypography.s14_5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    if (average != null)
                      Text(average,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _monthColWidth = 64;
  static const double _usedColWidth = 104;

  Widget _tableHeader() {
    final style = TextStyle(fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, 36, AppSpacing.v10),
      child: Row(
        children: [
          SizedBox(width: _monthColWidth, child: Text('เดือน', style: style)),
          Expanded(child: Text('เลขมิเตอร์', style: style)),
          SizedBox(width: _usedColWidth, child: Text('ใช้ไป ($_unit)', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }

  Widget _tableRow(StartMeterRecordModel r, double? used, double maxUsed, NumberFormat fmt) {
    final has = _hasData(r);
    final isCurrent = _isCurrentCycleRow(r);
    final muted = TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade400);
    const number = TextStyle(
        fontSize: AppTypography.s14,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
        fontFeatures: [FontFeature.tabularFigures()]);

    Widget reading;
    if (!has) {
      reading = Text('ไม่ได้กรอก', style: muted);
    } else if (!_showWater && widget.isTou) {
      reading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On ${fmt.format(r.peakValue)}', style: number.copyWith(fontSize: AppTypography.s13)),
          Text('Off ${fmt.format(r.offPeakValue)}', style: number.copyWith(fontSize: AppTypography.s13)),
        ],
      );
    } else {
      reading = Text(fmt.format(_reading(r)), style: number);
    }

    return InkWell(
      onTap: () => _showRecordActions(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
        child: Row(
          children: [
            SizedBox(
              width: _monthColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(thaiMonthsShort[r.billingMonth - 1],
                      style: const TextStyle(
                          fontSize: AppTypography.s14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  if (isCurrent)
                    const Text('ปัจจุบัน',
                        style: TextStyle(
                            fontSize: AppTypography.s10_5, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                ],
              ),
            ),
            Expanded(child: reading),
            SizedBox(
              width: _usedColWidth,
              child: used == null
                  ? Text(has ? 'รอบแรก' : '–', textAlign: TextAlign.end, style: muted)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmt.format(used),
                            style: TextStyle(
                                fontSize: AppTypography.s14,
                                fontWeight: FontWeight.w700,
                                color: _accent,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(height: AppSpacing.v4),
                        // แถบปริมาณเทียบกับรอบที่ใช้มากที่สุดในรายการที่แสดง
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.v2),
                          child: SizedBox(
                            width: 72,
                            height: 4,
                            child: LinearProgressIndicator(
                              value: maxUsed > 0 ? used / maxUsed : 0,
                              backgroundColor: _accent.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation(_accent),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v24),
      child: Column(
        children: [
          Icon(Icons.history_rounded, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.v8),
          Text('ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // เมนูของรายการ: แก้ไข (เฉพาะรอบปัจจุบัน — รอบเก่าใช้คำนวณหน่วยของรอบถัดไปไป
  // แล้ว แก้แล้วตัวเลขจะไม่ตรง จึงลบได้อย่างเดียว) และลบข้อมูลทีละฝั่ง
  Future<void> _showRecordActions(StartMeterRecordModel r) async {
    final isCurrent = _isCurrentCycleRow(r);
    final hasE = _hasElectricity(r);
    final hasW = r.waterValue > 0;
    final dateLabel = '${r.recordedAt.day} ${thaiMonthsShort[r.recordedAt.month - 1]} '
        '${(r.recordedAt.year + 543) % 100}';

    Widget action(String label, IconData icon, Color color, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          onTap: onTap,
        );

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v10, bottom: AppSpacing.v8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v14, AppSpacing.v20, AppSpacing.v6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ต้นรอบ ${_monthYearLabel(r.billingMonth, r.billingYear)}',
                        style: const TextStyle(
                            fontSize: AppTypography.s16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Text('บันทึกเมื่อ $dateLabel',
                        style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (isCurrent)
                action('แก้ไขรายการนี้', Icons.edit_outlined, AppColors.textDark, () {
                  Navigator.pop(ctx);
                  _openSheet();
                }),
              if (hasE)
                action('ลบข้อมูลไฟฟ้า', Icons.delete_outline_rounded, Colors.red.shade700, () {
                  Navigator.pop(ctx);
                  _confirmDelete(r, isCurrentCycleRow: isCurrent, isElectricity: true);
                }),
              if (hasW)
                action('ลบข้อมูลน้ำ', Icons.delete_outline_rounded, Colors.red.shade700, () {
                  Navigator.pop(ctx);
                  _confirmDelete(r, isCurrentCycleRow: isCurrent, isElectricity: false);
                }),
              if (!isCurrent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v4, AppSpacing.v20, AppSpacing.v4),
                  child: Text('รอบที่ผ่านมาแล้วแก้ไขไม่ได้ เพราะใช้คำนวณหน่วยของรอบถัดไปไปแล้วค่ะ',
                      style: TextStyle(fontSize: AppTypography.s11_5, height: 1.4, color: Colors.grey.shade600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// แถบจับด้านบนของแผ่นด้านล่าง (ใช้ในหน้าตั้งค่าทุกหน้า)
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(AppSpacing.v2),
        ),
      ),
    );
  }
}

// ชื่อเดือนเต็ม + ปี พ.ศ. เช่น "สิงหาคม 2569" — ใช้กับเดือนของใบแจ้งหนี้ในหน้าตั้งค่า
String _monthYearLabel(int month, int year) => '${thaiMonths[month - 1]} ${year + 543}';
