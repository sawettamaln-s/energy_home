part of 'settings_screen.dart';

// สร้างรายการ 6 รอบบิลล่าสุด (รวมรอบปัจจุบัน) อิงวันตัดรอบบิลจริง (billingDay)
// ไม่ใช่เดือนปฏิทิน — ผู้เรียกตัดรอบปัจจุบันออก (.skip(1)) เหลือ 5 เดือนย้อนหลัง
// ใช้ทั้งเป็นตัวเลือกในฟอร์ม และเช็คว่ากรอกครบแล้วหรือยังใน HistoricalBillListScreen
List<DateTime> _generateHistoricalMonthOptions(int billingDay) {
  final options = <DateTime>[];
  var cursor = EnergyForecaster.getCycleStart(DateTime.now(), billingDay);
  for (int i = 0; i < 6; i++) {
    options.add(cursor);
    cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
  }
  return options;
}

// หาเดือนที่ "ไม่มีบิลเลยไม่ว่า source ไหน" ไล่ย้อนจากรอบก่อนหน้ารอบปัจจุบันไป
// จนถึงเดือนที่ user เริ่มตั้งค่าระบบครั้งแรก (startBillingMonth/Year) — ขอบเขต
// เดียวกับที่ backfill loop ใน dashboard_loader.dart ใช้ตรวจจับรอบที่ขาด ตั้งใจ
// ไม่จำกัดแค่ 5 เดือนแบบ _generateHistoricalMonthOptions (นั่นมีไว้จำกัดแค่ตอน
// "เพิ่มบิลใหม่เอง" ผ่านปุ่ม +) เพราะเดือนที่ระบบเคยแจ้งเตือนไปแล้วว่าขาด ต้องยัง
// หาเจอในลิสต์นี้ได้เสมอไม่ว่าจะผ่านไปนานแค่ไหนก่อน user จะกดเข้ามาดู ไม่งั้น
// กดตาม notification เข้ามาแล้วจะเจอทางตัน หาเดือนที่ต้องการกรอกไม่เจอ
List<DateTime> _generateAllMissingMonths(
  int billingDay,
  Set<String> takenAnySource, {
  int startBillingYear = 0,
  int startBillingMonth = 0,
}) {
  final missing = <DateTime>[];
  var cursor = EnergyForecaster.getPreviousCycleStart(
      EnergyForecaster.getCycleStart(DateTime.now(), billingDay), billingDay);
  const maxLookback = 24; // กันลูปยาวเกินไปถ้าข้อมูล user ผิดปกติ
  for (var i = 0; i < maxLookback; i++) {
    if (startBillingYear != 0 &&
        (cursor.year < startBillingYear ||
            (cursor.year == startBillingYear &&
                cursor.month < startBillingMonth))) {
      break;
    }
    if (!takenAnySource.contains('${cursor.year}-${cursor.month}')) {
      missing.add(cursor);
    }
    cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
  }
  return missing;
}

// วิดเจ็ตหัวข้อย่อยที่ใช้ร่วมกันใน info popup หลายหน้า (ใช้ไอคอนจริงแทน
// อิโมจิ เพื่อความสม่ำเสมอกันทั้งแอป)
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

// กล่องข้อควรระวัง
Widget _infoWarningBox(String text) {
  return Container(
    padding: const EdgeInsets.all(AppSpacing.v10),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.v10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                fontSize: AppTypography.s12_5, height: 1.5, color: Colors.orange.shade900),
          ),
        ),
      ],
    ),
  );
}

