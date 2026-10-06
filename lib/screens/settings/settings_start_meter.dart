part of 'settings_screen.dart';

// ใบแจ้งหนี้ล่าสุดที่ควรใช้เป็นต้นรอบตอนนี้ คำนวณจาก billingDay จริงของ user
// สูตรเดียวกับรอบบิลบนหน้าหลัก (ห้ามใช้ getPreviousCycleStart ซ้อนอีกชั้น จะได้เดือนเก่ากว่าที่ควร)
DateTime _expectedInvoiceMonth(int billingDay) {
  final now = DateTime.now();
  return EnergyForecaster.getCycleStart(now, billingDay);
}

// แถวเดียวของการ์ดสรุป "เดือนก่อน -> ตอนนี้ = ใช้ไปกี่หน่วย" — label เป็น null
// สำหรับกรณีปกติ (คู่เดียว) ใช้ label เมื่อต้องแยกแสดง On-Peak/Off-Peak
class _MeterDeltaRow {
  final String? label;
  final double prevVal;
  final double currentVal;
  final double used;
  const _MeterDeltaRow(this.label, this.prevVal, this.currentVal, this.used);
}

// บันทึกเลขมิเตอร์ต้นรอบ (bottom sheet) — รวมกับหน้าประวัติผ่านปุ่ม FAB "+"
class _AddStartMeterSheet extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final bool isTou;

  const _AddStartMeterSheet({
    required this.uid,
    required this.firestoreService,
    this.isTou = false,
  });

  @override
  State<_AddStartMeterSheet> createState() => _AddStartMeterSheetState();
}

class _AddStartMeterSheetState extends State<_AddStartMeterSheet> {
  bool _isLoading = true;
  UserModel? _user;
  final _eCtrl = TextEditingController();
  final _peakCtrl = TextEditingController();
  final _offPeakCtrl = TextEditingController();
  final _wCtrl = TextEditingController();

  // ค่าใช้จ่ายของบิลล่าสุด จับคู่กับเลขมิเตอร์ต้นรอบของยูทิลิตี้เดียวกัน (กรอกเลขมิเตอร์
  // ต้องกรอกค่าใช้จ่ายด้วย หรือเว้นว่างทั้งคู่ — กติกาอยู่ที่ StartMeterValidation)
  final _eCostCtrl = TextEditingController();
  final _wCostCtrl = TextEditingController();
  // ช่อง "หน่วยที่ใช้ไปแล้ว" — โชว์เฉพาะตอนตั้งค่าครั้งแรกสุดของยูทิลิตี้นั้น
  final _eUsedCtrl = TextEditingController();
  final _wUsedCtrl = TextEditingController();
  // TOU: คู่ On-Peak/Off-Peak ของ "หน่วยที่ใช้ไปแล้ว" แทน _eUsedCtrl ตัวเดียว ผลรวมคือค่าที่ใช้จริง
  final _eUsedPeakCtrl = TextEditingController();
  final _eUsedOffPeakCtrl = TextEditingController();
  bool _electricityNoBillYet = false;
  bool _waterNoBillYet = false;
  // คำนวณค่าใช้จ่ายอัตโนมัติขณะพิมพ์ (ดู _CostAutofill)
  final _costAutofill = _CostAutofill();
  // โชว์ตอนกดบันทึกแล้วไม่มีคู่ไหนกรอกครบเลยสักคู่
  bool _generalError = false;
  List<BillModel> _existingBills = [];
  List<StartMeterRecordModel> _history = [];

  // ค่า default ก่อนที่ _loadCurrent() จะรู้ billingDay จริง (ใช้ 30 เป็นค่าเริ่มต้นชั่วคราว)
  static DateTime get _defaultInvoiceMonth {
    return _expectedInvoiceMonth(30);
  }

  int _selectedMonth = _defaultInvoiceMonth.month;
  int _selectedYear = _defaultInvoiceMonth.year;
  bool _isSaving = false;

  // ถ้าไม่ null = ค่าที่ตั้งไว้ล่าสุดตรงกับรอบตอนนี้พอดี กด "บันทึก" จะแก้ทับ record นี้แทนสร้างใหม่
  String? _editingRecordId;

  // ใช้โชว์ label ในฟอร์มว่ากำลังแก้ไขค่าที่เพิ่งตั้ง หรือตั้งค่าต้นรอบใหม่
  bool get _isEditingCurrentCycle => _editingRecordId != null;

  @override
  void initState() {
    super.initState();
    // รีเฟรช error ของการ์ดคู่แบบ live ทันทีที่พิมพ์ ไม่ต้องรอกดบันทึกก่อน
    for (final c in [
      _eCtrl,
      _peakCtrl,
      _offPeakCtrl,
      _wCtrl,
      _eCostCtrl,
      _wCostCtrl,
      _eUsedCtrl,
      _wUsedCtrl,
      _eUsedPeakCtrl,
      _eUsedOffPeakCtrl,
    ]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }

    // คำนวณ "ค่าใช้จ่าย" อัตโนมัติทุกครั้งที่ช่องหน่วย/เลขมิเตอร์ที่เกี่ยวข้องเปลี่ยน
    // (ทั้งกรณีครั้งแรกสุด และรอบถัดไปที่คำนวณ delta) — ผู้ใช้ยังแก้ค่าที่คำนวณได้เอง เพราะช่องไม่ถูก disable
    for (final c in [
      _eCtrl,
      _peakCtrl,
      _offPeakCtrl,
      _eUsedCtrl,
      _eUsedPeakCtrl,
      _eUsedOffPeakCtrl,
    ]) {
      c.addListener(_scheduleElectricityCostCalc);
    }
    for (final c in [_wCtrl, _wUsedCtrl]) {
      c.addListener(_scheduleWaterCostCalc);
    }

    _loadCurrent();
  }

