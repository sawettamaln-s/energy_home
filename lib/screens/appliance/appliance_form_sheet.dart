part of 'appliance_screen.dart';

// ==================== Bottom Sheet เพิ่ม/แก้ไขอุปกรณ์ ====================
class _AddApplianceSheet extends StatefulWidget {
  final FirestoreService firestoreService;
  final VoidCallback onAdded;
  final ApplianceModel? existing;
  final ApplianceRate rate;

  const _AddApplianceSheet({
    required this.firestoreService,
    required this.onAdded,
    required this.rate,
    this.existing,
  });

  @override
  State<_AddApplianceSheet> createState() => _AddApplianceSheetState();
}

class _AddApplianceSheetState extends State<_AddApplianceSheet> {
  final _nameController = TextEditingController();
  final _wattController = TextEditingController();
  final _hoursController = TextEditingController(text: '1');
  final _minutesController = TextEditingController(text: '0');
  Set<int> _selectedDays = {0, 1, 2, 3, 4, 5, 6}; // ทุกวันเป็นค่าเริ่มต้น
  bool _isCustom = false;
  bool _isSaving = false;
  String? _iconKey; // ไอคอนที่จะบันทึกกับอุปกรณ์ (null = อุปกรณ์ที่เพิ่มเอง)

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _isCustom = true; // แก้ไข: ข้ามหน้าเลือกรายการสามัญ เข้าฟอร์มตรง
      _nameController.text = existing.name;
      _iconKey = existing.iconKey ?? _defaultIconKeyForName(existing.name);
      _wattController.text = existing.watt.toStringAsFixed(0);
      if (existing.schedules.isNotEmpty) {
        final s = existing.schedules.first;
        final h = s.hoursPerDay.floor();
        final m = ((s.hoursPerDay - h) * 60).round();
        _hoursController.text = h.toString();
        _minutesController.text = m.toString();
        _selectedDays = s.days.toSet();
      } else {
        _selectedDays = {};
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wattController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _selectDefault(DefaultAppliance d) {
    setState(() {
      _nameController.text = d.name;
      _wattController.text = d.defaultWatt.toStringAsFixed(0);
      _iconKey = d.icon;
      _isCustom = true;
    });
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty || _wattController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบค่ะ')),
      );
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกวันที่ใช้งานอย่างน้อย 1 วันค่ะ')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final watt = double.parse(_wattController.text);
      final hours = _totalHours;

      final appliance = ApplianceModel(
        id: widget.existing?.id ?? const Uuid().v4(),
        uid: uid,
        name: _nameController.text,
        watt: watt,
        iconKey: _iconKey,
        schedules: [
          ScheduleModel(
            days: _selectedDays.toList()..sort(),
            startTime: '00:00',
            endTime: _hoursToTimeString(hours),
          ),
        ],
      );

      await widget.firestoreService.saveAppliance(appliance);
      widget.onAdded();

      if (mounted) Navigator.pop(context);
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

  String _hoursToTimeString(double hours) {
    int h = hours.floor();
    int m = ((hours - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  double get _totalHours {
    final h = double.tryParse(_hoursController.text) ?? 0;
    final m = double.tryParse(_minutesController.text) ?? 0;
    return h + (m / 60);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.v20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.v12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(AppSpacing.v2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    _isEditing
                        ? 'แก้ไขเครื่องใช้ไฟฟ้า'
                        : 'เพิ่มเครื่องใช้ไฟฟ้า',
                    style: const TextStyle(
                        fontSize: AppTypography.s18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.v16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isCustom) ...[
                    const Text('เลือกจากรายการสามัญประจำบ้าน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...DefaultAppliances.list.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.v8),
                          child: ListTile(
                            tileColor: Colors.grey.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.v10),
                            ),
                            leading: Icon(_defaultApplianceIcon(d.icon),
                                color: DashboardStyles.primaryGreen),
                            title: Text(d.name,
                                style: const TextStyle(fontSize: AppTypography.s14)),
                            subtitle: Text(
                                '${d.minWatt.toStringAsFixed(0)}-${d.maxWatt.toStringAsFixed(0)} วัตต์',
                                style: const TextStyle(fontSize: AppTypography.s11)),
                            onTap: () => _selectDefault(d),
                          ),
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _isCustom = true;
                        _iconKey = null;
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('เพิ่มเครื่องใช้ไฟฟ้าอื่น'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        if (!_isEditing)
                          IconButton(
                            icon: const Icon(Icons.arrow_back, size: 18),
                            onPressed: () => setState(() => _isCustom = false),
                          ),
                        Text(
                            _isEditing
                                ? 'แก้ไขข้อมูลอุปกรณ์'
                                : 'กรอกข้อมูลอุปกรณ์',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('ชื่ออุปกรณ์',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'เช่น แอร์ห้องนอน',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('กำลังไฟ (วัตต์)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _wattController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'เช่น 1200',
                        suffixText: 'วัตต์',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.v10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('ใช้งานประมาณกี่ชั่วโมง/วัน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hoursController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 8',
                              suffixText: 'ชม.',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.v10),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _minutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'เช่น 30',
                              suffixText: 'นาที',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.v10),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('วันที่ใช้งาน',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _buildDaySelector(),
                    const SizedBox(height: 20),
                    _buildEstimateCard(),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DashboardStyles.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.v20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.v12),
                          ),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(_isEditing ? 'บันทึกการแก้ไข' : 'บันทึก'),
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

  Widget _buildDaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.v14, horizontal: AppSpacing.v8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(AppSpacing.v12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (index) {
          final selected = _selectedDays.contains(index);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedDays.remove(index);
                } else {
                  _selectedDays.add(index);
                }
              });
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? DashboardStyles.primaryGreen : Colors.white,
                border: Border.all(
                  color:
                      selected ? DashboardStyles.primaryGreen : Colors.grey.shade300,
                ),
              ),
              child: Text(
                thaiWeekdaysShort[index],
                style: TextStyle(
                  fontSize: AppTypography.s11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // =====================================================================
  // อธิบายที่มาของตัวเลขประมาณการ อ้างอิงสูตรมาตรฐานที่การไฟฟ้า/เว็บคำนวณ
  // ค่าไฟทั่วไปใช้ (วัตต์ × ชั่วโมง ÷ 1000 = kWh) คูณอัตราเฉลี่ยประมาณการ
  // พร้อมเตือนเคสอุปกรณ์ที่มีคอมเพรสเซอร์ (ตู้เย็น/แอร์) ที่วัตต์บนฉลาก
  // มักเป็นค่าสูงสุด ไม่ใช่ค่าเฉลี่ยที่ใช้จริงตลอดเวลาที่เปิด
  // =====================================================================
  void _showEstimateInfoPopup() {
    showApplianceEstimateInfoDialog(context, rate: widget.rate);
  }

  Widget _buildEstimateCard() {
    double watt = double.tryParse(_wattController.text) ?? 0;
    double hours = _totalHours;
    final activeDaysPerWeek = _selectedDays.isEmpty ? 7 : _selectedDays.length;

    double kWhPerDay = (watt * hours) / 1000;
    // ค่าไฟเฉพาะวันที่ใช้ ด้วยอัตราเดียวกับหน้ารายการ (ดู ApplianceRate)
    double costPerDay = kWhPerDay * widget.rate.perUnit;
    double costPerMonth = costPerDay * (activeDaysPerWeek / 7) * 30;
    double costPerYear = costPerDay * (activeDaysPerWeek / 7) * 365;

    final formatter = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v16),
      decoration: BoxDecoration(
        color: DashboardStyles.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.v12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('ประมาณการค่าไฟ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.s14)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _showEstimateInfoPopup,
                child: Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/วัน', '${formatter.format(costPerDay)} บาท'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/เดือน', '${formatter.format(costPerMonth)} บาท'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _estimateBox(
                    'ค่าไฟ/ปี', '${formatter.format(costPerYear)} บาท'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _estimateBox(
                    'พลังงาน/วัน', '${kWhPerDay.toStringAsFixed(2)} kWh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estimateBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.v8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTypography.s15,
                  color: DashboardStyles.primaryGreen)),
        ],
      ),
    );
  }
}
