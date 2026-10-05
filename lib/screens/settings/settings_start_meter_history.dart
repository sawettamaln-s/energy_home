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

  // แถวนี้คือ record ที่ค่า start ใน user document อ้างอิงอยู่ไหม — เช็คด้วย
  // billingMonth/Year ของ record เทียบกับ user.startBillingMonth/Year ตรงๆ (ไม่ผูก
  // กับวันที่ตามปฏิทิน/billingDay) ถ้าเช็คกับ "รอบที่ควรจะเป็นตอนนี้" การรีเซ็ตค่า
  // ใน user document ตอนลบอาจถูกข้าม (เช่น billingDay เพิ่งเปลี่ยน) ทั้งที่ record
  // ถูกลบไปแล้ว เหลือ startMeterConfigured/startElectricityValue ค้างแบบไม่มี record
  bool _isCurrentCycleRow(StartMeterRecordModel r) =>
      _user != null && r.billingMonth == _user!.startBillingMonth && r.billingYear == _user!.startBillingYear;

  bool _hasElectricity(StartMeterRecordModel r) =>
      widget.isTou ? (r.peakValue > 0 || r.offPeakValue > 0) : r.electricityValue > 0;

  double _electricityTotal(StartMeterRecordModel r) =>
      widget.isTou ? r.peakValue + r.offPeakValue : r.electricityValue;

  // record ก่อนหน้า (เก่ากว่า) ที่ใกล้ที่สุดซึ่งมีข้อมูลของยูทิลิตี้นั้น — ใช้บอกหน่วย
  // ที่ใช้ระหว่างสองรอบ (_records เรียงใหม่ → เก่า)
  StartMeterRecordModel? _previousWith(int index, bool Function(StartMeterRecordModel) hasData) {
    for (var i = index + 1; i < _records.length; i++) {
      if (hasData(_records[i])) return _records[i];
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, 96),
                  children: [
                    Text(
                      'เลขที่มิเตอร์อ่านได้ตอนเริ่มแต่ละรอบบิล ใช้เป็นจุดตั้งต้นคำนวณหน่วยที่ใช้ค่ะ',
                      style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: AppSpacing.v12),
                    for (final (i, r) in _records.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.v10),
                      FadeSlideIn(
                        delay: Duration(milliseconds: 40 * (i < 6 ? i : 6)),
                        child: _buildRecordCard(r, i),
                      ),
                    ],
                  ],
                ),
      floatingActionButton: (_isLoading || _currentCycleConfigured)
          ? null
          : FloatingActionButton.extended(
              onPressed: _openSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('กรอกเลขรอบใหม่',
                  style: TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w600)),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.v32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(icon: Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 64),
            const SizedBox(height: AppSpacing.v16),
            const Text('ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.s15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: AppSpacing.v6),
            Text('กรอกเลขมิเตอร์จากใบแจ้งหนี้ล่าสุด เพื่อเริ่มคำนวณค่าไฟและค่าน้ำของรอบนี้ค่ะ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // การ์ด 1 รอบบิล: เดือนของใบแจ้งหนี้ + เลขมิเตอร์ไฟฟ้า/น้ำ พร้อมหน่วยที่ใช้เทียบ
  // รอบก่อน — กดเพื่อแก้ไข (เฉพาะรอบปัจจุบัน) หรือลบข้อมูลทีละฝั่ง
  Widget _buildRecordCard(StartMeterRecordModel r, int index) {
    final isCurrent = _isCurrentCycleRow(r);
    final prevE = _previousWith(index, _hasElectricity);
    final prevW = _previousWith(index, (x) => x.waterValue > 0);
    final fmt = NumberFormat('#,##0.##');

    String? electricityValue;
    if (_hasElectricity(r)) {
      electricityValue = widget.isTou
          ? 'On ${fmt.format(r.peakValue)} · Off ${fmt.format(r.offPeakValue)}'
          : fmt.format(r.electricityValue);
    }
    return AppCard(
      onTap: () => _showRecordActions(r),
      borderColor: isCurrent ? AppColors.primaryGreen.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v14, AppSpacing.v16, AppSpacing.v12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(_monthYearLabel(r.billingMonth, r.billingYear),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              ),
              if (isCurrent) ...[
                const SizedBox(width: AppSpacing.v8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8, vertical: AppSpacing.v2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.v20),
                  ),
                  child: const Text('รอบปัจจุบัน',
                      style: TextStyle(
                          fontSize: AppTypography.s11, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                ),
              ],
              const Spacer(),
              Icon(Icons.more_horiz_rounded, size: 20, color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: AppSpacing.v10),
          _utilityLine(
            icon: Icons.bolt_rounded,
            color: AppColors.electricityBorder,
            label: 'ไฟฟ้า',
            value: electricityValue,
            unit: 'หน่วย',
            used: electricityValue != null && prevE != null
                ? EnergyCalculator.calculateUsed(_electricityTotal(r), _electricityTotal(prevE))
                : null,
          ),
          const SizedBox(height: AppSpacing.v8),
          _utilityLine(
            icon: Icons.water_drop_rounded,
            color: AppColors.waterBorder,
            label: 'น้ำ',
            value: r.waterValue > 0 ? fmt.format(r.waterValue) : null,
            unit: 'ลบ.ม.',
            used: r.waterValue > 0 && prevW != null
                ? EnergyCalculator.calculateUsed(r.waterValue, prevW.waterValue)
                : null,
          ),
        ],
      ),
    );
  }

  // แถวเลขมิเตอร์ของยูทิลิตี้หนึ่ง — [value] null = รอบนี้ไม่ได้กรอกฝั่งนี้, [used] =
  // หน่วยที่ใช้นับจากรอบก่อนหน้า (null = ไม่มีรอบก่อนให้เทียบ)
  Widget _utilityLine({
    required IconData icon,
    required Color color,
    required String label,
    required String? value,
    required String unit,
    required double? used,
  }) {
    final fmt = NumberFormat('#,##0.##');
    return Row(
      children: [
        IconBadge(icon: icon, color: color, size: 30),
        const SizedBox(width: AppSpacing.v10),
        SizedBox(
          width: 44,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value ?? 'ยังไม่ได้กรอก',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: value == null ? AppTypography.s12_5 : AppTypography.s14,
              fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
              color: value == null ? Colors.grey.shade500 : AppColors.textDark,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (used != null) ...[
          const SizedBox(width: AppSpacing.v8),
          Flexible(
            child: Text('ใช้ ${fmt.format(used)} $unit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ],
    );
  }

  // เมนูของการ์ด: แก้ไข (เฉพาะรอบปัจจุบัน — รอบเก่าคำนวณหน่วยต่อเนื่องกันไปแล้ว
  // แก้แล้วตัวเลขรอบถัดไปจะไม่ตรง จึงลบได้อย่างเดียว) และลบข้อมูลทีละฝั่ง
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
