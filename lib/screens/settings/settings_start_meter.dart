part of 'settings_screen.dart';

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
  bool _noBillYet = false;
  // โชว์ตอนกดบันทึกแล้วไม่มีคู่ไหนกรอกครบเลยสักคู่ (ทั้งคู่ว่างหรือกรอก
  // ไม่ครบทั้งคู่) ต่างจาก error รายการ์ดที่ widget จัดการเองเวลากรอกครึ่งเดียว
  bool _generalError = false;
  List<BillModel> _existingBills = [];
  List<StartMeterRecordModel> _history = [];

  // มีบิลของเดือน/ปีนี้บันทึกไว้แล้ว (ไม่ว่าจะ compiled หรือ imported) —
  // ถ้ามีแล้วไม่โชว์ลิงก์เสริมเลย กันไม่ให้เขียนทับบิลจริงที่มีอยู่โดยไม่ตั้งใจ
  bool get _lastBillAlreadyRecorded => _existingBills
      .any((b) => b.year == _selectedYear && b.month == _selectedMonth);

  // ใช้เป็นค่า default แบบเร็วๆ ก่อนที่ _loadCurrent() จะรู้ billingDay จริง
  // ของ user (ตอนโหลดครั้งแรก _user ยังเป็น null อยู่) — ใช้ billingDay
  // สมมติ 30 เป็นค่าเริ่มต้นชั่วคราวเหมือนจุดอื่นในแอปที่ fallback แบบนี้
  static DateTime get _defaultInvoiceMonth {
    return _expectedInvoiceMonth(30);
  }

  // ใบแจ้งหนี้ล่าสุดที่ "ควร" ใช้เป็นต้นรอบตอนนี้ คำนวณจากวันตัดรอบบิลจริง
  // ของ user (billingDay) ไม่ใช่แค่เดือนปฏิทินก่อนหน้าเฉยๆ เหมือนเดิม —
  // ใช้สูตรเดียวกับที่ dashboard_screen.dart ใช้ตอน compileBill() เป๊ะๆ:
  // bill.month ของรอบที่เพิ่งปิดไป = getCycleStart(now, billingDay).month
  // (เพราะ "จุดเริ่มต้นของรอบที่กำลังเปิดอยู่ตอนนี้" ก็คือ "จุดสิ้นสุดของ
  // รอบก่อนหน้าที่เพิ่งปิดไป" นั่นเอง เป็นจุดเดียวกัน) — ต้องใช้สูตรนี้ตรงๆ
  // ไม่ใช่ getPreviousCycleStart ต่ออีกที (เคยพลาดใส่ getPreviousCycleStart
  // เพิ่มไปอีกชั้นซึ่งจะได้เดือนเก่ากว่าที่ควรไป 1 รอบเต็มๆ)
  static DateTime _expectedInvoiceMonth(int billingDay) {
    final now = DateTime.now();
    return EnergyForecaster.getCycleStart(now, billingDay);
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
    super.dispose();
  }

  // เป็นการตั้งค่าครั้งแรกสุดของยูทิลิตี้นั้นๆ ไหม (ไม่เคยมี record ก่อนหน้า
  // ที่มีค่า > 0 มาก่อนเลย) — เช็คแยกรายยูทิลิตี้ ไม่ใช่เช็ครวมทั้งบัญชี
  // เพราะตั้งแยกยูทิลิตี้ได้อิสระ (เช่น ตั้งไฟมาตั้งแต่เดือน 3 แต่เพิ่งมี
  // บิลน้ำใบแรกเดือน 6 — ฝั่งน้ำยังนับเป็นครั้งแรกอยู่ ทั้งที่ฝั่งไฟไม่ใช่)
  // ไม่นับ record ที่กำลังแก้ไขอยู่ (_editingRecordId) กันกรณีแก้ไข record
  // แรกสุดของตัวเองแล้วเข้าใจผิดว่ามี "record อื่น" อยู่ก่อนหน้า
  bool get _eIsFirstEntry => !_history.any(
      (r) => r.id != _editingRecordId && r.electricityValue > 0);
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
    final eVal = double.tryParse(_eCtrl.text) ?? 0;
    final peakVal = double.tryParse(_peakCtrl.text) ?? 0;
    final offPeakVal = double.tryParse(_offPeakCtrl.text) ?? 0;
    final wVal = double.tryParse(_wCtrl.text) ?? 0;
    final eCost = double.tryParse(_eCostCtrl.text) ?? 0;
    final wCost = double.tryParse(_wCostCtrl.text) ?? 0;
    final eUsedInput = double.tryParse(_eUsedCtrl.text) ?? 0;
    final wUsedInput = double.tryParse(_wUsedCtrl.text) ?? 0;

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
      noBillYet: _noBillYet,
      eIsFirstEntry: _eIsFirstEntry,
      eUsed: eUsedInput,
      wIsFirstEntry: _wIsFirstEntry,
      wUsed: wUsedInput,
    );
    if (!ok) {
      setState(() => _generalError = true);
      return;
    }
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
          noBillYet: _noBillYet,
          isFirstEntry: _eIsFirstEntry,
          eUsed: eUsedInput);
      final wComplete = StartMeterValidation.waterComplete(
          wVal: wVal,
          wCost: wCost,
          noBillYet: _noBillYet,
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
        // ถ้ากรอกค่าใช้จ่ายไว้ (คู่ไหนครบก็สร้างของคู่นั้น) สร้างเป็นบิล
        // ย้อนหลัง (source: imported) ให้เลย ใช้เดือน/ปีเดียวกับที่เลือกไว้
        // — กันไม่ให้เขียนทับบิลที่มีอยู่แล้วโดยไม่ตั้งใจด้วย
        // _lastBillAlreadyRecorded (เช็คไปแล้วตอนโชว์ช่องกรอก)
        //
        // แก้บั๊กเดิม: ตอนสร้างบิลนี้ไม่เคยใส่ electricityUsed/waterUsed เลย
        // (มีแต่ cost) พอไปโชว์ในหน้าประวัติบิลเลยเห็นเป็น "0 หน่วย" ทั้งที่
        // จ่ายจริง — ตอนนี้มี 2 ทาง: (1) ถ้ามี record ก่อนหน้าจริง (ไม่ใช่
        // ครั้งแรกสุดของยูทิลิตี้นั้น) คำนวณ delta ให้อัตโนมัติ (2) ถ้าเป็น
        // ครั้งแรกสุด (_eIsFirstEntry/_wIsFirstEntry) ใช้ค่าที่ผู้ใช้กรอกเอง
        // ในช่องที่ 3 ตรงๆ แทน (ผ่าน validation บังคับกรอกมาแล้วตอน canSave)
        final prev = _previousRecord;
        double eUsed = _eIsFirstEntry ? eUsedInput : 0;
        double wUsed = _wIsFirstEntry ? wUsedInput : 0;
        if (prev != null) {
          if (eComplete && prev.electricityValue > 0 && eVal > prev.electricityValue) {
            eUsed = eVal - prev.electricityValue;
          }
          if (wComplete && prev.waterValue > 0 && wVal > prev.waterValue) {
            wUsed = wVal - prev.waterValue;
          }
        }

        if (!_lastBillAlreadyRecorded && (eComplete || wComplete)) {
          await widget.firestoreService.saveBill(
            BillModel(
              id: const Uuid().v4(),
              uid: widget.uid,
              year: _selectedYear,
              month: _selectedMonth,
              electricityCost: eComplete ? eCost : 0,
              waterCost: wComplete ? wCost : 0,
              totalCost: (eComplete ? eCost : 0) + (wComplete ? wCost : 0),
              electricityUsed: eUsed,
              waterUsed: wUsed,
              source: 'imported',
            ),
          );
        }
        Navigator.pop(context, true);
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
                        'บันทึกเลขมิเตอร์ต้นรอบ',
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
                                  'แก้ไขค่าของรอบนี้ได้จนกว่าจะถึงวันตัดรอบบิล '
                                  'ครั้งถัดไป ระบบจะเปิดให้ตั้งค่ารอบใหม่'
                                  'อัตโนมัติตอนนั้น',
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
                                  const Color(0xFF2E7D32).withOpacity(0.08),
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
                          eIsFirstEntry: _eIsFirstEntry,
                          wIsFirstEntry: _wIsFirstEntry,
                          noBillYet: _noBillYet,
                          onNoBillYetChanged: (v) => setState(() {
                            _noBillYet = v;
                            if (v) {
                              _eCostCtrl.clear();
                              _wCostCtrl.clear();
                            }
                          }),
                          title: 'เลขมิเตอร์สะสมต้นรอบ',
                          subtitle: 'กรอกเลขและค่าใช้จ่ายจากใบแจ้งหนี้เดือนที่'
                              'เลือกไว้ด้านบน — มีบิลแค่ฝั่งไหนก็กรอกแค่ฝั่ง'
                              'นั้นได้',
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

class _StartMeterHistoryScreenState extends State<_StartMeterHistoryScreen> {
  List<StartMeterRecordModel> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final records = await widget.firestoreService.getStartMeterHistory(widget.uid);
    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
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

  Future<void> _confirmDelete(StartMeterRecordModel record) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบรายการนี้?',
      content: 'ต้องการลบประวัติการตั้งเลขมิเตอร์ต้นรอบรายการนี้ใช่ไหมคะ',
      borderRadius: 16,
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteStartMeterRecord(widget.uid, record.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');
    final dateFormatter = DateFormat('dd/MM/yyyy, HH:mm');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('เลขมิเตอร์ต้นรอบ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showStartMeterInfoPopup(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — บอกว่ามีกี่รอบ แล้วรอบล่าสุดคือเดือนไหน
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.white, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'บันทึกเลขมิเตอร์ต้นรอบทั้งหมด',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_records.length} รอบบิล',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_records.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ล่าสุด ${thaiMonths[_records.first.billingMonth - 1]}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),

                // Timeline ของแต่ละรอบ
                Expanded(
                  child: _records.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.speed_outlined,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีประวัติการตั้งเลขมิเตอร์ต้นรอบ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final r = _records[index];
                            final isLatest = index == 0;
                            final isLast = index == _records.length - 1;

                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // เส้น timeline + จุดด้านซ้าย
                                  Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isLatest
                                              ? const Color(0xFF2E7D32)
                                              : Colors.grey.shade300,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: isLatest
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF2E7D32)
                                                        .withOpacity(0.4),
                                                    blurRadius: 6,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                      if (!isLast)
                                        Expanded(
                                          child: Container(
                                            width: 2,
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // การ์ดข้อมูลของรอบนั้น
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: isLatest
                                              ? Border.all(
                                                  color: const Color(0xFF2E7D32)
                                                      .withOpacity(0.3),
                                                )
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.grey.withOpacity(0.08),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'ต้นรอบ ${thaiMonths[r.billingMonth - 1]} ${r.billingYear}',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14.5,
                                                    ),
                                                  ),
                                                ),
                                                if (isLatest)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF2E7D32)
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(20),
                                                    ),
                                                    child: const Text(
                                                      'ปัจจุบัน',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF2E7D32),
                                                      ),
                                                    ),
                                                  ),
                                                IconButton(
                                                  visualDensity: VisualDensity.compact,
                                                  icon: Icon(Icons.delete_outline,
                                                      size: 19, color: Colors.red.shade300),
                                                  onPressed: () => _confirmDelete(r),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'บันทึกเมื่อ ${dateFormatter.format(r.recordedAt)}',
                                              style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.grey.shade500),
                                            ),
                                            const SizedBox(height: 10),

                                            // ค่ามิเตอร์ — โชว์ peak/off-peak แทนค่าไฟปกติถ้าเป็น TOU
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: widget.isTou
                                                  ? [
                                                      ValueChip(
                                                        icon: Icons.bolt,
                                                        color: Colors.orange.shade700,
                                                        label: 'On-Peak',
                                                        value: '${formatter.format(r.peakValue)} หน่วย',
                                                      ),
                                                      ValueChip(
                                                        icon: Icons.bolt_outlined,
                                                        color: Colors.blueGrey,
                                                        label: 'Off-Peak',
                                                        value: '${formatter.format(r.offPeakValue)} หน่วย',
                                                      ),
                                                      ValueChip(
                                                        icon: Icons.water_drop,
                                                        color: Colors.blue,
                                                        label: 'น้ำ',
                                                        value: '${formatter.format(r.waterValue)} ลบ.ม.',
                                                      ),
                                                    ]
                                                  : [
                                                      ValueChip(
                                                        icon: Icons.bolt,
                                                        color: const Color(0xFF2E7D32),
                                                        label: 'ไฟ',
                                                        value: '${formatter.format(r.electricityValue)} หน่วย',
                                                      ),
                                                      ValueChip(
                                                        icon: Icons.water_drop,
                                                        color: Colors.blue,
                                                        label: 'น้ำ',
                                                        value: '${formatter.format(r.waterValue)} ลบ.ม.',
                                                      ),
                                                    ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSheet,
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}