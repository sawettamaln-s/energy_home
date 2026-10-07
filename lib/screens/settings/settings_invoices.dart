part of 'settings_screen.dart';

// ==================== หน้าเลขมิเตอร์จากใบแจ้งหนี้ ====================
// รวมใบแจ้งหนี้ทุกใบไว้ที่เดียว:
// - การ์ดใบล่าสุด: เลขมิเตอร์จากใบแจ้งหนี้ใบล่าสุด = เลขมิเตอร์ต้นรอบของรอบปัจจุบัน
//   (บังคับ ใช้เริ่มคำนวณรอบบิล) กรอก/แก้ด้วย _AddStartMeterSheet
// - บิลย้อนหลัง: เพิ่มบิลเดือนเก่าด้วย _AddHistoricalBillSheet (ไม่บังคับ)
// - ตารางรายเดือน: หนึ่งแถว = ใบแจ้งหนี้หนึ่งเดือน รวมบิลทุกแหล่ง (startMeter,
//   imported, compiled) กับประวัติเลขมิเตอร์ต้นรอบ จับคู่ด้วยปี/เดือนเดียวกัน — บิล
//   เก็บเดือนของใบแจ้งหนี้ (เดือนปิดรอบ) ซึ่งเป็นเดือนที่รอบถัดไปเริ่ม จึงตรงกับ
//   billingMonth ของ record ต้นรอบที่กรอกจากใบเดียวกัน
//   สลับดู "ยอดเงิน" (หน่วย + บาท) หรือ "เลขมิเตอร์" (เลขบนใบ + หน่วย) ได้
// กดแถวไหนก็จัดการได้ในหน้านี้ ระบบเลือกฟอร์มที่ถูกต้องให้เอง

// เปิดหน้าเลขมิเตอร์จากใบแจ้งหนี้ — ใช้จากแดชบอร์ด หน้าบันทึกมิเตอร์ และแจ้งเตือน
Future<void> openInvoiceScreen(
  BuildContext context,
  String uid,
  FirestoreService firestoreService,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => InvoiceScreen(uid: uid, firestoreService: firestoreService),
    ),
  );
}

// สร้างรายการ 6 รอบบิลล่าสุด (รวมรอบปัจจุบัน) อิงวันตัดรอบบิลจริง (billingDay)
// ไม่ใช่เดือนปฏิทิน — ตัวแรกคือเดือนของใบแจ้งหนี้ใบล่าสุด ผู้เรียกตัดออก (.skip(1))
// เหลือ 5 เดือนที่เพิ่มเป็นบิลย้อนหลังได้ ใช้ทั้งในฟอร์มและในหน้านี้
List<DateTime> _generateHistoricalMonthOptions(int billingDay) {
  final options = <DateTime>[];
  var cursor = EnergyForecaster.getCycleStart(DateTime.now(), billingDay);
  for (int i = 0; i < 6; i++) {
    options.add(cursor);
    cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
  }
  return options;
}

// หาเดือนที่ไม่มีใบแจ้งหนี้เลย ไล่ย้อนจากเดือนก่อนใบล่าสุดไปจนถึงเดือนแรกที่เริ่ม
// ติดตาม (StartMeterRecordModel.trackingStartKey) — ขอบเขตเดียวกับที่ backfill
// ใน dashboard_loader.dart ใช้ตรวจรอบที่ขาด ไม่จำกัดแค่ 5 เดือนแบบ
// _generateHistoricalMonthOptions เพราะเดือนที่ระบบเคยแจ้งเตือนว่าขาด ต้องหาเจอ
// ในตารางเสมอไม่ว่าจะผ่านไปนานแค่ไหน ไม่งั้นกดตามแจ้งเตือนเข้ามาแล้วเจอทางตัน
List<DateTime> _generateAllMissingMonths(
  int billingDay,
  Set<String> takenAnySource, {
  required int trackingStartKey,
}) {
  final missing = <DateTime>[];
  // ไม่รู้เดือนเริ่ม (ยังไม่เคยตั้งเลยสักครั้ง) — ไม่ไล่หาเดือนที่ขาด ไม่งั้นผู้ใช้จะเห็น
  // แถว "ยังไม่กรอก" ย้อนไป 24 เดือนทั้งที่ไม่ได้ขาดจริง
  if (trackingStartKey == 0) return missing;
  var cursor = EnergyForecaster.getPreviousCycleStart(
      EnergyForecaster.getCycleStart(DateTime.now(), billingDay), billingDay);
  const maxLookback = 24; // กันลูปยาวเกินไปถ้าข้อมูล user ผิดปกติ
  for (var i = 0; i < maxLookback; i++) {
    if (cursor.year * 12 + cursor.month < trackingStartKey) {
      break;
    }
    if (!takenAnySource.contains('${cursor.year}-${cursor.month}')) {
      missing.add(cursor);
    }
    cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
  }
  return missing;
}

// วิดเจ็ตหัวข้อย่อยที่ใช้ร่วมกันใน info popup หลายหน้า
Widget _infoSectionHeader(String label, {IconData icon = Icons.checklist_rounded}) {
  return Row(
    children: [
      Icon(icon, size: 15, color: DashboardStyles.primaryGreen),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              fontSize: AppTypography.s13_5,
              fontWeight: FontWeight.bold,
              color: DashboardStyles.primaryGreen)),
    ],
  );
}

// ปุ่ม ⓘ อธิบายหน้า วางที่มุมขวาบนของการ์ดแรกในหน้า
Widget _pageInfoButton({required String tooltip, required VoidCallback onPressed}) {
  return IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
    onPressed: onPressed,
  );
}

