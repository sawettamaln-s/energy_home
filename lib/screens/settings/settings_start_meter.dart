part of 'settings_screen.dart';

// ใบแจ้งหนี้ล่าสุดที่ "ควร" ใช้เป็นต้นรอบตอนนี้ คำนวณจากวันตัดรอบบิลจริง
// ของ user (billingDay) ไม่ใช่แค่เดือนปฏิทินก่อนหน้าเฉยๆ — ใช้สูตรเดียวกับที่
// dashboard_screen.dart ใช้ตอน compileBill() เป๊ะๆ: bill.month ของรอบที่
// เพิ่งปิดไป = getCycleStart(now, billingDay).month (เพราะ "จุดเริ่มต้นของ
// รอบที่กำลังเปิดอยู่ตอนนี้" ก็คือ "จุดสิ้นสุดของรอบก่อนหน้าที่เพิ่งปิดไป"
// นั่นเอง เป็นจุดเดียวกัน) — ต้องใช้สูตรนี้ตรงๆ ไม่ใช่ getPreviousCycleStart
// ต่ออีกที (เคยพลาดใส่ getPreviousCycleStart เพิ่มไปอีกชั้นซึ่งจะได้เดือน
// เก่ากว่าที่ควรไป 1 รอบเต็มๆ) — ย้ายออกมาเป็นฟังก์ชันกลางระดับไฟล์ เพราะ
// ทั้ง _AddStartMeterSheetState และ _StartMeterHistoryScreenState ต้องใช้
// เช็คว่า "รอบตอนนี้ตั้งค่าครบแล้วหรือยัง" เหมือนกัน
DateTime _expectedInvoiceMonth(int billingDay) {
  final now = DateTime.now();
  return EnergyForecaster.getCycleStart(now, billingDay);
}

