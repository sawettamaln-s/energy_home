part of 'settings_screen.dart';

// สร้างตัวเลือกเดือนโดยอิงวันตัดรอบบิลจริง (billingDay) แทนเดือนปฏิทิน
// ตรงๆ — ใช้สูตรเดียวกับที่ dashboard_screen.dart ใช้ตอน compileBill()
// ย้ายออกมาเป็นฟังก์ชันกลางระดับไฟล์ (เดิมเป็น method ส่วนตัวของ
// _AddHistoricalBillSheetState อย่างเดียว) เพื่อให้ _HistoricalBillListScreen
// เอาไปใช้เช็คว่า "ครบ 6 เดือนแล้วหรือยัง" ได้ด้วย โดยไม่ต้องก็อปสูตรซ้ำ
List<DateTime> _generateHistoricalMonthOptions(int billingDay) {
  final options = <DateTime>[];
  var cursor = EnergyForecaster.getCycleStart(DateTime.now(), billingDay);
  for (int i = 0; i < 6; i++) {
    options.add(cursor);
    cursor = EnergyForecaster.getPreviousCycleStart(cursor, billingDay);
  }
  return options;
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
  Set<String> _takenMonths = {}; // เก็บ 'year-month' ของเดือนที่มีบิลแล้ว
  bool _isLoadingTaken = true;
  bool _isSaving = false;

  final _eUsedCtrl = TextEditingController();
  final _eCostCtrl = TextEditingController();
  final _wUsedCtrl = TextEditingController();
  final _wCostCtrl = TextEditingController();

  // ----- ส่วนเสริม: ตั้งค่ามิเตอร์ต้นรอบต่อในฟอร์มเดียวกันเลย -----
  // โหลด user มาเองอิสระ (ตามแพทเทิร์นเดียวกับ _AddStartMeterSheet) เพื่อรู้
  // ว่าเป็นมิเตอร์ TOU ไหม และผู้ใช้เคยตั้งค่ามิเตอร์ต้นรอบไปแล้วหรือยัง
  // (ถ้าตั้งแล้วไม่โชว์ซ้ำ กันการเผลอเขียนทับค่าจริงที่ผู้ใช้บันทึกไปแล้ว)
  UserModel? _user;
  final _meterECtrl = TextEditingController();
  final _meterPeakCtrl = TextEditingController();
  final _meterOffPeakCtrl = TextEditingController();
  final _meterWCtrl = TextEditingController();

  // สร้างตัวเลือกเดือนโดยอิงวันตัดรอบบิลจริง (billingDay) แทนเดือนปฏิทิน
  // ตรงๆ — ใช้สูตรเดียวกับที่ dashboard_screen.dart ใช้ตอน compileBill()
  // เพื่อให้ "เดือนของบิล" ที่เลือกในฟอร์มนี้ ตรงกับนิยาม "เดือนของบิล"
  // ที่ระบบ compile อัตโนมัติใช้จริง ไม่งั้นถ้า billingDay ไม่ใช่ปลายเดือน
  // (เช่นวันที่ 3, 15) เดือนที่ให้เลือกในฟอร์มนี้กับเดือนที่ระบบ compile
  // ให้เองอาจไม่ตรงกัน ทำให้กรอกบิลย้อนหลังผิดเดือน/ทับซ้อนกับบิลที่ระบบ
  // จะ compile ให้ทีหลังโดยไม่รู้ตัว
  List<DateTime> _generateMonthOptions(int billingDay) =>
      _generateHistoricalMonthOptions(billingDay);

  @override
  void initState() {
    super.initState();
    final existing = widget.existingBill;
    // ใช้ billingDay = 30 (ปลายเดือน) เป็นค่าเริ่มต้นชั่วคราวก่อน จะไปแก้
    // เป็นค่าจริงของ user อีกทีใน _loadUser() พอโหลดเสร็จ (เห็นผลต่างชัด
    // เฉพาะกรณี billingDay ไม่ใช่ปลายเดือนเท่านั้น ระหว่างนี้ฟอร์มใช้งาน
    // ได้ปกติก่อนด้วยค่าประมาณที่ใกล้เคียงที่สุด)
    _monthOptions = _generateMonthOptions(30);
    // ถ้าแก้ไขบิลที่เดือนอยู่นอกช่วง 6 เดือนล่าสุด ให้เพิ่มเดือนนั้นเข้าไปในตัวเลือกด้วย
    if (existing != null &&
        !_monthOptions.any(
            (m) => m.year == existing.year && m.month == existing.month)) {
      _monthOptions.add(DateTime(existing.year, existing.month, 1));
    }
    // เดิมตั้ง _selectedMonth = DateTime(existing.year, existing.month, 1)
    // ตรงๆ แต่ตัวเลือกใน _monthOptions ใช้วันที่ = billingDay จริง (เช่น
    // 10, 30) ไม่ใช่วันที่ 1 ทำให้สอง DateTime นี้ไม่มีทางเท่ากันเลย
    // (DateTime เทียบทุกฟิลด์รวมวันที่) ผลคือ DropdownButtonFormField หา
    // item ที่ตรงกับ value ไม่เจอทุกครั้งที่กด "แก้ไข" จากเมนู 3 จุด —
    // ต้องหยิบ DateTime ตัวจริงจาก _monthOptions มาใช้แทนการสร้างขึ้นใหม่เอง
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
      _eCostCtrl.text =
          existing.electricityCost == 0 ? '' : existing.electricityCost.toStringAsFixed(2);
      _wUsedCtrl.text =
          existing.waterUsed == 0 ? '' : existing.waterUsed.toStringAsFixed(2);
      _wCostCtrl.text =
          existing.waterCost == 0 ? '' : existing.waterCost.toStringAsFixed(2);
    }
    _loadTakenMonths();
    _loadUser();

    for (final c in [_eUsedCtrl, _eCostCtrl, _wUsedCtrl, _wCostCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _loadUser() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    if (!mounted) return;

    // ถ้า billingDay จริงต่างจาก default ที่ใช้ไปก่อนหน้า (30) ให้สร้าง
    // ตัวเลือกเดือนใหม่ด้วยค่าจริง แล้วคง selection/แก้ไขเดิมไว้ให้เหมือนเดิม
    // ที่สุดเท่าที่ทำได้ (ไม่ให้ผู้ใช้เห็นตัวเลือกเปลี่ยนกะทันหันโดยไม่จำเป็น
    // ถ้า billingDay = 30 อยู่แล้วซึ่งเป็นค่าเริ่มต้นของ user ส่วนใหญ่)
    if (user != null && user.billingDay != 30) {
      final existing = widget.existingBill;
      final rebuilt = _generateMonthOptions(user.billingDay);
      if (existing != null &&
          !rebuilt.any(
              (m) => m.year == existing.year && m.month == existing.month)) {
        rebuilt.add(DateTime(existing.year, existing.month, 1));
      }
      // ต้องปรับ _selectedMonth ให้ตรงกับ _monthOptions ชุดใหม่ใน setState
      // เดียวกันนี้เลย ไม่งั้นจะมี 1 เฟรมที่ DropdownButtonFormField ถือค่า
      // _selectedMonth เดิม (มาจากชุด options เก่าที่คำนวณจาก billingDay=30)
      // ซึ่งไม่มีอยู่ใน _monthOptions ชุดใหม่ ทำให้ Flutter throw assertion
      // ("exactly one item with DropdownButton's value") จนเห็นจอแดงแว้ปนึง
      // ก่อนที่ _loadTakenMonths() ด้านล่างจะ setState แก้ค่าให้ตรงกันอีกที
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
    } else {
      setState(() => _user = user);
    }
  }

  @override
  void dispose() {
    _eUsedCtrl.dispose();
    _eCostCtrl.dispose();
    _wUsedCtrl.dispose();
    _wCostCtrl.dispose();
    _meterECtrl.dispose();
    _meterPeakCtrl.dispose();
    _meterOffPeakCtrl.dispose();
    _meterWCtrl.dispose();
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
    }
  }

  double get _eCost => double.tryParse(_eCostCtrl.text) ?? 0;
  double get _wCost => double.tryParse(_wCostCtrl.text) ?? 0;
  // ผลรวมค่าไฟ+ค่าน้ำเท่านั้น (ไม่รวม fixedCost) — ใช้เช็คว่ากรอกข้อมูล
  // บิลมาหรือยัง (validation) และโชว์ยอดไฟ+น้ำแยกในพรีวิว
  double get _total => _eCost + _wCost;

  // แก้บั๊ก: เดิม totalCost ของบิลย้อนหลังไม่รวมค่าใช้จ่ายคงที่เลย ในขณะที่
  // บิลที่ระบบ compile ให้เองรวม fixedCost ด้วยเสมอ (ดู compileBill() ใน
  // firestore_service.dart) ทำให้ totalCost ของสองแหล่งเทียบกันไม่ตรง —
  // ใช้ user.fixedCost (ค่าคงที่ปัจจุบันที่ตั้งไว้ในแอป) แบบเดียวกับที่
  // compileBill ใช้ เพื่อให้ยอดรวมที่โชว์ในประวัติสอดคล้องกันทั้งสองแหล่ง
  double get _fixedCost => _user?.fixedCost ?? 0;
  double get _totalWithFixedCost => _total + _fixedCost;

  bool get _isSelectedMonthTaken =>
      _takenMonths.contains('${_selectedMonth.year}-${_selectedMonth.month}');

  // เดือนล่าสุดใน 6 ตัวเลือก (เดือนก่อนเดือนนี้ทันที) — ต่อจากเดือนนี้คือรอบ
  // ที่ระบบจะเริ่ม track จริงผ่าน log มิเตอร์ จึงเป็นจุดเดียวที่ควรถามเลขมิเตอร์
  // ต้นรอบต่อ (เดือนอื่นๆ ที่เก่ากว่าไม่เกี่ยวกับรอบปัจจุบันแล้ว ไม่ต้องถาม)
  bool get _isMostRecentMonthSelected =>
      _selectedMonth.year == _monthOptions.first.year &&
      _selectedMonth.month == _monthOptions.first.month;

  // โชว์เฉพาะตอนเพิ่มใหม่ (ไม่ใช่แก้ไขบิลเก่า) + เลือกเดือนล่าสุด + ผู้ใช้
  // ยังไม่เคยตั้งค่ามิเตอร์ต้นรอบมาก่อน (กันเขียนทับค่าจริงที่ตั้งไปแล้ว)
  bool get _showStartMeterSection =>
      widget.existingBill == null &&
      _user != null &&
      !_user!.startMeterConfigured &&
      _isMostRecentMonthSelected;

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
        electricityUsed: double.tryParse(_eUsedCtrl.text) ?? 0,
        waterUsed: double.tryParse(_wUsedCtrl.text) ?? 0,
        electricityCost: _eCost,
        waterCost: _wCost,
        fixedCost: _fixedCost,
        totalCost: _totalWithFixedCost,
        // บิลย้อนหลังคือของจริงที่เกิดขึ้นแล้ว ไม่ใช่ค่าพยากรณ์
        forecastElectricity: _eCost,
        forecastWater: _wCost,
        forecastTotal: _totalWithFixedCost,
        source: 'imported',
      );
      await widget.firestoreService.saveBill(bill);

      // ----- ถ้าโชว์ส่วนตั้งค่ามิเตอร์ต้นรอบต่อ และผู้ใช้กรอกอย่างน้อย 1 ช่อง
      // ให้ตั้งค่าต้นรอบต่อเนื่องไปเลยในการกดบันทึกครั้งเดียวกัน (ไม่ต้อง
      // ไปเปิดหน้า "บันทึกมิเตอร์ต้นรอบ" แยกอีกรอบ) — เขียนทับ logic เดิม
      // เป๊ะๆ กับที่ settings_start_meter.dart ใช้ เพื่อให้ผลลัพธ์ตรงกัน -----
      if (_showStartMeterSection) {
        final eVal = double.tryParse(_meterECtrl.text) ?? 0;
        final peakVal = double.tryParse(_meterPeakCtrl.text) ?? 0;
        final offPeakVal = double.tryParse(_meterOffPeakCtrl.text) ?? 0;
        final wVal = double.tryParse(_meterWCtrl.text) ?? 0;
        final filledAnyMeterField =
            eVal > 0 || peakVal > 0 || offPeakVal > 0 || wVal > 0;

        if (filledAnyMeterField) {
          // แก้ให้ตรงกับ settings_start_meter.dart: billingMonth เก็บ "เดือน
          // ของใบแจ้งหนี้ที่ค่านี้มาจาก" ตรงๆ (เช่น กรอกบิลเดือน 6 → เก็บ
          // billingMonth = 6) ไม่ใช่ +1 เป็นเดือนถัดไปแบบเดิม — เดิมสอง
          // ฟอร์มนี้เก็บค่าคนละความหมายกัน (ฟอร์มนี้เก็บ 7 แต่ฟอร์มหลักเก็บ
          // 6 สำหรับใบแจ้งหนี้เดือนเดียวกัน) ทำให้ label ในหน้าประวัติสับสน
          // ได้ แม้จะไม่กระทบตัวเลขที่คำนวณจริงก็ตาม (มีแค่ startElectricity/
          // WaterValue เท่านั้นที่ใช้คำนวณจริง ไม่ใช่ billingMonth)

          await widget.firestoreService.updateUser(widget.uid, {
            'startElectricityValue': eVal,
            'startPeakValue': peakVal,
            'startOffPeakValue': offPeakVal,
            'startWaterValue': wVal,
            'startBillingMonth': _selectedMonth.month,
            'startBillingYear': _selectedMonth.year,
            'startMeterConfigured': true,
          });
          await widget.firestoreService.saveStartMeterRecord(
            StartMeterRecordModel(
              id: const Uuid().v4(),
              uid: widget.uid,
              electricityValue: eVal,
              waterValue: wVal,
              peakValue: peakVal,
              offPeakValue: offPeakVal,
              billingMonth: _selectedMonth.month,
              billingYear: _selectedMonth.year,
              recordedAt: DateTime.now(),
            ),
          );
        }
      }

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
        padding: const EdgeInsets.only(bottom: 8),
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
                    color: const Color(0xFF2E7D32).withOpacity(0.12),
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32))),
                ),
              ),
            ],
          ],
        ),
      );

  // อธิบายว่าช่อง "หน่วยที่ใช้" ต้องกรอกอะไร — ปัญหาที่เจอบ่อยคือคนกรอก
  // "เลขอ่านครั้งหลัง" (เลขสะสมบนมิเตอร์) มาใส่แทนที่จะเป็นยอดหน่วยที่ใช้
  // จริงของเดือนนั้น ซึ่งฟอร์มนี้ไม่ได้เอาเลขมิเตอร์ของ 2 เดือนมาลบกันให้
  // (ต่างจากหน้าบันทึกมิเตอร์ปกติที่ระบบลบให้อัตโนมัติ) เพราะบิลย้อนหลัง
  // แต่ละเดือนไม่ได้ต่อเนื่องกันเสมอไป จึงให้กรอกยอดหน่วยที่ใช้ตรงๆ จากบิล
  void _showUsageInfoPopup(String utilityLabel, String unitLabel) {
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
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          if (utilityLabel == 'หน่วยที่ใช้เดือนนี้ (ไฟ)') ...[
            const SizedBox(height: 10),
            Text(
              'กรณีมิเตอร์แบบ TOU: บิลจะแยกแสดง On-Peak และ Off-Peak '
              'คนละบรรทัด ให้นำสองยอดมารวมกันแล้วกรอกเป็นยอดเดียว '
              '(ช่องนี้ไม่แยก Peak/Off-Peak เนื่องจากค่าไฟกรอกตรงจากยอดบิล '
              'โดยไม่นำไปคำนวณราคาต่อหน่วยซ้ำ ตัวเลขหน่วยใช้เพื่อดู'
              'แนวโน้มการใช้ไฟในหน้าวิเคราะห์เท่านั้น)',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
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
                        fontSize: 12.5,
                        height: 1.5,
                        color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint, String? suffixText}) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
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
                Text(
                  widget.existingBill != null
                      ? 'แก้ไขบันทึกบิลย้อนหลัง'
                      : 'เพิ่มบันทึกบิลย้อนหลัง',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ไม่บังคับ • สูงสุด 6 เดือน • ช่วยให้หน้าวิเคราะห์มีข้อมูลตั้งแต่วันแรก',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('เดือน'),
                  _isLoadingTaken
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : DropdownButtonFormField<DateTime>(
                          value: _selectedMonth,
                          decoration: _fieldDecoration(),
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
                          onChanged: (val) =>
                              setState(() => _selectedMonth = val!),
                        ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('หน่วยที่ใช้เดือนนี้ (ไฟ)',
                                onInfoTap: () => _showUsageInfoPopup(
                                    'หน่วยที่ใช้เดือนนี้ (ไฟ)', 'kWh')),
                            TextField(
                              controller: _eUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _fieldDecoration(
                                  hint: 'เช่น 250', suffixText: 'หน่วย'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('ค่าไฟ'),
                            TextField(
                              controller: _eCostCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'บาท'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('หน่วยที่ใช้เดือนนี้ (น้ำ)',
                                onInfoTap: () => _showUsageInfoPopup(
                                    'หน่วยที่ใช้เดือนนี้ (น้ำ)', 'ลบ.ม.')),
                            TextField(
                              controller: _wUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _fieldDecoration(
                                  hint: 'เช่น 15', suffixText: 'หน่วย'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('ค่าน้ำ'),
                            TextField(
                              controller: _wCostCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'บาท'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_showStartMeterSection) ...[
                    const SizedBox(height: 20),
                    // ใช้ widget กลางตัวเดียวกับหน้าหลัก "บันทึกมิเตอร์
                    // ต้นรอบ" แทนโค้ดที่เคย copy มาเองในนี้ — ก่อนหน้านี้
                    // สองจุดนี้เก็บความหมาย billingMonth ต่างกัน (บั๊กที่
                    // เจอไปแล้ว) เพราะแยกกันคนละไฟล์ ตอนนี้ใช้ widget เดียว
                    // แก้ตรงไหนก็ตรงกันทั้งแอปอัตโนมัติ ไม่มีทางดริฟท์อีก
                    StartMeterFieldsSection(
                      isTou: _user!.meterType == 'tou',
                      electricityCtrl: _meterECtrl,
                      peakCtrl: _meterPeakCtrl,
                      offPeakCtrl: _meterOffPeakCtrl,
                      waterCtrl: _meterWCtrl,
                      title: 'ตั้งเลขมิเตอร์ต้นรอบเดือนถัดไปเลยไหม?',
                      subtitle: 'ไม่บังคับ • ข้ามได้ถ้าจะไปตั้งทีหลัง',
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
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
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32),
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
                                  fontSize: 11,
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
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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

// วิดเจ็ตหัวข้อย่อยที่ใช้ร่วมกันใน info popup หลายหน้า (แทนอิโมจินำหน้า
// ข้อความแบบเดิม ให้ใช้ไอคอนจริงแทนเพื่อความสม่ำเสมอกันทั้งแอป)
Widget _infoSectionHeader(String label, {IconData icon = Icons.checklist_rounded}) {
  return Row(
    children: [
      Icon(icon, size: 15, color: const Color(0xFF2E7D32)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32))),
    ],
  );
}

// กล่องข้อควรระวัง — แทนที่การขึ้นต้นด้วย "⚠️" ในข้อความเดิม
Widget _infoWarningBox(String text) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
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
                fontSize: 12.5, height: 1.5, color: Colors.orange.shade900),
          ),
        ),
      ],
    ),
  );
}

