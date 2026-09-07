part of 'settings_screen.dart';

// ==================== Fixed Cost (รายการแยก) ====================
// รายการตัวเลือกหมวดหมู่ค่าใช้จ่ายคงที่ที่พบบ่อย — เลือกแล้วชื่อจะถูกล็อกตาม
// label ของหมวดนั้นทันที แก้ไขเองไม่ได้ ยกเว้นหมวด "อื่นๆ" ที่พิมพ์ชื่อเองได้
// (เผื่อมีรายการที่ไม่ตรงกับหมวดสำเร็จรูปเหล่านี้)
const List<({String key, String label, IconData icon})> _fixedCostCategories =
    [
  (key: 'gas', label: 'ค่าแก๊สหุงต้ม', icon: Icons.local_fire_department),
  (key: 'internet', label: 'ค่าอินเทอร์เน็ตบ้าน', icon: Icons.wifi),
  (
    key: 'maintenance',
    label: 'ค่าส่วนกลาง/นิติบุคคล',
    icon: Icons.apartment
  ),
  (key: 'insurance', label: 'ค่าประกัน', icon: Icons.shield_outlined),
  (
    key: 'subscription',
    label: 'ค่าสมาชิก/บริการรายเดือน',
    icon: Icons.subscriptions_outlined
  ),
  (key: 'other', label: 'อื่นๆ', icon: Icons.receipt_long),
];

// หมายเหตุ: ใช้ thaiMonths ที่มาจาก lib/utils/thai_date_utils.dart (import
// ผ่าน settings_screen.dart อยู่แล้ว) ไม่ประกาศซ้ำที่นี่ เพราะ Dart จะฟ้อง
// "imported from both ... " ทันทีถ้ามีสอง const ชื่อเดียวกันจากคนละไฟล์
// ในสโคปเดียวกัน — ของใน thai_date_utils.dart เป็นชื่อเดือนเต็ม (เช่น
// "ตุลาคม") ซึ่งตรงกับที่ dashboard_screen.dart ใช้แสดงชื่อรอบบิลอยู่แล้วด้วย

IconData _iconForFixedCostCategory(String key) {
  for (final c in _fixedCostCategories) {
    if (c.key == key) return c.icon;
  }
  return Icons.receipt_long;
}

String _labelForFixedCostCategory(String key) {
  for (final c in _fixedCostCategories) {
    if (c.key == key) return c.label;
  }
  return 'อื่นๆ';
}

// อธิบายว่า Fixed Cost คืออะไร ทำไมต้องแยกเป็นรายการย่อยแทนยอดเดียว
void _showFixedCostInfoPopup(BuildContext context) {
  showInfoDialog(
    context,
    title: 'รายจ่ายประจำ คืออะไร?',
    message: 'ค่าใช้จ่ายประจำที่ไม่ใช่ค่าไฟหรือค่าน้ำ แต่จ่ายเป็นจำนวนคงที่ทุกเดือน '
        'เช่น ค่าแก๊สหุงต้ม ค่าอินเทอร์เน็ต ค่าส่วนกลางหมู่บ้าน/คอนโด '
        'เพื่อให้ "ยอดค่าใช้จ่ายเดือนนี้" สะท้อนภาพรวมที่แท้จริง '
        'ไม่จำกัดเฉพาะค่าไฟ-น้ำ\n\n'
        'ระบบแยกเป็นรายการย่อยเนื่องจากแต่ละรายการเปลี่ยนแปลงไม่พร้อมกัน '
        'ทำให้แก้ไขหรือลบทีละรายการได้ และรวมยอดทั้งหมดโดยอัตโนมัติเพื่อนำไปบวก'
        'กับค่าไฟ-น้ำในหน้าหลักและหน้าวิเคราะห์',
  );
}

// ปีเริ่มต้นที่เลือกได้ — ปกติเริ่มจากปีปัจจุบันเลย (ไม่ต้องมีปีย้อนหลังให้
// เกะกะ) ยกเว้นตอนแก้ไขรายการเก่าที่ startDate เดิมย้อนไปก่อนปีนี้ ค่อยขยับ
// ขอบเขตให้ครอบคลุมปีนั้นด้วย ไม่งั้นค่าที่เคยบันทึกไว้จะไม่มีในตัวเลือก
DateTime _fixedCostMinDate([DateTime? anchor]) {
  final base = DateTime(DateTime.now().year, 1);
  if (anchor != null && anchor.isBefore(base)) {
    return DateTime(anchor.year, 1);
  }
  return base;
}

