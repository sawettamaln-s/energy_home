part of 'settings_screen.dart';

// ==================== บันทึกค่ามิเตอร์ต้นรอบ (bottom sheet) ====================
// เดิมเป็น AlertDialog แยกอยู่คนละหน้ากับ "ประวัติค่ามิเตอร์ต้นรอบ" — ย้ายมา
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
    _loadCurrent();
  }

  // ดึงค่าปัจจุบันของ user มาตั้งเป็นค่าเริ่มต้นในฟอร์ม
  // ไม่ได้รับ UserModel มาจากหน้าก่อนหน้าตรงๆ เพื่อให้ widget นี้ใช้งาน
  // ได้เองอิสระ ไม่ผูกกับ state ของหน้าตั้งค่า
  //
  // แก้บั๊ก: เดิมกด "บันทึกค่ามิเตอร์ต้นรอบ" กี่ครั้งก็ได้ไม่จำกัด ทุกครั้ง
  // สร้าง record ใหม่ในประวัติเสมอ แม้จะยังอยู่รอบเดิม (ยังไม่ข้ามวันตัด
  // รอบบิลไปอีกรอบ) ทำให้ประวัติมีรายการซ้ำซ้อนของรอบเดียวกันได้ไม่จำกัด
  // ตอนนี้เช็คก่อนว่าค่าที่ตั้งไว้ล่าสุดตรงกับ "รอบที่ควรตั้งตอนนี้" ไหม
  // (คำนวณจาก billingDay จริง ไม่ใช่เดาจากเดือนปฏิทิน) ถ้าตรง = โหมดแก้ไข
  // (แก้ทับของเดิม) ถ้าไม่ตรง (ยังไม่เคยตั้ง หรือรอบขยับไปแล้ว) = โหมด
  // ตั้งค่าใหม่ (ฟอร์มว่าง สร้าง record ใหม่ตามปกติ)
  Future<void> _loadCurrent() async {
    final user = await widget.firestoreService.getUser(widget.uid);
    _user = user;
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
        final history =
            await widget.firestoreService.getStartMeterHistory(widget.uid);
        _editingRecordId = history.isNotEmpty ? history.first.id : null;
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
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _eCtrl.dispose();
    _peakCtrl.dispose();
    _offPeakCtrl.dispose();
    _wCtrl.dispose();
    super.dispose();
  }

  void _showInfoPopup() {
    showInfoDialog(
      context,
      title: 'กรอกเลขจากบิลตรงไหน?',
      message: 'เปิดใบแจ้งหนี้ค่าไฟ/ค่าน้ำเดือนล่าสุด แล้วมองหาช่อง'
          '"เลขอ่านครั้งหลัง" หรือ "Last Meter Reading" '
          'คือเลขที่มิเตอร์อ่านได้ล่าสุดตอนเจ้าหน้าที่มาจดในรอบบิลนั้น '
          'นำตัวเลขนี้มากรอก (ไม่ใช่ "เลขอ่านครั้งก่อน" ที่อยู่คู่กัน '
          'เนื่องจากเป็นเลขของรอบก่อนหน้า)\n\n'
          'ระบบใช้เลขนี้เป็นจุดเริ่มต้นของรอบบิลถัดไป เพื่อคำนวณหน่วยที่ใช้'
          'เมื่อเทียบกับเลขที่บันทึกในแอปครั้งถัดไป',
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final eVal = double.tryParse(_eCtrl.text) ?? 0;
      final peakVal = double.tryParse(_peakCtrl.text) ?? 0;
      final offPeakVal = double.tryParse(_offPeakCtrl.text) ?? 0;
      final wVal = double.tryParse(_wCtrl.text) ?? 0;

      await widget.firestoreService.updateUser(widget.uid, {
        'startElectricityValue': eVal,
        'startPeakValue': peakVal,
        'startOffPeakValue': offPeakVal,
        'startWaterValue': wVal,
        'startBillingMonth': _selectedMonth,
        'startBillingYear': _selectedYear,
        // เคยข้ามมาก่อนหรือไม่ก็ตาม กรอกค่าจริงสำเร็จแล้ว = configured แล้ว
        'startMeterConfigured': true,
      });
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

  // ล้างค่ามิเตอร์ต้นรอบ "จริง" ที่หน้าแรกใช้แสดงผล (user.startElectricityValue
  // ฯลฯ) — คนละอันกับการลบประวัติ (StartMeterRecordModel) ที่แค่ลบ snapshot
  // ไว้ดูย้อนหลังเฉยๆ ไม่เคยมีผลกับค่าจริงเลย ปุ่มนี้ตั้งใจแยกไว้ให้ชัดว่า
  // เป็น action ที่กระทบมากกว่า ต้องมี confirm แยกต่างหาก
  Future<void> _confirmClearStartMeter() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'ล้างค่ามิเตอร์ต้นรอบ',
      content: 'ค่ามิเตอร์ต้นรอบทั้งหมดจะถูกล้าง ต้องตั้งค่าใหม่ก่อนถึงจะ'
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
                        'บันทึกค่ามิเตอร์ต้นรอบ',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.info_outline,
                                color: Color(0xFF2E7D32)),
                            onPressed: _showInfoPopup,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
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
                        // แจ้งผู้ใช้ให้ชัดว่ากำลังแก้ไขค่าที่ตั้งไว้ล่าสุด
                        // (ยังอยู่รอบเดิม) หรือกำลังตั้งค่าต้นรอบใหม่ กันสับสน
                        // ว่าทำไมบางทีฟอร์มขึ้นมาว่าง บางทีมีค่าเดิมเติมไว้
                        if (_user != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: (_isEditingCurrentCycle
                                      ? Colors.blue
                                      : const Color(0xFF2E7D32))
                                  .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isEditingCurrentCycle
                                      ? Icons.edit_outlined
                                      : Icons.fiber_new_outlined,
                                  size: 15,
                                  color: _isEditingCurrentCycle
                                      ? Colors.blue.shade700
                                      : const Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _isEditingCurrentCycle
                                        ? 'แก้ไขค่าที่ตั้งไว้ล่าสุด (ยังอยู่รอบเดิม ยังไม่ถึงวันตัดรอบถัดไป)'
                                        : 'ตั้งค่าต้นรอบใหม่สำหรับรอบถัดไป',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _isEditingCurrentCycle
                                          ? Colors.blue.shade700
                                          : const Color(0xFF2E7D32),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const Text(
                          'เดือนของใบแจ้งหนี้',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: _selectedMonth,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: List.generate(12, (i) {
                                  return DropdownMenuItem(
                                    value: i + 1,
                                    child: Text(
                                      thaiMonths[i],
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }),
                                onChanged: (val) =>
                                    setState(() => _selectedMonth = val!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedYear,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: [
                                  DateTime.now().year - 1,
                                  DateTime.now().year,
                                ].map((year) {
                                  return DropdownMenuItem(
                                    value: year,
                                    child: Text(
                                      '$year',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedYear = val!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // ใช้ widget กลาง (StartMeterFieldsSection) แทนโค้ด
                        // ที่เคย copy ไว้เองในนี้ — เพื่อให้คำที่ใช้ ("เลข
                        // มิเตอร์สะสม") และ layout ตรงกันทุกจุดที่กรอกเลข
                        // มิเตอร์ต้นรอบในแอป (หน้านี้ / ฝังในบิลย้อนหลัง /
                        // ตอนสมัครสมาชิก) ไม่ต้องแก้ 3 ที่แยกกันอีกต่อไป
                        StartMeterFieldsSection(
                          isTou: widget.isTou,
                          electricityCtrl: _eCtrl,
                          peakCtrl: _peakCtrl,
                          offPeakCtrl: _offPeakCtrl,
                          waterCtrl: _wCtrl,
                          title: 'เลขมิเตอร์สะสมต้นรอบ',
                          subtitle: 'กรอกเลขจากใบแจ้งหนี้เดือนที่เลือกไว้ด้านบน',
                        ),
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
                                'ล้างค่ามิเตอร์ต้นรอบ',
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

// ==================== ประวัติค่ามิเตอร์ต้นรอบ ====================
// อธิบายภาพรวมของหน้า "ค่ามิเตอร์ต้นรอบ" ไว้ที่ AppBar ของหน้านี้เลย —
// ตามแพทเทิร์นเดียวกับ _showFixedCostInfoPopup / _showHistoricalBillInfoPopup
// เปิดหน้าตั้งค่ามิเตอร์ต้นรอบจากไฟล์อื่นได้ (เช่น Dashboard ตอนเจอบัญชีที่
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
    message: 'ค่ามิเตอร์ต้นรอบคือเลขที่มิเตอร์อ่านได้ตอนเริ่มรอบบิลใหม่ '
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

  // เปิด bottom sheet บันทึกค่ามิเตอร์ต้นรอบ — เดิมเป็นปุ่มแยกอยู่คนละหน้า
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
      content: 'ต้องการลบประวัติการตั้งค่ามิเตอร์ต้นรอบรายการนี้ใช่ไหมคะ',
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
        title: const Text('ค่ามิเตอร์ต้นรอบ'),
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
                              'บันทึกค่ามิเตอร์ต้นรอบทั้งหมด',
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
                                  'ยังไม่มีประวัติการตั้งค่ามิเตอร์ต้นรอบ',
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