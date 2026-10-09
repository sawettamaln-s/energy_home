part of 'settings_screen.dart';

// ==================== เพิ่ม/แก้ไขบันทึกบิลย้อนหลัง ====================
// ไม่บังคับ • เลือกได้ 5 เดือนย้อนหลัง (ไม่รวมรอบปัจจุบัน) — ใช้ให้หน้า
// วิเคราะห์มีข้อมูลตั้งแต่วันแรก
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
  // ข้อความผิดพลาดเหนือปุ่มบันทึก (null = ไม่มี) — ล้างเมื่อแก้ค่า/เปลี่ยนเดือน
  String? _error;
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
  // คำนวณค่าใช้จ่ายอัตโนมัติขณะพิมพ์ (ดู _CostAutofill)
  final _costAutofill = _CostAutofill();

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

  void _scheduleElectricityCostCalc() =>
      _costAutofill.scheduleElectricity(_autoCalcElectricityCost);

  void _scheduleWaterCostCalc() =>
      _costAutofill.scheduleWater(_autoCalcWaterCost);

  // ยังไม่รู้ user (โหลดไม่เสร็จ) -> คำนวณไม่ได้ ปล่อยผ่าน ไม่แตะค่าใช้จ่ายเดิม
  Future<void> _autoCalcElectricityCost() async {
    final user = _user;
    if (user == null) return;
    final text = await _CostAutofill.electricityText(
      user: user,
      isTou: _isTou,
      units: _isTou ? 0.0 : parseNumInput(_eUsedCtrl.text),
      peakUnits: _isTou ? parseNumInput(_ePeakUsedCtrl.text) : 0.0,
      offPeakUnits: _isTou ? parseNumInput(_eOffPeakUsedCtrl.text) : 0.0,
    );
    if (!mounted) return;
    setState(() => _eCostCtrl.text = text);
  }

  // เหมือน _autoCalcElectricityCost() แต่ฝั่งน้ำ (calculateWater เป็น sync ไม่ต้อง await)
  void _autoCalcWaterCost() {
    final user = _user;
    if (user == null) return;
    setState(() => _wCostCtrl.text =
        _CostAutofill.waterText(user, parseNumInput(_wUsedCtrl.text)));
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
    _costAutofill.dispose();
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

  // เปิดฟอร์มตั้งเลขมิเตอร์ต้นรอบจริง (ตัวเดียวกับการ์ดใบแจ้งหนี้ล่าสุดในหน้าเลขมิเตอร์จากใบแจ้งหนี้)
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
      useSafeArea: true,
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
  // TOU: หน่วยที่ใช้ (ไฟ) = ผลรวม On-Peak/Off-Peak (auto-sum) — บันทึกยอดรวม
  // ลง BillModel.electricityUsed (หน้าวิเคราะห์/แดชบอร์ดใช้ยอดรวมนี้) และเก็บ
  // แยกลง electricityPeakUsed/OffPeakUsed ด้วย
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
      setState(() => _error = 'เดือนนี้มีบิลบันทึกไว้แล้วค่ะ');
      return;
    }
    if (_total == 0) {
      setState(() => _error = 'กรุณากรอกยอดค่าไฟหรือค่าน้ำอย่างน้อย 1 ฝั่งค่ะ');
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
        source: 'imported',
      );
      await widget.firestoreService.saveBill(bill);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.v6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s13, color: AppColors.textDark)),
      );

  // แท็บเลือกไฟฟ้า/น้ำ — ใช้ TabChip กลางร่วมกับ StartMeterPairedFields
  // เครื่องหมาย ✓ ขึ้นเมื่อฝั่งนั้นกรอกค่าใช้จ่ายแล้ว (cost > 0) เพราะฟอร์มนี้ไม่บังคับกรอกครบทั้งคู่
  Widget _buildUtilityTabs() => UtilityTabChips(
        selectedIndex: _selectedTab,
        electricityDone: _eCost > 0,
        waterDone: _wCost > 0,
        onSelect: (i) => setState(() => _selectedTab = i),
      );

  // อธิบายว่าช่อง "หน่วยที่ใช้" ต้องกรอกยอดหน่วยที่ใช้จริงจากบิล ไม่ใช่เลขมิเตอร์สะสม
  // (ฟอร์มนี้ไม่ลบเลขมิเตอร์ 2 เดือนให้เหมือนหน้าบันทึกมิเตอร์ปกติ เพราะบิลย้อนหลังไม่ต่อเนื่องกันเสมอไป)
  // แนบ BillMockupCard ล้อมกรอบเฉพาะช่อง "จำนวนหน่วยที่ใช้" (highlightReading: false)
  // ถ้า _user ยังโหลดไม่เสร็จ (ไม่รู้ area/isTou จริง) จะไม่โชว์การ์ดมอคอัพ
  void _showUsageInfoPopup({required bool isElectricity}) {
    final user = _user;
    final unitLabel = isElectricity ? 'kWh' : 'ลบ.ม.';
    showInfoDialog(
      context,
      title: 'กรอกตรงไหนของบิล?',
      contentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'เปิดบิลเดือนที่จะบันทึกย้อนหลัง แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
            'หรือ "$unitLabel" และ "ยอดเงิน" นำตัวเลขมากรอก',
            style: const TextStyle(fontSize: AppTypography.s13_5, height: 1.6),
          ),
          const SizedBox(height: 12),
          _infoWarningBox(
            'ห้ามกรอก "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) เนื่องจากฟอร์มนี้'
            'ไม่นำเลขมิเตอร์ของแต่ละเดือนมาลบกันให้เหมือนหน้าบันทึกมิเตอร์ปกติ '
            'หากกรอกเลขมิเตอร์สะสมแทน ข้อมูลในหน้าวิเคราะห์จะคลาดเคลื่อน',
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

  InputDecoration _fieldDecoration({String? hint, String? suffixText, IconData? icon, Color? iconColor}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      suffixText: suffixText,
      prefixIcon: icon == null ? null : Icon(icon, color: iconColor, size: 20),
      filled: true,
      fillColor: Colors.white,
    );
  }

  // ปุ่มเลือกเดือน — เดือนที่มีบิลแล้ว (ทุกแหล่ง) กดไม่ได้ พร้อมป้าย "มีบิลแล้ว"
  Widget _monthChip(DateTime d) {
    final taken = _takenMonths.contains('${d.year}-${d.month}');
    final selected = !taken && d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    return Material(
      color: selected ? AppColors.primaryGreen : (taken ? Colors.grey.shade100 : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: selected ? AppColors.primaryGreen : Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: taken
            ? null
            : () {
                setState(() {
                  _selectedMonth = d;
                  _error = null;
                });
                _loadFixedCostForSelectedMonth();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}',
                  style: TextStyle(
                      fontSize: AppTypography.s13_5,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : (taken ? Colors.grey.shade400 : AppColors.textDark))),
              if (taken)
                Text('มีบิลแล้ว', style: TextStyle(fontSize: AppTypography.s10_5, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }

  // ช่องยอดเงิน — ระบบเติมให้จากหน่วยที่ใช้ (ดู _CostAutofill) แก้ตามบิลได้
  Widget _costField(TextEditingController controller, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('ยอดเงินตามใบแจ้งหนี้',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s13, color: AppColors.textDark)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8, vertical: AppSpacing.v2),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.v20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.primaryGreen),
                  SizedBox(width: 4),
                  Text('คิดให้อัตโนมัติ',
                      style: TextStyle(
                          fontSize: AppTypography.s11, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() => _error = null),
          decoration: _fieldDecoration(hint: '0.00', suffixText: 'บาท', icon: Icons.receipt_long, iconColor: accent),
        ),
        const SizedBox(height: 4),
        Text('คำนวณจากหน่วยที่ใช้ ถ้ายอดในใบแจ้งหนี้ต่างไป แก้ให้ตรงกับบิลได้เลยค่ะ',
            style: TextStyle(fontSize: AppTypography.s11_5, height: 1.4, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _usedField(TextEditingController controller, String unit, Color accent, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('หน่วยที่ใช้เดือนนี้'),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _fieldDecoration(hint: hint, suffixText: unit, icon: Icons.bar_chart, iconColor: accent),
        ),
        const SizedBox(height: 4),
        Text('ยอดหน่วยที่ใช้ของเดือนนี้ ไม่ใช่เลขสะสมบนมิเตอร์',
            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _utilityCard({required Color accent, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final existing = widget.existingBill;
    // ชีตหดตามคีย์บอร์ด ปุ่มบันทึกด้านล่างจึงอยู่เหนือคีย์บอร์ดเสมอ
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.9 - bottomInset;

    final electricity = _utilityCard(
      accent: DashboardStyles.electricityBorder,
      children: [
        if (_isTou)
          TouPairedUnitsField(
            title: 'หน่วยที่ใช้เดือนนี้',
            peakCtrl: _ePeakUsedCtrl,
            offPeakCtrl: _eOffPeakUsedCtrl,
            iconColor: DashboardStyles.electricityBorder,
            // โน้ตนี้เห็นเฉพาะบิลที่มียอดรวมแต่ไม่มีหน่วยแยก peak/offpeak ถ้าเคยกรอก
            // แบบแยกไว้แล้วจะ prefill จาก electricityPeakUsed/OffPeakUsed แทน
            helperText: (existing != null &&
                    existing.electricityUsed > 0 &&
                    existing.electricityPeakUsed == 0 &&
                    existing.electricityOffPeakUsed == 0)
                ? 'ค่าเดิมที่เคยบันทึกไว้ ${existing.electricityUsed.toStringAsFixed(0)} หน่วย '
                    '(ยังไม่แยก On-Peak/Off-Peak) — กรอกใหม่แยกคู่ด้านบนเพื่อแทนที่ค่านี้'
                : null,
          )
        else
          _usedField(_eUsedCtrl, 'หน่วย', DashboardStyles.electricityBorder, 'เช่น 250'),
        const SizedBox(height: 14),
        _costField(_eCostCtrl, DashboardStyles.electricityBorder),
      ],
    );
    final water = _utilityCard(
      accent: DashboardStyles.waterBorder,
      children: [
        _usedField(_wUsedCtrl, 'ลบ.ม.', DashboardStyles.waterBorder, 'เช่น 15'),
        const SizedBox(height: 14),
        _costField(_wCostCtrl, DashboardStyles.waterBorder),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: height < 320 ? 320 : height,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.v10),
            const _SheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v6, AppSpacing.v8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      existing != null && existing.source != 'missing' ? 'แก้ไขบิลย้อนหลัง' : 'เพิ่มบิลย้อนหลัง',
                      style: const TextStyle(
                          fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    ),
                  ),
                  IconButton(
                    tooltip: 'หน้านี้ใช้ทำอะไร',
                    icon: Icon(Icons.info_outline, color: Colors.grey.shade600),
                    onPressed: () => _showInvoiceInfoPopup(context),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v4, AppSpacing.v16, AppSpacing.v24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('บิลของเดือน'),
                    if (_isLoadingTaken)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.v12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      Wrap(
                        spacing: AppSpacing.v8,
                        runSpacing: AppSpacing.v8,
                        children: [for (final d in _monthOptions) _monthChip(d)],
                      ),
                    const SizedBox(height: AppSpacing.v16),
                    Row(
                      children: [
                        Expanded(
                          child: Text('มีบิลฝั่งไหนก็กรอกแค่ฝั่งนั้นได้ค่ะ',
                              style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                        ),
                        TextButton.icon(
                          onPressed: () => _showUsageInfoPopup(isElectricity: _selectedTab == 0),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v8),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: AppTypography.s12_5,
                                fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(Icons.help_outline_rounded, size: 18),
                          label: const Text('ดูตำแหน่งในบิล'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.v8),
                    _buildUtilityTabs(),
                    const SizedBox(height: AppSpacing.v12),
                    if (_selectedTab == 0) electricity else water,
                    const SizedBox(height: AppSpacing.v16),
                    // ยอดรวมของบิลเดือนนี้ (ไฟ + น้ำ + รายจ่ายประจำที่ active ในเดือนนั้น)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.v14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('ยอดรวมเดือนนี้',
                                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark)),
                              ),
                              Text('${formatter.format(_totalWithFixedCost)} บาท',
                                  style: const TextStyle(
                                      fontSize: AppTypography.s17,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryGreen)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.v2),
                          Text(
                            'ค่าไฟ ${formatter.format(_eCost)} · ค่าน้ำ ${formatter.format(_wCost)}'
                            '${_fixedCost > 0 ? ' · รายจ่ายประจำ ${formatter.format(_fixedCost)}' : ''}',
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.v12),
                    // เดือนของรอบปัจจุบันไม่อยู่ในตัวเลือก (เก็บเป็นเลขมิเตอร์สะสม) — ลิงก์ไป
                    // กรอกที่หน้าเลขมิเตอร์จากใบแจ้งหนี้แทน
                    InkWell(
                      onTap: _goSetStartMeter,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.v6, horizontal: AppSpacing.v4),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 15, color: Colors.grey.shade600),
                            const SizedBox(width: AppSpacing.v6),
                            Expanded(
                              child: Text(
                                'บิล${_monthYearLabel(_currentCycleMonth.month, _currentCycleMonth.year)} '
                                '(รอบปัจจุบัน) กรอกที่หน้าเลขมิเตอร์จากใบแจ้งหนี้',
                                style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade700),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.v10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: AppSpacing.v6),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.red.shade700)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v16, AppSpacing.v16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SafeArea(
                top: false,
                child: ElevatedButton(
                  onPressed: (_isSaving || _isSelectedMonthTaken) ? null : _save,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(existing != null && existing.source != 'missing' ? 'บันทึกการแก้ไข' : 'บันทึก'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