// กล่องข้อควรระวัง
Widget _infoWarningBox(String text) {
  return Container(
    padding: const EdgeInsets.all(AppSpacing.v10),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.v10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warningIcon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: AppTypography.s12_5, height: 1.5, color: AppColors.warningText),
          ),
        ),
      ],
    ),
  );
}

void _showInvoiceInfoPopup(BuildContext context) {
  const body = TextStyle(fontSize: AppTypography.s13_5, height: 1.6);
  showInfoDialog(
    context,
    title: 'หน้านี้ใช้ทำอะไร?',
    contentBuilder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('เก็บเลขมิเตอร์และยอดเงินจากใบแจ้งหนี้ค่าไฟและค่าน้ำทุกเดือนไว้ที่เดียวค่ะ', style: body),
        const SizedBox(height: 14),
        _infoSectionHeader('ใบแจ้งหนี้ล่าสุด (จำเป็น)', icon: Icons.receipt_long_outlined),
        const SizedBox(height: 4),
        const Text(
          'กรอกเลขมิเตอร์จากใบแจ้งหนี้ใบล่าสุดทุกครั้งที่ได้ใบใหม่ ระบบใช้เลขนี้'
          'เป็นจุดเริ่มคำนวณว่ารอบนี้ใช้ไฟ/น้ำไปกี่หน่วย',
          style: body,
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('บิลย้อนหลัง (ไม่บังคับ)', icon: Icons.history_rounded),
        const SizedBox(height: 4),
        const Text(
          'กรอกหน่วยที่ใช้กับยอดเงินของเดือนก่อนเริ่มใช้แอป (ได้ 5 เดือน) หรือเดือนที่'
          'ลืมบันทึก (ขึ้นเป็นแถว "ยังไม่กรอก") เพื่อให้กราฟและการพยากรณ์แม่นขึ้น',
          style: body,
        ),
        const SizedBox(height: 12),
        _infoWarningBox(
          'บิลย้อนหลังให้กรอกหน่วยที่ใช้ของเดือนนั้นเดือนเดียว ไม่ใช่เลขสะสม'
          'บนมิเตอร์ (ดูตัวอย่างได้จากปุ่ม "ดูตำแหน่งในบิล" ในฟอร์ม)',
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('ป้ายใต้ชื่อเดือนในตาราง', icon: Icons.label_outline_rounded),
        const SizedBox(height: 4),
        const Text(
          '"ใบล่าสุด" และ "ใบแจ้งหนี้" มาจากเลขมิเตอร์ที่กรอกจากใบแจ้งหนี้, '
          '"กรอกเอง" คือบิลย้อนหลังที่เพิ่มเอง, "ระบบประมาณ" คือบิลที่ระบบปิดให้'
          'เมื่อจบรอบ โดยประมาณจากเลขมิเตอร์ที่บันทึกไว้ถึงวันตัดรอบ กดแก้ไขเพื่อใส่'
          'ยอดจากใบแจ้งหนี้จริงได้ค่ะ',
          style: body,
        ),
      ],
    ),
  );
}

// แถวหนึ่งของตาราง = ใบแจ้งหนี้หนึ่งเดือน
class _InvoiceRow {
  final int year;
  final int month;
  final BillModel? bill;
  final StartMeterRecordModel? record;

  const _InvoiceRow({required this.year, required this.month, this.bill, this.record});

  int get key => year * 12 + month;
  // ไม่มีทั้งบิลและเลขมิเตอร์ = เดือนที่ขาด
  bool get isMissing => bill == null && record == null;
}

class InvoiceScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const InvoiceScreen({super.key, required this.uid, required this.firestoreService});

  @override
  State<InvoiceScreen> createState() => InvoiceScreenState();
}

class InvoiceScreenState extends State<InvoiceScreen> {
  UserModel? _user;
  List<BillModel> _bills = [];
  List<StartMeterRecordModel> _records = [];
  List<DateTime> _missingMonths = [];
  bool _isLoading = true;

