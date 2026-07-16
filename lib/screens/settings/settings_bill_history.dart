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

  // ----- ส่วนเสริม: ชวนตั้งค่ามิเตอร์ต้นรอบต่อ (เปิดฟอร์มจริงแยกต่างหาก) -----
  // โหลด user มาเองอิสระ (ตามแพทเทิร์นเดียวกับ _AddStartMeterSheet) เพื่อรู้
  // ว่าเป็นมิเตอร์ TOU ไหม และผู้ใช้เคยตั้งค่ามิเตอร์ต้นรอบไปแล้วหรือยัง
  // (ถ้าตั้งแล้วไม่โชว์ซ้ำ กันการเผลอเขียนทับค่าจริงที่ผู้ใช้บันทึกไปแล้ว)
  //
  // เดิมฝังชุด field เลขมิเตอร์สะสม (_meterECtrl ฯลฯ) ไว้ในฟอร์มนี้ตรงๆ
  // แล้วก็อป logic การเซฟมาเช็คเองอีกชุด — พังตรงที่แค่กรอกครบ 1 ช่องก็
  // mark startMeterConfigured = true ทันที ทั้งที่ช่องอื่นอาจยังไม่ได้กรอก
  // (ถูกเซฟเป็น 0 ถาวรโดยไม่ได้ตั้งใจ) เปลี่ยนมาเปิด _AddStartMeterSheet
  // ตัวจริงแทน ได้ทั้ง validation ที่ครบ (บังคับกรอกค่าใช้จ่ายด้วย) และเลิก
  // ปนฟอร์ม "บันทึกของเดือนที่ผ่านไปแล้ว" กับ "ตั้งค่าจุดเริ่มของรอบหน้า"
  // ไว้ในหน้าเดียวกันด้วย — สองเรื่องนี้เป็นคนละแนวคิดกันโดยสิ้นเชิง
  UserModel? _user;

  // สร้างตัวเลือกเดือนโดยอิงวันตัดรอบบิลจริง (billingDay) แทนเดือนปฏิทิน
  // ตรงๆ — ใช้สูตรเดียวกับที่ dashboard_screen.dart ใช้ตอน compileBill()
  // เพื่อให้ "เดือนของบิล" ที่เลือกในฟอร์มนี้ ตรงกับนิยาม "เดือนของบิล"
  // ที่ระบบ compile อัตโนมัติใช้จริง ไม่งั้นถ้า billingDay ไม่ใช่ปลายเดือน
  // (เช่นวันที่ 3, 15) เดือนที่ให้เลือกในฟอร์มนี้กับเดือนที่ระบบ compile
  // ให้เองอาจไม่ตรงกัน ทำให้กรอกบิลย้อนหลังผิดเดือน/ทับซ้อนกับบิลที่ระบบ
  // จะ compile ให้ทีหลังโดยไม่รู้ตัว
  //
  // ตัดตัวเลือกแรกสุด (รอบปัจจุบัน/รอบที่กำลังจะปิด) ออกไปเลย เหลือ 5 เดือน
  // — เดิมให้เลือกได้ครบ 6 เดือน รวมรอบปัจจุบันด้วย ซึ่งเป็นรอบเดียวกับที่
  // หน้า "เลขมิเตอร์ต้นรอบ" ใช้ ทำให้มีทาง "กรอกหน่วยที่ใช้" ปนเข้ามาได้ทั้ง
  // ที่รอบนั้นเก็บเป็นเลขสะสมเท่านั้น ไม่มีทางรู้ "หน่วยที่ใช้" ที่แม่นจริง
  // จากฟอร์มนี้ — ตัดออกจาก dropdown ไปเลยดีกว่า ปิดทางกรอกผิดตั้งแต่ต้น
  // แทนที่จะพึ่ง guard ทีหลัง ส่วนรอบนั้นมีลิงก์แยกไปหน้าเลขมิเตอร์ต้นรอบ
  // ให้กดแทน (ดู _goSetStartMeter() ด้านล่าง)
  List<DateTime> _generateMonthOptions(int billingDay) =>
      _generateHistoricalMonthOptions(billingDay).skip(1).toList();

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

  // เปิดฟอร์มตั้งเลขมิเตอร์ต้นรอบจริง (ตัวเดียวกับที่ปุ่ม FAB ในหน้า
  // ประวัติมิเตอร์ต้นรอบใช้) — เดิมเปิดซ้อน (push) บน sheet นี้เลย แต่พอมี
  // 2 sheet ซ้อนกัน backdrop dim ของแต่ละชั้นทับกัน ดูแน่นเกินไป เปลี่ยนมา
  // "ปิด sheet นี้ก่อนแล้วค่อยเปิดตัวใหม่" แทน (เหลือมองเห็นแค่ชั้นเดียว
  // เสมอ) แต่ต้องกันข้อมูลบิลที่กรอกค้างไว้หายเงียบๆ — ถ้ายังไม่ได้กรอก
  // อะไรเลยปิดแล้วเปิดใหม่ได้ทันที ถ้ากรอกมาบ้างแล้ว (มีค่าไฟ/น้ำ) ให้ถาม
  // ยืนยันก่อนว่าจะทิ้งข้อมูลที่กรอกไว้ไหม
  Future<void> _goSetStartMeter() async {
    if (_user == null) return;
    final hasUnsavedInput = _eUsedCtrl.text.isNotEmpty ||
        _eCostCtrl.text.isNotEmpty ||
        _wUsedCtrl.text.isNotEmpty ||
        _wCostCtrl.text.isNotEmpty;
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

  // เดือนของรอบปัจจุบัน (รอบที่กำลังจะปิด) — ตัดออกจาก _monthOptions ไปแล้ว
  // ด้านบน เก็บไว้แค่โชว์ชื่อเดือนในลิงก์ท้ายฟอร์ม ให้ผู้ใช้กดไปกรอกที่หน้า
  // เลขมิเตอร์ต้นรอบแทน (ดู _goSetStartMeter())
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
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
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
              color: Colors.orange.withValues(alpha: 0.08),
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
                          initialValue: _selectedMonth,
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
                  const SizedBox(height: 14),
                  // ลิงก์ไปหน้าเลขมิเตอร์ต้นรอบเสมอ — เดือนของรอบปัจจุบัน
                  // (${_currentCycleMonth}) ตัดออกจาก dropdown ด้านบนไปแล้ว
                  // (ดูคอมเมนต์ที่ _generateMonthOptions) เพราะเป็นคนละ
                  // แนวคิดกับฟอร์มนี้โดยสิ้นเชิง โชว์เป็นลิงก์เล็กๆ เสมอแทน
                  // การ์ดใหญ่แบบมีเงื่อนไข ให้ผู้ใช้กดไปกรอกที่ถูกที่ได้ตลอด
                  // ไม่ว่าจะเคยตั้งมาก่อนแล้วหรือยัง (กดแล้วไปแก้ไขค่าที่
                  // ตั้งไว้แล้วก็ได้ ไม่ใช่แค่ตั้งใหม่ครั้งแรก)
                  InkWell(
                    onTap: _goSetStartMeter,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.speed,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'มีบิลของ${thaiMonths[_currentCycleMonth.month - 1]} '
                              '${_currentCycleMonth.year} ด้วยไหม? '
                              'กรอกที่หน้าเลขมิเตอร์ต้นรอบแทน',
                              style: TextStyle(
                                  fontSize: 11.5,
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
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
      color: Colors.orange.withValues(alpha: 0.08),
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
    extends State<_HistoricalBillListScreen> with SingleTickerProviderStateMixin {
  List<BillModel> _bills = [];
  bool _isLoading = true;
  int _billingDay = 30;
  UserModel? _user;
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
    final all = await widget.firestoreService.getBills(widget.uid);
    // โชว์ทั้งบิลที่กรอกเองในหน้านี้ (imported) และบิลที่ auto-create มาจาก
    // หน้า "เลขมิเตอร์ต้นรอบ" (startMeter) — ตัวหลังยังต้องโชว์ในลิสต์
    // เหมือนเดิม แค่แก้ไข/ลบตรงนี้ไม่ได้ (ดู _isStartMeterBill + onRowTap)
    final relevant = all
        .where((b) => b.source == 'imported' || b.source == 'startMeter')
        .toList();
    if (mounted) {
      setState(() {
        _user = user;
        _billingDay = user?.billingDay ?? 30;
        _bills = relevant;
        _isLoading = false;
      });
    }
  }

  // เดือนของรอบปัจจุบัน (รอบเดียวกับที่หน้า "เลขมิเตอร์ต้นรอบ" ใช้) — บิลของ
  // เดือนนี้ไม่ได้เกิดจากการกรอกในฟอร์มนี้เลย (ตัด option ออกจาก dropdown
  // ไปแล้ว) แต่มาจากการตั้งเลขมิเตอร์ต้นรอบแทน ยังโชว์ในลิสต์นี้ตามปกติ
  // (source ก็ 'imported' เหมือนกัน) แต่กด "แก้ไข" ต้องพาไปฟอร์มที่ถูกต้อง
  bool _isCurrentCycleBill(BillModel bill) {
    final m = _generateHistoricalMonthOptions(_billingDay).first;
    return bill.year == m.year && bill.month == m.month;
  }

  // บิลที่มาจากหน้า "เลขมิเตอร์ต้นรอบ" (ไม่ใช่กรอกเองในหน้านี้) — แก้ไข/ลบ
  // ตรงนี้ไม่ได้ เพราะจะทำให้ BillModel กับ StartMeterRecordModel (เลข
  // มิเตอร์สะสม) ไม่ตรงกัน ต้องไปจัดการที่หน้าเลขมิเตอร์ต้นรอบแทนเท่านั้น
  bool _isStartMeterBill(BillModel bill) => bill.source == 'startMeter';

  // พาไปหน้า/ฟอร์มที่ถูกต้องสำหรับแก้ไขบิลที่มาจากเลขมิเตอร์ต้นรอบ — ถ้า
  // เป็นรอบปัจจุบัน (ยังไม่ปิดรอบ) เปิดฟอร์มแก้ไขตรงๆ ได้เลย ถ้าเป็นรอบเก่า
  // ที่ปิดไปแล้ว ฟอร์มนั้นแก้ไขรอบเก่าไม่ได้ (คำนวณ delta ใหม่ไม่ถูกต้อง)
  // พาไปหน้าประวัติเลขมิเตอร์ต้นรอบแทน ให้จัดการที่นั่น (ดู/ลบได้)
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

  // หน้านี้มีไว้กรอกบิลย้อนหลัง "ก่อนสมัครใช้แอป" เท่านั้น เหลือขอบเขตแค่ 5
  // เดือน (เดิม 6 เดือน แต่ตัดเดือนของรอบปัจจุบันออกจาก dropdown ไปแล้ว เพราะ
  // เป็นรอบเดียวกับเลขมิเตอร์ต้นรอบ ดู _generateMonthOptions) พอกรอกครบทั้ง 5
  // เดือนแล้ว ปุ่ม (+) ไม่มีที่ให้เพิ่มต่อแล้วจริงๆ (กดไปก็จะเจอแค่ข้อความ
  // "เดือนนี้มีบิลบันทึกไว้แล้ว" ทุกเดือน) ซ่อนปุ่มไปเลยดีกว่าปล่อยให้กดแล้วงง
  // — ยังแก้ไข/ลบรายการเดิมได้ตามปกติผ่านการแตะแถวในตาราง
  bool get _allSixMonthsRecorded {
    final options = _generateHistoricalMonthOptions(_billingDay).skip(1);
    final taken =
        _bills.map((b) => '${b.year}-${b.month}').toSet();
    return options
        .every((m) => taken.contains('${m.year}-${m.month}'));
  }

  Future<void> _openSheet({BillModel? existingBill}) async {
    // บิลของรอบปัจจุบันไม่ได้เกิดจากฟอร์มนี้ (ตัดออกจาก dropdown ไปแล้ว)
    // กด "แก้ไข" ต้องพาไปฟอร์มเลขมิเตอร์ต้นรอบตัวจริงแทน ไม่งั้นจะเปิดฟอร์ม
    // นี้ขึ้นมาเจอช่อง "หน่วยที่ใช้" ที่ไม่มีทางกรอกได้ถูกต้องสำหรับเดือนนี้
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
    final electricBills = _bills.where((b) => b.electricityCost > 0).toList();
    final waterBills = _bills.where((b) => b.waterCost > 0).toList();

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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                // การ์ดสรุปด้านบน — แยกแสดงตามแท็บที่เลือก (ไฟฟ้า/ประปา)
                // สไตล์เดียวกับแถบสรุปในหน้าประวัติมิเตอร์ไฟฟ้า/ประปา
                Builder(builder: (context) {
                  final isWater = _tabController.index == 1;
                  final accent = isWater ? Colors.blue : Colors.orange;
                  final icon = isWater ? Icons.water_drop : Icons.bolt;
                  final tabBills = isWater ? waterBills : electricBills;
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
                          '${tabBills.length} เดือน',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (!_isLoading && _allSixMonthsRecorded)
                          Text(
                            'ครบ 6 เดือนแล้ว',
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
                        bills: _bills,
                        latestId: latestId,
                        accent: Colors.orange,
                        unitLabel: 'หน่วยที่ใช้',
                        costLabel: 'ค่าไฟ',
                        emptyIcon: Icons.bolt,
                        usedOf: (b) => b.electricityUsed,
                        costOf: (b) => b.electricityCost,
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
              backgroundColor: const Color(0xFF2E7D32),
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
  }) {
    final formatter = NumberFormat('#,##0.00');

    if (bills.isEmpty) {
      return excelTableEmptyState(
        icon: emptyIcon,
        message: 'ยังไม่มีบิลย้อนหลัง\nกดปุ่ม + เพื่อเพิ่มบิลของเดือนก่อนๆ',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ExcelStyleTable(
        accent: accent,
        columns: [
          const ExcelTableColumn('เดือน ปี', align: TextAlign.left, flex: 3),
          ExcelTableColumn(unitLabel, flex: 2),
          ExcelTableColumn(costLabel, flex: 2),
        ],
        rowCount: bills.length,
        isLatest: (row) => bills[row].id == latestId,
        cellText: (row, col) {
          final b = bills[row];
          final missing = costOf(b) <= 0;
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
          // บิลที่มาจากหน้า "เลขมิเตอร์ต้นรอบ" (source == 'startMeter') แก้ไข/
          // ลบตรงนี้ไม่ได้ (ดู _isStartMeterBill ด้านบน) — เดิม onRowTap ไม่ได้
          // เช็คจุดนี้เลย ทำให้บิล startMeter ของรอบเก่าที่ปิดไปแล้วยังหลุดเข้า
          // ไปเปิดฟอร์มบันทึกบิลย้อนหลังได้ (คำนวณ delta ผิด) ตอนนี้ล็อกไว้แทน
          // แล้วพาไปหน้าที่ถูกต้องผ่าน _goToStartMeterFor
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