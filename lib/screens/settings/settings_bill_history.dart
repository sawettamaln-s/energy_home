part of 'settings_screen.dart';

// สร้างตัวเลือก 6 เดือนย้อนหลัง อิงวันตัดรอบบิลจริง (billingDay) ไม่ใช่เดือนปฏิทิน
// เป็นฟังก์ชันกลาง ให้ HistoricalBillListScreen เรียกใช้เช็ค "ครบ 6 เดือนหรือยัง" ได้ด้วย
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
// เดียวกับที่ backfill loop ใน dashboard_screen.dart ใช้ตรวจจับรอบที่ขาด ตั้งใจ
// ไม่จำกัดแค่ 6 เดือนแบบ _generateHistoricalMonthOptions (นั่นมีไว้จำกัดแค่ตอน
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

// ==================== เพิ่ม/แก้ไขบันทึกบิลย้อนหลัง ====================
// ไม่บังคับ • สูงสุด 6 เดือน — ใช้ให้หน้าวิเคราะห์มีข้อมูลตั้งแต่วันแรก
class _AddHistoricalBillSheet extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final BillModel? existingBill; // null = เพิ่มใหม่, ไม่ null = แก้ไขของเดิม

  const _AddHistoricalBillSheet({
    required this.uid,
    required this.firestoreService,
    this.existingBill,
  });

  @override
  State<_AddHistoricalBillSheet> createState() =>
      _AddHistoricalBillSheetState();
}

class _AddHistoricalBillSheetState extends State<_AddHistoricalBillSheet> {
  late List<DateTime> _monthOptions;
  late DateTime _selectedMonth;
  // แบ่งสัดส่วนไฟฟ้า/น้ำให้ชัดเจนแบบหน้า "บันทึกมิเตอร์ต้นรอบ" — 0 = ไฟฟ้า,
  // 1 = น้ำ (ดู StartMeterPairedFields ใน widgets/start_meter_fields.dart)
  int _selectedTab = 0;
  Set<String> _takenMonths = {}; // เก็บ 'year-month' ของเดือนที่มีบิลแล้ว
  bool _isLoadingTaken = true;
  bool _isSaving = false;
  // ยอด fixed cost ที่ active จริงของ _selectedMonth (ไม่ใช่ยอดวันนี้ที่ cache
  // ไว้ที่ user.fixedCost) — โหลดใหม่ทุกครั้งที่ _selectedMonth เปลี่ยน ดู
  // _loadFixedCostForSelectedMonth()
  double _fixedCostForSelectedMonth = 0;

  final _eUsedCtrl = TextEditingController();
  final _eCostCtrl = TextEditingController();
  final _wUsedCtrl = TextEditingController();
  final _wCostCtrl = TextEditingController();
  // TOU เท่านั้น: แยกช่อง On-Peak/Off-Peak แทน _eUsedCtrl ตัวเดียว แล้วรวมให้อัตโนมัติ
  final _ePeakUsedCtrl = TextEditingController();
  final _eOffPeakUsedCtrl = TextEditingController();
  // debounce ก่อนคำนวณค่าใช้จ่ายอัตโนมัติ กันเรียก getFtRate() (อ่าน Firestore) ทุกตัวอักษรที่พิมพ์
  Timer? _eCostDebounce;
  Timer? _wCostDebounce;

  // ส่วนเสริม: ชวนตั้งค่ามิเตอร์ต้นรอบต่อ — โหลด user เองเพื่อรู้ว่าเป็นมิเตอร์ TOU
  // ไหมและเคยตั้งค่าไปแล้วหรือยัง (ถ้าตั้งแล้วไม่โชว์ซ้ำ) กดแล้วเปิด _AddStartMeterSheet
  // ตัวจริงแยกต่างหาก ไม่ฝัง field ซ้ำในฟอร์มนี้ เพราะ "บันทึกของเดือนที่ผ่านไปแล้ว"
  // กับ "ตั้งค่าจุดเริ่มรอบหน้า" เป็นคนละเรื่องกัน ปนกันแล้ว validation จะไม่ครบ
  UserModel? _user;

  // ตัดรอบปัจจุบันออกจากตัวเลือก เหลือ 5 เดือนย้อนหลัง เพราะรอบปัจจุบันเก็บเป็น
  // เลขมิเตอร์สะสม ไม่มีทางรู้ "หน่วยที่ใช้" ที่แม่นจากฟอร์มนี้ — ให้ไปกรอกที่หน้า
  // เลขมิเตอร์ต้นรอบแทน (ดู _goSetStartMeter() ด้านล่าง)
  List<DateTime> _generateMonthOptions(int billingDay) =>
      _generateHistoricalMonthOptions(billingDay).skip(1).toList();