// ปีสิ้นสุดที่เลือกได้ไกลสุด (4 ปีข้างหน้า ครอบคลุมเคสของที่มีกำหนดระยะยาว
// เช่น ค่าประกัน 1 ปี)
DateTime _fixedCostMaxDate() {
  final now = DateTime.now();
  return DateTime(now.year + 4, 12);
}

// ตัดวันที่ให้อยู่ในช่วง [min, max] เทียบแค่ระดับเดือน — ใช้เก็บวันที่ 1
// ของเดือนนั้นเสมอ เพราะ isActiveInMonth() เทียบแค่ระดับเดือน ไม่สนวันที่จริง
DateTime _clampToMonthRange(DateTime d, DateTime min, DateTime max) {
  final asMonth = DateTime(d.year, d.month, 1);
  if (asMonth.isBefore(min)) return min;
  if (asMonth.isAfter(max)) return max;
  return asMonth;
}

// ช่องเลือกเดือน/ปีแบบกดเปิด dialog กลางจอทีเดียว — เปิดแล้วเจอการ์ดปฏิทินมี
// สปินเนอร์เดือน/ปีแบบลูกศรขึ้น-ลง กดเลือกแล้วกด "เลือก" เพื่อยืนยัน
class _MonthYearField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime?>? onChanged;
  final bool enabled;

  const _MonthYearField({
    required this.label,
    required this.value,
    required this.minDate,
    required this.maxDate,
    required this.onChanged,
    this.enabled = true,
  });

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: _MonthYearPickerSheet(
          label: label,
          initialValue: value,
          minDate: minDate,
          maxDate: maxDate,
        ),
      ),
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = value != null
        ? '${thaiMonths[value!.month - 1]} ${value!.year + 543}'
        : 'เลือก';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => _openPicker(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: !enabled,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          suffixIcon: Icon(Icons.expand_more,
              size: 18, color: enabled ? Colors.black54 : Colors.grey),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// เนื้อหา dialog เลือกปี+เดือน — การ์ดปฏิทินโครงตามภาพเรฟที่ส่งมา (ช่องเดือน/ปีคู่
// ทรงแคปซูลมีลูกศรขึ้น-ลงกดปรับทีละสเต็ป) แต่ปรับสีจากส้ม-แดงในเรฟให้เป็นธีม
// เขียวของแอป และตัดกริดวันในเดือนออกเพราะระบบเก็บข้อมูลแค่ระดับเดือน-ปี
// ไม่ได้ลงถึงวันที่จริง ปีที่แสดงเป็น พ.ศ. ให้ตรงกับส่วนอื่นของแอป (เก็บเป็น
// ค.ศ. ภายในเหมือนเดิม)
// แสดงผลผ่าน showDialog เป็นการ์ดลอยกลางจอ (ไม่ใช่ bottom sheet) จึงไม่ต้องมี
// หูจับลากหรือ SafeArea แบบที่ bottom sheet ต้องการ
class _MonthYearPickerSheet extends StatefulWidget {
  final String label;
  final DateTime? initialValue;
  final DateTime minDate;
  final DateTime maxDate;

  const _MonthYearPickerSheet({
    required this.label,
    required this.initialValue,
    required this.minDate,
    required this.maxDate,
  });

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue ?? DateTime.now();
    _year = v.year.clamp(widget.minDate.year, widget.maxDate.year);
    _month = v.month;
    _clampMonth();
  }

  List<int> _monthsForYear(int year) {
    final lo = year == widget.minDate.year ? widget.minDate.month : 1;
    final hi = year == widget.maxDate.year ? widget.maxDate.month : 12;
    return [for (var m = lo; m <= hi; m++) m];
  }

  // ถ้าเดือนที่เลือกอยู่หลุดขอบเขตของปีใหม่ (โดนตัดจาก minDate/maxDate) ปัด
  // ไปเดือนแรก/เดือนสุดท้ายที่ยังเลือกได้ของปีนั้นแทน
  void _clampMonth() {
    final months = _monthsForYear(_year);
    if (_month < months.first) _month = months.first;
    if (_month > months.last) _month = months.last;
  }

  void _stepMonth(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      if (y < widget.minDate.year || y > widget.maxDate.year) return;
      _year = y;
      _month = m;
      _clampMonth();
    });
  }

  void _stepYear(int delta) {
    setState(() {
      final y = _year + delta;
      if (y < widget.minDate.year || y > widget.maxDate.year) return;
      _year = y;
      _clampMonth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final months = _monthsForYear(_year);
    final years = [
      for (var y = widget.minDate.year; y <= widget.maxDate.year; y++) y
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('เลือก${widget.label}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                child: _MonthYearSpinner(
                  text: thaiMonths[_month - 1],
                  options: [for (final m in months) thaiMonths[m - 1]],
                  selectedIndex: months.indexOf(_month),
                  onSelectIndex: (i) =>
                      setState(() => _month = months[i]),
                  onUp: () => _stepMonth(1),
                  onDown: () => _stepMonth(-1),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: _MonthYearSpinner(
                  text: '${_year + 543}',
                  options: [for (final y in years) '${y + 543}'],
                  selectedIndex: years.indexOf(_year),
                  onSelectIndex: (i) => setState(() {
                    _year = years[i];
                    _clampMonth();
                  }),
                  onUp: () => _stepYear(1),
                  onDown: () => _stepYear(-1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 292,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: DashboardStyles.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () =>
                  Navigator.pop(context, DateTime(_year, _month, 1)),
              child: const Text('เลือก',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ช่องแคปซูลโค้งมนแบบในภาพเรฟ แบ่ง 2 โซนคั่นด้วยเส้นบางๆ:
// - โซนซ้าย (ข้อความ + ไอคอน ▾) กดแล้วเด้ง dropdown ให้เลือกตรงได้เลย
// - โซนขวา (▲▼) กดปรับทีละสเต็ปแบบเดิม แยกจากโซนซ้ายชัดเจน
class _MonthYearSpinner extends StatelessWidget {
  final String text;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const _MonthYearSpinner({
    required this.text,
    required this.options,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = DashboardStyles.primaryGreen.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: PopupMenuButton<int>(
              padding: EdgeInsets.zero,
              position: PopupMenuPosition.under,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (context) => [
                for (var i = 0; i < options.length; i++)
                  PopupMenuItem(
                    value: i,
                    height: 36,
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: i == selectedIndex
                            ? DashboardStyles.primaryGreen
                            : Colors.black87,
                      ),
                    ),
                  ),
              ],
              onSelected: onSelectIndex,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          letterSpacing: 0.3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more,
                      size: 15, color: DashboardStyles.primaryGreen),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: borderColor,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onUp,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Icon(Icons.keyboard_arrow_up,
                      size: 14, color: DashboardStyles.primaryGreen),
                ),
              ),
              InkWell(
                onTap: onDown,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Icon(Icons.keyboard_arrow_down,
                      size: 14, color: DashboardStyles.primaryGreen),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FixedCostScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _FixedCostScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_FixedCostScreen> createState() => _FixedCostScreenState();
}

class _FixedCostScreenState extends State<_FixedCostScreen> {
  List<FixedCostItemModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await widget.firestoreService.getFixedCostItems(widget.uid);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  // รวมเฉพาะรายการที่ "แอคทีฟ" ในเดือนปัจจุบัน — รายการที่หมดอายุ (endDate
  // ผ่านไปแล้ว) หรือยังไม่ถึงวันเริ่ม จะไม่ถูกนับในยอดนี้ แต่ยังโชว์ในลิสต์ด้านล่าง
  double get _total => _items
      .where((item) => item.isActiveInMonth(DateTime.now()))
      .fold(0, (sum, item) => sum + item.amount);

  // เปิด popup เพิ่ม/แก้ไขรายการ — ถ้าส่ง existing มาคือแก้ไข ไม่ส่งคือเพิ่มใหม่
  Future<void> _showAddEditItem({FixedCostItemModel? existing}) async {
    String selectedCategory = existing?.category ?? _fixedCostCategories.first.key;
    // ชื่อรายการ: ถ้าหมวดหมู่ไม่ใช่ "อื่นๆ" ชื่อจะถูกล็อกตาม label ของหมวดนั้นเสมอ
    // (ครอบคลุมกรณีแก้ไขรายการเก่าที่ชื่ออาจไม่ตรงกับ label ปัจจุบันด้วย)
    final nameController = TextEditingController(
      text: selectedCategory == 'other'
          ? (existing?.name ?? '')
          : _labelForFixedCostCategory(selectedCategory),
    );
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    String? errorText;
    // ขอบเขตปี/เดือนที่เลือกได้ — ต้อง clamp startDate/endDate ของรายการเดิม
    // ให้อยู่ในช่วงนี้เสมอ ไม่งั้นปี/เดือนอาจไม่มีในดรอปดาวน์
    final minDate = _fixedCostMinDate(existing?.startDate);
    final maxDate = _fixedCostMaxDate();
    // ช่วงเวลา: startDate เริ่มนับตั้งแต่เดือนนี้เป็น default, endDate = null
    // หมายถึงต่อเนื่องไม่มีกำหนด (พฤติกรรมเดิมของรายการที่ไม่มีวันสิ้นสุด)
    DateTime startDate = _clampToMonthRange(
        existing?.startDate ?? DateTime.now(), minDate, maxDate);
    DateTime? endDate = existing?.endDate == null
        ? null
        : _clampToMonthRange(existing!.endDate!, minDate, maxDate);
    bool hasEndDate = endDate != null;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'เพิ่มรายการ Fixed Cost' : 'แก้ไขรายการ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('หมวดหมู่',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _fixedCostCategories.map((c) {
                    final selected = c.key == selectedCategory;
                    return ChoiceChip(
                      label: Text(c.label, style: const TextStyle(fontSize: 12)),
                      avatar: Icon(c.icon,
                          size: 16,
                          color: selected ? Colors.white : DashboardStyles.primaryGreen),
                      selected: selected,
                      selectedColor: DashboardStyles.primaryGreen,
                      labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87),
                      onSelected: (_) => setDialogState(() {
                        selectedCategory = c.key;
                        if (c.key == 'other') {
                          // สลับมา "อื่นๆ" ให้พิมพ์ชื่อเองได้ — เคลียร์ช่องออก
                          // เฉพาะตอนที่ข้อความเดิมเป็น label ที่ล็อกไว้จากหมวดก่อนหน้า
                          // (กันเขียนทับชื่อที่ user เคยพิมพ์เองไว้ก่อนสลับหมวดไปมา)
                          if (_fixedCostCategories
                              .map((e) => e.label)
                              .contains(nameController.text)) {
                            nameController.text = '';
                          }
                        } else {
                          // หมวดสำเร็จรูป: ล็อกชื่อให้ตรงกับ label เสมอ แก้ไขเองไม่ได้
                          nameController.text = c.label;
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  // แก้ไขได้เฉพาะหมวด "อื่นๆ" — หมวดสำเร็จรูปอื่นชื่อถูกล็อกไว้
                  enabled: selectedCategory == 'other',
                  decoration: InputDecoration(
                    labelText: 'ชื่อรายการ',
                    hintText: 'เช่น ค่าที่จอดรถรายเดือน',
                    filled: selectedCategory != 'other',
                    fillColor: Colors.grey.shade100,
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'ยอดต่อเดือน',
                    suffixText: ' บาท',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text('ช่วงเวลา',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MonthYearField(
                        label: 'เริ่ม',
                        value: startDate,
                        minDate: minDate,
                        maxDate: maxDate,
                        onChanged: (picked) {
                          if (picked == null) return;
                          setDialogState(() {
                            startDate = picked;
                            // ถ้าเดือนสิ้นสุดที่ตั้งไว้ดันมาก่อนเดือนเริ่มใหม่
                            // (เพราะ user ย้ายเดือนเริ่มมาทีหลัง) ดันตามไปด้วย
                            if (endDate != null && endDate!.isBefore(startDate)) {
                              endDate = startDate;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MonthYearField(
                        label: 'สิ้นสุด',
                        value: endDate,
                        enabled: hasEndDate,
                        minDate: startDate,
                        maxDate: maxDate,
                        onChanged: (picked) =>
                            setDialogState(() => endDate = picked),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: hasEndDate,
                  onChanged: (v) => setDialogState(() {
                    hasEndDate = v ?? false;
                    if (hasEndDate) {
                      endDate ??= startDate;
                    } else {
                      endDate = null;
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  activeColor: DashboardStyles.primaryGreen,
                  title: const Text('มีวันสิ้นสุด', style: TextStyle(fontSize: 13)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    hasEndDate
                        ? 'จะไม่ถูกนับรวมในยอด Fixed Cost หลังวันที่สิ้นสุด'
                        : 'นับรวมทุกเดือนต่อเนื่อง ไม่มีกำหนดสิ้นสุด',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final amount = double.tryParse(amountController.text);
                if (name.isEmpty) {
                  setDialogState(() => errorText = 'กรอกชื่อรายการด้วยค่ะ');
                  return;
                }
                if (amount == null || amount <= 0) {
                  setDialogState(() => errorText = 'กรอกยอดเงินให้ถูกต้องด้วยค่ะ');
                  return;
                }
                if (hasEndDate && endDate!.isBefore(startDate)) {
                  setDialogState(
                      () => errorText = 'วันสิ้นสุดต้องไม่มาก่อนวันเริ่มค่ะ');
                  return;
                }

                final item = FixedCostItemModel(
                  id: existing?.id ?? const Uuid().v4(),
                  uid: widget.uid,
                  name: name,
                  category: selectedCategory,
                  amount: amount,
                  createdAt: existing?.createdAt ?? DateTime.now(),
                  startDate: startDate,
                  endDate: hasEndDate ? endDate : null,
                );
                await widget.firestoreService.saveFixedCostItem(item);
                if (context.mounted) Navigator.pop(context);
                await _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DashboardStyles.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FixedCostItemModel item) async {
final confirmed = await showConfirmDialog(
      context,
      title: 'ลบรายการนี้?',
      content: 'ต้องการลบ "${item.name}" ออกจาก Fixed Cost ใช่ไหม',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteFixedCostItem(widget.uid, item.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0');
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: AppTopBar(
        title: 'รายจ่ายประจำ',
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFixedCostInfoPopup(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DashboardStyles.primaryGreen))
          : Column(
              children: [
                // การ์ดสรุปยอดรวมด้านบน
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: DashboardStyles.primaryGreen,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: DashboardStyles.primaryGreen.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.summarize_outlined,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'รวม Fixed Cost ต่อเดือน',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatter.format(_total)} บาท',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_items.length} รายการ',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // รายการ Fixed Cost
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'ยังไม่มีรายการ Fixed Cost\nกดปุ่ม + เพื่อเพิ่มรายการแรกได้เลยค่ะ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isLatest = index == 0;
                            final isLast = index == _items.length - 1;
                            const accent = DashboardStyles.primaryGreen;
                            // รายการที่หมดอายุแล้วไม่ถูกนับในยอดรวมด้านบนแล้ว
                            // การ์ดจะจางลงพร้อม badge ให้เห็นชัดว่าทำไมยอดถึงลด
                            // เช็คแบบเดือน (ไม่ใช่วัน) ให้ตรงกับ isActiveInMonth()
                            // ที่ใช้คำนวณยอดรวมจริง — กันไม่ให้ badge กับยอดขัดกัน
                            final isExpired = item.endDate != null &&
                                !item.isActiveInMonth(DateTime.now());
                            final periodLabel = item.endDate == null
                                ? null
                                : 'ถึง ${thaiMonths[item.endDate!.month - 1]} ${item.endDate!.year}';

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
                                                        .withValues(alpha: 0.4),
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

                                  Expanded(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Opacity(
                                        opacity: isExpired ? 0.55 : 1,
                                        child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: isLatest
                                              ? Border.all(
                                                  color:
                                                      accent.withValues(alpha: 0.3))
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.grey
                                                  .withValues(alpha: 0.1),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: accent
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                _iconForFixedCostCategory(
                                                    item.category),
                                                color: accent,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _labelForFixedCostCategory(
                                                        item.category),
                                                    style: TextStyle(
                                                        fontSize: 11.5,
                                                        color: Colors
                                                            .grey.shade500),
                                                  ),
                                                  if (isExpired) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 7,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .red.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                      child: Text(
                                                        'หมดอายุแล้ว',
                                                        style: TextStyle(
                                                            fontSize: 10.5,
                                                            color: Colors
                                                                .red.shade400),
                                                      ),
                                                    ),
                                                  ] else if (periodLabel !=
                                                      null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      periodLabel,
                                                      style: TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.grey
                                                              .shade400),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Text(
                                              '${formatter.format(item.amount)} บาท',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: accent,
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert,
                                                  size: 18,
                                                  color:
                                                      Colors.grey.shade500),
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _showAddEditItem(
                                                      existing: item);
                                                } else if (value ==
                                                    'delete') {
                                                  _confirmDelete(item);
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
                                                          color: Colors.red)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
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
        onPressed: () => _showAddEditItem(),
        backgroundColor: DashboardStyles.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}