// ==================== รายการบิลย้อนหลัง (แก้ไข/ลบได้) ====================
// อธิบายภาพรวมของหน้าไว้ที่ AppBar ของหน้ารายการเลย ไม่ต้องรอกดปุ่ม + ก่อนถึงจะเห็นคำอธิบาย
void _showHistoricalBillInfoPopup(BuildContext context) {
  showInfoDialog(
    context,
    title: 'หน้านี้ใช้ทำอะไร?',
    contentBuilder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'สำหรับเพิ่มบิลของเดือนก่อนๆ ที่ไม่มีข้อมูลในระบบ ไม่ว่าจะเป็นเดือน'
          'ก่อนเริ่มใช้แอป (กรอกได้สูงสุด 6 เดือนผ่านปุ่ม +) หรือเดือนที่ใช้แอป'
          'อยู่แล้วแต่ดันลืมบันทึกไปทั้งเดือน (ระบบจะโชว์เป็นแถว "(ยังไม่'
          'กรอก)" ให้กดกรอกได้เลย) เพื่อให้หน้าวิเคราะห์มีข้อมูลย้อนหลังไป'
          'เปรียบเทียบได้ครบถ้วน',
          style: TextStyle(fontSize: AppTypography.s13_5, height: 1.6),
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('กรอกยังไง'),
        const SizedBox(height: 4),
        const Text(
          'เปิดบิลค่าไฟ/ค่าน้ำเดือนนั้น แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
          '(kWh หรือ ลบ.ม.) กับ "ยอดเงิน" นำตัวเลขทั้งสองมากรอก',
          style: TextStyle(fontSize: AppTypography.s13_5, height: 1.6),
        ),
        const SizedBox(height: 12),
        _infoWarningBox(
          'กรอกยอดหน่วยที่ใช้จริงของเดือนนั้นเดือนเดียว ไม่ใช่เลขสะสม'
          'บนมิเตอร์ (ดูวิธีกรอกละเอียดได้จากไอคอน "!" ข้างช่องกรอก)',
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('เดือนที่ขึ้นว่า (ประมาณ)', icon: Icons.info_outline),
        const SizedBox(height: 4),
        const Text(
          'คือบิลที่ระบบปิดให้เองเมื่อจบรอบ โดยประมาณจากเลขมิเตอร์ที่บันทึกไว้'
          'จนถึงวันตัดรอบ กดที่แถวแล้วเลือกแก้ไข เพื่อใส่ยอดจากใบแจ้งหนี้จริงได้ค่ะ',
          style: TextStyle(fontSize: AppTypography.s13_5, height: 1.6),
        ),
      ],
    ),
  );
}


class HistoricalBillListScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const HistoricalBillListScreen({
    super.key,
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<HistoricalBillListScreen> createState() =>
      HistoricalBillListScreenState();
}

class HistoricalBillListScreenState
    extends State<HistoricalBillListScreen> with SingleTickerProviderStateMixin {
  List<BillModel> _bills = [];
  // เดือนที่ "ไม่มีบิลเลยไม่ว่า source ไหน" ย้อนไปจนถึงเดือนที่เริ่มใช้แอป — คือรอบที่
  // user ข้ามไปจริงๆ ไม่ได้เปิดแอปบันทึกเลยทั้งรอบ (ไม่ใช่แค่ยังไม่กรอกฟอร์มนี้)
  // ต่างจาก _bills ตรงที่ไม่มี Firestore doc รองรับจริง เป็นแค่ช่องว่างที่ตรวจพบ
  // ใน build() จะแปลงเป็น placeholder BillModel (source: 'missing') ชั่วคราว
  // เพื่อโชว์เป็นแถว "- -" ในตาราง กดแก้ไขได้เหมือนบิลปกติ
  List<DateTime> _missingMonths = [];
  bool _isLoading = true;
  int _billingDay = 30;
  UserModel? _user;
  late TabController _tabController;

  bool get _isTou => _user?.meterType == 'tou';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final user = await widget.firestoreService.getUser(widget.uid);
    // โชว์บิลทุกแหล่ง: กรอกเองในหน้านี้ (imported), มาจากหน้าเลขมิเตอร์ต้นรอบ
    // (startMeter — แก้/ลบตรงนี้ไม่ได้ ดู _isStartMeterBill) และระบบปิดให้จาก
    // บันทึกมิเตอร์ (compiled — แก้ทับเป็นยอดจากใบแจ้งหนี้ได้ ดู _isCompiledBill)
    // ชุดเดียวกับที่ฟอร์มใช้กันเดือนซ้ำ ปุ่ม (+) จึงตัดสินจากข้อมูลเดียวกัน
    final all = await widget.firestoreService.getBills(widget.uid);

    final billingDay = user?.billingDay ?? 30;
    // หาเดือนที่ "ไม่มีบิลเลย" ไล่ย้อนไปจนถึงเดือนเริ่มระบบ ไม่ใช่แค่ 5 เดือน
    // ล่าสุด (ดู _generateAllMissingMonths ด้านบนว่าทำไมถึงต้องไม่จำกัด)
    final takenAnySource = all.map((b) => '${b.year}-${b.month}').toSet();
    final missing = _generateAllMissingMonths(
      billingDay,
      takenAnySource,
      startBillingYear: user?.startBillingYear ?? 0,
      startBillingMonth: user?.startBillingMonth ?? 0,
    );

    if (mounted) {
      setState(() {
        _user = user;
        _billingDay = billingDay;
        _bills = all;
        _missingMonths = missing;
        _isLoading = false;
      });
    }
  }

  // เดือนของรอบปัจจุบัน (รอบเดียวกับหน้าเลขมิเตอร์ต้นรอบ) — ไม่ได้เกิดจากฟอร์มนี้
  // แต่โชว์ในลิสต์ตามปกติ กด "แก้ไข" ต้องพาไปฟอร์มที่ถูกต้องแทน
  bool _isCurrentCycleBill(BillModel bill) {
    final m = _generateHistoricalMonthOptions(_billingDay).first;
    return bill.year == m.year && bill.month == m.month;
  }

  // บิลที่มาจากหน้าเลขมิเตอร์ต้นรอบ แก้ไข/ลบตรงนี้ไม่ได้ เพราะจะทำให้ BillModel
  // กับ StartMeterRecordModel (เลขมิเตอร์สะสม) ไม่ตรงกัน ต้องไปจัดการที่หน้าเลขมิเตอร์ต้นรอบแทน
  bool _isStartMeterBill(BillModel bill) => bill.source == 'startMeter';

  // บิลที่ระบบปิดให้เมื่อจบรอบ (ประมาณจากบันทึกมิเตอร์ถึงวันตัดรอบ) — แก้ทับ
  // ด้วยยอดจากใบแจ้งหนี้ได้ แต่ไม่ให้ลบ เพราะเปิดหน้าหลักครั้งถัดไประบบจะ
  // ปิดบิลเดือนที่ว่างให้ใหม่
  bool _isCompiledBill(BillModel bill) => bill.source == 'compiled';

  // พาไปหน้า/ฟอร์มที่ถูกต้องสำหรับแก้ไขบิลที่มาจากเลขมิเตอร์ต้นรอบ — รอบปัจจุบัน
  // เปิดฟอร์มแก้ไขตรงๆ ได้เลย รอบเก่าที่ปิดไปแล้วคำนวณ delta ใหม่ไม่ถูกต้อง พาไปหน้าประวัติแทน
  Future<void> _goToStartMeterFor(BillModel bill) async {
    if (_isCurrentCycleBill(bill)) {
      await _openStartMeterSheet();
    } else {
      await openStartMeterSetup(
        context,
        widget.uid,
        widget.firestoreService,
        _user?.meterType == 'tou',
      );
      _load();
    }
  }

  // ปุ่ม (+) เพิ่มบิลได้แค่ 5 เดือนย้อนหลัง (ตัดเดือนของรอบปัจจุบันออกจาก
  // dropdown แล้ว ดู _generateMonthOptions) พอทุกเดือนมีบิลแล้ว (นับทุกแหล่ง
  // เหมือนฟอร์ม) ซ่อนปุ่ม เพราะกดไปก็จะเจอแค่ "มีบิลแล้ว" ทุกเดือน — แก้ไขของเดิมได้ตามปกติ
  bool get _allMonthOptionsRecorded {
    final options = _generateHistoricalMonthOptions(_billingDay).skip(1);
    final taken =
        _bills.map((b) => '${b.year}-${b.month}').toSet();
    return options
        .every((m) => taken.contains('${m.year}-${m.month}'));
  }

  Future<void> _openSheet({BillModel? existingBill}) async {
    // บิลของรอบปัจจุบันไม่ได้เกิดจากฟอร์มนี้ กด "แก้ไข" ต้องพาไปฟอร์มเลขมิเตอร์ต้นรอบตัวจริงแทน
    if (existingBill != null && _isCurrentCycleBill(existingBill)) {
      await _openStartMeterSheet();
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddHistoricalBillSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        existingBill: existingBill,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openStartMeterSheet() async {
    if (_user == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddStartMeterSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        isTou: _user!.meterType == 'tou',
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(BillModel bill) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบบิลนี้?',
      content: 'ต้องการลบบันทึกบิลของเดือน ${thaiMonths[bill.month - 1]} ${bill.year} ใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteBill(widget.uid, bill.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final latestId = _bills.isNotEmpty ? _bills.first.id : null;
    // แปลง _missingMonths เป็น placeholder BillModel ชั่วคราว (source: 'missing')
    // ไม่มี Firestore doc จริงรองรับ — สร้างขึ้นแค่ตอน build() เพื่อโชว์เป็นแถว
    // "- -" ในตาราง ผสมกับบิลจริงแล้วเรียงใหม่สุดก่อน
    final placeholderBills = _missingMonths
        .map((m) => BillModel(
              id: 'missing_${m.year}_${m.month}',
              uid: widget.uid,
              year: m.year,
              month: m.month,
              source: 'missing',
            ))
        .toList();
    final displayBills = [..._bills, ...placeholderBills]
      ..sort((a, b) => b.yearMonth.compareTo(a.yearMonth));
    // ทั้งสองแท็บแสดงทุกแถว (placeholder ไม่รู้ว่าขาดฝั่งไหน อาจขาดทั้งคู่) แถวที่
    // ฝั่งนั้นยังไม่มียอดขึ้น "(ยังไม่กรอก)" — การ์ดสรุปนับเฉพาะเดือนที่มียอดฝั่งนั้นจริง
    final electricCount = _bills.where((b) => b.electricityCost > 0).length;
    final waterCount = _bills.where((b) => b.waterCost > 0).length;

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'เพิ่มบิลเดือนเก่าเข้าระบบ',
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHistoricalBillInfoPopup(context),
          ),
        ],
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DashboardStyles.primaryGreen))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — สไตล์เดียวกับแถบสรุปในหน้าประวัติมิเตอร์ไฟฟ้า/ประปา
                Builder(builder: (context) {
                  final isWater = _tabController.index == 1;
                  final accent = isWater ? Colors.blue : Colors.orange;
                  final icon = isWater ? Icons.water_drop : Icons.bolt;
                  final recordedCount = isWater ? waterCount : electricCount;
                  return Container(
                    margin: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.v16, vertical: AppSpacing.v14),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppSpacing.v14),
                      border: Border.all(color: accent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: accent, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          '$recordedCount เดือน',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: AppTypography.s13,
                          ),
                        ),
                        const Spacer(),
                        if (!_isLoading && _allMonthOptionsRecorded)
                          Text(
                            'ครบ 6 เดือนแล้ว',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: AppTypography.s14,
                            ),
                          ),
                      ],
                    ),
                  );
                }),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTable(
                        bills: displayBills,
                        latestId: latestId,
                        accent: Colors.orange,
                        unitLabel: 'หน่วยที่ใช้',
                        costLabel: 'ค่าไฟ',
                        emptyIcon: Icons.bolt,
                        usedOf: (b) => b.electricityUsed,
                        costOf: (b) => b.electricityCost,
                        isTouTable: _isTou,
                      ),
                      _buildTable(
                        bills: displayBills,
                        latestId: latestId,
                        accent: Colors.blue,
                        unitLabel: 'ลบ.ม.ที่ใช้',
                        costLabel: 'ค่าน้ำ',
                        emptyIcon: Icons.water_drop,
                        usedOf: (b) => b.waterUsed,
                        costOf: (b) => b.waterCost,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: (_isLoading || _allMonthOptionsRecorded)
          ? null
          : FloatingActionButton(
              onPressed: () => _openSheet(),
              backgroundColor: DashboardStyles.primaryGreen,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  // ใช้ร่วมกันทั้งแท็บไฟฟ้า/ประปา ต่างกันแค่สี, label คอลัมน์ และฟิลด์ที่ดึง
  Widget _buildTable({
    required List<BillModel> bills,
    required String? latestId,
    required Color accent,
    required String unitLabel,
    required String costLabel,
    required IconData emptyIcon,
    required double Function(BillModel) usedOf,
    required double Function(BillModel) costOf,
    // TOU: โชว์ On-Peak/Off-Peak แยกกันแทนคอลัมน์ "หน่วยที่ใช้" เดียว (เฉพาะแท็บไฟฟ้า)
    bool isTouTable = false,
  }) {
    final formatter = NumberFormat('#,##0.00');

    if (bills.isEmpty) {
      return excelTableEmptyState(
        icon: emptyIcon,
        message: 'ยังไม่มีบิลย้อนหลัง\nกดปุ่ม + เพื่อเพิ่มบิลของเดือนก่อนๆ',
      );
    }

    final columns = isTouTable
        ? const [
            ExcelTableColumn('เดือน ปี', align: TextAlign.left, flex: 3),
            ExcelTableColumn('On-Peak', flex: 2),
            ExcelTableColumn('Off-Peak', flex: 2),
            ExcelTableColumn('รวม', flex: 2),
            ExcelTableColumn('ค่าไฟ', flex: 2),
          ]
        : [
            const ExcelTableColumn('เดือน ปี', align: TextAlign.left, flex: 3),
            ExcelTableColumn(unitLabel, flex: 2),
            ExcelTableColumn(costLabel, flex: 2),
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v8, AppSpacing.v16, AppSpacing.v16),
      child: ExcelStyleTable(
        accent: accent,
        columns: columns,
        rowCount: bills.length,
        isLatest: (row) => bills[row].id == latestId,
        cellText: (row, col) {
          final b = bills[row];
          final missing = costOf(b) <= 0;
          if (isTouTable) {
            switch (col) {
              case 0:
                return '${thaiMonths[b.month - 1]} ${b.year}'
                    '${missing ? ' (ยังไม่กรอก)' : _isCompiledBill(b) ? ' (ประมาณ)' : ''}';
              case 1:
                return b.electricityPeakUsed > 0
                    ? formatter.format(b.electricityPeakUsed)
                    : '-';
              case 2:
                return b.electricityOffPeakUsed > 0
                    ? formatter.format(b.electricityOffPeakUsed)
                    : '-';
              case 3:
                // หน่วยที่ใช้ (รวม) = On-Peak + Off-Peak เสมอ (มาจาก electricityUsed
                // ตรงๆ ค่าเดียวกับที่หน้าวิเคราะห์ใช้)
                return b.electricityUsed > 0
                    ? formatter.format(b.electricityUsed)
                    : '-';
              default:
                return missing ? '-' : formatter.format(costOf(b));
            }
          }
          switch (col) {
            case 0:
              return '${thaiMonths[b.month - 1]} ${b.year}'
                  '${missing ? ' (ยังไม่กรอก)' : _isCompiledBill(b) ? ' (ประมาณ)' : ''}';
            case 1:
              final used = usedOf(b);
              return used > 0 ? formatter.format(used) : '-';
            default:
              return missing ? '-' : formatter.format(costOf(b));
          }
        },
        onRowTap: (row) {
          final b = bills[row];
          // รอบที่ตรวจพบว่าขาดหาย (ไม่มี log เลยทั้งรอบ) — ยังไม่มีบิลจริงให้ลบ
          // เปิดฟอร์มกรอกย้อนหลังได้เลย (เหมือนกดปุ่ม + แต่เลือกเดือนไว้ให้แล้ว)
          if (b.source == 'missing') {
            showTableRowActions(
              context,
              title: '${thaiMonths[b.month - 1]} ${b.year}',
              subtitle: 'ยังไม่ได้บันทึกข้อมูลเดือนนี้ค่ะ',
              onEdit: () => _openSheet(existingBill: b),
            );
            return;
          }
          // บิลที่มาจากหน้าเลขมิเตอร์ต้นรอบ (source == 'startMeter') แก้ไข/ลบตรงนี้ไม่ได้
          // (ดู _isStartMeterBill) — ล็อกไว้กันเปิดฟอร์มบันทึกบิลย้อนหลังแล้วคำนวณ delta ผิด
          // พาไปหน้าที่ถูกต้องผ่าน _goToStartMeterFor แทน
          if (_isStartMeterBill(b)) {
            showTableRowActions(
              context,
              title: '${thaiMonths[b.month - 1]} ${b.year}',
              subtitle: 'รวม ${formatter.format(b.totalCost)} บาท',
              locked: true,
              lockedMessage: 'บิลนี้มาจากการตั้งเลขมิเตอร์ต้นรอบ '
                  'แก้ไข/ลบได้ที่หน้า "เลขมิเตอร์จากใบแจ้งหนี้" เท่านั้น เพื่อไม่ให้'
                  'เลขมิเตอร์สะสมกับบิลไม่ตรงกัน',
              lockedActionLabel: 'ไปหน้าเลขมิเตอร์จากใบแจ้งหนี้',
              onLockedAction: () => _goToStartMeterFor(b),
            );
            return;
          }
          // บิลที่ระบบปิดให้ — แก้ทับเป็นยอดจากใบแจ้งหนี้ได้ (บันทึกแล้วกลายเป็น
          // บิลที่กรอกเอง) แต่ไม่มีปุ่มลบ (ดู _isCompiledBill)
          if (_isCompiledBill(b)) {
            showTableRowActions(
              context,
              title: '${thaiMonths[b.month - 1]} ${b.year}',
              subtitle: 'รวม ${formatter.format(b.totalCost)} บาท • ระบบปิดบิลให้'
                  'จากบันทึกมิเตอร์ (ประมาณถึงวันตัดรอบ) กดแก้ไขเพื่อใส่ยอด'
                  'จากใบแจ้งหนี้จริงได้ค่ะ',
              onEdit: () => _openSheet(existingBill: b),
            );
            return;
          }
          showTableRowActions(
            context,
            title: '${thaiMonths[b.month - 1]} ${b.year}',
            subtitle: 'รวม ${formatter.format(b.totalCost)} บาท',
            onEdit: () => _openSheet(existingBill: b),
            onDelete: () => _confirmDelete(b),
          );
        },
      ),
    );
  }
}