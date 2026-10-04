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

class _StartMeterHistoryScreenState extends State<_StartMeterHistoryScreen>
    with SingleTickerProviderStateMixin {
  List<StartMeterRecordModel> _records = [];
  // ค่าไฟ/ค่าน้ำของแต่ละรอบ ดึงจาก BillModel (source: startMeter) แยกเก็บจาก StartMeterRecordModel จับคู่กันด้วยเดือน/ปี
  List<BillModel> _bills = [];
  UserModel? _user;
  bool _isLoading = true;
  late TabController _tabController;

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
      backgroundColor: Colors.transparent,
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

  @override
  Widget build(BuildContext context) {
    // ใช้รอบล่าสุด (index 0 ของ _records ก่อนกรองแยกไฟ/น้ำ) ไฮไลต์แถวว่าเป็นรอบปัจจุบัน
    final latestId = _records.isNotEmpty ? _records.first.id : null;

    final electricRecords = _records;
    final waterRecords = _records;

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'เลขมิเตอร์จากใบแจ้งหนี้',
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showStartMeterInfoPopup(context),
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
          ? const Center(child: CircularProgressIndicator(color: DashboardStyles.primaryGreen))
          : Column(
              children: [
                // การ์ดสรุปด้านบน แยกแสดงตามแท็บที่เลือก (ไฟฟ้า/ประปา)
                Builder(builder: (context) {
                  final isWater = _tabController.index == 1;
                  final accent = isWater ? Colors.blue : Colors.orange;
                  final icon = isWater ? Icons.water_drop : Icons.bolt;
                  final tabRecords = isWater ? waterRecords : electricRecords;
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
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
                          '${tabRecords.length} รอบบิล',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: AppTypography.s13,
                          ),
                        ),
                        const Spacer(),
                        if (tabRecords.isNotEmpty)
                          Text(
                            'ล่าสุด ${thaiMonths[tabRecords.first.billingMonth - 1]}',
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
                        records: electricRecords,
                        latestId: latestId,
                        accent: Colors.orange,
                        unitLabel: 'หน่วยสะสม',
                        emptyIcon: Icons.bolt,
                        valueOf: (r) => r.electricityValue,
                        isTouTable: widget.isTou,
                        isElectricity: true,
                      ),
                      _buildTable(
                        records: waterRecords,
                        latestId: latestId,
                        accent: Colors.blue,
                        unitLabel: 'ลบ.ม.สะสม',
                        emptyIcon: Icons.water_drop,
                        valueOf: (r) => r.waterValue,
                        isElectricity: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: (_isLoading || _currentCycleConfigured)
          ? null
          : FloatingActionButton(
              onPressed: _openSheet,
              backgroundColor: DashboardStyles.primaryGreen,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  // ใช้ร่วมกันทั้งแท็บไฟฟ้า/ประปา ต่างกันแค่สี, label คอลัมน์ และฟิลด์ที่ดึง
  // ไม่มีคอลัมน์ค่าไฟ/ค่าน้ำ — หน้านี้คือเลขมิเตอร์สะสม ค่าใช้จ่ายไปโชว์ที่หน้าบันทึกบิลย้อนหลังแทน
  Widget _buildTable({
    required List<StartMeterRecordModel> records,
    required String? latestId,
    required Color accent,
    required String unitLabel,
    required IconData emptyIcon,
    required double Function(StartMeterRecordModel) valueOf,
    // มิเตอร์ TOU ไม่เคยเซ็ต electricityValue (ใช้ peakValue/offPeakValue) จึงแยกตารางเป็น On-Peak/Off-Peak คนละคอลัมน์ (เฉพาะตารางไฟฟ้า)
    bool isTouTable = false,
    required bool isElectricity,
  }) {
    final formatter = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd/MM/yyyy, HH:mm');

    if (records.isEmpty) {
      return excelTableEmptyState(
        icon: emptyIcon,
        message: 'ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ',
      );
    }

    final columns = isTouTable
        ? const [
            ExcelTableColumn('เดือน ปี', align: TextAlign.left, flex: 3),
            ExcelTableColumn('On-Peak', flex: 2),
            ExcelTableColumn('Off-Peak', flex: 2),
            ExcelTableColumn('หน่วยสะสม', flex: 2),
          ]
        : [
            const ExcelTableColumn('เดือน ปี', align: TextAlign.left, flex: 3),
            ExcelTableColumn(unitLabel, flex: 2),
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ExcelStyleTable(
        accent: accent,
        columns: columns,
        rowCount: records.length,
        isLatest: (row) => records[row].id == latestId,
        cellText: (row, col) {
          final r = records[row];
          if (isTouTable) {
            final missing = r.peakValue <= 0 && r.offPeakValue <= 0;
            switch (col) {
              case 0:
                return '${thaiMonths[r.billingMonth - 1]} ${r.billingYear}'
                    '${missing ? ' (ยังไม่ได้กรอกข้อมูล)' : ''}';
              case 1:
                return r.peakValue <= 0 ? '-' : formatter.format(r.peakValue);
              case 2:
                return r.offPeakValue <= 0
                    ? '-'
                    : formatter.format(r.offPeakValue);
              default:
                final total = r.peakValue + r.offPeakValue;
                return total <= 0 ? '-' : formatter.format(total);
            }
          }
          final missing = valueOf(r) <= 0;
          switch (col) {
            case 0:
              return '${thaiMonths[r.billingMonth - 1]} ${r.billingYear}'
                  '${missing ? ' (ยังไม่ได้กรอกข้อมูล)' : ''}';
            default:
              return missing ? '-' : formatter.format(valueOf(r));
          }
        },
        onRowTap: (row) {
          final r = records[row];
          // เช็คด้วย billingMonth/Year ของ record เทียบกับ user.startBillingMonth/
          // Year ตรงๆ (ไม่ผูกกับวันที่ตามปฏิทิน/billingDay) เพื่อให้สะท้อนว่า "นี่คือ
          // record ที่ค่า start ใน user document อ้างอิงอยู่จริงไหม" — ถ้าเช็คกับ
          // "รอบที่ควรจะเป็นตอนนี้" การรีเซ็ตค่าใน user document ตอนลบอาจถูกข้าม
          // (เช่น billingDay เพิ่งเปลี่ยน) ทั้งที่ record ถูกลบไปแล้ว เหลือ
          // startMeterConfigured/startElectricityValue ค้างแบบไม่มี record รองรับ
          final isCurrentCycleRow = _user != null &&
              r.billingMonth == _user!.startBillingMonth &&
              r.billingYear == _user!.startBillingYear;
          showTableRowActions(
            context,
            title: 'ต้นรอบ ${thaiMonths[r.billingMonth - 1]} ${r.billingYear}',
            subtitle: 'บันทึกเมื่อ ${dateFormatter.format(r.recordedAt)}',
            // แก้ไข/ล้างค่าได้เฉพาะรอบปัจจุบัน รอบเก่าคำนวณ delta ใหม่ให้ไม่ถูกต้อง จึงลบได้อย่างเดียว
            onEdit: isCurrentCycleRow ? _openSheet : null,
            onDelete: () => _confirmDelete(
              r,
              isCurrentCycleRow: isCurrentCycleRow,
              isElectricity: isElectricity,
            ),
          );
        },
      ),
    );
  }
}