  bool get _isTou => _user?.meterType == 'tou';
  int get _billingDay => _user?.billingDay ?? 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final user = await widget.firestoreService.getUser(widget.uid);
    final results = await Future.wait([
      widget.firestoreService.getBills(widget.uid),
      widget.firestoreService.getStartMeterHistory(widget.uid),
    ]);
    final bills = results[0] as List<BillModel>;
    final records = results[1] as List<StartMeterRecordModel>;
    final taken = {
      for (final b in bills) '${b.year}-${b.month}',
      for (final r in records) '${r.billingYear}-${r.billingMonth}',
    };
    final missing = _generateAllMissingMonths(
      user?.billingDay ?? 30,
      taken,
      trackingStartKey: StartMeterRecordModel.trackingStartKey(
        records,
        startYear: user?.startBillingYear ?? 0,
        startMonth: user?.startBillingMonth ?? 0,
      ),
    );
    if (mounted) {
      setState(() {
        _user = user;
        _bills = bills;
        _records = records;
        _missingMonths = missing;
        _isLoading = false;
      });
    }
  }

  // ---- ข้อมูลของแต่ละแถว ----

  // รวมบิล + record ต้นรอบ + เดือนที่ขาด เป็นแถวละหนึ่งเดือน
  List<_InvoiceRow> _rows() {
    final bills = <int, BillModel>{for (final b in _bills) b.year * 12 + b.month: b};
    final records = <int, StartMeterRecordModel>{
      for (final r in _records) r.billingYear * 12 + r.billingMonth: r,
    };
    final keys = {...bills.keys, ...records.keys, for (final m in _missingMonths) m.year * 12 + m.month};
    return [
      for (final k in keys)
        _InvoiceRow(
          year: (k - 1) ~/ 12,
          month: (k - 1) % 12 + 1,
          bill: bills[k],
          record: records[k],
        ),
    ];
  }

  // record ที่ค่าต้นรอบใน user document อ้างอิงอยู่ — เทียบ billingMonth/Year ตรงๆ
  // (ไม่ผูกกับวันที่ปัจจุบัน) เพื่อให้ตอนลบรีเซ็ตค่าใน user document ถูกแถวเสมอ
  // แม้ billingDay เพิ่งเปลี่ยน
  bool _isCurrentRecord(StartMeterRecordModel r) =>
      _user != null && r.billingMonth == _user!.startBillingMonth && r.billingYear == _user!.startBillingYear;

  // ตั้งเลขต้นรอบของรอบปัจจุบันครบแล้วไหม (ตัวเดียวกับ _AddStartMeterSheetState)
  bool get _latestConfigured {
    final user = _user;
    if (user == null) return false;
    return user.startMeterConfigured &&
        EnergyForecaster.matchesCurrentCycle(
          billingMonth: user.startBillingMonth,
          billingYear: user.startBillingYear,
          billingDay: user.billingDay,
        );
  }

  StartMeterRecordModel? get _latestRecord {
    if (!_latestConfigured) return null;
    for (final r in _records) {
      if (_isCurrentRecord(r)) return r;
    }
    return null;
  }

  // เดือนของใบแจ้งหนี้ใบล่าสุด (ใบที่ใช้ตั้งต้นรอบปัจจุบัน)
  DateTime get _latestMonth => _generateHistoricalMonthOptions(_billingDay).first;

  bool _isLatestRow(_InvoiceRow row) => row.year == _latestMonth.year && row.month == _latestMonth.month;

  BillModel? _billFor(int month, int year) {
    for (final b in _bills) {
      if (b.month == month && b.year == year) return b;
    }
    return null;
  }

  bool _hasElectricity(StartMeterRecordModel r) => _isTou ? (r.peakValue > 0 || r.offPeakValue > 0) : r.electricityValue > 0;

  bool _hasReading(StartMeterRecordModel r, bool water) => water ? r.waterValue > 0 : _hasElectricity(r);

  double _reading(StartMeterRecordModel r, bool water) =>
      water ? r.waterValue : (_isTou ? r.peakValue + r.offPeakValue : r.electricityValue);

  // หน่วยที่ใช้ระหว่างใบแจ้งหนี้สองใบ = เลขใบนี้ − เลขใบก่อนหน้าที่ใกล้ที่สุดซึ่งมีข้อมูล
  // (คิดจากประวัติทั้งหมด) — ไม่มีใบก่อนให้เทียบ = ไม่มีค่า
  Map<String, double> _readingUsedById(bool water) {
    final withData = _records.where((r) => _hasReading(r, water)).toList()
      ..sort((a, b) => (a.billingYear * 12 + a.billingMonth).compareTo(b.billingYear * 12 + b.billingMonth));
    final used = <String, double>{};
    for (var i = 1; i < withData.length; i++) {
      used[withData[i].id] = EnergyCalculator.calculateUsed(_reading(withData[i], water), _reading(withData[i - 1], water));
    }
    return used;
  }

  // ป้ายที่มาใต้ชื่อเดือน
  (String, Color) _sourceLabel(_InvoiceRow row) {
    final bill = row.bill;
    if (row.isMissing) return ('ยังไม่กรอก', AppColors.warningText);
    if (bill == null || bill.source == 'startMeter') {
      return _isLatestRow(row) ? ('ใบล่าสุด', AppColors.primaryGreen) : ('ใบแจ้งหนี้', Colors.grey.shade600);
    }
    if (bill.source == 'compiled') return ('ระบบประมาณ', AppColors.warningIcon);
    return ('กรอกเอง', Colors.grey.shade600);
  }

  // ---- เปิดฟอร์ม ----

  Future<void> _openLatestSheet() async {
    if (_user == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddStartMeterSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        isTou: _isTou,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openPastSheet({BillModel? existingBill}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddHistoricalBillSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        existingBill: existingBill,
      ),
    );
    // โหลดใหม่เสมอ: ฟอร์มนี้มีลิงก์ปิดตัวเองแล้วเปิดฟอร์มใบล่าสุดต่อ ซึ่งไม่ส่งผลกลับมา
    if (saved != false) _load();
  }

  // ปุ่ม "เพิ่มใบเดือนก่อนๆ" เพิ่มได้แค่ 5 เดือนก่อนใบล่าสุด พอทุกเดือนมีใบแล้ว
  // (นับทุกแหล่งเหมือนฟอร์ม) ซ่อนปุ่ม เพราะกดไปจะเจอแค่ "มีบิลแล้ว" ทุกเดือน
  bool get _allPastMonthsRecorded {
    final taken = _bills.map((b) => '${b.year}-${b.month}').toSet();
    return _generateHistoricalMonthOptions(_billingDay).skip(1).every((m) => taken.contains('${m.year}-${m.month}'));
  }

  // ---- ลบ ----

  Future<void> _confirmDeleteBill(BillModel bill) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'ลบบิลนี้?',
      content: 'ต้องการลบบิลเดือน ${_monthYearLabel(bill.month, bill.year)} ใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteBill(widget.uid, bill.id);
      _load();
    }
  }

  // ลบเลขมิเตอร์ของฝั่งเดียว — record เก็บทั้งไฟและน้ำของเดือนนั้นรวมกัน (บิลคู่กันก็เก็บ
  // ยอดของทั้งสองฝั่ง) ถ้าอีกฝั่งยังมีข้อมูลให้เซฟทับโดยล้างเฉพาะฝั่งที่ลบ ถ้าไม่มีลบทั้ง
  // record/บิล — startMeterConfigured เป็น false ก็ต่อเมื่อไม่เหลือฝั่งไหนตั้งค่าไว้
  Future<void> _confirmDeleteReading(StartMeterRecordModel record, {required bool isElectricity}) async {
    final isCurrent = _isCurrentRecord(record);
    final utilityLabel = isElectricity ? 'ไฟฟ้า' : 'น้ำ';
    final otherUtilityHasData = isElectricity ? record.waterValue > 0 : _hasElectricity(record);

    final confirmed = await showConfirmDialog(
      context,
      title: 'ลบข้อมูล$utilityLabelของบิลนี้?',
      content: isCurrent
          ? 'ลบแล้วเลขมิเตอร์ต้นรอบ$utilityLabelของรอบปัจจุบันจะถูกรีเซ็ต '
              'ต้องกรอกใบแจ้งหนี้ล่าสุดใหม่ก่อนถึงจะบันทึกมิเตอร์ต่อได้ และยอด$utilityLabel'
              'ของบิลนี้จะถูกลบไปด้วย ต้องการดำเนินการต่อใช่ไหมคะ?'
          : 'ต้องการลบเลขมิเตอร์และยอด$utilityLabelของบิลนี้ใช่ไหมคะ',
      borderRadius: 16,
    );
    if (confirmed != true) return;

    final pairedBill = _billFor(record.billingMonth, record.billingYear);

    if (otherUtilityHasData) {
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
        final remainingCost = isElectricity ? pairedBill.waterCost : pairedBill.electricityCost;
        await widget.firestoreService.saveBill(
          BillModel(
            id: pairedBill.id,
            uid: pairedBill.uid,
            year: pairedBill.year,
            month: pairedBill.month,
            electricityCost: isElectricity ? 0 : pairedBill.electricityCost,
            waterCost: isElectricity ? pairedBill.waterCost : 0,
            totalCost: remainingCost + pairedBill.fixedCost,
            electricityUsed: isElectricity ? 0 : pairedBill.electricityUsed,
            electricityPeakUsed: isElectricity ? 0 : pairedBill.electricityPeakUsed,
            electricityOffPeakUsed: isElectricity ? 0 : pairedBill.electricityOffPeakUsed,
            waterUsed: isElectricity ? pairedBill.waterUsed : 0,
            fixedCost: pairedBill.fixedCost,
            source: pairedBill.source,
          ),
        );
      }
    } else {
      await widget.firestoreService.deleteStartMeterRecord(widget.uid, record.id);
      if (pairedBill != null && pairedBill.source == 'startMeter') {
        await widget.firestoreService.deleteBill(widget.uid, pairedBill.id);
      }
    }

    if (isCurrent) {
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
      final otherStillConfigured =
          isElectricity ? (_user?.waterStartConfigured ?? false) : (_user?.electricityStartConfigured ?? false);
      if (!otherStillConfigured) {
        updates['startMeterConfigured'] = false;
        updates['startBillingMonth'] = 0;
        updates['startBillingYear'] = 0;
      }
      await widget.firestoreService.updateUser(widget.uid, updates);
    }

    _load();
  }

  // ---- มุมมองตาราง (UI state ล้วนๆ) ----
  bool _showWater = false;
  bool _showReadings = false; // false = ยอดเงิน, true = เลขมิเตอร์
  bool _newestFirst = true;
  // ปีที่กางอยู่ — null = ยังไม่เคยแตะ ใช้ค่าเริ่มต้นคือกางเฉพาะปีล่าสุด
  Set<int>? _expandedYears;

  String get _unit => _showWater ? 'ลบ.ม.' : 'หน่วย';
  Color get _accent => _showWater ? AppColors.waterBorder : AppColors.electricityBorder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'เลขมิเตอร์จากใบแจ้งหนี้'),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
    );
  }

  Widget _buildBody() {
    final rows = _rows()..sort((a, b) => _newestFirst ? b.key.compareTo(a.key) : a.key.compareTo(b.key));
    final firstTime = !_latestConfigured;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
      children: [
        FadeSlideIn(child: _buildLatestCard(firstTime)),
        const SizedBox(height: AppSpacing.v12),
        FadeSlideIn(delay: const Duration(milliseconds: 70), child: _buildPastCard(firstTime)),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.v24),
          Row(
            children: [
              const Expanded(child: Text('บิลแต่ละเดือน', style: DashboardStyles.sectionTitle)),
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
          _buildFilters(),
          const SizedBox(height: AppSpacing.v12),
          ..._buildYearSections(rows),
        ],
      ],
    );
  }

  // ---- การ์ดใบล่าสุด ----

  Widget _stepChip(String label, {required bool required}) {
    final color = required ? AppColors.primaryGreen : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8, vertical: AppSpacing.v2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.v10),
      ),
      child: Text(label, style: TextStyle(fontSize: AppTypography.s11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _cardTitle(String title, {String? chip, bool chipRequired = false}) {
    return Wrap(
      spacing: AppSpacing.v6,
      runSpacing: AppSpacing.v4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title,
            style: const TextStyle(fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        if (chip != null) _stepChip(chip, required: chipRequired),
      ],
    );
  }

  Widget _buildLatestCard(bool firstTime) {
    final latest = _latestRecord;
    final infoButton = _pageInfoButton(tooltip: 'หน้านี้ใช้ทำอะไร', onPressed: () => _showInvoiceInfoPopup(context));

    if (latest == null) {
      final month = _latestMonth;
      return AppCard(
        borderColor: AppColors.primaryGreen.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.v16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(icon: Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 40),
                const SizedBox(width: AppSpacing.v12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardTitle(firstTime ? '1. ใบแจ้งหนี้ล่าสุด' : 'ใบแจ้งหนี้ล่าสุด',
                          chip: 'จำเป็น', chipRequired: true),
                      const SizedBox(height: AppSpacing.v2),
                      Text(
                        'กรอกเลขมิเตอร์จากใบแจ้งหนี้เดือน ${_monthYearLabel(month.month, month.year)} '
                        'เพื่อเริ่มคำนวณค่าไฟ/ค่าน้ำรอบนี้ค่ะ',
                        style: TextStyle(fontSize: AppTypography.s12_5, height: 1.4, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                infoButton,
              ],
            ),
            const SizedBox(height: AppSpacing.v14),
            ElevatedButton.icon(
              onPressed: _openLatestSheet,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('กรอกใบแจ้งหนี้ล่าสุด'),
            ),
          ],
        ),
      );
    }

    final fmt = NumberFormat('#,##0.##');
    final money = NumberFormat('#,##0.00');
    final bill = _billFor(latest.billingMonth, latest.billingYear);
    String? eReading;
    if (_hasElectricity(latest)) {
      eReading = _isTou
          ? 'On ${fmt.format(latest.peakValue)} · Off ${fmt.format(latest.offPeakValue)}'
          : fmt.format(latest.electricityValue);
    }
    final wReading = latest.waterValue > 0 ? fmt.format(latest.waterValue) : null;
    String? costOf(double c) => c > 0 ? '${money.format(c)} บาท' : null;

    return AppCard(
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
                    Text('ใบแจ้งหนี้ล่าสุด', style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                    Text(_monthYearLabel(latest.billingMonth, latest.billingYear),
                        style: const TextStyle(
                            fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openLatestSheet,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('แก้ไข'),
              ),
              infoButton,
            ],
          ),
          const SizedBox(height: AppSpacing.v12),
          Row(
            children: [
              Expanded(
                child: _latestValue(Icons.bolt_rounded, AppColors.electricityBorder, 'ไฟฟ้า', eReading,
                    costOf(bill?.electricityCost ?? 0)),
              ),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: _latestValue(
                    Icons.water_drop_rounded, AppColors.waterBorder, 'น้ำ', wReading, costOf(bill?.waterCost ?? 0)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ช่องสรุปของใบล่าสุด: เลขมิเตอร์บนใบ + ยอดเงิน (ถ้ากรอก)
  Widget _latestValue(IconData icon, Color color, String label, String? reading, String? cost) {
    final filled = reading != null;
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
                child: Text('เลขมิเตอร์$label',
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
            child: Text(reading ?? 'ไม่ได้กรอก',
                style: TextStyle(
                    fontSize: filled ? AppTypography.s16 : AppTypography.s13,
                    fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
                    color: filled ? AppColors.textDark : Colors.grey.shade500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (cost != null)
            Text('ยอดเงิน $cost',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  // ---- บิลย้อนหลัง ----

  Widget _buildPastCard(bool firstTime) {
    final latest = _latestMonth;
    final pastBills = _bills.where((b) => b.year * 12 + b.month < latest.year * 12 + latest.month).toList();
    final oldest = pastBills.isEmpty ? null : pastBills.reduce((a, b) => a.yearMonth < b.yearMonth ? a : b);
    final missingSorted = [..._missingMonths]..sort((a, b) => b.compareTo(a));
    final canAdd = !_allPastMonthsRecorded;

    // การ์ดเต็มมีเฉพาะตอนเริ่มใช้งาน (ช่วงที่การเพิ่มบิลเก่ามีประโยชน์ที่สุด) หรือเมื่อมีเดือน
    // ที่ขาดจริง — นอกนั้น (หรือเมื่อครบแล้ว) เหลือบรรทัดบางๆ ไม่ให้ดูเหมือนงานค้างสำหรับคนที่ไม่มีบิลเก่า
    if (missingSorted.isEmpty && (!firstTime || !canAdd)) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.v4),
        child: Row(
          children: [
            Icon(canAdd ? Icons.history_rounded : Icons.check_circle_rounded,
                size: 16, color: canAdd ? Colors.grey.shade600 : AppColors.primaryGreen),
            const SizedBox(width: AppSpacing.v6),
            Expanded(
              child: Text(
                  canAdd
                      ? (pastBills.isEmpty ? 'ยังไม่มีบิลย้อนหลัง (ไม่บังคับ)' : 'มีบิลย้อนหลัง ${pastBills.length} เดือน')
                      : 'บันทึกบิลย้อนหลังครบแล้ว แก้ไขได้ในตารางด้านล่างค่ะ',
                  style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
            ),
            if (canAdd)
              TextButton.icon(
                onPressed: () => _openPastSheet(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('เพิ่มบิลย้อนหลัง'),
              ),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: Icons.history_rounded, color: Colors.grey.shade600, size: 40),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardTitle(firstTime ? '2. บิลย้อนหลัง' : 'บิลย้อนหลัง',
                        chip: 'ไม่บังคับ'),
                    const SizedBox(height: AppSpacing.v2),
                    Text(
                      oldest == null
                          ? 'เพิ่มหน่วยและยอดเงินของเดือนก่อนๆ ช่วยให้กราฟและการพยากรณ์แม่นขึ้นค่ะ'
                          : 'มี ${pastBills.length} เดือน ย้อนหลังถึง ${_monthYearLabel(oldest.month, oldest.year)}',
                      style: TextStyle(fontSize: AppTypography.s12_5, height: 1.4, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (missingSorted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.v12),
            Container(
              padding: const EdgeInsets.all(AppSpacing.v12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningIcon),
                  const SizedBox(width: AppSpacing.v8),
                  Expanded(
                    child: Text(
                      'ขาดบิล ${missingSorted.length} เดือน: '
                      '${missingSorted.map((m) => '${thaiMonthsShort[m.month - 1]} ${(m.year + 543) % 100}').join(', ')}',
                      style: const TextStyle(fontSize: AppTypography.s12_5, height: 1.4, color: AppColors.warningText),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.v8),
                  TextButton(
                    onPressed: () => _openPastSheet(existingBill: _missingPlaceholder(missingSorted.first)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.warningText,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8),
                    ),
                    child: const Text('กรอก'),
                  ),
                ],
              ),
            ),
          ],
          if (canAdd) ...[
            const SizedBox(height: AppSpacing.v12),
            OutlinedButton.icon(
              onPressed: () => _openPastSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('เพิ่มบิลย้อนหลัง'),
            ),
          ],
        ],
      ),
    );
  }

  // บิลชั่วคราวของเดือนที่ขาด (ไม่มี Firestore doc) ส่งให้ฟอร์มเปิดที่เดือนนั้น
  BillModel _missingPlaceholder(DateTime m) => BillModel(
        id: 'missing_${m.year}_${m.month}',
        uid: widget.uid,
        year: m.year,
        month: m.month,
        source: 'missing',
      );

  // ---- ตาราง ----

  // ตัวกรองของตาราง 2 แถว มีป้ายบอกว่าแต่ละแถวเลือกอะไร: ประเภท (ไฟฟ้า/น้ำ) และ
  // แสดง (ยอดเงิน/เลขมิเตอร์) — ตัวที่เลือกเป็นพื้นสีจางขอบสีพร้อม ✓ ตัวที่ไม่ได้เลือกเป็นพื้นครีม
  Widget _buildFilters() {
    Widget row(String label, List<Widget> options) => Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            ),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.v8),
              Expanded(child: options[i]),
            ],
          ],
        );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v12),
      child: Column(
        children: [
          row('ประเภท', [
            _filterOption('ไฟฟ้า', Icons.bolt_rounded, AppColors.electricityBorder, !_showWater,
                () => setState(() => _showWater = false)),
            _filterOption('น้ำ', Icons.water_drop_rounded, AppColors.waterBorder, _showWater,
                () => setState(() => _showWater = true)),
          ]),
          const SizedBox(height: AppSpacing.v10),
          row('แสดง', [
            _filterOption('ยอดเงิน', Icons.payments_outlined, AppColors.primaryGreen, !_showReadings,
                () => setState(() => _showReadings = false)),
            _filterOption('เลขมิเตอร์', Icons.speed_rounded, AppColors.primaryGreen, _showReadings,
                () => setState(() => _showReadings = true)),
          ]),
        ],
      ),
    );
  }

  Widget _filterOption(String label, IconData icon, Color color, bool selected, VoidCallback onTap) {
    final fg = selected ? color : Colors.grey.shade600;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? color.withValues(alpha: 0.10) : AppColors.inputFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          side: BorderSide(
              color: selected ? color.withValues(alpha: 0.55) : AppColors.inputBorder, width: selected ? 1.2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? Icons.check_rounded : icon,
                    size: 16, color: selected ? color : color.withValues(alpha: 0.55)),
                const SizedBox(width: AppSpacing.v4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTypography.s13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _costOf(_InvoiceRow r) => _showWater ? (r.bill?.waterCost ?? 0) : (r.bill?.electricityCost ?? 0);

  // หน่วยที่ใช้ของใบนี้: จากบิลก่อน ถ้าบิลไม่มีหน่วยใช้ส่วนต่างของเลขมิเตอร์
  double? _usedOf(_InvoiceRow r, Map<String, double> readingUsed) {
    final fromBill = _showWater ? (r.bill?.waterUsed ?? 0) : (r.bill?.electricityUsed ?? 0);
    if (fromBill > 0) return fromBill;
    return r.record == null ? null : readingUsed[r.record!.id];
  }

  List<Widget> _buildYearSections(List<_InvoiceRow> rows) {
    final readingUsed = _readingUsedById(_showWater);
    final groups = <int, List<_InvoiceRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.year, () => []).add(r);
    }
    final expanded = _expandedYears ?? {rows.map((r) => r.year).reduce((a, b) => a > b ? a : b)};
    // ปีของใบล่าสุดเป็นการ์ดขาว ปีก่อนๆ ที่ปิดไปแล้วใช้พื้นจาง (AppColors.closedSurface)
    final latestYear = _latestMonth.year;
    return [
      for (final entry in groups.entries) ...[
        _yearHeader(entry.key, entry.value, readingUsed, isOpen: expanded.contains(entry.key), onTap: () {
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
                    color: entry.key == latestYear ? Colors.white : AppColors.closedSurface,
                    borderColor: entry.key == latestYear ? null : AppColors.closedBorder,
                    child: Column(
                      children: [
                        _tableHeader(),
                        for (final r in entry.value) ...[
                          const Divider(),
                          _tableRow(r, readingUsed),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.v6),
      ],
    ];
  }

  // หัวปี (กดเพื่อพับ/กาง) + สรุปของปีนั้นตามมุมมองที่เลือก
  Widget _yearHeader(int year, List<_InvoiceRow> rows, Map<String, double> readingUsed,
      {required bool isOpen, required VoidCallback onTap}) {
    final String summary;
    String? detail;
    if (_showReadings) {
      final used = rows.map((r) => _usedOf(r, readingUsed)).whereType<double>().where((u) => u > 0).toList();
      final total = used.fold<double>(0, (s, u) => s + u);
      summary = used.isEmpty ? '${rows.length} เดือน' : '${used.length} เดือน · ใช้รวม ${NumberFormat('#,##0').format(total)} $_unit';
      if (used.isNotEmpty) detail = 'เฉลี่ย ${NumberFormat('#,##0').format(total / used.length)} $_unit/เดือน';
    } else {
      final costs = rows.map(_costOf).where((c) => c > 0).toList();
      final total = costs.fold<double>(0, (s, c) => s + c);
      final baht = NumberFormat('#,##0');
      summary = costs.isEmpty ? '${rows.length} เดือน' : '${costs.length} เดือน · รวม ${baht.format(total)} บาท';
      if (costs.isNotEmpty) detail = 'เฉลี่ย ${baht.format(total / costs.length)} บาท/เดือน';
    }
    final isLatestYear = year == _latestMonth.year;
    return Material(
      color: isOpen ? Colors.transparent : (isLatestYear ? Colors.white : AppColors.closedSurface),
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
                    if (detail != null)
                      Text(detail,
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

  static const double _monthColWidth = 76;
  static const double _rightColWidth = 96;

  Widget _tableHeader() {
    final style = TextStyle(fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, 36, AppSpacing.v10),
      child: Row(
        children: [
          SizedBox(width: _monthColWidth, child: Text('เดือน', style: style)),
          Expanded(child: Text(_showReadings ? 'เลขมิเตอร์' : 'ใช้ไป ($_unit)', style: style)),
          SizedBox(
              width: _rightColWidth,
              child: Text(_showReadings ? 'ใช้ไป ($_unit)' : 'ยอดเงิน (บาท)', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }

  Widget _tableRow(_InvoiceRow r, Map<String, double> readingUsed) {
    final fmt = NumberFormat('#,##0.##');
    final money = NumberFormat('#,##0.00');
    final muted = TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade400);
    const number = TextStyle(
        fontSize: AppTypography.s14,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
        fontFeatures: [FontFeature.tabularFigures()]);
    final (label, labelColor) = _sourceLabel(r);
    final used = _usedOf(r, readingUsed);

    Widget usedText({bool accent = false, TextAlign align = TextAlign.start}) => used == null || used <= 0
        ? Text('–', textAlign: align, style: muted)
        : Text(fmt.format(used),
            textAlign: align,
            style: accent ? number.copyWith(fontWeight: FontWeight.w700, color: _accent) : number);

    final Widget middle;
    final Widget right;
    if (_showReadings) {
      final rec = r.record;
      if (rec == null || !_hasReading(rec, _showWater)) {
        middle = Text(r.isMissing ? '–' : 'ไม่ได้กรอก', style: muted);
      } else if (!_showWater && _isTou) {
        middle = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On ${fmt.format(rec.peakValue)}', style: number.copyWith(fontSize: AppTypography.s13)),
            Text('Off ${fmt.format(rec.offPeakValue)}', style: number.copyWith(fontSize: AppTypography.s13)),
          ],
        );
      } else {
        middle = Text(fmt.format(_reading(rec, _showWater)), style: number);
      }
      right = usedText(accent: true, align: TextAlign.end);
    } else {
      final bill = r.bill;
      if (!_showWater && _isTou && bill != null && (bill.electricityPeakUsed > 0 || bill.electricityOffPeakUsed > 0)) {
        middle = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            usedText(),
            Text('On ${fmt.format(bill.electricityPeakUsed)} · Off ${fmt.format(bill.electricityOffPeakUsed)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
          ],
        );
      } else {
        middle = usedText();
      }
      final cost = _costOf(r);
      right = cost <= 0
          ? Text('–', textAlign: TextAlign.end, style: muted)
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(money.format(cost),
                  style: number.copyWith(fontWeight: FontWeight.w700, color: _accent)),
            );
    }

    return InkWell(
      onTap: () => _showRowActions(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
        child: Row(
          children: [
            SizedBox(
              width: _monthColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(thaiMonthsShort[r.month - 1],
                      style: TextStyle(
                          fontSize: AppTypography.s14,
                          fontWeight: FontWeight.w600,
                          color: r.isMissing ? Colors.grey.shade500 : AppColors.textDark)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.s10_5, fontWeight: FontWeight.w600, color: labelColor)),
                ],
              ),
            ),
            Expanded(child: middle),
            SizedBox(width: _rightColWidth, child: right),
            SizedBox(
              width: 28,
              child: Icon(r.isMissing ? Icons.add_circle_outline_rounded : Icons.chevron_right_rounded,
                  size: r.isMissing ? 16 : 20, color: r.isMissing ? AppColors.warningIcon : Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ---- เมนูของแถว ----
  // ทุกแถวจัดการได้ในหน้านี้ ระบบเลือกฟอร์มให้ตามที่มาของใบ:
  // - เดือนที่ขาด / ใบที่กรอกเอง / ใบที่ระบบประมาณ -> ฟอร์มใบเดือนก่อนๆ
  // - ใบล่าสุด -> ฟอร์มใบแจ้งหนี้ล่าสุด
  // - ใบที่มาจากเลขมิเตอร์ของรอบที่ผ่านไปแล้ว -> แก้ไม่ได้ (เลขนี้ใช้คิดหน่วยของรอบถัดไป
  //   แล้ว แก้แล้วตัวเลขจะไม่ตรงกัน) แต่ลบข้อมูลทีละฝั่งได้
  Future<void> _showRowActions(_InvoiceRow r) async {
    final bill = r.bill;
    final record = r.record;
    final isLatest = _isLatestRow(r);
    final fmt = NumberFormat('#,##0.##');
    final money = NumberFormat('#,##0.00');

    // รายละเอียดแต่ละฝั่ง: เลขมิเตอร์ · ใช้ไป · ยอดเงิน (เฉพาะที่มี)
    String? detail(bool water) {
      final parts = <String>[];
      if (record != null && _hasReading(record, water)) {
        parts.add(!water && _isTou
            ? 'เลขมิเตอร์ On ${fmt.format(record.peakValue)} / Off ${fmt.format(record.offPeakValue)}'
            : 'เลขมิเตอร์ ${fmt.format(_reading(record, water))}');
      }
      final used = water ? (bill?.waterUsed ?? 0) : (bill?.electricityUsed ?? 0);
      if (used > 0) parts.add('ใช้ไป ${fmt.format(used)} ${water ? 'ลบ.ม.' : 'หน่วย'}');
      final cost = water ? (bill?.waterCost ?? 0) : (bill?.electricityCost ?? 0);
      if (cost > 0) parts.add('${money.format(cost)} บาท');
      return parts.isEmpty ? null : parts.join(' · ');
    }

    final eDetail = detail(false);
    final wDetail = detail(true);

    Widget action(String text, IconData icon, Color color, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: color),
          title: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          onTap: onTap,
        );

    Widget detailLine(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.v6),
              Expanded(
                  child: Text(text,
                      style: const TextStyle(fontSize: AppTypography.s13, height: 1.4, color: AppColors.textDark))),
            ],
          ),
        );

    final lockedOldReading = !isLatest && bill?.source != 'imported' && bill?.source != 'compiled' && !r.isMissing;

    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        void close(VoidCallback next) {
          Navigator.pop(ctx);
          next();
        }

        return SafeArea(
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
                      Text('บิล ${_monthYearLabel(r.month, r.year)}',
                          style: const TextStyle(
                              fontSize: AppTypography.s16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                      Text(
                        r.isMissing
                            ? 'ยังไม่ได้กรอกบิลเดือนนี้ค่ะ'
                            : bill?.source == 'compiled'
                                ? 'ระบบประมาณจากเลขมิเตอร์ที่บันทึกไว้ถึงวันตัดรอบ แก้เป็นยอดจากใบแจ้งหนี้จริงได้ค่ะ'
                                : isLatest
                                    ? 'ใบล่าสุด ใช้ตั้งต้นรอบบิลปัจจุบัน'
                                    : bill?.source == 'imported'
                                        ? 'กรอกเองจากใบแจ้งหนี้'
                                        : 'กรอกจากเลขมิเตอร์บนใบแจ้งหนี้',
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade600),
                      ),
                      if (eDetail != null) detailLine(Icons.bolt_rounded, AppColors.electricityBorder, eDetail),
                      if (wDetail != null) detailLine(Icons.water_drop_rounded, AppColors.waterBorder, wDetail),
                      if (bill != null && bill.totalCost > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.v6),
                          child: Text(
                            'รวม ${money.format(bill.totalCost)} บาท'
                            '${bill.fixedCost > 0 ? ' (รวมรายจ่ายประจำแล้ว)' : ''}',
                            style: const TextStyle(
                                fontSize: AppTypography.s13, fontWeight: FontWeight.w700, color: AppColors.textDark),
                          ),
                        ),
                    ],
                  ),
                ),
                if (r.isMissing)
                  action('กรอกบิลเดือนนี้', Icons.edit_note_rounded, AppColors.textDark,
                      () => close(() => _openPastSheet(existingBill: _missingPlaceholder(DateTime(r.year, r.month)))))
                else if (isLatest)
                  action('แก้ไขใบแจ้งหนี้ล่าสุด', Icons.edit_outlined, AppColors.textDark, () => close(_openLatestSheet))
                else if (bill != null && (bill.source == 'imported' || bill.source == 'compiled'))
                  action(bill.source == 'compiled' ? 'ใส่ยอดจากใบแจ้งหนี้จริง' : 'แก้ไข', Icons.edit_outlined,
                      AppColors.textDark, () => close(() => _openPastSheet(existingBill: bill))),
                if (bill != null && bill.source == 'imported')
                  action('ลบบิลนี้', Icons.delete_outline_rounded, Colors.red.shade700,
                      () => close(() => _confirmDeleteBill(bill))),
                if (record != null && _hasElectricity(record))
                  action('ลบข้อมูลไฟฟ้าของบิลนี้', Icons.delete_outline_rounded, Colors.red.shade700,
                      () => close(() => _confirmDeleteReading(record, isElectricity: true))),
                if (record != null && record.waterValue > 0)
                  action('ลบข้อมูลน้ำของบิลนี้', Icons.delete_outline_rounded, Colors.red.shade700,
                      () => close(() => _confirmDeleteReading(record, isElectricity: false))),
                if (lockedOldReading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v4, AppSpacing.v20, AppSpacing.v4),
                    child: Text('บิลของรอบที่ผ่านมาแล้วแก้เลขมิเตอร์ไม่ได้ เพราะใช้คำนวณหน่วยของรอบถัดไปไปแล้วค่ะ',
                        style: TextStyle(fontSize: AppTypography.s11_5, height: 1.4, color: Colors.grey.shade600)),
                  ),
              ],
            ),
          ),
        );
      },
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