// ==================== บันทึกเลขมิเตอร์ต้นรอบ (bottom sheet) ====================
// เดิมเป็น AlertDialog แยกอยู่คนละหน้ากับ "ประวัติเลขมิเตอร์ต้นรอบ" — ย้ายมา
// เป็น bottom sheet แบบเดียวกับ _AddHistoricalBillSheet แล้วรวมเข้ากับหน้า
// ประวัติผ่านปุ่ม FAB "+" แทน ตามที่ขอ (กดดูประวัติ + เพิ่มค่าใหม่ได้ในหน้า
// เดียวกันเลย ไม่ต้องสลับไปมา 2 หน้าเหมือนก่อน)
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

  // ----- ค่าใช้จ่ายของบิลล่าสุด (จับคู่กับเลขมิเตอร์ต้นรอบของยูทิลิตี้
  // เดียวกัน) -----
  // เดิมเป็นช่องเสริมแยกก้อนล่าง ไม่บังคับ ทำให้งงว่าทำไมต้องกรอก "2 ชุด"
  // ในฟอร์มเดียว (เลขมิเตอร์ vs ค่าใช้จ่าย) ตอนนี้เปลี่ยนเป็นจับคู่ตาม
  // ยูทิลิตี้แทน: กรอกเลขมิเตอร์ไฟต้องกรอกค่าไฟด้วย (หรือเว้นว่างทั้งคู่)
  // เช่นเดียวกับน้ำ — กติกาอยู่ที่ StartMeterValidation (widgets/
  // start_meter_fields.dart) ใช้ร่วมกับ setup_screen.dart จุดเดียวกัน
  final _eCostCtrl = TextEditingController();
  final _wCostCtrl = TextEditingController();
  // ช่องที่ 3 "หน่วยที่ใช้ไปแล้ว" — โชว์เฉพาะตอนเป็นการตั้งค่าครั้งแรกสุด
  // ของยูทิลิตี้นั้นๆ (ดู _eIsFirstEntry/_wIsFirstEntry ด้านล่าง)
  final _eUsedCtrl = TextEditingController();
  final _wUsedCtrl = TextEditingController();
  // TOU เท่านั้น: คู่ On-Peak/Off-Peak ของ "หน่วยที่ใช้ไปแล้ว" (ครั้งแรกสุด)
  // แทน _eUsedCtrl ตัวเดียว — ผลรวมของสองช่องนี้คือค่าที่เอาไปใช้จริง
  // (ดู StartMeterPairedFields/_usedFieldTou)
  final _eUsedPeakCtrl = TextEditingController();
  final _eUsedOffPeakCtrl = TextEditingController();
  bool _electricityNoBillYet = false;
  bool _waterNoBillYet = false;
  // โชว์ตอนกดบันทึกแล้วไม่มีคู่ไหนกรอกครบเลยสักคู่ (ทั้งคู่ว่างหรือกรอก
  // ไม่ครบทั้งคู่) ต่างจาก error รายการ์ดที่ widget จัดการเองเวลากรอกครึ่งเดียว
  bool _generalError = false;
  List<BillModel> _existingBills = [];
  List<StartMeterRecordModel> _history = [];

  // ใช้เป็นค่า default แบบเร็วๆ ก่อนที่ _loadCurrent() จะรู้ billingDay จริง
  // ของ user (ตอนโหลดครั้งแรก _user ยังเป็น null อยู่) — ใช้ billingDay
  // สมมติ 30 เป็นค่าเริ่มต้นชั่วคราวเหมือนจุดอื่นในแอปที่ fallback แบบนี้
  static DateTime get _defaultInvoiceMonth {
    return _expectedInvoiceMonth(30);
  }

  int _selectedMonth = _defaultInvoiceMonth.month;
  int _selectedYear = _defaultInvoiceMonth.year;
  bool _isSaving = false;

  // ถ้าไม่ null แปลว่าค่าที่ตั้งไว้ล่าสุดยังตรงกับรอบที่ควรตั้งตอนนี้พอดี
  // (ยังไม่ข้ามวันตัดรอบไปอีกรอบ) → กด "บันทึก" จะแก้ทับ record นี้แทน
  // การสร้าง entry ใหม่ในประวัติ กันไม่ให้ตั้งค่า "รอบใหม่" ซ้ำไม่จำกัดจน
  // ประวัติรกไปด้วยรายการที่จริงๆ เป็นรอบเดียวกันหมด
  String? _editingRecordId;

  // ใช้โชว์ label ในฟอร์มให้ผู้ใช้รู้ว่ากำลังแก้ไขค่าที่เพิ่งตั้งไปหรือ
  // กำลังตั้งค่าต้นรอบใหม่สำหรับรอบถัดไป
  bool get _isEditingCurrentCycle => _editingRecordId != null;

  @override
  void initState() {
    super.initState();
    // ให้ทุกช่องรีเฟรช error ของการ์ดคู่ (isPartial ใน StartMeterPairedFields)
    // แบบ live ทันทีที่พิมพ์ ไม่ต้องรอกดบันทึกก่อนถึงจะเห็นว่ากรอกไม่ครบคู่
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

  // ดึงค่าปัจจุบันของ user มาตั้งเป็นค่าเริ่มต้นในฟอร์ม
  // ไม่ได้รับ UserModel มาจากหน้าก่อนหน้าตรงๆ เพื่อให้ widget นี้ใช้งาน
  // ได้เองอิสระ ไม่ผูกกับ state ของหน้าตั้งค่า
  //
  // แก้บั๊ก: เดิมกด "บันทึกเลขมิเตอร์ต้นรอบ" กี่ครั้งก็ได้ไม่จำกัด ทุกครั้ง
  // สร้าง record ใหม่ในประวัติเสมอ แม้จะยังอยู่รอบเดิม (ยังไม่ข้ามวันตัด
  // รอบบิลไปอีกรอบ) ทำให้ประวัติมีรายการซ้ำซ้อนของรอบเดียวกันได้ไม่จำกัด
  // ตอนนี้เช็คก่อนว่าค่าที่ตั้งไว้ล่าสุดตรงกับ "รอบที่ควรตั้งตอนนี้" ไหม
  // (คำนวณจาก billingDay จริง ไม่ใช่เดาจากเดือนปฏิทิน) ถ้าตรง = โหมดแก้ไข
  // (แก้ทับของเดิม) ถ้าไม่ตรง (ยังไม่เคยตั้ง หรือรอบขยับไปแล้ว) = โหมด
  // ตั้งค่าใหม่ (ฟอร์มว่าง สร้าง record ใหม่ตามปกติ)
  Future<void> _loadCurrent() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    _user = user;
    _existingBills = await widget.firestoreService.getBills(widget.uid);
    // โหลดประวัติเสมอ (เดิมโหลดแค่ตอนโหมดแก้ไข) เพราะตอนบันทึกต้องใช้หา
    // "ค่าสะสมของรอบก่อนหน้า" มาคำนวณหน่วยที่ใช้ไปของรอบที่เพิ่งปิด (delta)
    // ให้บิลที่สร้างอัตโนมัติ ไม่ใช่โชว์แค่ยอดเงินอย่างเดียวเหมือนเดิม
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

        // หา record ล่าสุดในประวัติ (ควรเป็นตัวเดียวกับที่เพิ่งเซ็ตค่านี้)
        // เพื่อเอา id มาใช้แก้ทับตอนบันทึก แทนการสร้างใหม่
        _editingRecordId = _history.isNotEmpty ? _history.first.id : null;
      } else {
        // โหมดตั้งใหม่: ยังไม่เคยตั้ง หรือรอบขยับไปแล้ว (ผ่านวันตัดรอบ
        // บิลมาแล้ว) → ฟอร์มว่าง ตั้ง default เดือน/ปีเป็นรอบที่ควรตั้ง
        // ตอนนี้จริงๆ (ไม่ใช่ค่าเก่าที่ค้างจากรอบก่อน)
        _eCtrl.clear();
        _peakCtrl.clear();
        _offPeakCtrl.clear();
        _wCtrl.clear();
        _selectedMonth = expected.month;
        _selectedYear = expected.year;
        _editingRecordId = null;
      }

      // prefill ค่าใช้จ่าย ถ้าเดือน/ปีนี้มีบิลบันทึกไว้แล้ว (เช่นกลับมาแก้ไข
      // ค่าที่เพิ่งบันทึกไปในรอบเดียวกัน) กันไม่ให้ต้องพิมพ์ซ้ำของเดิม
      final existingBill = _existingBills.where(
          (b) => b.year == _selectedYear && b.month == _selectedMonth);
      if (existingBill.isNotEmpty) {
        final b = existingBill.first;
        _eCostCtrl.text = b.electricityCost == 0 ? '' : b.electricityCost.toString();
        _wCostCtrl.text = b.waterCost == 0 ? '' : b.waterCost.toString();
        _eUsedCtrl.text = b.electricityUsed == 0 ? '' : b.electricityUsed.toString();
        _wUsedCtrl.text = b.waterUsed == 0 ? '' : b.waterUsed.toString();
        // เดิมลืม prefill คู่ TOU ตรงนี้ — ทำให้ตอนกลับมาแก้ไขค่าที่เพิ่ง
        // บันทึกไปในรอบเดียวกัน ช่อง On/Off ของ "หน่วยที่ใช้ไปแล้ว" ว่างเปล่า
        // ทั้งที่เลขมิเตอร์สะสมกับยอดเงินยัง prefill ให้ถูกต้องอยู่แล้ว
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

  // เป็นการตั้งค่าครั้งแรกสุดของยูทิลิตี้นั้นๆ ไหม (ไม่เคยมี record ก่อนหน้า
  // ที่มีค่า > 0 มาก่อนเลย) — เช็คแยกรายยูทิลิตี้ ไม่ใช่เช็ครวมทั้งบัญชี
  // เพราะตั้งแยกยูทิลิตี้ได้อิสระ (เช่น ตั้งไฟมาตั้งแต่เดือน 3 แต่เพิ่งมี
  // บิลน้ำใบแรกเดือน 6 — ฝั่งน้ำยังนับเป็นครั้งแรกอยู่ ทั้งที่ฝั่งไฟไม่ใช่)
  // ไม่นับ record ที่กำลังแก้ไขอยู่ (_editingRecordId) กันกรณีแก้ไข record
  // แรกสุดของตัวเองแล้วเข้าใจผิดว่ามี "record อื่น" อยู่ก่อนหน้า
  // มิเตอร์ TOU ไม่เคยเซ็ต electricityValue เลย (ใช้ peakValue/offPeakValue
  // แทน) เช็คแบบเดิม (r.electricityValue > 0) เลยเจอ record ก่อนหน้าไม่ได้
  // สักตัว ทำให้ TOU ถูกตีความว่าเป็น "ครั้งแรกสุด" ทุกครั้งไม่ว่าจะเคย
  // ตั้งมากี่รอบแล้วก็ตาม ผลคือฟอร์มโชว์ช่อง "หน่วยที่ใช้ไปแล้ว" ทุกรอบ (ควร
  // โชว์แค่รอบแรกจริงๆ) และตอนบันทึกก็ไม่เคยคำนวณ delta จากรอบก่อนหน้าให้เลย
  bool get _eIsFirstEntry => !_history.any((r) =>
      r.id != _editingRecordId &&
      (widget.isTou
          ? (r.peakValue > 0 || r.offPeakValue > 0)
          : r.electricityValue > 0));
  bool get _wIsFirstEntry =>
      !_history.any((r) => r.id != _editingRecordId && r.waterValue > 0);

  // หา record ก่อนหน้าที่ใกล้ที่สุดในประวัติ (ไม่นับตัวที่กำลังแก้ไขอยู่)
  // เอาไว้คำนวณ "หน่วยที่ใช้ไปในรอบที่เพิ่งปิด" = ค่าสะสมรอบนี้ - ค่าสะสม
  // รอบก่อนหน้า — ถ้าไม่มี record ก่อนหน้าเลย (ตั้งครั้งแรกสุด) จะคำนวณ
  // ไม่ได้ ปล่อยเป็น null แล้วให้บิลที่สร้างมีแต่ค่าใช้จ่ายอย่างเดียวไปก่อน
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
    // TOU: หน่วยที่ใช้ไปแล้ว (ครั้งแรกสุด) มาจากผลรวม On-Peak/Off-Peak ที่
    // กรอกแยก แทนช่องเดียวแบบเดิม (สอดคล้องกับที่ widget ใช้ auto-sum แล้ว)
    final eUsedInput = widget.isTou
        ? parseNumInput(_eUsedPeakCtrl.text) + parseNumInput(_eUsedOffPeakCtrl.text)
        : parseNumInput(_eUsedCtrl.text);
    final wUsedInput = parseNumInput(_wUsedCtrl.text);

    // กติกาจับคู่ + อย่างน้อย 1 คู่ต้องครบ + ช่องที่ 3 (ถ้าโชว์) ใช้ตัวเดียว
    // กับที่ widget ใช้โชว์ error รายการ์ด กันไม่ให้ UI กับตอน save เช็คคน
    // ละเกณฑ์กัน
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

      // อัปเดตเฉพาะยูทิลิตี้ที่กรอกครบคู่จริงๆ เท่านั้น — ถ้าอีกฝั่งเว้นว่าง
      // ไว้ (เช่น มีแค่บิลไฟ ไม่มีบิลน้ำตอนนี้) ต้องไม่ไปเขียนทับค่าที่เคย
      // ตั้งไว้ก่อนหน้าของฝั่งนั้นด้วยศูนย์โดยไม่ตั้งใจ
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
      // เคยข้ามมาก่อนหรือไม่ก็ตาม พอมีอย่างน้อย 1 ยูทิลิตี้ครบแล้ว = ถือว่า
      // configured แล้วในความหมายรวม (จุดอื่นที่ยังอ้างอิง flag รวมอยู่ เช่น
      // dashboard_screen.dart จะยังทำงานถูกต้องต่อไปได้)
      updates['startMeterConfigured'] = true;

      await widget.firestoreService.updateUser(widget.uid, updates);

      // แก้บั๊ก: usedFromStart/cost ของ log รายวันแต่ละอัน เป็น snapshot ที่
      // คำนวณตอนกดบันทึกครั้งนั้นๆ ค้างไว้เฉยๆ ไม่ได้คำนวณสดจาก
      // startElectricityValue/startWaterValue ปัจจุบันทุกครั้ง — พอมาแก้ไข
      // เลขต้นรอบของรอบปัจจุบัน (เช่น กรอกผิดแล้วมาแก้ทีหลัง) ตัวเลขสะสมที่
      // หน้าหลักโชว์ (อ่านจาก log ล่าสุดตรงๆ) จะยังผิดค้างต่อไปจนกว่าจะไปลบ/
      // แก้ log เองทีละอัน ตอนนี้ถ้าอยู่ในโหมดแก้ไขรอบปัจจุบันและค่าที่กรอก
      // เปลี่ยนไปจากเดิมจริง ให้ไล่คำนวณ log ทุกอันในรอบนี้ใหม่ทั้งหมด
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

      // เก็บ snapshot ไว้ในประวัติ เผื่อย้อนดูทีหลังว่าเคยตั้งค่าอะไรไว้
      // ถ้าอยู่ในโหมดแก้ไข (ยังเป็นรอบเดิม) ใช้ id เดิมเพื่อ "แก้ทับ" record
      // เดิมแทนการสร้างรายการใหม่ซ้ำในประวัติ — ป้องกันไม่ให้กดบันทึกซ้ำ
      // หลายครั้งในรอบเดียวกันแล้วประวัติรกไปด้วยรายการที่จริงๆ คือรอบเดียวกัน
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
        // ถ้ากรอกค่าใช้จ่ายไว้ (คู่ไหนครบก็อัปเดต/สร้างของคู่นั้น) บันทึกเป็น
        // บิลของรอบที่เพิ่งปิด ใช้เดือน/ปีเดียวกับที่เลือกไว้ — ถ้าเดือนนี้มี
        // บิลอยู่แล้ว (เช่นเคยกรอกค่าใช้จ่ายไปตอนตั้งค่าครั้งก่อน) ใช้ id เดิม
        // เพื่อ "อัปเดตทับ" แทนการสร้างใหม่ซ้ำ — เดิมจุดนี้เช็ค
        // _lastBillAlreadyRecorded แล้วข้าม save ไปทั้งก้อนถ้ามีบิลอยู่แล้ว
        // ทำให้แก้ค่าใช้จ่ายซ้ำจากหน้านี้ไม่มีผลอะไรเลย (หายเงียบ ไม่มี error
        // แจ้ง) แก้แล้วให้ update บิลเดิมได้จริงแทน
        //
        // แก้บั๊กเดิม: ตอนสร้างบิลนี้ไม่เคยใส่ electricityUsed/waterUsed เลย
        // (มีแต่ cost) พอไปโชว์ในหน้าประวัติบิลเลยเห็นเป็น "0 หน่วย" ทั้งที่
        // จ่ายจริง — ตอนนี้มี 2 ทาง: (1) ถ้ามี record ก่อนหน้าจริง (ไม่ใช่
        // ครั้งแรกสุดของยูทิลิตี้นั้น) คำนวณ delta ให้อัตโนมัติ (2) ถ้าเป็น
        // ครั้งแรกสุด (_eIsFirstEntry/_wIsFirstEntry) ใช้ค่าที่ผู้ใช้กรอกเอง
        // ในช่องที่ 3 ตรงๆ แทน (ผ่าน validation บังคับกรอกมาแล้วตอน canSave)
        final prev = _previousRecord;
        double wUsed = _wIsFirstEntry ? wUsedInput : 0;
        // TOU: หน่วยที่ใช้คำนวณจากคู่ On-Peak/Off-Peak เสมอ (electricityValue
        // ไม่เคยถูกเซ็ตสำหรับ TOU เลย ใช้คำนวณ eUsed แบบเดิมไม่ได้) ผลรวม
        // ของสองค่านี้คือ eUsed รวมที่เอาไปเก็บในบิลด้วย (ดู bill_model.dart)
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
              // 'startMeter' = บิลที่สร้าง/อัปเดตจากหน้าเลขมิเตอร์ต้นรอบ
              // (ต่างจาก 'imported' ที่กรอกเองในหน้าบันทึกบิลย้อนหลัง) —
              // แยกไว้เพื่อให้หน้าบันทึกบิลย้อนหลังรู้ว่ารายการไหนต้องล็อก
              // ไม่ให้แก้ไข/ลบตรงนั้น ต้องมาแก้ที่หน้านี้แทน
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

  // ไล่คำนวณ usedFromStart + cost ของ log รายวันทุกอันในรอบบิลปัจจุบันใหม่
  // ตามเลขต้นรอบที่แก้ไข แล้ว resave ทับของเดิม (id เดิม แค่ค่าเปลี่ยน) —
  // usedFromLast ไม่ต้องแก้ เพราะเป็นผลต่างระหว่างมิเตอร์ 2 ครั้งที่บันทึก
  // จริง ไม่เกี่ยวกับเลขต้นรอบเลย
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

  // ล้างเลขมิเตอร์ต้นรอบ "จริง" ที่หน้าแรกใช้แสดงผล (user.startElectricityValue
  // ฯลฯ) — คนละอันกับการลบประวัติ (StartMeterRecordModel) ที่แค่ลบ snapshot
  // ไว้ดูย้อนหลังเฉยๆ ไม่เคยมีผลกับค่าจริงเลย ปุ่มนี้ตั้งใจแยกไว้ให้ชัดว่า
  // เป็น action ที่กระทบมากกว่า ต้องมี confirm แยกต่างหาก
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
                        // ลิงก์เล็กๆ ชวนตั้งวันตัดรอบบิลไปพร้อมกันเลย — โชว์
                        // เฉพาะบัญชีที่ยังไม่เคยเลือกวันเอง (billingDayConfigured
                        // false) เพราะจังหวะนี้ผู้ใช้กำลังตั้งค่าเริ่มต้นของ
                        // รอบบิลอยู่แล้วพอดี ถือโอกาสชวนตั้งอีกอย่างที่มักลืม
                        // ไปด้วยเลย ไม่ผูกกับ flow เดิม กดแล้วแค่เปิดหน้า
                        // ตั้งค่าพร้อม quickAction เดียวกับที่จุดอื่นใช้อยู่
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
                        // เดิมมีกล่องแบนเนอร์สีเต็มความกว้างแยกต่างหากบอก
                        // โหมดแก้ไข/ตั้งใหม่ แต่พอมาดูของจริงแล้วมันซ้ำกับ
                        // สิ่งที่ส่วนเลือกเดือนด้านล่างสื่อสารอยู่แล้ว (โหมด
                        // แก้ไข = กล่องเทาล็อกไว้เฉยๆ, โหมดตั้งใหม่ = มีให้
                        // เลือก 2 ทาง) เลยตัดออก เหลือแค่ tag เล็กๆ ข้าง label
                        // พอ ไม่ต้องมีกล่องสีเต็มความกว้างซ้อนกันอีกกล่อง
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
                        // แก้ตามที่ทดลองใช้จริงแล้วพบว่าไม่สมเหตุสมผล:
                        // เดิมให้เลือกได้ทั้ง 12 เดือน x 2 ปี (24 ทาง) ทั้งที่
                        // ระบบรู้อยู่แล้วว่า "เดือนที่ควรตั้งตอนนี้" คือเดือน
                        // ไหนจากวันตัดรอบบิลจริง (billingDay) — การให้เลือก
                        // อิสระขนาดนั้นแค่เปิดช่องให้เลือกเดือนที่ไม่ตรงกับ
                        // รอบจริงเลย ซึ่งจะทำให้ระบบ lock (โหมดแก้ไข/ตั้งใหม่)
                        // สับสน เพราะอิงกับเดือนที่คำนวณจาก billingDay เท่านั้น
                        //
                        // ตอนนี้: โหมดแก้ไข (ยังอยู่รอบเดิม) แสดงเป็นข้อความ
                        // เฉยๆ ไม่ให้เปลี่ยน เพราะกำลังแก้ค่าของรอบที่ระบุ
                        // ตายตัวอยู่แล้ว / โหมดตั้งใหม่ แสดงเดือนที่ระบบ
                        // คำนวณให้อัตโนมัติเดือนเดียว ไม่ให้ผู้ใช้เลือกเอง
                        // เลย (เคยมีลิงก์ให้ย้อนไปตั้งรอบก่อนหน้าได้ด้วย แต่
                        // ตัดออกแล้ว ดูเหตุผลที่คอมเมนต์ก่อนกล่องด้านล่าง)
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
                          // ระบบรู้อยู่แล้วว่า "ตอนนี้ควรตั้งค่าเดือนไหน" จาก
                          // billingDay จริง (คำนวณถูกต้องแม้แต่วันสุดท้ายก่อน
                          // ตัดรอบ — ดู getCycleStart ใน forecaster.dart)
                          // จึงเลือกให้อัตโนมัติเลยเดือนเดียว ไม่ต้องให้
                          // ผู้ใช้เลือกเอง (เดิมมีลิงก์ให้ย้อนไปตั้งรอบก่อน
                          // หน้าได้ด้วย แต่เคสที่จำเป็นต้องใช้จริงแคบมาก
                          // ไม่คุ้มกับความซับซ้อนที่เพิ่มใน UI เลยตัดออก)
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
                        // ใช้ widget กลาง (StartMeterPairedFields) แทนโค้ด
                        // ที่เคย copy ไว้เองในนี้ — จับคู่เลขมิเตอร์กับ
                        // ค่าใช้จ่ายของยูทิลิตี้เดียวกันไว้การ์ดเดียวกัน ใช้
                        // ทั้งหน้านี้และตอนสมัครสมาชิก (setup_screen.dart)
                        // ไม่ต้องแก้ 2 ที่แยกกันอีกต่อไป
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
                          // ไม่ส่ง title — sheet นี้มีหัว "บันทึกมิเตอร์ต้นรอบ"
                          // อยู่แล้ว (ดู AppBar/title ด้านบนของ sheet) ใส่ซ้ำ
                          // อีกชั้นแค่ทำให้ดูซ้ำซ้อนโดยไม่จำเป็น
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

// ==================== ประวัติเลขมิเตอร์ต้นรอบ ====================
// อธิบายภาพรวมของหน้า "เลขมิเตอร์ต้นรอบ" ไว้ที่ AppBar ของหน้านี้เลย —
// ตามแพทเทิร์นเดียวกับ _showFixedCostInfoPopup / _showHistoricalBillInfoPopup
// เปิดหน้าตั้งเลขมิเตอร์ต้นรอบจากไฟล์อื่นได้ (เช่น Dashboard ตอนเจอบัญชีที่
// ข้ามขั้นตอนนี้มาจาก setup) — เพราะ _StartMeterHistoryScreen ด้านล่างเป็น
// private ในไฟล์นี้ เข้าถึงจากนอกไฟล์ไม่ได้โดยตรง
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
  // ใช้หาค่าไฟ/ค่าน้ำของแต่ละรอบมาโชว์ในตาราง (คอลัมน์ "ค่าไฟ"/"ค่าน้ำ") —
  // ค่าใช้จ่ายไม่ได้เก็บอยู่ใน StartMeterRecordModel เอง แต่ถูกบันทึกแยก
  // เป็น BillModel (source: startMeter) ตอนกดบันทึกพร้อมกัน จับคู่กันด้วย
  // เดือน/ปีเดียวกัน
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

  // ตั้งค่าของรอบปัจจุบันไว้ครบแล้วไหม (ยังไม่ข้ามวันตัดรอบบิลไปอีกรอบ) —
  // สูตรเดียวกับที่ _AddStartMeterSheetState ใช้เช็คว่าเข้าโหมดแก้ไขหรือ
  // ตั้งใหม่ ใช้ที่นี่เพื่อรู้ว่าควรซ่อนปุ่ม (+) ไหม (ตั้งไว้ครบแล้ว ไม่มี
  // อะไรให้เพิ่มจนกว่าจะถึงวันตัดรอบรอบถัดไป)
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

  // เปิด bottom sheet บันทึกเลขมิเตอร์ต้นรอบ — เดิมเป็นปุ่มแยกอยู่คนละหน้า
  // ในหมวด "ตั้งค่าระบบ" ย้ายมารวมกับหน้าประวัติผ่านปุ่ม FAB นี้แทน
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

  // ลบ record หนึ่งแถว
  //
  // แก้บั๊ก: เดิม record หนึ่งแถวเก็บทั้งไฟและน้ำของเดือนนั้นรวมกันไว้ในก้อน
  // เดียว (electricityValue/peakValue/offPeakValue + waterValue) และบิลคู่กัน
  // ก็เก็บทั้ง electricityCost/waterCost รวมกันด้วยเช่นกัน แต่แท็บไฟฟ้ากับ
  // แท็บประปาต่างก็ render จาก _records ก้อนเดียวกัน พอกดลบจากแท็บไหนก็ตาม
  // (isElectricity บอกว่าเป็นแท็บไหน) เดิมโค้ดลบทั้ง record และบิลทั้งแถวไป
  // เลยไม่สนใจว่าอีกยูทิลิตี้ยังมีข้อมูลอยู่ไหม ทำให้ลบไฟแล้วน้ำหายไปด้วย
  //
  // ตอนนี้แก้เป็น: เช็คก่อนว่าอีกยูทิลิตี้ (ฝั่งที่ไม่ได้กดลบ) ของรอบนี้ยังมี
  // ข้อมูลอยู่ไหม
  //   - มี → เซฟทับ record/bill เดิมด้วย field ของฝั่งที่ลบเป็น 0 อย่างเดียว
  //     เก็บฝั่งที่เหลือไว้ครบ (ไม่ลบทั้งแถว)
  //   - ไม่มี (อีกฝั่งว่างอยู่ก่อนแล้ว) → ลบทั้ง record/bill ได้เลยเหมือนเดิม
  // และตอนรีเซ็ตค่า user (เฉพาะรอบปัจจุบัน) ก็รีเซ็ตเฉพาะฝั่งที่ลบเท่านั้น
  // ไม่แตะฝั่งที่เหลือ — startMeterConfigured (flag รวม) จะเป็น false ก็
  // ต่อเมื่อไม่มียูทิลิตี้ไหนตั้งค่าไว้เหลือแล้วเท่านั้น กันปุ่ม (+) โผล่มา
  // ทั้งที่อีกยูทิลิตี้ยังตั้งค่าไว้ครบอยู่
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
    // ใช้รอบล่าสุด (index 0 ของ _records ทั้งหมดก่อนกรองแยกไฟ/น้ำ) มา
    // ไฮไลต์แถวว่าเป็นรอบปัจจุบัน เพราะประวัตินี้เรียงใหม่สุดก่อนเสมอ
    final latestId = _records.isNotEmpty ? _records.first.id : null;

    final electricRecords = _records;
    final waterRecords = _records;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('บันทึกมิเตอร์ต้นรอบ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showStartMeterInfoPopup(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2E7D32),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2E7D32),
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
                // การ์ดสรุปด้านบน — แยกแสดงตามแท็บที่เลือก (ไฟฟ้า/ประปา)
                // สไตล์เดียวกับแถบสรุปในหน้าประวัติมิเตอร์ไฟฟ้า/ประปา
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
  //
  // เดิมมีคอลัมน์ค่าไฟ/ค่าน้ำ (costOf/costLabel) ตัดออกแล้ว — หน้านี้คือ
  // "เลขมิเตอร์สะสม" ไม่ใช่ค่าใช้จ่าย เอาค่าใช้จ่ายมาโชว์คู่กับหน่วยสะสมแล้ว
  // ดูไม่สอดคล้องกัน (หน่วยสะสม ≠ หน่วยที่ใช้ ซึ่งเป็นตัวคูณค่าไฟจริง) ค่า
  // ใช้จ่ายไปโชว์ที่หน้า "บันทึกบิลย้อนหลัง" คู่กับหน่วยที่ใช้แทน ถูกที่กว่า
  Widget _buildTable({
    required List<StartMeterRecordModel> records,
    required String? latestId,
    required Color accent,
    required String unitLabel,
    required IconData emptyIcon,
    required double Function(StartMeterRecordModel) valueOf,
    // มิเตอร์ TOU ไม่เคยเซ็ต electricityValue เลย (ใช้ peakValue/offPeakValue
    // แทน) เลยต้องแยกตารางเป็น On-Peak/Off-Peak คนละคอลัมน์ ไม่งั้นคอลัมน์
    // "หน่วยสะสม" เดิมจะอ่าน valueOf แล้วเจอ 0 โชว์ "-" ตลอดทุกแถว (บั๊กที่
    // เจอ) ใช้เฉพาะตารางไฟฟ้าเท่านั้น ตารางน้ำไม่มี TOU จึงไม่ต้องแตะ
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
            // แก้ไข/ล้างค่าได้เฉพาะรอบปัจจุบัน (ที่ยังไม่ข้ามวันตัดรอบไป) —
            // รอบเก่าที่ปิดไปแล้วฟอร์มคำนวณ delta ใหม่ให้ไม่ได้ถูกต้อง จึง
            // เปิดให้ลบได้อย่างเดียวเหมือนเดิม
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