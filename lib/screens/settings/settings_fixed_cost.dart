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
// "ตุลาคม") ซึ่งตรงกับที่หน้าหลัก (widgets/cost_summary_card.dart) ใช้แสดงชื่อรอบบิลอยู่แล้วด้วย

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.v20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.v24),
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
        : (enabled ? 'เลือก' : 'ไม่มีกำหนด');
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.v12),
      onTap: enabled ? () => _openPicker(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: !enabled,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.v12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.v12, vertical: AppSpacing.v14),
          suffixIcon: Icon(Icons.expand_more,
              size: 18, color: enabled ? Colors.black54 : Colors.grey),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: AppTypography.s13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// เนื้อหา dialog เลือกปี+เดือน — ช่องเดือน/ปีคู่ทรงแคปซูล มีลูกศรขึ้น-ลง
// กดปรับทีละสเต็ป ใช้สีเขียวของแอป ไม่มีกริดวันในเดือน เพราะระบบเก็บข้อมูล
// แค่ระดับเดือน-ปี ปีที่แสดงเป็น พ.ศ. ให้ตรงกับส่วนอื่นของแอป (เก็บเป็น
// ค.ศ. ภายใน)
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v24, AppSpacing.v20, AppSpacing.v24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('เลือก${widget.label}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s15)),
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.v13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.v14)),
                elevation: 0,
              ),
              onPressed: () =>
                  Navigator.pop(context, DateTime(_year, _month, 1)),
              child: const Text('เลือก',
                  style:
                      TextStyle(fontSize: AppTypography.s15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ช่องแคปซูลโค้งมน แบ่ง 2 โซนคั่นด้วยเส้นบางๆ:
// - โซนซ้าย (ข้อความ + ไอคอน ▾) กดแล้วเด้ง dropdown ให้เลือกตรงได้เลย
// - โซนขวา (▲▼) กดปรับทีละสเต็ป
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
      padding: const EdgeInsets.only(left: AppSpacing.v14, right: AppSpacing.v4, top: AppSpacing.v5, bottom: AppSpacing.v5),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.v30),
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
                  borderRadius: BorderRadius.circular(AppSpacing.v12)),
              itemBuilder: (context) => [
                for (var i = 0; i < options.length; i++)
                  PopupMenuItem(
                    value: i,
                    height: 36,
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: AppTypography.s13,
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
                          fontSize: AppTypography.s14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          letterSpacing: 0.3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more,
                      size: 15, color: DashboardStyles.primaryGreen),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.v4),
            color: borderColor,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onUp,
                borderRadius: BorderRadius.circular(AppSpacing.v20),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.v1),
                  child: Icon(Icons.keyboard_arrow_up,
                      size: 14, color: DashboardStyles.primaryGreen),
                ),
              ),
              InkWell(
                onTap: onDown,
                borderRadius: BorderRadius.circular(AppSpacing.v20),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.v1),
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