// ==================== รายการบิลย้อนหลัง (แก้ไข/ลบได้) ====================
// อธิบายภาพรวมของหน้า "บันทึกบิลย้อนหลัง" ไว้ที่ AppBar ของหน้ารายการเลย
// (ไม่ใช่แค่ในฟอร์มเพิ่ม/แก้ไข) เพราะเดิมผู้ใช้ต้องกดปุ่ม + ก่อนถึงจะเห็น
// คำอธิบาย ถ้ายังไม่เคยกรอกมาก่อนจะไม่รู้เลยว่าต้องกรอกอะไร
void _showHistoricalBillInfoPopup(BuildContext context) {
  showInfoDialog(
    context,
    title: 'หน้านี้ใช้ทำอะไร?',
    contentBuilder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'สำหรับเพิ่มบิลของเดือนก่อนๆ ที่ไม่ได้บันทึกผ่านแอปตั้งแต่แรก '
          'เพื่อให้หน้าวิเคราะห์มีข้อมูลย้อนหลังไปเปรียบเทียบได้ (สูงสุด 6 เดือน)',
          style: TextStyle(fontSize: 13.5, height: 1.6),
        ),
        const SizedBox(height: 14),
        _infoSectionHeader('กรอกยังไง'),
        const SizedBox(height: 4),
        const Text(
          'เปิดบิลค่าไฟ/ค่าน้ำเดือนนั้น แล้วมองหาช่อง "จำนวนหน่วยที่ใช้" '
          '(kWh หรือ ลบ.ม.) กับ "ยอดเงิน" นำตัวเลขทั้งสองมากรอก',
          style: TextStyle(fontSize: 13.5, height: 1.6),
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


class _HistoricalBillListScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _HistoricalBillListScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_HistoricalBillListScreen> createState() =>
      _HistoricalBillListScreenState();
}

class _HistoricalBillListScreenState
    extends State<_HistoricalBillListScreen> {
  List<BillModel> _bills = [];
  bool _isLoading = true;
  int _billingDay = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final user = await widget.firestoreService.getUser(widget.uid);
    final all = await widget.firestoreService.getBills(widget.uid);
    // เฉพาะบิลที่กรอกย้อนหลังเอง (ไม่ใช่บิลที่ระบบสรุปจาก log อัตโนมัติ)
    final imported = all.where((b) => b.source == 'imported').toList();
    if (mounted) {
      setState(() {
        _billingDay = user?.billingDay ?? 30;
        _bills = imported;
        _isLoading = false;
      });
    }
  }

  // หน้านี้มีไว้กรอกบิลย้อนหลัง "ก่อนสมัครใช้แอป" เท่านั้น (ขอบเขตคงที่ 6
  // เดือนตาม _generateHistoricalMonthOptions) พอกรอกครบทั้ง 6 เดือนแล้ว
  // ปุ่ม (+) ไม่มีที่ให้เพิ่มต่อแล้วจริงๆ (กดไปก็จะเจอแค่ข้อความ "เดือนนี้มี
  // บิลบันทึกไว้แล้ว" ทุกเดือน) ซ่อนปุ่มไปเลยดีกว่าปล่อยให้กดแล้วงง — ยังแก้
  // ไข/ลบรายการเดิมได้ตามปกติผ่านเมนู 3 จุดของแต่ละรายการ
  bool get _allSixMonthsRecorded {
    final options = _generateHistoricalMonthOptions(_billingDay);
    final taken =
        _bills.map((b) => '${b.year}-${b.month}').toSet();
    return options
        .every((m) => taken.contains('${m.year}-${m.month}'));
  }

  Future<void> _openSheet({BillModel? existingBill}) async {
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
    final formatter = NumberFormat('#,##0.00');
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('บันทึกบิลย้อนหลัง'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHistoricalBillInfoPopup(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — สไตล์เดียวกับหน้าประวัติค่ามิเตอร์ต้นรอบ
                // เดิมหน้านี้ไม่มีการ์ดสรุป ดูจืดกว่าหน้าอื่นในแอป
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
                      const Icon(Icons.receipt_long,
                          color: Colors.white, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'บันทึกบิลย้อนหลังทั้งหมด',
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_bills.length} เดือน',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_isLoading && _allSixMonthsRecorded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'ครบ 6 เดือนแล้ว',
                            style: TextStyle(
                                color: Colors.white, fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),

                // รายการบิลแต่ละเดือน
                Expanded(
                  child: _bills.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีบิลย้อนหลัง\nกดปุ่ม + เพื่อเพิ่มบิลของเดือนก่อนๆ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _bills.length,
                          itemBuilder: (context, index) {
                            final bill = _bills[index];
                            final isLatest = index == 0;
                            final isLast = index == _bills.length - 1;
                            const accent = Color(0xFF2E7D32);

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
                                              ? accent
                                              : Colors.grey.shade300,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: isLatest
                                              ? [
                                                  BoxShadow(
                                                    color: accent
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

                                  // การ์ดข้อมูลของบิลเดือนนั้น
                                  Expanded(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: isLatest
                                              ? Border.all(
                                                  color:
                                                      accent.withOpacity(0.3))
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.grey
                                                  .withOpacity(0.08),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${thaiMonths[bill.month - 1]} ${bill.year}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14.5,
                                                    ),
                                                  ),
                                                ),
                                                if (isLatest)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: accent
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(20),
                                                    ),
                                                    child: const Text(
                                                      'ล่าสุด',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: accent,
                                                      ),
                                                    ),
                                                  ),
                                                PopupMenuButton<String>(
                                                  icon: Icon(Icons.more_vert,
                                                      size: 18,
                                                      color: Colors
                                                          .grey.shade500),
                                                  onSelected: (value) {
                                                    if (value == 'edit') {
                                                      _openSheet(
                                                          existingBill: bill);
                                                    } else if (value ==
                                                        'delete') {
                                                      _confirmDelete(bill);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text('แก้ไข'),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('ลบ',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .red)),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'รวม ${formatter.format(bill.totalCost)} บาท',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: accent,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            // แสดงเฉพาะรายการที่มีค่า (บางเดือน
                                            // อาจกรอกแค่ค่าไฟ หรือแค่ค่าน้ำ)
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                if (bill.electricityCost > 0)
                                                  ValueChip(
                                                    icon: Icons.bolt,
                                                    color: Colors.orange.shade700,
                                                    label: 'ไฟ',
                                                    value: '${formatter.format(bill.electricityUsed)} หน่วย · ${formatter.format(bill.electricityCost)} บาท',
                                                  ),
                                                if (bill.waterCost > 0)
                                                  ValueChip(
                                                    icon: Icons.water_drop,
                                                    color: Colors.blue,
                                                    label: 'น้ำ',
                                                    value: '${formatter.format(bill.waterUsed)} ลบ.ม. · ${formatter.format(bill.waterCost)} บาท',
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
      floatingActionButton: (_isLoading || _allSixMonthsRecorded)
          ? null
          : FloatingActionButton(
              onPressed: () => _openSheet(),
              backgroundColor: const Color(0xFF2E7D32),
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }
}