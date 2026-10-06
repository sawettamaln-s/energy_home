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
          'ก่อนเริ่มใช้แอป (กรอกได้ 5 เดือนย้อนหลังผ่านปุ่ม "เพิ่มบิลย้อนหลัง") '
          'หรือเดือนที่ใช้แอปอยู่แล้วแต่ลืมบันทึกไปทั้งเดือน (ระบบจะโชว์เป็นแถว '
          '"ยังไม่กรอก" ให้กดกรอกได้เลย) เพื่อให้หน้าวิเคราะห์มีข้อมูลย้อนหลังไป'
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
          'บนมิเตอร์ (ดูตัวอย่างได้จากปุ่ม "ดูตำแหน่งในบิล" ในฟอร์ม)',
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('เดือนที่มีป้าย "ประมาณ"', icon: Icons.info_outline),
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

class HistoricalBillListScreenState extends State<HistoricalBillListScreen> {
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

  bool get _isTou => _user?.meterType == 'tou';

  @override
  void initState() {
    super.initState();
    _load();
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
      useSafeArea: true,
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
      useSafeArea: true,
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
      content: 'ต้องการลบบันทึกบิลของเดือน ${_monthYearLabel(bill.month, bill.year)} ใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteBill(widget.uid, bill.id);
      _load();
    }
  }

  // ---- มุมมองตาราง (UI state ล้วนๆ) ----
  bool _showWater = false;
  bool _newestFirst = true;
  // ปีที่กางอยู่ — null = ยังไม่เคยแตะ ใช้ค่าเริ่มต้นคือกางเฉพาะปีล่าสุด
  Set<int>? _expandedYears;

  String _shortMonthYear(int month, int year) => '${thaiMonthsShort[month - 1]} ${(year + 543) % 100}';

  @override
  Widget build(BuildContext context) {
    // แปลง _missingMonths เป็น placeholder BillModel ชั่วคราว (source: 'missing')
    // ไม่มี Firestore doc จริงรองรับ — สร้างขึ้นแค่ตอน build() เพื่อโชว์เป็นแถว
    // "ยังไม่กรอก" ในตาราง กดแล้วเปิดฟอร์มกรอกเดือนนั้น
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
      ..sort((a, b) => _newestFirst ? b.yearMonth.compareTo(a.yearMonth) : a.yearMonth.compareTo(b.yearMonth));

    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'บิลย้อนหลัง'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
              children: [
                FadeSlideIn(child: _buildSummaryCard(placeholderBills)),
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
                            fontFamily: AppTheme.fontFamily,
                            fontSize: AppTypography.s12_5,
                            fontWeight: FontWeight.w600),
                      ),
                      icon: Icon(_newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 16),
                      label: Text(_newestFirst ? 'ใหม่ → เก่า' : 'เก่า → ใหม่'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.v8),
                _utilityToggle(),
                const SizedBox(height: AppSpacing.v12),
                if (displayBills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.v24),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: AppSpacing.v8),
                        Text('ยังไม่มีบิลย้อนหลัง',
                            style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                else
                  ..._buildYearSections(displayBills),
              ],
            ),
    );
  }

  // การ์ดบนสุด: มีบิลกี่เดือน ย้อนไปถึงเดือนไหน เดือนที่ขาด (ถ้ามี) และปุ่มเพิ่มบิล
  Widget _buildSummaryCard(List<BillModel> missing) {
    final realBills = _bills;
    final oldest = realBills.isEmpty ? null : realBills.reduce((a, b) => a.yearMonth < b.yearMonth ? a : b);
    final canAdd = !_allMonthOptionsRecorded;
    final missingSorted = [...missing]..sort((a, b) => b.yearMonth.compareTo(a.yearMonth));

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.inventory_2_outlined, color: AppColors.primaryGreen, size: 40),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('มีบิลในระบบ ${realBills.length} เดือน',
                        style: const TextStyle(
                            fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    Text(
                      oldest == null
                          ? 'เพิ่มบิลเดือนก่อนๆ เพื่อให้กราฟและการคาดการณ์แม่นขึ้นค่ะ'
                          : 'ย้อนหลังถึง ${_monthYearLabel(oldest.month, oldest.year)}',
                      style: TextStyle(fontSize: AppTypography.s12_5, height: 1.4, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _pageInfoButton(
                tooltip: 'หน้านี้ใช้ทำอะไร',
                onPressed: () => _showHistoricalBillInfoPopup(context),
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
                      '${missingSorted.map((b) => _shortMonthYear(b.month, b.year)).join(', ')}',
                      style: const TextStyle(
                          fontSize: AppTypography.s12_5, height: 1.4, color: AppColors.warningText),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.v8),
                  TextButton(
                    onPressed: () => _openSheet(existingBill: missingSorted.first),
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
          const SizedBox(height: AppSpacing.v12),
          if (canAdd)
            ElevatedButton.icon(
              onPressed: () => _openSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('เพิ่มบิลย้อนหลัง'),
            )
          else
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primaryGreen),
                const SizedBox(width: AppSpacing.v6),
                Expanded(
                  child: Text('มีบิลครบ 5 เดือนล่าสุดแล้ว แก้ไขบิลแต่ละเดือนได้จากตารางด้านล่าง',
                      style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade700)),
                ),
              ],
            ),
        ],
      ),
    );
  }

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

  double _costOf(BillModel b) => _showWater ? b.waterCost : b.electricityCost;
  double _usedOf(BillModel b) => _showWater ? b.waterUsed : b.electricityUsed;
  Color get _accent => _showWater ? AppColors.waterBorder : AppColors.electricityBorder;

  List<Widget> _buildYearSections(List<BillModel> bills) {
    final groups = <int, List<BillModel>>{};
    for (final b in bills) {
      groups.putIfAbsent(b.year, () => []).add(b);
    }
    final expanded = _expandedYears ?? {bills.map((b) => b.year).reduce((a, b) => a > b ? a : b)};
    return [
      for (final entry in groups.entries) ...[
        _yearHeader(entry.key, entry.value, isOpen: expanded.contains(entry.key), onTap: () {
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
                        for (final b in entry.value) ...[
                          const Divider(),
                          _tableRow(b),
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

  // หัวปี (กดเพื่อพับ/กาง) + สรุปของปีนั้นเฉพาะเดือนที่มียอดของยูทิลิตี้ที่กำลังดู
  Widget _yearHeader(int year, List<BillModel> bills, {required bool isOpen, required VoidCallback onTap}) {
    final withCost = bills.where((b) => _costOf(b) > 0).toList();
    final total = withCost.fold<double>(0, (s, b) => s + _costOf(b));
    final baht = NumberFormat('#,##0');
    return Material(
      color: isOpen ? Colors.transparent : Colors.white,
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
                    Text(
                      withCost.isEmpty
                          ? '${bills.length} เดือน'
                          : '${withCost.length} เดือน · รวม ${baht.format(total)} บาท',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                    ),
                    if (withCost.isNotEmpty)
                      Text('เฉลี่ย ${baht.format(total / withCost.length)} บาท/เดือน',
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

  static const double _monthColWidth = 72;
  static const double _costColWidth = 96;

  Widget _tableHeader() {
    final style = TextStyle(fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v10, 36, AppSpacing.v10),
      child: Row(
        children: [
          SizedBox(width: _monthColWidth, child: Text('เดือน', style: style)),
          Expanded(child: Text('ใช้ไป (${_showWater ? 'ลบ.ม.' : 'หน่วย'})', style: style)),
          SizedBox(width: _costColWidth, child: Text('ยอดเงิน (บาท)', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }

  Widget _tableRow(BillModel b) {
    final fmt = NumberFormat('#,##0.##');
    final money = NumberFormat('#,##0.00');
    final isMissing = b.source == 'missing';
    final cost = _costOf(b);
    final used = _usedOf(b);
    final notFilled = isMissing || cost <= 0;
    final muted = TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade400);

    // ป้ายที่มาใต้ชื่อเดือน: ยังไม่กรอก / ประมาณ (ระบบปิดบิลให้) / ใบแจ้งหนี้
    // (ทั้งที่กรอกในหน้านี้และจากหน้าเลขมิเตอร์ — แบบหลังแยกด้วยไอคอนกุญแจท้ายแถว)
    final String sourceLabel;
    Color sourceColor = Colors.grey.shade600;
    if (notFilled) {
      sourceLabel = 'ยังไม่กรอก';
      sourceColor = AppColors.warningText;
    } else if (_isCompiledBill(b)) {
      sourceLabel = 'ประมาณ';
      sourceColor = AppColors.warningIcon;
    } else {
      sourceLabel = 'ใบแจ้งหนี้';
    }

    Widget usedCell;
    if (used <= 0) {
      usedCell = Text('–', style: muted);
    } else if (!_showWater && _isTou && (b.electricityPeakUsed > 0 || b.electricityOffPeakUsed > 0)) {
      usedCell = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fmt.format(used),
              style: const TextStyle(
                  fontSize: AppTypography.s14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Text('On ${fmt.format(b.electricityPeakUsed)} · Off ${fmt.format(b.electricityOffPeakUsed)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
        ],
      );
    } else {
      usedCell = Text(fmt.format(used),
          style: const TextStyle(
              fontSize: AppTypography.s14,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
              fontFeatures: [FontFeature.tabularFigures()]));
    }

    final IconData trailing;
    if (isMissing) {
      trailing = Icons.add_circle_outline_rounded;
    } else if (_isStartMeterBill(b)) {
      trailing = Icons.lock_outline_rounded;
    } else {
      trailing = Icons.chevron_right_rounded;
    }

    return InkWell(
      onTap: () => _onRowTap(b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
        child: Row(
          children: [
            SizedBox(
              width: _monthColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(thaiMonthsShort[b.month - 1],
                      style: TextStyle(
                          fontSize: AppTypography.s14,
                          fontWeight: FontWeight.w600,
                          color: notFilled ? Colors.grey.shade500 : AppColors.textDark)),
                  Text(sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.s10_5, fontWeight: FontWeight.w600, color: sourceColor)),
                ],
              ),
            ),
            Expanded(child: usedCell),
            SizedBox(
              width: _costColWidth,
              child: notFilled
                  ? Text('–', textAlign: TextAlign.end, style: muted)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(money.format(cost),
                          style: TextStyle(
                              fontSize: AppTypography.s14,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
            ),
            SizedBox(
              width: 28,
              child: Icon(trailing,
                  size: trailing == Icons.chevron_right_rounded ? 20 : 16,
                  color: isMissing ? AppColors.warningIcon : Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  void _onRowTap(BillModel b) {
    final money = NumberFormat('#,##0.00');
    final title = _monthYearLabel(b.month, b.year);
    // รอบที่ตรวจพบว่าขาดหาย (ไม่มีบิลเลย) — เปิดฟอร์มกรอกเดือนนั้นได้เลย
    if (b.source == 'missing') {
      showTableRowActions(
        context,
        title: title,
        subtitle: 'ยังไม่ได้บันทึกบิลเดือนนี้ค่ะ',
        onEdit: () => _openSheet(existingBill: b),
      );
      return;
    }
    // บิลที่มาจากหน้าเลขมิเตอร์ต้นรอบ แก้ไข/ลบตรงนี้ไม่ได้ (ดู _isStartMeterBill)
    if (_isStartMeterBill(b)) {
      showTableRowActions(
        context,
        title: title,
        subtitle: 'รวม ${money.format(b.totalCost)} บาท',
        locked: true,
        lockedMessage: 'บิลนี้มาจากการตั้งเลขมิเตอร์ต้นรอบ '
            'แก้ไข/ลบได้ที่หน้า "เลขมิเตอร์จากใบแจ้งหนี้" เท่านั้น เพื่อไม่ให้'
            'เลขมิเตอร์สะสมกับบิลไม่ตรงกัน',
        lockedActionLabel: 'ไปหน้าเลขมิเตอร์จากใบแจ้งหนี้',
        onLockedAction: () => _goToStartMeterFor(b),
      );
      return;
    }
    // บิลที่ระบบปิดให้ — แก้ทับเป็นยอดจากใบแจ้งหนี้ได้ แต่ไม่มีปุ่มลบ (ดู _isCompiledBill)
    if (_isCompiledBill(b)) {
      showTableRowActions(
        context,
        title: title,
        subtitle: 'รวม ${money.format(b.totalCost)} บาท • ระบบปิดบิลให้จากบันทึกมิเตอร์ '
            '(ประมาณถึงวันตัดรอบ) กดแก้ไขเพื่อใส่ยอดจากใบแจ้งหนี้จริงได้ค่ะ',
        onEdit: () => _openSheet(existingBill: b),
      );
      return;
    }
    showTableRowActions(
      context,
      title: title,
      subtitle: 'รวม ${money.format(b.totalCost)} บาท',
      onEdit: () => _openSheet(existingBill: b),
      onDelete: () => _confirmDelete(b),
    );
  }
}