  @override
  void initState() {
    super.initState();
    final existing = widget.existingBill;
    // ใช้ billingDay = 30 เป็นค่าเริ่มต้นชั่วคราว จะแก้เป็นค่าจริงของ user ใน _loadUser()
    _monthOptions = _generateMonthOptions(30);
    // ถ้าแก้ไขบิลที่เดือนอยู่นอกช่วง 6 เดือนล่าสุด ให้เพิ่มเดือนนั้นเข้าไปในตัวเลือกด้วย
    if (existing != null &&
        !_monthOptions.any(
            (m) => m.year == existing.year && m.month == existing.month)) {
      _monthOptions.add(DateTime(existing.year, existing.month, 1));
    }
    // ต้องหยิบ DateTime ตัวจริงจาก _monthOptions มาใช้ (ไม่สร้างใหม่เอง) เพราะตัวเลือก
    // ใช้วันที่ = billingDay จริง (เช่น 10, 30) ไม่ใช่วันที่ 1 ถ้าสร้างเองจะไม่ match กัน
    // และ DropdownButtonFormField จะหา item ที่ตรงกับ value ไม่เจอ
    _selectedMonth = existing != null
        ? _monthOptions.firstWhere(
            (m) => m.year == existing.year && m.month == existing.month,
            orElse: () => DateTime(existing.year, existing.month, 1),
          )
        : _monthOptions.first;
    if (existing != null) {
      _eUsedCtrl.text = existing.electricityUsed == 0
          ? ''
          : existing.electricityUsed.toStringAsFixed(2);
      _ePeakUsedCtrl.text = existing.electricityPeakUsed == 0
          ? ''
          : existing.electricityPeakUsed.toStringAsFixed(2);
      _eOffPeakUsedCtrl.text = existing.electricityOffPeakUsed == 0
          ? ''
          : existing.electricityOffPeakUsed.toStringAsFixed(2);
      _eCostCtrl.text = existing.electricityCost == 0
          ? ''
          : existing.electricityCost.toStringAsFixed(2);
      _wCostCtrl.text =
          existing.waterCost == 0 ? '' : existing.waterCost.toStringAsFixed(2);
      _wUsedCtrl.text =
          existing.waterUsed == 0 ? '' : existing.waterUsed.toStringAsFixed(2);
    } else {
      // เพิ่มบิลใหม่: เซตค่าใช้จ่ายเป็น "0.00" ไว้ก่อนตั้งแต่เปิดฟอร์ม ไม่ปล่อยว่าง
      _eCostCtrl.text = '0.00';
      _wCostCtrl.text = '0.00';
    }
    _loadTakenMonths();
    _loadUser();
    _loadFixedCostForSelectedMonth();

    for (final c in [
      _eUsedCtrl,
      _eCostCtrl,
      _wUsedCtrl,
      _wCostCtrl,
      _ePeakUsedCtrl,
      _eOffPeakUsedCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }

    // คำนวณค่าใช้จ่ายอัตโนมัติทุกครั้งที่ "หน่วยที่ใช้" เปลี่ยน (กรอกหน่วยตรงๆ
    // ไม่ใช่เลขมิเตอร์สะสม จึงคำนวณได้ทันทีไม่ต้องหา delta) แก้ไขเองทับได้ ช่องไม่ถูก disable
    for (final c in [_eUsedCtrl, _ePeakUsedCtrl, _eOffPeakUsedCtrl]) {
      c.addListener(_scheduleElectricityCostCalc);
    }
    _wUsedCtrl.addListener(_scheduleWaterCostCalc);
  }

  void _scheduleElectricityCostCalc() {
    _eCostDebounce?.cancel();
    _eCostDebounce =
        Timer(const Duration(milliseconds: 400), _autoCalcElectricityCost);
  }

  void _scheduleWaterCostCalc() {
    _wCostDebounce?.cancel();
    _wCostDebounce =
        Timer(const Duration(milliseconds: 400), _autoCalcWaterCost);
  }

  // ยังไม่รู้ user (โหลดไม่เสร็จ) -> คำนวณไม่ได้ ปล่อยผ่าน ไม่แตะค่าใช้จ่ายเดิม
  Future<void> _autoCalcElectricityCost() async {
    if (_user == null) return;
    final units = _isTou ? 0.0 : parseNumInput(_eUsedCtrl.text);
    final peakUnits = _isTou ? parseNumInput(_ePeakUsedCtrl.text) : 0.0;
    final offPeakUnits = _isTou ? parseNumInput(_eOffPeakUsedCtrl.text) : 0.0;

    if (units <= 0 && peakUnits <= 0 && offPeakUnits <= 0) {
      if (mounted) setState(() => _eCostCtrl.text = '0.00');
      return;
    }

    final cost = await EnergyCalculator.calculateElectricityByType(
      units: units,
      meterType: _isTou ? 'tou' : 'normal',
      area: _user!.area,
      peakUnits: peakUnits,
      offPeakUnits: offPeakUnits,
    );
    if (!mounted) return;
    setState(() => _eCostCtrl.text = cost.toStringAsFixed(2));
  }

  // เหมือน _autoCalcElectricityCost() แต่ฝั่งน้ำ (calculateWater เป็น sync ไม่ต้อง await)
  void _autoCalcWaterCost() {
    if (_user == null) return;
    final units = parseNumInput(_wUsedCtrl.text);
    if (units <= 0) {
      setState(() => _wCostCtrl.text = '0.00');
      return;
    }
    final cost = EnergyCalculator.calculateWater(units, _user!.area);
    setState(() => _wCostCtrl.text = cost.toStringAsFixed(2));
  }

  Future<void> _loadUser() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    if (!mounted) return;

    // ถ้า billingDay จริงต่างจาก default (30) ให้สร้างตัวเลือกเดือนใหม่ด้วยค่าจริง
    if (user != null && user.billingDay != 30) {
      final existing = widget.existingBill;
      final rebuilt = _generateMonthOptions(user.billingDay);
      if (existing != null &&
          !rebuilt.any(
              (m) => m.year == existing.year && m.month == existing.month)) {
        rebuilt.add(DateTime(existing.year, existing.month, 1));
      }
      // ต้องปรับ _selectedMonth ให้ตรงกับ _monthOptions ชุดใหม่ใน setState เดียวกันนี้เลย
      // ไม่งั้น DropdownButtonFormField จะถือค่าเก่าที่ไม่มีใน options ชุดใหม่ แล้ว throw assertion
      final matchInRebuilt = rebuilt.firstWhere(
        (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
        orElse: () => rebuilt.first,
      );
      setState(() {
        _monthOptions = rebuilt;
        _selectedMonth = matchInRebuilt;
        _user = user;
      });
      // ตัวเลือกเปลี่ยนไปแล้ว ต้องคำนวณเดือนที่ยังว่างใหม่จากชุดตัวเลือกใหม่
      await _loadTakenMonths();
      // _selectedMonth อาจเปลี่ยนไปจากค่า default ตอน initState (billingDay=30)
      // มาเป็นค่าจริงแล้ว ต้องคำนวณ fixedCost ของเดือนนี้ใหม่ให้ตรง
      await _loadFixedCostForSelectedMonth();
    } else {
      setState(() => _user = user);
    }
  }

  @override
  void dispose() {
    _eCostDebounce?.cancel();
    _wCostDebounce?.cancel();
    _eUsedCtrl.dispose();
    _eCostCtrl.dispose();
    _wUsedCtrl.dispose();
    _wCostCtrl.dispose();
    _ePeakUsedCtrl.dispose();
    _eOffPeakUsedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTakenMonths() async {
    final bills = await widget.firestoreService.getBills(widget.uid);
    final taken = bills.map((b) => '${b.year}-${b.month}').toSet();
    // กำลังแก้ไขบิลเดือนนี้อยู่ → ไม่ถือว่าเดือนนี้ "ถูกจองแล้ว" สำหรับตัวมันเอง
    final existing = widget.existingBill;
    if (existing != null) {
      taken.remove('${existing.year}-${existing.month}');
    }

    // ถ้าเดือนแรก (ใหม่สุด) มีบิลแล้ว ให้เลื่อนไปเลือกเดือนแรกที่ยังว่างแทน
    // (เฉพาะตอนเพิ่มใหม่ — ตอนแก้ไขให้คงเดือนเดิมของบิลไว้)
    DateTime initialSelection = _selectedMonth;
    if (existing == null) {
      for (final m in _monthOptions) {
        if (!taken.contains('${m.year}-${m.month}')) {
          initialSelection = m;
          break;
        }
      }
    }

    if (mounted) {
      setState(() {
        _takenMonths = taken;
        _selectedMonth = initialSelection;
        _isLoadingTaken = false;
      });
      // initialSelection อาจต่างจาก _selectedMonth เดิม (เลื่อนไปเดือนว่างแรก)
      // ต้องคำนวณ fixedCost ของเดือนที่เลือกจริงใหม่เสมอ
      await _loadFixedCostForSelectedMonth();
    }
  }

  // คำนวณยอด fixed cost ที่ active จริงใน _selectedMonth (ไม่ใช่ user.fixedCost
  // ที่เป็น cache ของ "วันนี้" เท่านั้น) — เรียกใหม่ทุกครั้งที่ _selectedMonth
  // เปลี่ยน (เลือกเดือนใหม่จาก dropdown, หรือถูกปรับโดย _loadUser/_loadTakenMonths)
  Future<void> _loadFixedCostForSelectedMonth() async {
    final amount = await widget.firestoreService
        .calcFixedCostForMonth(widget.uid, _selectedMonth);
    if (!mounted) return;
    setState(() => _fixedCostForSelectedMonth = amount);
  }

  // เปิดฟอร์มตั้งเลขมิเตอร์ต้นรอบจริง (ตัวเดียวกับปุ่ม FAB ในหน้าประวัติมิเตอร์ต้นรอบ)
  // ปิด sheet นี้ก่อนแล้วค่อยเปิดตัวใหม่ (กัน backdrop ซ้อนกัน 2 ชั้น) — ถ้ากรอกข้อมูล
  // ไว้บ้างแล้ว (มีค่าไฟ/น้ำ) ให้ถามยืนยันก่อนทิ้งข้อมูล
  Future<void> _goSetStartMeter() async {
    if (_user == null) return;
    final hasUnsavedInput = _eUsedCtrl.text.isNotEmpty ||
        _eCostCtrl.text.isNotEmpty ||
        _wUsedCtrl.text.isNotEmpty ||
        _wCostCtrl.text.isNotEmpty ||
        _ePeakUsedCtrl.text.isNotEmpty ||
        _eOffPeakUsedCtrl.text.isNotEmpty;
    if (hasUnsavedInput) {
      final confirm = await showConfirmDialog(
        context,
        title: 'ยังไม่ได้บันทึกบิลเดือนนี้',
        content: 'ข้อมูลที่กรอกไว้ในฟอร์มนี้จะหายไป ต้องการออกไปตั้งเลข'
            'มิเตอร์ต้นรอบก่อนใช่ไหมคะ?',
      );
      if (confirm != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddStartMeterSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        isTou: _user!.meterType == 'tou',
      ),
    );
  }

  double get _eCost => parseNumInput(_eCostCtrl.text);
  double get _wCost => parseNumInput(_wCostCtrl.text);
  bool get _isTou => _user?.meterType == 'tou';
  // TOU: หน่วยที่ใช้ (ไฟ) = ผลรวม On-Peak/Off-Peak (auto-sum) แต่ยังเก็บลง
  // BillModel.electricityUsed ตัวเดียวเหมือนเดิม เพราะหน้าวิเคราะห์/แดชบอร์ดอ้างอิงยอดรวมนี้
  double get _eUsed => _isTou
      ? parseNumInput(_ePeakUsedCtrl.text) + parseNumInput(_eOffPeakUsedCtrl.text)
      : parseNumInput(_eUsedCtrl.text);
  // ผลรวมค่าไฟ+ค่าน้ำเท่านั้น (ไม่รวม fixedCost) — ใช้เช็คว่ากรอกข้อมูล
  // บิลมาหรือยัง (validation) และโชว์ยอดไฟ+น้ำแยกในพรีวิว
  double get _total => _eCost + _wCost;

  // totalCost ต้องรวม fixedCost ที่ active จริงในเดือนที่กำลังกรอก (ไม่ใช่
  // user.fixedCost ซึ่งเป็น cache ของ "วันนี้" เท่านั้น ไม่งั้นบิลย้อนหลังจะได้
  // fixedCost ผิดถ้ารายการเปลี่ยน/หมดอายุไปตั้งแต่เดือนนั้น) — โหลดจาก
  // _loadFixedCostForSelectedMonth()
  double get _fixedCost => _fixedCostForSelectedMonth;
  double get _totalWithFixedCost => _total + _fixedCost;

  bool get _isSelectedMonthTaken =>
      _takenMonths.contains('${_selectedMonth.year}-${_selectedMonth.month}');

  // เดือนของรอบปัจจุบัน — ตัดออกจาก _monthOptions แล้ว เก็บไว้แค่โชว์ในลิงก์ท้ายฟอร์ม
  // ให้กดไปกรอกที่หน้าเลขมิเตอร์ต้นรอบแทน (ดู _goSetStartMeter())
  DateTime get _currentCycleMonth =>
      _generateHistoricalMonthOptions(_user?.billingDay ?? 30).first;

  Future<void> _save() async {
    final isEditing = widget.existingBill != null;
    if (_isSelectedMonthTaken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เดือนนี้มีบิลบันทึกไว้แล้วค่ะ')),
      );
      return;
    }
    if (_total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกยอดค่าไฟหรือค่าน้ำอย่างน้อย 1 ช่องค่ะ')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final bill = BillModel(
        id: isEditing ? widget.existingBill!.id : const Uuid().v4(),
        uid: widget.uid,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
        electricityUsed: _eUsed,
        electricityPeakUsed:
            _isTou ? parseNumInput(_ePeakUsedCtrl.text) : 0,
        electricityOffPeakUsed:
            _isTou ? parseNumInput(_eOffPeakUsedCtrl.text) : 0,
        waterUsed: parseNumInput(_wUsedCtrl.text),
        electricityCost: _eCost,
        waterCost: _wCost,
        fixedCost: _fixedCost,
        totalCost: _totalWithFixedCost,
        // บิลย้อนหลังคือของจริงที่เกิดขึ้นแล้ว ไม่ใช่ค่าคาดการณ์
        forecastElectricity: _eCost,
        forecastWater: _wCost,
        forecastTotal: _totalWithFixedCost,
        source: 'imported',
      );
      await widget.firestoreService.saveBill(bill);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดบางอย่างค่ะ กรุณาลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _label(String text, {VoidCallback? onInfoTap}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.v8),
        child: Row(
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (onInfoTap != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onInfoTap,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DashboardStyles.primaryGreen.withValues(alpha: 0.12),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          fontSize: AppTypography.s10,
                          fontWeight: FontWeight.bold,
                          color: DashboardStyles.primaryGreen)),
                ),
              ),
            ],
          ],
        ),
      );

  // แท็บเลือกไฟฟ้า/น้ำ — ใช้ TabChip กลางร่วมกับ StartMeterPairedFields
  // เครื่องหมาย ✓ ขึ้นเมื่อฝั่งนั้นกรอกค่าใช้จ่ายแล้ว (cost > 0) เพราะฟอร์มนี้ไม่บังคับกรอกครบทั้งคู่
  Widget _buildUtilityTabs() {
    final eHasData = _eCost > 0;
    final wHasData = _wCost > 0;
    return Row(
      children: [
        Expanded(
          child: TabChip(
            label: 'ไฟฟ้า',
            icon: Icons.bolt,
            color: DashboardStyles.electricityBorder,
            selected: _selectedTab == 0,
            checked: eHasData,
            onTap: () => setState(() => _selectedTab = 0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TabChip(
            label: 'น้ำ',
            icon: Icons.water_drop,
            color: DashboardStyles.waterBorder,
            selected: _selectedTab == 1,
            checked: wHasData,
            onTap: () => setState(() => _selectedTab = 1),
          ),
        ),
      ],
    );
  }

  // การ์ดสีตามยูทิลิตี้ — สไตล์เดียวกับ _utilityCard ใน StartMeterPairedFields ให้ดูสอดคล้องกัน
  Widget _utilityCard({
    required String label,
    required Color accentColor,
    required IconData icon,
    required Widget child,
    VoidCallback? onInfoTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: DashboardStyles.accentCard(accentColor, radius: 14).copyWith(
        color: accentColor.withValues(alpha: 0.045),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.v6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: AppTypography.s14)),
              // ปุ่ม info อยู่ที่หัวการ์ดจุดเดียว (ไม่ผูกกับ label ช่อง "หน่วยที่ใช้"
              // เพราะฝั่งไฟฟ้าตอนเป็น TOU ใช้ TouPairedUnitsField แทน)
              if (onInfoTap != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onInfoTap,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.info_outline,
                        size: 12, color: accentColor),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // อธิบายว่าช่อง "หน่วยที่ใช้" ต้องกรอกยอดหน่วยที่ใช้จริงจากบิล ไม่ใช่เลขมิเตอร์สะสม
  // (ฟอร์มนี้ไม่ลบเลขมิเตอร์ 2 เดือนให้เหมือนหน้าบันทึกมิเตอร์ปกติ เพราะบิลย้อนหลังไม่ต่อเนื่องกันเสมอไป)
  // แนบ BillMockupCard (แบบเดียวกับ popup หน้าบันทึกมิเตอร์ประจำเดือน) แต่ตั้ง
  // highlightReading: false เพื่อล้อมกรอบเฉพาะช่อง "จำนวนหน่วยที่ใช้" อย่างเดียว
  // ไม่ล้อมช่องเลขอ่านครั้งหลัง เพราะฟอร์มนี้ห้ามกรอกเลขนั้นตามคำเตือนด้านล่าง
  // ถ้า _user ยังโหลดไม่เสร็จ (ไม่รู้ area/isTou จริง) จะไม่โชว์การ์ดมอคอัพ
  void _showUsageInfoPopup(
    String utilityLabel,
    String unitLabel, {
    required bool isElectricity,
  }) {
    final user = _user;
    showInfoDialog(
      context,
      title: 'กรอก "$utilityLabel" ตรงไหนของบิล?',
      contentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'เปิดบิลเดือนที่จะบันทึกย้อนหลัง แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
            'หรือ "$unitLabel" นำตัวเลขดังกล่าวมากรอกในช่องนี้',
            style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(AppSpacing.v10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.v10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ห้ามกรอก "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) เนื่องจากฟอร์มนี้'
                    'ไม่นำเลขมิเตอร์ของแต่ละเดือนมาลบกันให้เหมือนหน้าบันทึกมิเตอร์ปกติ '
                    'ระบบจะบันทึกเฉพาะยอดหน่วยที่ใช้จริงของเดือนนั้นเพื่อการวิเคราะห์ '
                    'หากกรอกเลขมิเตอร์สะสมแทน ข้อมูลในหน้าวิเคราะห์จะคลาดเคลื่อน',
                    style: TextStyle(
                        fontSize: AppTypography.s12_5,
                        height: 1.5,
                        color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 12),
            BillMockupCard(
              isElectricity: isElectricity,
              area: user.area,
              isTou: isElectricity && _isTou,
              highlightUsed: true,
              highlightReading: false,
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    String? hint,
    String? suffixText,
    IconData? icon,
    Color? iconColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      suffixText: suffixText,
      prefixIcon:
          icon == null ? null : Icon(icon, color: iconColor, size: 20),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.v10),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.v20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.v12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(AppSpacing.v2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      widget.existingBill != null
                          ? 'แก้ไขบิลเดือนเก่าเข้าระบบ'
                          : 'เพิ่มบิลเดือนเก่าเข้าระบบ',
                      style: const TextStyle(
                          fontSize: AppTypography.s18, fontWeight: FontWeight.bold),
                    ),
                    // ตัดคำอธิบายยาวใต้หัวข้อออก (ซ้ำกับ _showHistoricalBillInfoPopup)
                    // เหลือแค่ไอคอน info กดดูได้แทน ลดความรกตอนเปิดฟอร์มครั้งแรก
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.info_outline,
                          size: 18, color: Colors.grey.shade600),
                      onPressed: () => _showHistoricalBillInfoPopup(context),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.v16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('เดือน'),
                  _isLoadingTaken
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.v12),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : DropdownButtonFormField<DateTime>(
                          initialValue: _selectedMonth,
                          icon: const Icon(Icons.expand_more,
                              color: DashboardStyles.primaryGreen),
                          decoration: _fieldDecoration(
                            icon: Icons.calendar_month,
                            iconColor: DashboardStyles.primaryGreen,
                          ),
                          items: _monthOptions.map((d) {
                            final taken =
                                _takenMonths.contains('${d.year}-${d.month}');
                            return DropdownMenuItem(
                              value: d,
                              enabled: !taken,
                              child: Text(
                                taken
                                    ? '${thaiMonths[d.month - 1]} ${d.year} (มีบิลแล้ว)'
                                    : '${thaiMonths[d.month - 1]} ${d.year}',
                                style: TextStyle(
                                  color: taken ? Colors.grey.shade400 : null,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedMonth = val!);
                            _loadFixedCostForSelectedMonth();
                          },
                        ),
                  const SizedBox(height: 16),
                  _buildUtilityTabs(),
                  const SizedBox(height: 12),
                  if (_selectedTab == 0)
                    _utilityCard(
                      label: 'ไฟฟ้า',
                      accentColor: DashboardStyles.electricityBorder,
                      icon: Icons.bolt,
                      // info อยู่ที่หัวการ์ดจุดเดียว ใช้ได้ทั้ง TOU และไม่ใช่ TOU
                      onInfoTap: () => _showUsageInfoPopup(
                          'หน่วยที่ใช้เดือนนี้ (ไฟ)', 'kWh',
                          isElectricity: true),
                      child: _isTou
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TouPairedUnitsField(
                                  title: 'หน่วยที่ใช้เดือนนี้ (ไฟ)',
                                  peakCtrl: _ePeakUsedCtrl,
                                  offPeakCtrl: _eOffPeakUsedCtrl,
                                  iconColor: DashboardStyles.electricityBorder,
                                  // โน้ตนี้เห็นเฉพาะบิลเก่าก่อนมีฟิลด์แยก peak/offpeak
                                  // (มียอดรวมแต่แยกไม่ได้) ถ้าเคยกรอกแบบแยกไว้แล้วจะ prefill จาก
                                  // electricityPeakUsed/OffPeakUsed แทน ไม่ต้องมีโน้ตนี้
                                  helperText: (widget.existingBill != null &&
                                          widget.existingBill!.electricityUsed >
                                              0 &&
                                          widget.existingBill!
                                                  .electricityPeakUsed ==
                                              0 &&
                                          widget.existingBill!
                                                  .electricityOffPeakUsed ==
                                              0)
                                      ? 'ค่าเดิมที่เคยบันทึกไว้ '
                                          '${widget.existingBill!.electricityUsed.toStringAsFixed(0)} '
                                          'หน่วย (ยังไม่แยก On-Peak/Off-Peak) '
                                          '— กรอกใหม่แยกคู่ด้านบนเพื่อแทนที่ค่านี้'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                _label('ค่าไฟ'),
                                TextField(
                                  controller: _eCostCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: _fieldDecoration(
                                    hint: '0',
                                    suffixText: 'บาท',
                                    icon: Icons.receipt_long,
                                    iconColor: DashboardStyles.electricityBorder,
                                  ),
                                ),
                              ],
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 340;
                                final usedField = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('หน่วยที่ใช้เดือนนี้ (ไฟ)'),
                                    TextField(
                                      controller: _eUsedCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      decoration: _fieldDecoration(
                                        hint: 'เช่น 250',
                                        suffixText: 'หน่วย',
                                        icon: Icons.bar_chart,
                                        iconColor:
                                            DashboardStyles.electricityBorder,
                                      ),
                                    ),
                                  ],
                                );
                                final costField = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _label('ค่าไฟ'),
                                    TextField(
                                      controller: _eCostCtrl,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      decoration: _fieldDecoration(
                                        hint: '0',
                                        suffixText: 'บาท',
                                        icon: Icons.receipt_long,
                                        iconColor:
                                            DashboardStyles.electricityBorder,
                                      ),
                                    ),
                                  ],
                                );
                                if (narrow) {
                                  return Column(children: [
                                    usedField,
                                    const SizedBox(height: 10),
                                    costField,
                                  ]);
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: usedField),
                                    const SizedBox(width: 10),
                                    Expanded(child: costField),
                                  ],
                                );
                              },
                            ),
                    )
                  else
                    _utilityCard(
                      label: 'น้ำ',
                      accentColor: DashboardStyles.waterBorder,
                      icon: Icons.water_drop,
                      onInfoTap: () => _showUsageInfoPopup(
                          'หน่วยที่ใช้เดือนนี้ (น้ำ)', 'ลบ.ม.',
                          isElectricity: false),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 340;
                          final usedField = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('หน่วยที่ใช้เดือนนี้ (น้ำ)'),
                              TextField(
                                controller: _wUsedCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: _fieldDecoration(
                                  hint: 'เช่น 15',
                                  suffixText: 'หน่วย',
                                  icon: Icons.bar_chart,
                                  iconColor: DashboardStyles.waterBorder,
                                ),
                              ),
                            ],
                          );
                          final costField = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('ค่าน้ำ'),
                              TextField(
                                controller: _wCostCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: _fieldDecoration(
                                  hint: '0',
                                  suffixText: 'บาท',
                                  icon: Icons.receipt_long,
                                  iconColor: DashboardStyles.waterBorder,
                                ),
                              ),
                            ],
                          );
                          if (narrow) {
                            return Column(children: [
                              usedField,
                              const SizedBox(height: 10),
                              costField,
                            ]);
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: usedField),
                              const SizedBox(width: 10),
                              Expanded(child: costField),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  // ลิงก์ไปหน้าเลขมิเตอร์ต้นรอบเสมอ — เดือนของรอบปัจจุบันตัดออกจาก
                  // dropdown แล้ว (คนละแนวคิดกับฟอร์มนี้) โชว์เป็นลิงก์เล็กๆ เสมอ กดแก้ไขได้
                  // ไม่ว่าจะเคยตั้งมาก่อนแล้วหรือยัง
                  InkWell(
                    onTap: _goSetStartMeter,
                    borderRadius: BorderRadius.circular(AppSpacing.v8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v4),
                      child: Row(
                        children: [
                          Icon(Icons.speed,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'มีบิลของ${thaiMonths[_currentCycleMonth.month - 1]} '
                              '${_currentCycleMonth.year}? ไปกรอกที่หน้าเลขมิเตอร์ต้นรอบ',
                              style: TextStyle(
                                  fontSize: AppTypography.s11_5,
                                  color: Colors.grey.shade600,
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 16, color: Colors.grey.shade500),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.v16),
                    decoration: BoxDecoration(
                      color: DashboardStyles.primaryGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppSpacing.v12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ยอดรวมเดือนนี้',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${formatter.format(_totalWithFixedCost)} บาท',
                              style: const TextStyle(
                                fontSize: AppTypography.s18,
                                fontWeight: FontWeight.bold,
                                color: DashboardStyles.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        if (_fixedCost > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'ไฟ+น้ำ ${formatter.format(_total)} บาท '
                                '+ ค่าใช้จ่ายคงที่ ${formatter.format(_fixedCost)} บาท',
                                style: TextStyle(
                                  fontSize: AppTypography.s11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _isSelectedMonthTaken)
                          ? null
                          : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardStyles.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(widget.existingBill != null ? 'บันทึกการแก้ไข' : 'บันทึก'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          'อยู่แล้วแต่ดันลืมบันทึกไปทั้งเดือน (ระบบจะโชว์เป็นแถว "ยังไม่ได้'
          'บันทึก" ให้กดกรอกได้เลย) เพื่อให้หน้าวิเคราะห์มีข้อมูลย้อนหลังไป'
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
  // เดือนที่ "ไม่มีบิลเลยไม่ว่า source ไหน" ในช่วง 5 เดือนย้อนหลัง — คือรอบที่
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
    final all = await widget.firestoreService.getBills(widget.uid);
    // โชว์ทั้งบิลที่กรอกเองในหน้านี้ (imported) และบิลที่ auto-create มาจาก
    // หน้าเลขมิเตอร์ต้นรอบ (startMeter) — ตัวหลังแก้ไข/ลบตรงนี้ไม่ได้ (ดู _isStartMeterBill + onRowTap)
    final relevant = all
        .where((b) => b.source == 'imported' || b.source == 'startMeter')
        .toList();

    final billingDay = user?.billingDay ?? 30;
    // หาเดือนที่ "ไม่มีบิลเลย" เทียบกับบิลทุก source (รวม 'compiled' ด้วย ไม่ใช่
    // แค่ relevant) กันไม่ให้เดือนที่ระบบ compile ให้เองสำเร็จแล้วถูกเข้าใจผิดว่า
    // "ขาด" — ไล่ย้อนไปจนถึงเดือนเริ่มระบบ ไม่ใช่แค่ 5 เดือนล่าสุด (ดู
    // _generateAllMissingMonths ด้านบนว่าทำไมถึงต้องไม่จำกัด)
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
        _bills = relevant;
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

  // หน้านี้มีไว้กรอกบิลย้อนหลัง "ก่อนสมัครใช้แอป" เท่านั้น ขอบเขตแค่ 5 เดือน
  // (ตัดเดือนของรอบปัจจุบันออกจาก dropdown แล้ว ดู _generateMonthOptions) พอกรอกครบ
  // ซ่อนปุ่ม (+) เพราะกดไปก็จะเจอแค่ "เดือนนี้มีบิลบันทึกไว้แล้ว" ทุกเดือน — แก้ไข/ลบเดิมได้ตามปกติ
  bool get _allSixMonthsRecorded {
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
    // "- -" ในตาราง ผสมกับบิลจริงแล้วเรียงใหม่สุดก่อนเหมือนเดิม
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
    // รวม placeholder เข้าทั้งสองแท็บเสมอ (ไม่รู้ว่าขาดฝั่งไฟหรือน้ำ อาจขาดทั้งคู่)
    // ต่างจากบิลจริงที่กรองด้วย cost > 0 ตามปกติ เพื่อแยกว่าเดือนนั้นมีข้อมูลฝั่งไหนบ้าง
    final electricBills = displayBills
        .where((b) => b.electricityCost > 0 || b.source == 'missing')
        .toList();
    final waterBills = displayBills
        .where((b) => b.waterCost > 0 || b.source == 'missing')
        .toList();

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
                  final tabBills = isWater ? waterBills : electricBills;
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
                          '${tabBills.length} เดือน',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: AppTypography.s13,
                          ),
                        ),
                        const Spacer(),
                        if (!_isLoading && _allSixMonthsRecorded)
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
                        bills: _bills,
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
                        bills: _bills,
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
      floatingActionButton: (_isLoading || _allSixMonthsRecorded)
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
                    '${missing ? ' (ยังไม่กรอก)' : ''}';
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
                  '${missing ? ' (ยังไม่กรอก)' : ''}';
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
                  'แก้ไข/ลบได้ที่หน้า "เลขมิเตอร์ต้นรอบ" เท่านั้น เพื่อไม่ให้'
                  'เลขมิเตอร์สะสมกับบิลไม่ตรงกัน',
              lockedActionLabel: 'ไปหน้าเลขมิเตอร์ต้นรอบ',
              onLockedAction: () => _goToStartMeterFor(b),
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