// หน้ารายจ่ายประจำ: การ์ดยอดเดือนนี้ + รายการแยกกลุ่ม ใช้อยู่ / ยังไม่เริ่ม /
// สิ้นสุดแล้ว (พับไว้) แตะแถวเพื่อแก้ไขหรือลบ
class FixedCostScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const FixedCostScreen({
    super.key,
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<FixedCostScreen> createState() => _FixedCostScreenState();
}

class _FixedCostScreenState extends State<FixedCostScreen> {
  List<FixedCostItemModel> _items = [];
  bool _isLoading = true;
  // กลุ่ม "สิ้นสุดแล้ว" พับไว้เป็นค่าเริ่มต้น (ไม่มีผลกับยอดแล้ว)
  bool _showEnded = false;

  static final _baht = NumberFormat('#,##0');

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

  // สถานะเทียบกับเดือนนี้ (ระดับเดือน ตรงกับ isActiveInMonth ที่ใช้คำนวณยอดจริง)
  bool _isActive(FixedCostItemModel i) => i.isActiveInMonth(DateTime.now());
  bool _isUpcoming(FixedCostItemModel i) {
    final now = DateTime.now();
    return DateTime(i.startDate.year, i.startDate.month).isAfter(DateTime(now.year, now.month));
  }

  List<FixedCostItemModel> get _active => _items.where(_isActive).toList();
  List<FixedCostItemModel> get _upcoming => _items.where((i) => !_isActive(i) && _isUpcoming(i)).toList();
  List<FixedCostItemModel> get _ended => _items.where((i) => !_isActive(i) && !_isUpcoming(i)).toList();

  // ยอดรวมเฉพาะรายการที่ใช้อยู่เดือนนี้ — เป็นยอดเดียวกับที่หน้าหลักนับ
  double get _total => _active.fold(0, (sum, item) => sum + item.amount);

  String _shortMonth(DateTime d) => '${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

  String _periodText(FixedCostItemModel i) {
    if (i.endDate == null) return 'ทุกเดือน ตั้งแต่ ${_shortMonth(i.startDate)}';
    return '${_shortMonth(i.startDate)} – ${_shortMonth(i.endDate!)}';
  }

  Future<void> _showAddEditItem({FixedCostItemModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FixedCostFormSheet(
        uid: widget.uid,
        firestoreService: widget.firestoreService,
        existing: existing,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _confirmDelete(FixedCostItemModel item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'ลบรายการนี้?',
      content: 'ต้องการลบ "${item.name}" ออกจากรายจ่ายประจำใช่ไหมคะ',
    );
    if (confirmed == true) {
      await widget.firestoreService.deleteFixedCostItem(widget.uid, item.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardStyles.background,
      appBar: const AppTopBar(title: 'รายจ่ายประจำ'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v16, AppSpacing.v16, AppSpacing.v32),
              children: [
                FadeSlideIn(child: _buildSummaryCard()),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.v32),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: AppSpacing.v8),
                        Text('ยังไม่มีรายจ่ายประจำ',
                            style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                if (_active.isNotEmpty) ..._section('ใช้อยู่', _active),
                if (_upcoming.isNotEmpty) ..._section('ยังไม่เริ่ม', _upcoming),
                if (_ended.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.v16),
                  InkWell(
                    onTap: () => setState(() => _showEnded = !_showEnded),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v6, horizontal: AppSpacing.v4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('สิ้นสุดแล้ว (${_ended.length})',
                                style: TextStyle(
                                    fontSize: AppTypography.s13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700)),
                          ),
                          AnimatedRotation(
                            turns: _showEnded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.expand_more_rounded, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _showEnded
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.v6),
                            child: _itemCard(_ended, muted: true),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.payments_outlined, color: AppColors.primaryGreen, size: 40),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('รายจ่ายประจำเดือนนี้',
                        style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedAmount(
                        value: _total,
                        pattern: '#,##0',
                        suffix: ' บาท',
                        style: const TextStyle(
                            fontSize: AppTypography.s24, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      ),
                    ),
                  ],
                ),
              ),
              _pageInfoButton(
                tooltip: 'รายจ่ายประจำคืออะไร',
                onPressed: () => _showFixedCostInfoPopup(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v6),
          Text(
            _active.isEmpty
                ? 'ค่าใช้จ่ายที่จ่ายเท่ากันทุกเดือน เช่น อินเทอร์เน็ต ค่าส่วนกลาง จะถูกนับรวมในยอดหน้าหลักค่ะ'
                : 'นับรวมในยอดค่าใช้จ่ายหน้าหลัก · ${_active.length} รายการที่ใช้อยู่',
            style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade600),
          ),
          const SizedBox(height: AppSpacing.v14),
          ElevatedButton.icon(
            onPressed: () => _showAddEditItem(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('เพิ่มรายจ่ายประจำ'),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<FixedCostItemModel> items) {
    return [
      const SizedBox(height: AppSpacing.v20),
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.v4, bottom: AppSpacing.v8),
        child: Text('$title (${items.length})',
            style: TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      ),
      _itemCard(items),
    ];
  }

  Widget _itemCard(List<FixedCostItemModel> items, {bool muted = false}) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const Divider(indent: 66),
            _itemRow(item, muted: muted),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(FixedCostItemModel item, {required bool muted}) {
    final color = muted ? Colors.grey.shade500 : AppColors.primaryGreen;
    return InkWell(
      onTap: () => showTableRowActions(
        context,
        title: item.name,
        subtitle: '${_baht.format(item.amount)} บาท/เดือน · ${_periodText(item)}',
        onEdit: () => _showAddEditItem(existing: item),
        onDelete: () => _confirmDelete(item),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
        child: Row(
          children: [
            IconBadge(icon: _iconForFixedCostCategory(item.category), color: color, size: 38),
            const SizedBox(width: AppSpacing.v12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppTypography.s14,
                          fontWeight: FontWeight.w600,
                          color: muted ? Colors.grey.shade600 : AppColors.textDark)),
                  const SizedBox(height: AppSpacing.v2),
                  Text(_periodText(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.v8),
            Text('${_baht.format(item.amount)} บาท',
                style: TextStyle(
                    fontSize: AppTypography.s14,
                    fontWeight: FontWeight.w700,
                    color: muted ? Colors.grey.shade500 : AppColors.textDark,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ==================== ฟอร์มเพิ่ม/แก้ไขรายจ่ายประจำ (bottom sheet) ====================
// หมวดสำเร็จรูปล็อกชื่อตาม label ของหมวด ส่วนหมวด "อื่นๆ" พิมพ์ชื่อเองได้ ช่วงเวลา
// เก็บระดับเดือน (วันที่ 1) — ไม่มีวันสิ้นสุด = นับทุกเดือนต่อเนื่อง
class _FixedCostFormSheet extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final FixedCostItemModel? existing;

  const _FixedCostFormSheet({required this.uid, required this.firestoreService, this.existing});

  @override
  State<_FixedCostFormSheet> createState() => _FixedCostFormSheetState();
}

class _FixedCostFormSheetState extends State<_FixedCostFormSheet> {
  late String _category = widget.existing?.category ?? _fixedCostCategories.first.key;
  late final _nameCtrl =
      TextEditingController(text: _category == 'other' ? (widget.existing?.name ?? '') : '');
  late final _amountCtrl =
      TextEditingController(text: widget.existing != null ? widget.existing!.amount.toStringAsFixed(0) : '');
  // ขอบเขตปี/เดือนที่เลือกได้ — clamp วันที่ของรายการเดิมให้อยู่ในช่วงนี้เสมอ
  late final DateTime _minDate = _fixedCostMinDate(widget.existing?.startDate);
  late final DateTime _maxDate = _fixedCostMaxDate();
  late DateTime _startDate = _clampToMonthRange(widget.existing?.startDate ?? DateTime.now(), _minDate, _maxDate);
  late DateTime? _endDate =
      widget.existing?.endDate == null ? null : _clampToMonthRange(widget.existing!.endDate!, _minDate, _maxDate);
  late bool _hasEndDate = _endDate != null;
  String? _error;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _category == 'other' ? _nameCtrl.text.trim() : _labelForFixedCostCategory(_category);
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (name.isEmpty) {
      setState(() => _error = 'กรอกชื่อรายการด้วยค่ะ');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'กรอกยอดเงินต่อเดือนให้ถูกต้องด้วยค่ะ');
      return;
    }
    if (_hasEndDate && _endDate!.isBefore(_startDate)) {
      setState(() => _error = 'เดือนสิ้นสุดต้องไม่มาก่อนเดือนเริ่มค่ะ');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final item = FixedCostItemModel(
        id: widget.existing?.id ?? const Uuid().v4(),
        uid: widget.uid,
        name: name,
        category: _category,
        amount: amount,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        startDate: _startDate,
        endDate: _hasEndDate ? _endDate : null,
      );
      await widget.firestoreService.saveFixedCostItem(item);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.v8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.s13_5, color: AppColors.textDark)),
      );

  Widget _categoryTile(({String key, String label, IconData icon}) c) {
    final selected = c.key == _category;
    return Material(
      color: selected ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: selected ? AppColors.primaryGreen : Colors.grey.shade300, width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _category = c.key;
          _error = null;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v10, vertical: AppSpacing.v10),
          child: Row(
            children: [
              Icon(c.icon, size: 18, color: selected ? AppColors.primaryGreen : Colors.grey.shade600),
              const SizedBox(width: AppSpacing.v8),
              Expanded(
                child: Text(c.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppTypography.s12_5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? AppColors.primaryGreen : AppColors.textDark)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.9 - bottomInset;
    const categories = _fixedCostCategories;

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
                    child: Text(widget.existing == null ? 'เพิ่มรายจ่ายประจำ' : 'แก้ไขรายจ่ายประจำ',
                        style: const TextStyle(
                            fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
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
                    _label('หมวดหมู่'),
                    // ตาราง 2 คอลัมน์ แต่ละแถวสูงเท่าช่องที่สูงที่สุด (ชื่อหมวดยาว 2 บรรทัด)
                    for (var i = 0; i < categories.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.v8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _categoryTile(categories[i])),
                            const SizedBox(width: AppSpacing.v8),
                            Expanded(
                                child: i + 1 < categories.length
                                    ? _categoryTile(categories[i + 1])
                                    : const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ],
                    if (_category == 'other') ...[
                      const SizedBox(height: AppSpacing.v16),
                      _label('ชื่อรายการ'),
                      TextField(
                        controller: _nameCtrl,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: const InputDecoration(hintText: 'เช่น ค่าที่จอดรถรายเดือน'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.v16),
                    _label('ยอดต่อเดือน'),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _error = null),
                      decoration: const InputDecoration(hintText: 'เช่น 599', suffixText: 'บาท'),
                    ),
                    const SizedBox(height: AppSpacing.v20),
                    _label('ช่วงเวลา'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MonthYearField(
                            label: 'เดือนเริ่ม',
                            value: _startDate,
                            minDate: _minDate,
                            maxDate: _maxDate,
                            onChanged: (picked) {
                              if (picked == null) return;
                              setState(() {
                                _startDate = picked;
                                // เดือนสิ้นสุดมาก่อนเดือนเริ่มใหม่ — ดันตามไปด้วย
                                if (_endDate != null && _endDate!.isBefore(_startDate)) _endDate = _startDate;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.v10),
                        Expanded(
                          child: _MonthYearField(
                            label: 'เดือนสิ้นสุด',
                            value: _hasEndDate ? _endDate : null,
                            enabled: _hasEndDate,
                            minDate: _startDate,
                            maxDate: _maxDate,
                            onChanged: (picked) => setState(() => _endDate = picked),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.v8),
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _hasEndDate,
                        onChanged: (v) => setState(() {
                          _hasEndDate = v;
                          if (v) _endDate ??= _startDate;
                        }),
                        title: const Text('มีเดือนสิ้นสุด',
                            style: TextStyle(fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _hasEndDate
                              ? 'ไม่นับรวมในยอดหลังเดือนสิ้นสุด'
                              : 'นับรวมทุกเดือนต่อเนื่อง ไม่มีกำหนดสิ้นสุด',
                          style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.v12),
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
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(widget.existing == null ? 'บันทึก' : 'บันทึกการแก้ไข'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
