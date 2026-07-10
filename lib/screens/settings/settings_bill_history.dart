part of 'settings_screen.dart';

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
  late final List<DateTime> _monthOptions;
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

  @override
  void initState() {
    super.initState();
    final existing = widget.existingBill;
    final now = DateTime.now();
    _monthOptions = List.generate(
      6,
      (i) => DateTime(now.year, now.month - (i + 1), 1),
    );
    // ถ้าแก้ไขบิลที่เดือนอยู่นอกช่วง 6 เดือนล่าสุด ให้เพิ่มเดือนนั้นเข้าไปในตัวเลือกด้วย
    if (existing != null &&
        !_monthOptions.any(
            (m) => m.year == existing.year && m.month == existing.month)) {
      _monthOptions.add(DateTime(existing.year, existing.month, 1));
    }
    _selectedMonth = existing != null
        ? DateTime(existing.year, existing.month, 1)
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
    if (mounted) setState(() => _user = user);
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
  // ตัด Fixed Cost ออกจากฟีเจอร์นี้ทั้งหมดตามที่ขอ — บันทึกบิลย้อนหลัง
  // เก็บแค่เรื่องบิลไฟ/น้ำล้วนๆ ไม่ปนกับค่าใช้จ่ายคงที่รายเดือนแล้ว
  double get _total => _eCost + _wCost;

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
        totalCost: _total,
        // บิลย้อนหลังคือของจริงที่เกิดขึ้นแล้ว ไม่ใช่ค่าพยากรณ์
        forecastElectricity: _eCost,
        forecastWater: _wCost,
        forecastTotal: _total,
        isComplete: true,
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
          // รอบถัดจากเดือนที่เพิ่งกรอกบิล คือรอบที่เลขมิเตอร์นี้จะถูกใช้เป็น
          // จุดตั้งต้น (เช่น กรอกบิลเดือน 6 → ตั้งต้นให้รอบเดือน 7)
          final nextCycle =
              DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);

          await widget.firestoreService.updateUser(widget.uid, {
            'startElectricityValue': eVal,
            'startPeakValue': peakVal,
            'startOffPeakValue': offPeakVal,
            'startWaterValue': wVal,
            'startBillingMonth': nextCycle.month,
            'startBillingYear': nextCycle.year,
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
              billingMonth: nextCycle.month,
              billingYear: nextCycle.year,
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
          if (utilityLabel == 'หน่วยไฟที่ใช้') ...[
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

  void _showMeterBundleInfoPopup() {
    showInfoDialog(
      context,
      title: 'เลขนี้เอาไปใช้ทำอะไร?',
      message: 'เดือนนี้เป็นเดือนล่าสุดก่อนที่แอปจะเริ่มติดตามการใช้ไฟ/น้ำ'
          'จริงผ่านการบันทึกมิเตอร์ทุกวัน ระบบจึงต้องมี "เลขมิเตอร์สะสม" '
          'ณ วันตัดรอบของเดือนนี้ไว้เป็นจุดเริ่มต้น เพื่อคำนวณหน่วยที่ใช้'
          'ของรอบถัดไปให้ถูกต้อง\n\n'
          'เปิดใบแจ้งหนี้เดือนนี้ แล้วมองหาช่อง "เลขอ่านครั้งหลัง" '
          '(ตัวเลขสะสมบนมิเตอร์ ไม่ใช่หน่วยที่ใช้ที่กรอกด้านบน) '
          'กรอกที่นี่ได้เลย ไม่ต้องไปกรอกซ้ำที่หน้า "บันทึกมิเตอร์ต้นรอบ" อีก\n\n'
          'ไม่บังคับ — ถ้าข้ามไป ยังไปตั้งค่าที่หน้า "บันทึกมิเตอร์ต้นรอบ" '
          'ทีหลังได้ตามปกติ',
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
                            _label('หน่วยไฟที่ใช้',
                                onInfoTap: () =>
                                    _showUsageInfoPopup('หน่วยไฟที่ใช้', 'kWh')),
                            TextField(
                              controller: _eUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'หน่วย'),
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
                            _label('หน่วยน้ำที่ใช้',
                                onInfoTap: () => _showUsageInfoPopup(
                                    'หน่วยน้ำที่ใช้', 'ลบ.ม.')),
                            TextField(
                              controller: _wUsedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _fieldDecoration(hint: '0', suffixText: 'หน่วย'),
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
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.speed,
                                  size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'ตั้งเลขมิเตอร์ต้นรอบเดือนถัดไปเลยไหม?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ),
                              GestureDetector(
                                onTap: _showMeterBundleInfoPopup,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blue.withOpacity(0.15),
                                  ),
                                  child: Text('!',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ไม่บังคับ • กรอกเลขมิเตอร์สะสม (ไม่ใช่หน่วยที่ใช้) '
                            'จากใบแจ้งหนี้เดือนนี้ ข้ามได้ถ้าจะไปตั้งทีหลัง',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          if (_user!.meterType == 'tou') ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('เลขมิเตอร์ On-Peak'),
                                      TextField(
                                        controller: _meterPeakCtrl,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: _fieldDecoration(
                                            hint: 'เช่น 8500',
                                            suffixText: 'หน่วย'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('เลขมิเตอร์ Off-Peak'),
                                      TextField(
                                        controller: _meterOffPeakCtrl,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: _fieldDecoration(
                                            hint: 'เช่น 5400',
                                            suffixText: 'หน่วย'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            _label('เลขมิเตอร์ไฟฟ้า'),
                            TextField(
                              controller: _meterECtrl,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: _fieldDecoration(
                                  hint: 'เช่น 14009', suffixText: 'หน่วย'),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _label('เลขมิเตอร์น้ำ'),
                          TextField(
                            controller: _meterWCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: _fieldDecoration(
                                hint: 'เช่น 148', suffixText: 'หน่วย'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ยอดรวมเดือนนี้',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${formatter.format(_total)} บาท',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final all = await widget.firestoreService.getBills(widget.uid);
    // เฉพาะบิลที่กรอกย้อนหลังเอง (ไม่ใช่บิลที่ระบบสรุปจาก log อัตโนมัติ)
    final imported = all.where((b) => b.source == 'imported').toList();
    if (mounted) {
      setState(() {
        _bills = imported;
        _isLoading = false;
      });
    }
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
                                                    value: '${formatter.format(bill.electricityCost)} บาท',
                                                  ),
                                                if (bill.waterCost > 0)
                                                  ValueChip(
                                                    icon: Icons.water_drop,
                                                    color: Colors.blue,
                                                    label: 'น้ำ',
                                                    value: '${formatter.format(bill.waterCost)} บาท',
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
        onPressed: () => _openSheet(),
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}