  void _scheduleElectricityCostCalc() =>
      _costAutofill.scheduleElectricity(_autoCalcElectricityCost);

  void _scheduleWaterCostCalc() =>
      _costAutofill.scheduleWater(_autoCalcWaterCost);

  // คำนวณ "ค่าใช้จ่าย" ไฟฟ้าอัตโนมัติตามอัตรา (MEA/PEA ปกติ หรือ TOU)
  // กรณีครั้งแรกสุด: ใช้หน่วยที่กรอกในช่อง "หน่วยที่ใช้ไปแล้ว" ตรงๆ
  // กรณีมีรอบก่อนหน้าแล้ว: คำนวณจาก delta ของเลขมิเตอร์สะสม เหมือนตอนกด "บันทึก" จริง (ดู _save())
  // ยังไม่กรอกหน่วย (หรือคำนวณ delta ไม่ได้) -> เซตค่าใช้จ่ายเป็น 0.00
  Future<void> _autoCalcElectricityCost() async {
    if (!mounted || _isLoading || _electricityNoBillYet) return;
    final user = _user;
    if (user == null) return;

    double units = 0;
    double peakUnits = 0;
    double offPeakUnits = 0;

    if (_eIsFirstEntry) {
      if (widget.isTou) {
        peakUnits = parseNumInput(_eUsedPeakCtrl.text);
        offPeakUnits = parseNumInput(_eUsedOffPeakCtrl.text);
      } else {
        units = parseNumInput(_eUsedCtrl.text);
      }
    } else {
      final prev = _previousElectricityRecord;
      if (prev != null) {
        if (widget.isTou) {
          final peakVal = parseNumInput(_peakCtrl.text);
          final offPeakVal = parseNumInput(_offPeakCtrl.text);
          peakUnits = _deltaUsed(peakVal, prev.peakValue);
          offPeakUnits = _deltaUsed(offPeakVal, prev.offPeakValue);
        } else {
          final eVal = parseNumInput(_eCtrl.text);
          units = _deltaUsed(eVal, prev.electricityValue);
        }
      }
    }

    final text = await _CostAutofill.electricityText(
      user: user,
      isTou: widget.isTou,
      units: units,
      peakUnits: peakUnits,
      offPeakUnits: offPeakUnits,
    );
    if (!mounted) return;
    setState(() => _eCostCtrl.text = text);
  }

  // เหมือน _autoCalcElectricityCost() แต่ฝั่งน้ำ (ไม่มี TOU ให้แยก และ
  // calculateWater เป็น sync function ไม่ต้อง await)
  void _autoCalcWaterCost() {
    if (!mounted || _isLoading || _waterNoBillYet) return;
    final user = _user;
    if (user == null) return;

    double units = 0;
    if (_wIsFirstEntry) {
      units = parseNumInput(_wUsedCtrl.text);
    } else {
      final prev = _previousWaterRecord;
      if (prev != null) {
        final wVal = parseNumInput(_wCtrl.text);
        units = _deltaUsed(wVal, prev.waterValue);
      }
    }

    setState(() => _wCostCtrl.text = _CostAutofill.waterText(user, units));
  }

