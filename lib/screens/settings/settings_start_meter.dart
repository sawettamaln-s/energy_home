part of 'settings_screen.dart';

// ใบแจ้งหนี้ล่าสุดที่ควรใช้เป็นต้นรอบตอนนี้ คำนวณจาก billingDay จริงของ user (ไม่ใช่เดือนปฏิทิน)
// สูตรเดียวกับ dashboard_screen.dart: bill.month ของรอบที่เพิ่งปิด = getCycleStart(now, billingDay).month
// (ห้ามใช้ getPreviousCycleStart ซ้อนอีกชั้น จะได้เดือนเก่ากว่าที่ควร 1 รอบ)
DateTime _expectedInvoiceMonth(int billingDay) {
  final now = DateTime.now();
  return EnergyForecaster.getCycleStart(now, billingDay);
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

  // ค่าใช้จ่ายของบิลล่าสุด จับคู่กับเลขมิเตอร์ต้นรอบของยูทิลิตี้เดียวกัน
  // กรอกเลขมิเตอร์ไฟต้องกรอกค่าไฟด้วย (หรือเว้นว่างทั้งคู่) เช่นเดียวกับน้ำ
  // กติกาอยู่ที่ StartMeterValidation (widgets/start_meter_fields.dart)
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
    _loadCurrent();
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
          user.startBillingMonth == expected.month &&
          user.startBillingYear == expected.year;

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

      // prefill ค่าใช้จ่าย ถ้าเดือน/ปีนี้มีบิลบันทึกไว้แล้ว
      final existingBill = _existingBills.where(
          (b) => b.year == _selectedYear && b.month == _selectedMonth);
      if (existingBill.isNotEmpty) {
        final b = existingBill.first;
        _eCostCtrl.text = b.electricityCost == 0 ? '' : b.electricityCost.toString();
        _wCostCtrl.text = b.waterCost == 0 ? '' : b.waterCost.toString();
        _eUsedCtrl.text = b.electricityUsed == 0 ? '' : b.electricityUsed.toString();
        _wUsedCtrl.text = b.waterUsed == 0 ? '' : b.waterUsed.toString();
        // prefill คู่ TOU ด้วย (ช่อง On/Off ของ "หน่วยที่ใช้ไปแล้ว") ตอนกลับมาแก้ไขค่าที่เพิ่งบันทึก
        _eUsedPeakCtrl.text =
            b.electricityPeakUsed == 0 ? '' : b.electricityPeakUsed.toString();
        _eUsedOffPeakCtrl.text = b.electricityOffPeakUsed == 0
            ? ''
            : b.electricityOffPeakUsed.toString();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
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

  // หา record ก่อนหน้าที่ใกล้ที่สุด (ไม่นับตัวที่กำลังแก้ไข) เอาไว้คำนวณหน่วยที่ใช้ไปในรอบที่เพิ่งปิด (delta)
  StartMeterRecordModel? get _previousRecord {
    final candidates = _history.where((r) =>
        r.id != _editingRecordId &&
        (r.billingYear < _selectedYear ||
            (r.billingYear == _selectedYear &&
                r.billingMonth < _selectedMonth)));
    if (candidates.isEmpty) return null;
    final list = candidates.toList()
      ..sort((a, b) => (b.billingYear * 12 + b.billingMonth)
          .compareTo(a.billingYear * 12 + a.billingMonth));
    return list.first;
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
          await _recalcCurrentCycleLogs(
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
        final prev = _previousRecord;
        double wUsed = _wIsFirstEntry ? wUsedInput : 0;
        // TOU: หน่วยที่ใช้คำนวณจากคู่ On-Peak/Off-Peak เสมอ (electricityValue ไม่เคยถูกเซ็ตสำหรับ TOU)
        double eUsed = widget.isTou ? 0 : (_eIsFirstEntry ? eUsedInput : 0);
        double ePeakUsed = widget.isTou && _eIsFirstEntry
            ? parseNumInput(_eUsedPeakCtrl.text)
            : 0;
        double eOffPeakUsed = widget.isTou && _eIsFirstEntry
            ? parseNumInput(_eUsedOffPeakCtrl.text)
            : 0;
        if (prev != null) {
          if (widget.isTou) {
            if (eComplete && prev.peakValue > 0 && peakVal > prev.peakValue) {
              ePeakUsed = peakVal - prev.peakValue;
            }
            if (eComplete &&
                prev.offPeakValue > 0 &&
                offPeakVal > prev.offPeakValue) {
              eOffPeakUsed = offPeakVal - prev.offPeakValue;
            }
          } else if (eComplete &&
              prev.electricityValue > 0 &&
              eVal > prev.electricityValue) {
            eUsed = eVal - prev.electricityValue;
          }
          if (wComplete && prev.waterValue > 0 && wVal > prev.waterValue) {
            wUsed = wVal - prev.waterValue;
          }
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
          await widget.firestoreService.saveBill(
            BillModel(
              id: existingBillForMonth?.id ?? const Uuid().v4(),
              uid: widget.uid,
              year: _selectedYear,
              month: _selectedMonth,
              electricityCost: newECost,
              waterCost: newWCost,
              totalCost: newECost + newWCost,
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
              fixedCost: existingBillForMonth?.fixedCost ?? 0,
              forecastElectricity: existingBillForMonth?.forecastElectricity ?? 0,
              forecastWater: existingBillForMonth?.forecastWater ?? 0,
              forecastTotal: existingBillForMonth?.forecastTotal ?? 0,
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

  // ไล่คำนวณ usedFromStart + cost ของ log รายวันทุกอันในรอบปัจจุบันใหม่ตามเลขต้นรอบที่แก้ไข แล้ว resave ทับของเดิม
  Future<void> _recalcCurrentCycleLogs({
    required bool recalcElectricity,
    required bool recalcWater,
    required double newStartE,
    required double newStartPeak,
    required double newStartOffPeak,
    required double newStartW,
  }) async {
    final user = _user;
    if (user == null) return;
    final now = DateTime.now();
    final startDate = EnergyForecaster.getCycleStart(now, user.billingDay);
    final endDate = EnergyForecaster.getCycleEnd(now, user.billingDay);

    if (recalcElectricity) {
      final logs = await widget.firestoreService
          .getCurrentMonthElectricityLogs(widget.uid, startDate, endDate);
      for (final log in logs) {
        double usedFromStart;
        double cost;
        if (widget.isTou) {
          final peakUnits = EnergyCalculator.calculateUsed(
              log.peakMeterValue ?? 0, newStartPeak);
          final offPeakUnits = EnergyCalculator.calculateUsed(
              log.offPeakMeterValue ?? 0, newStartOffPeak);
          usedFromStart = peakUnits + offPeakUnits;
          cost = await EnergyCalculator.calculateElectricityByType(
            units: 0,
            meterType: 'tou',
            area: user.area,
            peakUnits: peakUnits,
            offPeakUnits: offPeakUnits,
          );
        } else {
          usedFromStart =
              EnergyCalculator.calculateUsed(log.meterValue, newStartE);
          cost = await EnergyCalculator.calculateElectricityByType(
            units: usedFromStart,
            meterType: 'normal',
            area: user.area,
          );
        }
        await widget.firestoreService.saveElectricityLog(
          ElectricityLogModel(
            id: log.id,
            uid: log.uid,
            date: log.date,
            meterValue: log.meterValue,
            peakMeterValue: log.peakMeterValue,
            offPeakMeterValue: log.offPeakMeterValue,
            usedFromStart: usedFromStart,
            usedFromLast: log.usedFromLast,
            cost: cost,
            isMonthEnd: log.isMonthEnd,
          ),
        );
      }
    }

    if (recalcWater) {
      final logs = await widget.firestoreService
          .getCurrentMonthWaterLogs(widget.uid, startDate, endDate);
      for (final log in logs) {
        final usedFromStart =
            EnergyCalculator.calculateUsed(log.meterValue, newStartW);
        final cost = EnergyCalculator.calculateWater(usedFromStart, user.area);
        await widget.firestoreService.saveWaterLog(
          WaterLogModel(
            id: log.id,
            uid: log.uid,
            date: log.date,
            meterValue: log.meterValue,
            usedFromStart: usedFromStart,
            usedFromLast: log.usedFromLast,
            cost: cost,
            isMonthEnd: log.isMonthEnd,
          ),
        );
      }
    }
  }

  // ล้างเลขมิเตอร์ต้นรอบจริง (user.startElectricityValue ฯลฯ) — คนละอันกับลบประวัติ (snapshot) ต้อง confirm แยกเพราะกระทบมากกว่า
  Future<void> _confirmClearStartMeter() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'ล้างเลขมิเตอร์ต้นรอบ',
      content: 'เลขมิเตอร์ต้นรอบทั้งหมดจะถูกล้าง ต้องตั้งค่าใหม่ก่อนถึงจะ'
          'บันทึกมิเตอร์รายวันต่อได้\n\nประวัติมิเตอร์ที่บันทึกไว้ในรอบนี้'
          'จะยังอยู่ แต่จะคำนวณอ้างอิงกับต้นรอบเดิมไม่ได้แล้ว จนกว่าจะตั้ง'
          'ค่าต้นรอบใหม่อีกครั้ง ต้องการดำเนินการต่อใช่ไหมคะ?',
    );
    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'บันทึกมิเตอร์ต้นรอบ',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ลิงก์ชวนตั้งวันตัดรอบบิล — โชว์เฉพาะบัญชีที่ยังไม่เคยเลือกวันเอง กดแล้วเปิดหน้าตั้งค่า
                        if (_user?.billingDayConfigured == false)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsScreen(
                                        quickAction:
                                            SettingsQuickAction.billingDay),
                                  ),
                                );
                                if (mounted) await _loadCurrent();
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.event_repeat,
                                        size: 17,
                                        color: Colors.grey.shade700),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'ยังไม่ได้ตั้งวันตัดรอบบิล ตั้งไปพร้อมกันไหม',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios,
                                        size: 12, color: Colors.grey.shade500),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // ตัดกล่องแบนเนอร์บอกโหมดแก้ไข/ตั้งใหม่ออก เพราะซ้ำกับสิ่งที่ส่วนเลือกเดือนสื่อสารอยู่แล้ว เหลือแค่ tag เล็กๆ
                        Row(
                          children: [
                            const Text(
                              'เดือนของใบแจ้งหนี้',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            if (_user != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _isEditingCurrentCycle ? 'แก้ไข' : 'ตั้งใหม่',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ไม่ให้เลือกเดือน/ปีอิสระอีกต่อไป เพราะระบบรู้อยู่แล้วว่าเดือนไหนควรตั้งจาก billingDay
                        // โหมดแก้ไข: แสดงเป็นข้อความเฉยๆ ไม่ให้เปลี่ยน / โหมดตั้งใหม่: แสดงเดือนที่คำนวณอัตโนมัติเดือนเดียว
                        if (_isEditingCurrentCycle)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${thaiMonths[_selectedMonth - 1]} $_selectedYear',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'แก้ไขได้จนกว่าจะถึงรอบบิลถัดไป',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        else
                          // เลือกเดือนให้อัตโนมัติจาก billingDay จริง (ถูกต้องแม้วันสุดท้ายก่อนตัดรอบ ดู getCycleStart ใน forecaster.dart)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF2E7D32).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${thaiMonths[_selectedMonth - 1]} $_selectedYear',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2E7D32)),
                            ),
                          ),
                        const SizedBox(height: 4),
                        // ใช้ widget กลาง StartMeterPairedFields ร่วมกับ setup_screen.dart ไม่ต้องแก้ 2 ที่แยกกัน
                        StartMeterPairedFields(
                          isTou: widget.isTou,
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
                          // ไม่ส่ง title ซ้ำ — sheet นี้มีหัว "บันทึกมิเตอร์ต้นรอบ" อยู่แล้ว
                          subtitle: 'กรอกจากใบแจ้งหนี้เดือนที่เลือกไว้ด้านบน '
                              'มีบิลฝั่งไหนก็กรอกแค่ฝั่งนั้น',
                        ),
                        if (_generalError) ...[
                          const SizedBox(height: 8),
                          Text(
                            'กรอกให้ครบอย่างน้อย 1 ประเภท (ไฟฟ้า หรือ น้ำ) '
                            'ก่อนถึงจะบันทึกได้',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.red.shade600),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const Text('บันทึก'),
                          ),
                        ),
                        if (_user?.startMeterConfigured == true) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: TextButton.icon(
                              onPressed:
                                  _isSaving ? null : _confirmClearStartMeter,
                              icon: Icon(Icons.delete_forever_outlined,
                                  size: 18, color: Colors.red.shade300),
                              label: Text(
                                'ล้างเลขมิเตอร์ต้นรอบ',
                                style: TextStyle(color: Colors.red.shade300),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

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

  // เช็คว่าตั้งค่าของรอบปัจจุบันครบแล้วไหม สูตรเดียวกับ _AddStartMeterSheetState — ใช้ซ่อนปุ่ม (+) เมื่อครบแล้ว
  bool get _currentCycleConfigured {
    final user = _user;
    if (user == null) return false;
    final expected = _expectedInvoiceMonth(user.billingDay);
    return user.startMeterConfigured &&
        user.startBillingMonth == expected.month &&
        user.startBillingYear == expected.year;
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
            forecastElectricity: pairedBill.forecastElectricity,
            forecastWater: pairedBill.forecastWater,
            forecastTotal: pairedBill.forecastTotal,
            source: pairedBill.source,
          ),
        );
      }
    } else {
      // อีกยูทิลิตี้ไม่มีข้อมูลอยู่แล้ว — ลบทั้งแถว/บิลได้เลยเหมือนเดิม
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('บันทึกมิเตอร์ต้นรอบ'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
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
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
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
                      borderRadius: BorderRadius.circular(14),
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
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (tabRecords.isNotEmpty)
                          Text(
                            'ล่าสุด ${thaiMonths[tabRecords.first.billingMonth - 1]}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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
              backgroundColor: const Color(0xFF2E7D32),
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
          final isCurrentCycleRow =
              _currentCycleConfigured && r.id == latestId;
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