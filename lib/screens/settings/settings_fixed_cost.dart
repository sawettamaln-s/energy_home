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

// ช่องแสดง/เลือกวันที่แบบกดแล้วเปิด date picker — ใช้ทั้งช่องเริ่มและสิ้นสุด
// ในส่วน "ช่วงเวลา" ของ dialog เพิ่ม/แก้ไขรายการ
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback? onTap;
  final bool enabled;

  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: !enabled,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Text(
          date != null ? DateFormat('d MMM yyyy').format(date!) : '—',
          style: TextStyle(
            fontSize: 13,
            color: enabled ? Colors.black87 : Colors.grey.shade500,
          ),
        ),
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
    // ช่วงเวลา: startDate เริ่มนับตั้งแต่เดือนนี้เป็น default, endDate = null
    // หมายถึงต่อเนื่องไม่มีกำหนด (พฤติกรรมเดิมของรายการที่ไม่มีวันสิ้นสุด)
    DateTime startDate = existing?.startDate ?? DateTime.now();
    DateTime? endDate = existing?.endDate;
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
                      child: _DateField(
                        label: 'เริ่ม',
                        date: startDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: 'สิ้นสุด',
                        date: endDate,
                        enabled: hasEndDate,
                        onTap: !hasEndDate
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: endDate ?? startDate,
                                  firstDate: startDate,
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() => endDate = picked);
                                }
                              },
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
      appBar: AppBar(
        title: const Text('รายจ่ายประจำ'),
        backgroundColor: DashboardStyles.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
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
                            final isExpired = item.endDate != null &&
                                item.endDate!.isBefore(DateTime.now());
                            final periodLabel = item.endDate == null
                                ? null
                                : 'ถึง ${DateFormat('d MMM yyyy').format(item.endDate!)}';

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