  // ดึงค่าปัจจุบันของ user มาตั้งเป็นค่าเริ่มต้นในฟอร์ม (widget ทำงานอิสระ ไม่ผูกกับ state หน้าตั้งค่า)
  // เช็คว่าค่าที่ตั้งไว้ล่าสุดตรงกับรอบที่ควรตั้งตอนนี้ไหม (คำนวณจาก billingDay จริง)
  // ตรง = โหมดแก้ไข (แก้ทับของเดิม), ไม่ตรง = โหมดตั้งค่าใหม่ (ฟอร์มว่าง สร้าง record ใหม่)
  Future<void> _loadCurrent() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    _user = user;
    _existingBills = await widget.firestoreService.getBills(widget.uid);
    // โหลดประวัติเสมอ เพราะตอนบันทึกต้องใช้หาค่าสะสมของรอบก่อนหน้ามาคำนวณ delta ให้บิลที่สร้างอัตโนมัติ
    _history = await widget.firestoreService.getStartMeterHistory(widget.uid);
    if (user != null && mounted) {
      final expected = _expectedInvoiceMonth(user.billingDay);
      final matchesCurrentCycle = user.startMeterConfigured &&
          EnergyForecaster.matchesCurrentCycle(
            billingMonth: user.startBillingMonth,
            billingYear: user.startBillingYear,
            billingDay: user.billingDay,
          );

      if (matchesCurrentCycle) {
        // โหมดแก้ไข: ค่าที่ตั้งไว้ล่าสุดตรงกับรอบที่ควรตั้งตอนนี้พอดี
        _eCtrl.text = user.startElectricityValue == 0
            ? ''
            : user.startElectricityValue.toString();
        _peakCtrl.text =
            user.startPeakValue == 0 ? '' : user.startPeakValue.toString();
        _offPeakCtrl.text = user.startOffPeakValue == 0
            ? ''
            : user.startOffPeakValue.toString();
        _wCtrl.text =
            user.startWaterValue == 0 ? '' : user.startWaterValue.toString();
        _selectedMonth = user.startBillingMonth;
        _selectedYear = user.startBillingYear;

        // หา record ล่าสุดในประวัติ เอา id มาใช้แก้ทับตอนบันทึก แทนการสร้างใหม่
        _editingRecordId = _history.isNotEmpty ? _history.first.id : null;

        // prefill ค่าใช้จ่าย เฉพาะโหมดแก้ไขรอบปัจจุบันเท่านั้น ห้ามรันตอนโหมดตั้งใหม่
        // ไม่งั้นถ้ามีบิลเก่าค้างของเดือนนี้ (สร้างจากจุดอื่นโดยไม่มีเลขมิเตอร์ผูกมา) จะได้ค่าใช้จ่าย
        // > 0 ทั้งที่เลขมิเตอร์ถูก clear เป็นค่าว่างแล้ว ทำให้ StartMeterValidation มองว่ากรอกค้างไว้ (partial)
        final existingBill = _existingBills.where(
            (b) => b.year == _selectedYear && b.month == _selectedMonth);
        if (existingBill.isNotEmpty) {
          final b = existingBill.first;
          _eCostCtrl.text =
              b.electricityCost == 0 ? '' : b.electricityCost.toString();
          _wCostCtrl.text = b.waterCost == 0 ? '' : b.waterCost.toString();
          _eUsedCtrl.text =
              b.electricityUsed == 0 ? '' : b.electricityUsed.toString();
          _wUsedCtrl.text = b.waterUsed == 0 ? '' : b.waterUsed.toString();
          // prefill คู่ TOU ด้วย (ช่อง On/Off ของ "หน่วยที่ใช้ไปแล้ว") ตอนกลับมาแก้ไขค่าที่เพิ่งบันทึก
          _eUsedPeakCtrl.text = b.electricityPeakUsed == 0
              ? ''
              : b.electricityPeakUsed.toString();
          _eUsedOffPeakCtrl.text = b.electricityOffPeakUsed == 0
              ? ''
              : b.electricityOffPeakUsed.toString();
        }
      } else {
        // โหมดตั้งใหม่ (ยังไม่เคยตั้ง หรือรอบขยับไปแล้ว): ฟอร์มว่าง ตั้ง default เดือน/ปีเป็นรอบที่ควรตั้งตอนนี้
        _eCtrl.clear();
        _peakCtrl.clear();
        _offPeakCtrl.clear();
        _wCtrl.clear();
        _selectedMonth = expected.month;
        _selectedYear = expected.year;
        _editingRecordId = null;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _costAutofill.dispose();
    _eCtrl.dispose();
    _peakCtrl.dispose();
    _offPeakCtrl.dispose();
    _wCtrl.dispose();
    _eCostCtrl.dispose();
    _wCostCtrl.dispose();
    _eUsedCtrl.dispose();
    _wUsedCtrl.dispose();
    _eUsedPeakCtrl.dispose();
    _eUsedOffPeakCtrl.dispose();
    super.dispose();
  }

  // เช็คว่าเป็นการตั้งค่าครั้งแรกสุดของยูทิลิตี้นั้นไหม (แยกรายยูทิลิตี้ ไม่นับ _editingRecordId)
  // TOU ไม่เคยเซ็ต electricityValue (ใช้ peakValue/offPeakValue แทน) ต้องเช็คคู่นี้ด้วย ไม่งั้นจะถูกตีความว่าเป็นครั้งแรกทุกครั้ง
  bool get _eIsFirstEntry => !_history.any((r) =>
      r.id != _editingRecordId &&
      (widget.isTou
          ? (r.peakValue > 0 || r.offPeakValue > 0)
          : r.electricityValue > 0));
  bool get _wIsFirstEntry =>
      !_history.any((r) => r.id != _editingRecordId && r.waterValue > 0);

  // หา record ก่อนหน้าที่ใกล้ที่สุด "ที่มีข้อมูลของยูทิลิตี้นั้นจริงๆ" ไว้คำนวณ delta
  // ต้องกรองด้วย hasData ก่อนเสมอ เพราะบางรอบอาจมี record ที่ยูทิลิตี้นี้ไม่มีค่าเลย
  // (เช่นกรอกแค่น้ำ ไม่แตะไฟฟ้า หรือเคยลบทิ้งผ่าน _confirmDelete) ถ้าไม่กรองจะได้ค่า 0
  // มาเป็น baseline ผิดๆ ทำให้เลขมิเตอร์สะสมทั้งก้อนถูกนับเป็น "หน่วยที่ใช้"
  StartMeterRecordModel? _previousRecordWhere(
      bool Function(StartMeterRecordModel r) hasData) {
    final candidates = _history.where((r) =>
        r.id != _editingRecordId &&
        hasData(r) &&
        (r.billingYear < _selectedYear ||
            (r.billingYear == _selectedYear &&
                r.billingMonth < _selectedMonth)));
    if (candidates.isEmpty) return null;
    final list = candidates.toList()
      ..sort((a, b) => (b.billingYear * 12 + b.billingMonth)
          .compareTo(a.billingYear * 12 + a.billingMonth));
    return list.first;
  }

  // ไฟฟ้า: TOU เช็คจากคู่ peak/offPeak (electricityValue ไม่เคยถูกเซ็ตสำหรับ TOU) — ใช้ตัวเดียวกับ _eIsFirstEntry
  StartMeterRecordModel? get _previousElectricityRecord =>
      _previousRecordWhere((r) => widget.isTou
          ? (r.peakValue > 0 || r.offPeakValue > 0)
          : r.electricityValue > 0);

  StartMeterRecordModel? get _previousWaterRecord =>
      _previousRecordWhere((r) => r.waterValue > 0);

  // คำนวณ "หน่วยที่ใช้ไป" แบบ delta เดียวใช้ร่วมกันทั้ง preview และตอนกด "บันทึก"
  // จริง กันตัวเลขที่โชว์กับที่เซฟไม่ตรงกัน — previous <= 0 หมายถึงไม่มี
  // baseline ที่เชื่อถือได้ ต้องคืน 0 เสมอ (ไม่งั้น preview จะโชว์ตัวเลขพุ่งผิดปกติ)
  double _deltaUsed(double current, double previous) =>
      previous > 0 ? EnergyCalculator.calculateUsed(current, previous) : 0;

  // รายชื่อรอบบิลที่ "ไม่มี record" คั่นอยู่ระหว่าง record ก่อนหน้า (prev) กับรอบที่
  // กำลังตั้งค่าอยู่ตอนนี้ (_selectedMonth/_selectedYear) — ปกติ prev คือรอบก่อนหน้า
  // ติดกันพอดี ฟังก์ชันนี้จะคืน list ว่าง แต่ถ้า user ข้ามไปหลายรอบไม่ได้ตั้งค่าเลย
  // จะได้ชื่อเดือนที่ขาดมาไว้โชว์เป็น note ในการ์ดสรุป เพื่อให้เห็นชัดว่าตัวเลข
  // "ใช้ไปทั้งหมด" ที่คำนวณจาก prev -> ตอนนี้ นับรวมหลายเดือน ไม่ใช่แค่เดือนเดียว
  List<String> _skippedMonthsBetween(StartMeterRecordModel prev) {
    final billingDay = _user?.billingDay ?? 30;
    final months = <String>[];
    var cursor = EnergyForecaster.getPreviousCycleStart(
        EnergyForecaster.safeBillingDate(
            _selectedYear, _selectedMonth, billingDay),
        billingDay);
    while (cursor.year > prev.billingYear ||
        (cursor.year == prev.billingYear && cursor.month > prev.billingMonth)) {
      months.add(_monthYearLabel(cursor.month, cursor.year));
      cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
    }
    return months.reversed.toList(); // เรียงเก่า -> ใหม่ ให้อ่านง่าย
  }

  // เช็คว่าเลขมิเตอร์ที่กรอกรอบนี้ "ต่ำกว่า" รอบก่อนหน้าไหม (เลขมิเตอร์สะสมต้องเพิ่มขึ้นเรื่อยๆ)
  // ส่วนใหญ่เป็นการกรอกผิด (พิมพ์เลขเก่า/ตกหลัก) — ใช้เตือนแบบ live ใต้ฟอร์ม และกันไว้อีกชั้นใน _save()
  // ไม่เช็คตอน isFirstEntry เพราะยังไม่มี record ก่อนหน้าให้เทียบ
  bool get _eBelowPrevious {
    final prev = _previousElectricityRecord;
    if (prev == null) return false;
    if (widget.isTou) {
      final peakVal = parseNumInput(_peakCtrl.text);
      final offPeakVal = parseNumInput(_offPeakCtrl.text);
      return (peakVal > 0 && peakVal < prev.peakValue) ||
          (offPeakVal > 0 && offPeakVal < prev.offPeakValue);
    }
    final eVal = parseNumInput(_eCtrl.text);
    return eVal > 0 && eVal < prev.electricityValue;
  }

  bool get _wBelowPrevious {
    final prev = _previousWaterRecord;
    if (prev == null) return false;
    final wVal = parseNumInput(_wCtrl.text);
    return wVal > 0 && wVal < prev.waterValue;
  }

  // การ์ดสรุป "เดือนก่อน -> ตอนนี้ = ใช้ไปกี่หน่วย" ให้เช็คก่อนบันทึกจริงว่าถูกไหม —
  // โชว์เฉพาะรอบถัดๆ ไปที่มีรอบก่อนหน้าให้เทียบ ใช้ _deltaUsed() ตัวเดียวกับตอนกด "บันทึก" เป๊ะๆ
  Widget? get _eUsageSummary {
    if (_eIsFirstEntry) return null;
    final prev = _previousElectricityRecord;
    if (prev == null) return null;
    final rows = <_MeterDeltaRow>[];
    if (widget.isTou) {
      final peakVal = parseNumInput(_peakCtrl.text);
      final offPeakVal = parseNumInput(_offPeakCtrl.text);
      rows.add(_MeterDeltaRow('On-Peak', prev.peakValue, peakVal,
          _deltaUsed(peakVal, prev.peakValue)));
      rows.add(_MeterDeltaRow('Off-Peak', prev.offPeakValue, offPeakVal,
          _deltaUsed(offPeakVal, prev.offPeakValue)));
    } else {
      final eVal = parseNumInput(_eCtrl.text);
      rows.add(_MeterDeltaRow(null, prev.electricityValue, eVal,
          _deltaUsed(eVal, prev.electricityValue)));
    }
    return _usageSummaryCard(
      rows: rows,
      unit: 'หน่วย',
      color: DashboardStyles.electricityBorder,
      prevMonthLabel: _monthYearLabel(prev.billingMonth, prev.billingYear),
      skippedMonths: _skippedMonthsBetween(prev),
    );
  }

  Widget? get _wUsageSummary {
    if (_wIsFirstEntry) return null;
    final prev = _previousWaterRecord;
    if (prev == null) return null;
    final wVal = parseNumInput(_wCtrl.text);
    return _usageSummaryCard(
      rows: [
        _MeterDeltaRow(
            null, prev.waterValue, wVal, _deltaUsed(wVal, prev.waterValue)),
      ],
      unit: 'ลบ.ม.',
      color: DashboardStyles.waterBorder,
      prevMonthLabel: _monthYearLabel(prev.billingMonth, prev.billingYear),
      skippedMonths: _skippedMonthsBetween(prev),
    );
  }

  // กล่องผลคำนวณหน่วยที่ใช้ — ตัวหนา "ใช้ไป 320 หน่วย" ใต้ลงมาเป็นที่มาของตัวเลข
  // (เลขที่กรอก − เลขของใบแจ้งหนี้รอบก่อน) ยังไม่กรอกเลขรอบนี้ = บอกให้พิมพ์ก่อน
  // ตัวเลขอัปเดตทันทีที่พิมพ์ (rebuild ผ่าน listener ที่มีอยู่แล้ว)
  Widget _usageSummaryCard({
    required List<_MeterDeltaRow> rows,
    required String unit,
    required Color color,
    required String prevMonthLabel,
    List<String> skippedMonths = const [],
  }) {
    final fmt = NumberFormat('#,##0.##');
    final filledRows = rows.where((r) => r.currentVal > 0).toList();
    final total = filledRows.fold<double>(0, (s, r) => s + r.used);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.v12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: Icons.calculate_outlined, color: color, size: 32),
          const SizedBox(width: AppSpacing.v10),
          Expanded(
            child: filledRows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.v6),
                    child: Text(
                      'พิมพ์เลขมิเตอร์ด้านบน แล้วระบบจะคำนวณหน่วยที่ใช้ตั้งแต่ใบแจ้งหนี้ $prevMonthLabel ให้ค่ะ',
                      style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade600),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in filledRows) ...[
                        Text(
                          '${r.label != null ? '${r.label} ' : ''}ใช้ไป ${fmt.format(r.used)} $unit',
                          style: TextStyle(
                              fontSize: AppTypography.s14, fontWeight: FontWeight.w700, color: color),
                        ),
                        Text(
                          '${fmt.format(r.currentVal)} − ${fmt.format(r.prevVal)} (เลขของ $prevMonthLabel)',
                          style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: AppSpacing.v4),
                      ],
                      if (filledRows.length > 1)
                        Text(
                          'รวมใช้ไปทั้งหมด ${fmt.format(total)} $unit',
                          style: const TextStyle(
                              fontSize: AppTypography.s13, fontWeight: FontWeight.w700, color: AppColors.textDark),
                        ),
                      // มีรอบบิลที่ไม่มี record คั่นอยู่ (ข้ามไปหลายรอบ) — ตัวเลขข้างบนคือ
                      // ยอดรวมของทุกรอบที่ขาด ไม่ใช่รอบเดียว กันสับสนว่าทำไมหน่วยเยอะผิดปกติ
                      if (skippedMonths.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.v4),
                          child: Text(
                            'รวม ${skippedMonths.length} รอบที่ไม่ได้บันทึก (${skippedMonths.join(', ')}) '
                            'ถ้าจำหน่วยแยกรายเดือนได้ กรอกย้อนหลังทีละเดือนที่หน้า "บิลย้อนหลัง" จะแม่นกว่าค่ะ',
                            style: const TextStyle(
                                fontSize: AppTypography.s11_5, height: 1.4, color: AppColors.warningText),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final eVal = parseNumInput(_eCtrl.text);
    final peakVal = parseNumInput(_peakCtrl.text);
    final offPeakVal = parseNumInput(_offPeakCtrl.text);
    final wVal = parseNumInput(_wCtrl.text);
    final eCost = parseNumInput(_eCostCtrl.text);
    final wCost = parseNumInput(_wCostCtrl.text);
    // TOU: หน่วยที่ใช้ไปแล้วมาจากผลรวม On-Peak/Off-Peak ที่กรอกแยก
    final eUsedInput = widget.isTou
        ? parseNumInput(_eUsedPeakCtrl.text) + parseNumInput(_eUsedOffPeakCtrl.text)
        : parseNumInput(_eUsedCtrl.text);
    final wUsedInput = parseNumInput(_wUsedCtrl.text);

    // กติกาจับคู่ + อย่างน้อย 1 คู่ต้องครบ ใช้ตัวเดียวกับที่ widget ใช้โชว์ error
    final ok = StartMeterValidation.canSave(
      isTou: widget.isTou,
      eVal: eVal,
      peakVal: peakVal,
      offPeakVal: offPeakVal,
      eCost: eCost,
      wVal: wVal,
      wCost: wCost,
      eNoBillYet: _electricityNoBillYet,
      wNoBillYet: _waterNoBillYet,
      eIsFirstEntry: _eIsFirstEntry,
      eUsed: eUsedInput,
      wIsFirstEntry: _wIsFirstEntry,
      wUsed: wUsedInput,
    );
    if (!ok) {
      setState(() => _generalError = true);
      return;
    }
    // เลขมิเตอร์ต่ำกว่ารอบก่อนหน้า มักเป็นการกรอกผิด — ไม่บล็อกเด็ดขาด เผื่อเปลี่ยน
    // มิเตอร์ตัวใหม่จริงๆ ที่เลขเริ่มนับใหม่ต่ำกว่าตัวเก่า แต่ต้องให้ยืนยันก่อนเสมอ
    if (_eBelowPrevious || _wBelowPrevious) {
      final confirm = await showConfirmDialog(
        context,
        title: 'เลขมิเตอร์ต่ำกว่ารอบก่อนหน้า',
        content: '${[
          if (_eBelowPrevious) 'เลขมิเตอร์ไฟฟ้า',
          if (_wBelowPrevious) 'เลขมิเตอร์น้ำ',
        ].join(' และ ')}'
            'ที่กรอกไว้ต่ำกว่ารอบก่อนหน้า ถ้าไม่ได้เพิ่งเปลี่ยนมิเตอร์ตัวใหม่ '
            'อาจเป็นการกรอกผิด ต้องการบันทึกต่อเลยไหมคะ?',
        confirmLabel: 'บันทึกต่อ',
        cancelLabel: 'กลับไปแก้ไข',
        confirmColor: DashboardStyles.primaryGreen,
      );
      if (confirm != true || !mounted) return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _generalError = false;
      _isSaving = true;
    });
    try {
      final eComplete = StartMeterValidation.electricityComplete(
          isTou: widget.isTou,
          eVal: eVal,
          peakVal: peakVal,
          offPeakVal: offPeakVal,
          eCost: eCost,
          eNoBillYet: _electricityNoBillYet,
          isFirstEntry: _eIsFirstEntry,
          eUsed: eUsedInput);
      final wComplete = StartMeterValidation.waterComplete(
          wVal: wVal,
          wCost: wCost,
          wNoBillYet: _waterNoBillYet,
          isFirstEntry: _wIsFirstEntry,
          wUsed: wUsedInput);

      // อัปเดตเฉพาะยูทิลิตี้ที่กรอกครบคู่จริงๆ กันไม่ให้เขียนทับค่าฝั่งที่เว้นว่างไว้ด้วยศูนย์
      final updates = <String, dynamic>{
        'startBillingMonth': _selectedMonth,
        'startBillingYear': _selectedYear,
      };
      if (eComplete) {
        updates['startElectricityValue'] = eVal;
        updates['startPeakValue'] = peakVal;
        updates['startOffPeakValue'] = offPeakVal;
        updates['electricityStartConfigured'] = true;
      }
      if (wComplete) {
        updates['startWaterValue'] = wVal;
        updates['waterStartConfigured'] = true;
      }
      // มีอย่างน้อย 1 ยูทิลิตี้ครบแล้ว = ถือว่า configured ในความหมายรวม (จุดอื่นที่อ้างอิง flag รวมยังทำงานถูกต้อง)
      updates['startMeterConfigured'] = true;

      await widget.firestoreService.updateUser(widget.uid, updates);

      // log รายวันแต่ละอันเป็น snapshot ที่คำนวณตอนกดบันทึกครั้งนั้น ไม่คำนวณสดจาก start value ปัจจุบัน
      // ถ้าแก้ไขเลขต้นรอบของรอบปัจจุบันและค่าที่กรอกเปลี่ยนไปจริง ให้ไล่คำนวณ log ทุกอันในรอบนี้ใหม่ทั้งหมด
      if (_isEditingCurrentCycle) {
        final oldE = _user?.startElectricityValue ?? 0;
        final oldPeak = _user?.startPeakValue ?? 0;
        final oldOffPeak = _user?.startOffPeakValue ?? 0;
        final oldW = _user?.startWaterValue ?? 0;
        final electricityChanged = eComplete &&
            (eVal != oldE || peakVal != oldPeak || offPeakVal != oldOffPeak);
        final waterChanged = wComplete && wVal != oldW;
        if (electricityChanged || waterChanged) {
          await widget.firestoreService.recalcCurrentCycleLogs(
            _user!,
            isTou: widget.isTou,
            recalcElectricity: electricityChanged,
            recalcWater: waterChanged,
            newStartE: eVal,
            newStartPeak: peakVal,
            newStartOffPeak: offPeakVal,
            newStartW: wVal,
          );
        }
      }

      // เก็บ snapshot ไว้ในประวัติ ถ้าอยู่โหมดแก้ไข (รอบเดิม) ใช้ id เดิมแก้ทับ record เดิม กันประวัติรก
      await widget.firestoreService.saveStartMeterRecord(
        StartMeterRecordModel(
          id: _editingRecordId ?? const Uuid().v4(),
          uid: widget.uid,
          electricityValue: eVal,
          waterValue: wVal,
          peakValue: peakVal,
          offPeakValue: offPeakVal,
          billingMonth: _selectedMonth,
          billingYear: _selectedYear,
          recordedAt: DateTime.now(),
        ),
      );

      if (mounted) {
        // ถ้ากรอกค่าใช้จ่ายไว้ บันทึกเป็นบิลของรอบที่เพิ่งปิด ถ้าเดือนนี้มีบิลอยู่แล้วใช้ id เดิมอัปเดตทับ
        // บิลต้องมี electricityUsed/waterUsed ด้วย ไม่ใช่แค่ cost: ถ้ามี record ก่อนหน้าคำนวณ delta อัตโนมัติ
        // ถ้าเป็นครั้งแรกสุดใช้ค่าที่ผู้ใช้กรอกในช่อง "หน่วยที่ใช้ไปแล้ว" ตรงๆ
        // แยก prev ของไฟฟ้ากับน้ำออกจากกัน (คนละ record ก่อนหน้ากันได้) กันไม่ให้หยิบ
        // record ที่ไม่มีข้อมูลของยูทิลิตี้นั้นมาเป็น baseline ผิดๆ (ดู _previousElectricityRecord / _previousWaterRecord)
        final prevE = _previousElectricityRecord;
        final prevW = _previousWaterRecord;
        double wUsed = _wIsFirstEntry ? wUsedInput : 0;
        // TOU: หน่วยที่ใช้คำนวณจากคู่ On-Peak/Off-Peak เสมอ (electricityValue ไม่เคยถูกเซ็ตสำหรับ TOU)
        double eUsed = widget.isTou ? 0 : (_eIsFirstEntry ? eUsedInput : 0);
        double ePeakUsed = widget.isTou && _eIsFirstEntry
            ? parseNumInput(_eUsedPeakCtrl.text)
            : 0;
        double eOffPeakUsed = widget.isTou && _eIsFirstEntry
            ? parseNumInput(_eUsedOffPeakCtrl.text)
            : 0;
        if (prevE != null) {
          if (widget.isTou) {
            if (eComplete) {
              ePeakUsed = _deltaUsed(peakVal, prevE.peakValue);
              eOffPeakUsed = _deltaUsed(offPeakVal, prevE.offPeakValue);
            }
          } else if (eComplete) {
            eUsed = _deltaUsed(eVal, prevE.electricityValue);
          }
        }
        if (prevW != null && wComplete) {
          wUsed = _deltaUsed(wVal, prevW.waterValue);
        }
        if (widget.isTou) {
          eUsed = ePeakUsed + eOffPeakUsed;
        }

        final existingMatches = _existingBills.where(
            (b) => b.year == _selectedYear && b.month == _selectedMonth);
        final existingBillForMonth =
            existingMatches.isNotEmpty ? existingMatches.first : null;

        if (eComplete || wComplete) {
          final newECost = eComplete ? eCost : (existingBillForMonth?.electricityCost ?? 0);
          final newWCost = wComplete ? wCost : (existingBillForMonth?.waterCost ?? 0);
          // รายจ่ายประจำที่ active ในเดือนบิลนี้ (กติกาเดียวกับ compileBill และ
          // ฟอร์มบิลย้อนหลัง) ยอดรวมของบิลทุกแหล่งจึงรวมรายจ่ายประจำเหมือนกัน
          final fixedCost = await widget.firestoreService.calcFixedCostForMonth(
              widget.uid, DateTime(_selectedYear, _selectedMonth, 1));
          await widget.firestoreService.saveBill(
            BillModel(
              id: existingBillForMonth?.id ?? const Uuid().v4(),
              uid: widget.uid,
              year: _selectedYear,
              month: _selectedMonth,
              electricityCost: newECost,
              waterCost: newWCost,
              totalCost: newECost + newWCost + fixedCost,
              electricityUsed:
                  eComplete ? eUsed : (existingBillForMonth?.electricityUsed ?? 0),
              electricityPeakUsed: eComplete
                  ? ePeakUsed
                  : (existingBillForMonth?.electricityPeakUsed ?? 0),
              electricityOffPeakUsed: eComplete
                  ? eOffPeakUsed
                  : (existingBillForMonth?.electricityOffPeakUsed ?? 0),
              waterUsed:
                  wComplete ? wUsed : (existingBillForMonth?.waterUsed ?? 0),
              fixedCost: fixedCost,
              // 'startMeter' = บิลที่สร้าง/อัปเดตจากหน้านี้ (ต่างจาก 'imported') — ล็อกไม่ให้แก้/ลบจากหน้าบันทึกบิลย้อนหลัง
              source: 'startMeter',
            ),
          );
        }
        if (!mounted) return;
        navigator.pop(true);
      }
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

  // ล้างเลขมิเตอร์ต้นรอบจริง (user.startElectricityValue ฯลฯ) — คนละอันกับลบประวัติ (snapshot) ต้อง confirm แยกเพราะกระทบมากกว่า
  Future<void> _confirmClearStartMeter() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'ล้างเลขมิเตอร์ต้นรอบ',
      content: 'เลขมิเตอร์ต้นรอบทั้งหมดจะถูกล้าง ต้องตั้งค่าใหม่ก่อนถึงจะ'
          'บันทึกมิเตอร์รายวันต่อได้ รายการต้นรอบของรอบนี้ในหน้าประวัติ '
          '(และบิลที่สร้างอัตโนมัติ ถ้ามี) จะถูกลบไปด้วย\n\nประวัติมิเตอร์'
          'รายวันที่บันทึกไว้ในรอบนี้จะยังอยู่ แต่จะคำนวณอ้างอิงกับต้นรอบ'
          'เดิมไม่ได้แล้ว จนกว่าจะตั้งค่าต้นรอบใหม่อีกครั้ง ต้องการดำเนินการ'
          'ต่อใช่ไหมคะ?',
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isSaving = true);
    try {
      // ล้างทั้งไฟและน้ำพร้อมกัน จึงลบทั้งแถวประวัติ/บิลคู่กันได้เลย ไม่ต้องเช็คว่าอีก
      // ยูทิลิตี้ยังมีข้อมูลเหลือไหมเหมือน _confirmDelete (ที่ลบแยกทีละยูทิลิตี้)
      if (_editingRecordId != null) {
        await widget.firestoreService
            .deleteStartMeterRecord(widget.uid, _editingRecordId!);
        final pairedBill = _existingBills.where(
            (b) => b.year == _selectedYear && b.month == _selectedMonth);
        if (pairedBill.isNotEmpty && pairedBill.first.source == 'startMeter') {
          await widget.firestoreService
              .deleteBill(widget.uid, pairedBill.first.id);
        }
      }

      await widget.firestoreService.updateUser(widget.uid, {
        'startElectricityValue': 0,
        'startPeakValue': 0,
        'startOffPeakValue': 0,
        'startWaterValue': 0,
        'startBillingMonth': 0,
        'startBillingYear': 0,
        'startMeterConfigured': false,
        'electricityStartConfigured': false,
        'waterStartConfigured': false,
      });
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

  @override
  Widget build(BuildContext context) {
    // ชีตหดตามคีย์บอร์ด ปุ่มบันทึกด้านล่างจึงอยู่เหนือคีย์บอร์ดเสมอ
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.9 - bottomInset;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: height < 320 ? 320 : height,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: AppSpacing.v10),
                  const _SheetGrabber(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v6, AppSpacing.v8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('เลขมิเตอร์จากใบแจ้งหนี้',
                              style: TextStyle(
                                  fontSize: AppTypography.s17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark)),
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
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.v16, AppSpacing.v4, AppSpacing.v16, AppSpacing.v24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ชวนตั้งวันตัดรอบบิล — เฉพาะบัญชีที่ยังไม่เคยเลือกวันเอง
                          if (_user?.billingDayConfigured == false) ...[
                            _billingDayPrompt(),
                            const SizedBox(height: AppSpacing.v12),
                          ],
                          _invoiceMonthCard(),
                          const SizedBox(height: AppSpacing.v16),
                          // ใช้ widget กลาง StartMeterPairedFields (widgets/start_meter_fields.dart)
                          StartMeterPairedFields(
                            isTou: widget.isTou,
                            area: _user?.area ?? 'bangkok',
                            electricityCtrl: _eCtrl,
                            peakCtrl: _peakCtrl,
                            offPeakCtrl: _offPeakCtrl,
                            eCostCtrl: _eCostCtrl,
                            waterCtrl: _wCtrl,
                            wCostCtrl: _wCostCtrl,
                            eUsedCtrl: _eUsedCtrl,
                            wUsedCtrl: _wUsedCtrl,
                            eUsedPeakCtrl: _eUsedPeakCtrl,
                            eUsedOffPeakCtrl: _eUsedOffPeakCtrl,
                            eIsFirstEntry: _eIsFirstEntry,
                            wIsFirstEntry: _wIsFirstEntry,
                            eNoBillYet: _electricityNoBillYet,
                            onENoBillYetChanged: (v) => setState(() {
                              _electricityNoBillYet = v;
                              if (v) _eCostCtrl.clear();
                            }),
                            wNoBillYet: _waterNoBillYet,
                            onWNoBillYetChanged: (v) => setState(() {
                              _waterNoBillYet = v;
                              if (v) _wCostCtrl.clear();
                            }),
                            subtitle: 'มีบิลฝั่งไหนก็กรอกแค่ฝั่งนั้นได้ค่ะ',
                            eUsageSummary: _eUsageSummary,
                            wUsageSummary: _wUsageSummary,
                          ),
                          if (_eBelowPrevious || _wBelowPrevious) ...[
                            const SizedBox(height: AppSpacing.v12),
                            _note(
                              '${[
                                if (_eBelowPrevious) 'เลขมิเตอร์ไฟฟ้าที่กรอกต่ำกว่ารอบก่อนหน้า',
                                if (_wBelowPrevious) 'เลขมิเตอร์น้ำที่กรอกต่ำกว่ารอบก่อนหน้า',
                              ].join(' และ ')}'
                              ' กรุณาตรวจสอบว่าพิมพ์ถูกไหมค่ะ (เลขมิเตอร์สะสมควรเพิ่มขึ้นทุกรอบ)',
                            ),
                          ],
                          if (_generalError) ...[
                            const SizedBox(height: AppSpacing.v12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                                const SizedBox(width: AppSpacing.v6),
                                Expanded(
                                  child: Text(
                                    'กรอกให้ครบอย่างน้อย 1 ประเภท (ไฟฟ้า หรือ น้ำ) ก่อนถึงจะบันทึกได้',
                                    style: TextStyle(
                                        fontSize: AppTypography.s12, height: 1.4, color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          // ล้างได้เฉพาะตอนแก้เลขของรอบปัจจุบัน — ตอนกรอกรอบใหม่ ค่าต้นรอบ
                          // ที่มีอยู่เป็นของรอบที่แล้ว (หมดอายุแล้ว) ไม่มีอะไรให้ล้าง
                          if (_isEditingCurrentCycle) ...[
                            const SizedBox(height: AppSpacing.v16),
                            TextButton.icon(
                              onPressed: _isSaving ? null : _confirmClearStartMeter,
                              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('ล้างเลขมิเตอร์ต้นรอบ'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.v16, AppSpacing.v12, AppSpacing.v16, AppSpacing.v16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('บันทึก'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // เดือนของใบแจ้งหนี้ที่กำลังกรอก — ระบบเลือกให้จาก billingDay (ผู้ใช้เลือกเองไม่ได้)
  // ป้าย "แก้ไข" = แก้ค่าของรอบปัจจุบันที่ตั้งไว้แล้ว, "ตั้งใหม่" = รอบใหม่
  Widget _invoiceMonthCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          const IconBadge(icon: Icons.receipt_long_outlined, color: AppColors.primaryGreen, size: 40),
          const SizedBox(width: AppSpacing.v12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ใบแจ้งหนี้เดือน', style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                Text(_monthYearLabel(_selectedMonth, _selectedYear),
                    style: const TextStyle(
                        fontSize: AppTypography.s15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                if (_isEditingCurrentCycle)
                  Text('แก้ไขได้จนกว่าจะถึงรอบบิลถัดไป',
                      style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (_user != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.v20),
              ),
              child: Text(
                _isEditingCurrentCycle ? 'แก้ไข' : 'ตั้งใหม่',
                style: const TextStyle(
                    fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
              ),
            ),
        ],
      ),
    );
  }

  Widget _billingDayPrompt() {
    return Material(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SettingsScreen(
                quickAction: SettingsQuickAction.billingDay,
                firestoreService: widget.firestoreService,
              ),
            ),
          );
          if (mounted) await _loadCurrent();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v10),
          child: Row(
            children: [
              const Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.warningIcon),
              const SizedBox(width: AppSpacing.v8),
              const Expanded(
                child: Text('ยังไม่ได้ตั้งวันตัดรอบบิล ตั้งไปพร้อมกันไหมคะ',
                    style: TextStyle(
                        fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: AppColors.warningText)),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningIcon),
          const SizedBox(width: AppSpacing.v8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: AppTypography.s12, height: 1.45, color: AppColors.warningText)),
          ),
        ],
      ),
    );
  }
}
