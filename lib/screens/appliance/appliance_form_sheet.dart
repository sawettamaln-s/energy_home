part of 'appliance_screen.dart';

// ==================== Bottom Sheet เพิ่ม/แก้ไขอุปกรณ์ ====================
// 2 ขั้น: (1) เลือกชนิดจากรายการสามัญประจำบ้าน (เติมชื่อ/กำลังไฟให้) หรือกรอกเอง
// (2) ฟอร์มรายละเอียด ชื่อ กำลังไฟ เวลาใช้งานต่อวัน วันที่ใช้ พร้อมค่าไฟประมาณการ
// สด แก้ไขอุปกรณ์เดิมเข้าขั้นที่ 2 ตรง
//
// ตรวจค่าก่อนบันทึก: กำลังไฟต้องเป็นตัวเลขมากกว่า 0, เวลารวมต้องมากกว่า 0 และไม่
// เกิน 24 ชม. (นาทีไม่เกิน 59), เลือกวันอย่างน้อย 1 วัน — ข้อความผิดขึ้นใต้ช่อง
// นั้นๆ หลังกดบันทึกครั้งแรก แล้วอัปเดตตามที่พิมพ์แก้ กำลังไฟนอกช่วงทั่วไปของ
// อุปกรณ์ชนิดนั้นแค่เตือน ไม่บล็อก
class _AddApplianceSheet extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;
  final ApplianceModel? existing;
  final ApplianceRate rate;

  const _AddApplianceSheet({
    required this.uid,
    required this.firestoreService,
    required this.rate,
    this.existing,
  });

  @override
  State<_AddApplianceSheet> createState() => _AddApplianceSheetState();
}

// ปุ่มลัดเวลาใช้งานต่อวัน (ชั่วโมง, นาที)
const _timePresets = <(String, int, int)>[
  ('15 นาที', 0, 15),
  ('30 นาที', 0, 30),
  ('1 ชม.', 1, 0),
  ('2 ชม.', 2, 0),
  ('4 ชม.', 4, 0),
  ('8 ชม.', 8, 0),
  ('24 ชม.', 24, 0),
];

// ปุ่มลัดวันที่ใช้งาน (0 = จันทร์ ... 6 = อาทิตย์)
const _dayPresets = <(String, Set<int>)>[
  ('ทุกวัน', {0, 1, 2, 3, 4, 5, 6}),
  ('จ–ศ', {0, 1, 2, 3, 4}),
  ('ส–อา', {5, 6}),
];

class _AddApplianceSheetState extends State<_AddApplianceSheet> {
  final _nameController = TextEditingController();
  final _wattController = TextEditingController();
  final _hoursController = TextEditingController(text: '1');
  final _minutesController = TextEditingController(text: '0');
  Set<int> _selectedDays = {0, 1, 2, 3, 4, 5, 6}; // ทุกวันเป็นค่าเริ่มต้น
  bool _showForm = false;
  bool _isSaving = false;
  String? _iconKey; // ไอคอนที่จะบันทึกกับอุปกรณ์ (null = อุปกรณ์ที่เพิ่มเอง)
  // ชนิดที่เลือกจากรายการสามัญ — ใช้บอกช่วงกำลังไฟทั่วไป (null = กรอกเอง)
  DefaultAppliance? _selectedDefault;

  // กดบันทึกไปแล้วอย่างน้อยครั้งหนึ่ง — หลังจากนั้นข้อความผิดอัปเดตตามที่พิมพ์
  bool _submitted = false;
  String? _nameError;
  String? _wattError;
  String? _timeError;
  String? _daysError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _showForm = true;
      _nameController.text = existing.name;
      _selectedDefault = DefaultAppliances.byName(existing.name);
      _iconKey = existing.iconKey ?? _selectedDefault?.icon;
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
      _selectedDefault = d;
      _showForm = true;
    });
  }

  void _selectCustom() {
    setState(() {
      _nameController.clear();
      _wattController.clear();
      _iconKey = null;
      _selectedDefault = null;
      _showForm = true;
    });
  }

  void _backToPicker() {
    setState(() {
      _showForm = false;
      _submitted = false;
      _nameError = _wattError = _timeError = _daysError = null;
    });
  }

  // ---- ค่าที่กรอก --------------------------------------------------------

  double? get _watt => double.tryParse(_wattController.text.replaceAll(',', '').trim());

  // ช่องว่าง = 0, พิมพ์ไม่ใช่ตัวเลข = null
  double? _numberOrZero(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text);
  }

  double get _totalHours {
    final h = _numberOrZero(_hoursController) ?? 0;
    final m = _numberOrZero(_minutesController) ?? 0;
    return h + (m / 60);
  }

  // ---- ตรวจค่า -----------------------------------------------------------

  bool _validate() {
    final watt = _watt;
    final h = _numberOrZero(_hoursController);
    final m = _numberOrZero(_minutesController);
    String? timeError;
    if (h == null || m == null || h < 0 || m < 0) {
      timeError = 'กรุณากรอกเวลาเป็นตัวเลขค่ะ';
    } else if (m >= 60) {
      timeError = 'นาทีต้องไม่เกิน 59 ค่ะ';
    } else if (h + m / 60 <= 0) {
      timeError = 'กรุณาระบุเวลาที่ใช้ต่อวันค่ะ';
    } else if (h + m / 60 > 24) {
      timeError = 'ใช้งานได้ไม่เกิน 24 ชั่วโมงต่อวันค่ะ';
    }
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'กรุณาตั้งชื่ออุปกรณ์ค่ะ' : null;
      _wattError = watt == null || watt <= 0 ? 'กรุณากรอกกำลังไฟเป็นตัวเลขที่มากกว่า 0 ค่ะ' : null;
      _timeError = timeError;
      _daysError = _selectedDays.isEmpty ? 'กรุณาเลือกวันที่ใช้งานอย่างน้อย 1 วันค่ะ' : null;
    });
    return _nameError == null && _wattError == null && _timeError == null && _daysError == null;
  }

  // เรียกทุกครั้งที่ค่าในฟอร์มเปลี่ยน — อัปเดตการ์ดประมาณการ และข้อความผิด
  // (เฉพาะหลังกดบันทึกครั้งแรก ก่อนหน้านั้นไม่ขึ้นแดงระหว่างที่ยังพิมพ์ไม่เสร็จ)
  void _onChanged() {
    if (_submitted) {
      _validate();
    } else {
      setState(() {});
    }
  }

  // คำเตือน (ไม่บล็อก) เมื่อกำลังไฟอยู่นอกช่วงทั่วไปของชนิดที่เลือก
  String? get _wattWarning {
    final d = _selectedDefault;
    final watt = _watt;
    if (d == null || watt == null || watt <= 0 || _wattError != null) return null;
    final range = '${_wattFmt.format(d.minWatt)}–${_wattFmt.format(d.maxWatt)} วัตต์';
    if (watt > d.maxWatt) return 'สูงกว่าช่วงทั่วไป ($range) ลองตรวจตัวเลขบนฉลากอีกครั้งนะคะ';
    if (watt < d.minWatt) return 'ต่ำกว่าช่วงทั่วไป ($range) ลองตรวจตัวเลขบนฉลากอีกครั้งนะคะ';
    return null;
  }

  Future<void> _save() async {
    _submitted = true;
    if (!_validate()) return;

    setState(() => _isSaving = true);
    try {
      final appliance = ApplianceModel(
        id: widget.existing?.id ?? const Uuid().v4(),
        uid: widget.uid,
        name: _nameController.text.trim(),
        watt: _watt!,
        iconKey: _iconKey,
        schedules: [
          ScheduleModel(
            days: _selectedDays.toList()..sort(),
            startTime: '00:00',
            endTime: _hoursToTimeString(_totalHours),
          ),
        ],
      );

      await widget.firestoreService.saveAppliance(appliance);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่อีกครั้งค่ะ')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _hoursToTimeString(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // =====================================================================
  // Layout
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    // ชีตหดตามคีย์บอร์ด ปุ่มบันทึกด้านล่างจึงอยู่เหนือคีย์บอร์ดเสมอ
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.9 - bottomInset;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: height < 320 ? 320 : height,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.v10),
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v8, AppSpacing.v6, AppSpacing.v8, 0),
              child: Row(
                children: [
                  if (_showForm && !_isEditing)
                    IconButton(
                      tooltip: 'เลือกชนิดใหม่',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: _backToPicker,
                    )
                  else
                    const SizedBox(width: AppSpacing.v12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'แก้ไขเครื่องใช้ไฟฟ้า' : 'เพิ่มเครื่องใช้ไฟฟ้า',
                      style: const TextStyle(
                          fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    ),
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
                padding: const EdgeInsets.fromLTRB(AppSpacing.v16, AppSpacing.v8, AppSpacing.v16, AppSpacing.v24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _showForm
                      ? KeyedSubtree(key: const ValueKey('form'), child: _buildForm())
                      : KeyedSubtree(key: const ValueKey('picker'), child: _buildPicker()),
                ),
              ),
            ),
            if (_showForm)
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
                        : Text(_isEditing ? 'บันทึกการแก้ไข' : 'บันทึก'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- ขั้นที่ 1: เลือกชนิด ------------------------------------------------

  Widget _buildPicker() {
    final tiles = <Widget>[
      for (final d in DefaultAppliances.list)
        _pickerTile(
          icon: _defaultApplianceIcon(d.icon),
          title: d.name,
          subtitle: '${_wattFmt.format(d.minWatt)}–${_wattFmt.format(d.maxWatt)} วัตต์',
          onTap: () => _selectDefault(d),
        ),
      _pickerTile(
        icon: Icons.add_rounded,
        title: 'อุปกรณ์อื่น',
        subtitle: 'กรอกชื่อและกำลังไฟเอง',
        onTap: _selectCustom,
        outlined: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('เลือกชนิดเครื่องใช้ไฟฟ้า ระบบจะเติมกำลังไฟทั่วไปให้ แล้วปรับเองได้ในขั้นถัดไปค่ะ',
            style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600)),
        const SizedBox(height: AppSpacing.v14),
        // ตาราง 2 คอลัมน์ — แต่ละแถวสูงเท่ากับช่องที่สูงที่สุดในแถว (ชื่อยาว 2 บรรทัด)
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.v10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: AppSpacing.v10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return Material(
      color: outlined ? Colors.white : DashboardStyles.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: outlined ? BorderSide(color: AppColors.primaryGreen.withValues(alpha: 0.35)) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.v12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: icon,
                color: AppColors.primaryGreen,
                size: 40,
                background: outlined ? null : Colors.white,
              ),
              const SizedBox(height: AppSpacing.v10),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              const SizedBox(height: AppSpacing.v2),
              Text(subtitle, style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  // ---- ขั้นที่ 2: ฟอร์ม ----------------------------------------------------

  Widget _buildForm() {
    final d = _selectedDefault;
    final warning = _wattWarning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ชนิดที่เลือก
        Row(
          children: [
            IconBadge(icon: _defaultApplianceIcon(_iconKey ?? ''), color: AppColors.primaryGreen, size: 48),
            const SizedBox(width: AppSpacing.v12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d?.name ?? (_isEditing ? 'อุปกรณ์ที่เพิ่มเอง' : 'อุปกรณ์อื่น'),
                      style: const TextStyle(
                          fontSize: AppTypography.s15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  Text(
                    d != null
                        ? 'กำลังไฟทั่วไป ${_wattFmt.format(d.minWatt)}–${_wattFmt.format(d.maxWatt)} วัตต์'
                        : 'กรอกชื่อและกำลังไฟตามฉลากของเครื่อง',
                    style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.v20),

        _label('ชื่ออุปกรณ์'),
        TextField(
          controller: _nameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _onChanged(),
          decoration: InputDecoration(
            hintText: 'เช่น แอร์ห้องนอน',
            helperText: 'ตั้งชื่อให้แยกออกจากเครื่องอื่นได้ เช่น ระบุห้อง',
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: AppSpacing.v16),

        _label('กำลังไฟ'),
        TextField(
          controller: _wattController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _onChanged(),
          decoration: InputDecoration(
            hintText: d != null ? 'เช่น ${_wattFmt.format(d.defaultWatt)}' : 'เช่น 1200',
            suffixText: 'วัตต์',
            helperText: 'ดูได้จากฉลากหรือสติกเกอร์ข้างเครื่อง (หน่วย W)',
            helperMaxLines: 2,
            errorText: _wattError,
            errorMaxLines: 2,
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: AppSpacing.v8),
          _note(warning, icon: Icons.warning_amber_rounded, color: AppColors.warningText),
        ],
        const SizedBox(height: AppSpacing.v20),

        _label('ใช้งานวันละ'),
        Wrap(
          spacing: AppSpacing.v8,
          runSpacing: AppSpacing.v8,
          children: [
            for (final (label, h, m) in _timePresets)
              _choiceChip(
                label: label,
                selected: _numberOrZero(_hoursController) == h && _numberOrZero(_minutesController) == m,
                onTap: () {
                  _hoursController.text = '$h';
                  _minutesController.text = '$m';
                  _onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.v10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _hoursController,
                keyboardType: TextInputType.number,
                onChanged: (_) => _onChanged(),
                decoration: InputDecoration(
                  suffixText: 'ชม.',
                  errorText: _timeError == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.v10),
            Expanded(
              child: TextField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                onChanged: (_) => _onChanged(),
                decoration: InputDecoration(
                  suffixText: 'นาที',
                  errorText: _timeError == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
          ],
        ),
        if (_timeError != null) ...[
          const SizedBox(height: AppSpacing.v6),
          _errorText(_timeError!),
        ],
        // ตู้เย็น/แอร์ คอมเพรสเซอร์ตัดเข้า-ออกเป็นรอบ ถ้ากรอกชั่วโมงที่เปิดเครื่อง
        // ค่าไฟจะสูงกว่าจริง จึงแนะนำให้กรอกชั่วโมงที่เครื่องทำงานจริง
        if (_compressorHint case final hint?) ...[
          const SizedBox(height: AppSpacing.v8),
          _note(hint, icon: Icons.lightbulb_outline_rounded, color: Colors.grey.shade700),
        ],
        const SizedBox(height: AppSpacing.v20),

        _label('วันที่ใช้งาน'),
        Wrap(
          spacing: AppSpacing.v8,
          runSpacing: AppSpacing.v8,
          children: [
            for (final (label, days) in _dayPresets)
              _choiceChip(
                label: label,
                selected: _selectedDays.length == days.length && _selectedDays.containsAll(days),
                onTap: () {
                  _selectedDays = {...days};
                  _onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.v12),
        _buildDaySelector(),
        if (_daysError != null) ...[
          const SizedBox(height: AppSpacing.v6),
          _errorText(_daysError!),
        ],
        const SizedBox(height: AppSpacing.v20),

        _buildEstimateCard(),
      ],
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.v8),
      child: Text(text,
          style: const TextStyle(fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
    );
  }

  Widget _errorText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.v12),
      child: Text(text, style: TextStyle(fontSize: AppTypography.s12, color: Theme.of(context).colorScheme.error)),
    );
  }

  String? get _compressorHint => switch (_iconKey) {
        'kitchen' => 'ตู้เย็นเสียบปลั๊กทั้งวัน แต่คอมเพรสเซอร์ทำงานเป็นช่วงๆ '
            'ถ้าอยากได้ค่าใกล้เคียงจริง กรอกราว 8–12 ชม. แทน 24 ชม. ค่ะ',
        'ac_unit' => 'แอร์จะหยุดคอมเพรสเซอร์เป็นช่วงเมื่อห้องเย็นพอ '
            'ค่าไฟจากชั่วโมงที่เปิดจึงเป็นค่าสูงสุด ค่าจริงมักต่ำกว่านี้ค่ะ',
        _ => null,
      };

  Widget _note(String text, {required IconData icon, required Color color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: AppSpacing.v6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: color)),
        ),
      ],
    );
  }

  Widget _choiceChip({required String label, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? AppColors.primaryGreen : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.primaryGreen : Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v14, vertical: AppSpacing.v7),
          child: Text(label,
              style: TextStyle(
                fontSize: AppTypography.s12_5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.textDark,
              )),
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final selected = _selectedDays.contains(index);
        return Flexible(
          child: GestureDetector(
            onTap: () {
              if (selected) {
                _selectedDays.remove(index);
              } else {
                _selectedDays.add(index);
              }
              _onChanged();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primaryGreen : Colors.white,
                border: Border.all(color: selected ? AppColors.primaryGreen : Colors.grey.shade300),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  thaiWeekdaysShort[index],
                  style: TextStyle(
                    fontSize: AppTypography.s12_5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ---- ประมาณการค่าไฟสด ---------------------------------------------------

  Widget _buildEstimateCard() {
    final watt = _watt ?? 0;
    final hours = _totalHours;
    final ready = watt > 0 && hours > 0 && hours <= 24 && _selectedDays.isNotEmpty;
    final activeDaysPerWeek = _selectedDays.length;

    final kWhPerDay = ApplianceEnergy.kWhPerDay(watt, hours);
    // อัตราเดียวกับหน้ารายการ (ดู ApplianceRate)
    final costPerDay = kWhPerDay * widget.rate.perUnit;
    final costPerMonth = costPerDay * (activeDaysPerWeek / 7) * 30;
    final costPerYear = costPerDay * (activeDaysPerWeek / 7) * 365;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v16),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: AppSpacing.v6),
              const Expanded(
                child: Text('ค่าไฟโดยประมาณ',
                    style: TextStyle(
                        fontSize: AppTypography.s13_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
              InkWell(
                onTap: () => showApplianceEstimateInfoDialog(context, rate: widget.rate),
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.v4),
                  child: Icon(Icons.info_outline, size: 18, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.v8),
          if (!ready)
            Text('กรอกกำลังไฟ เวลาใช้งาน และวันที่ใช้ เพื่อดูค่าไฟโดยประมาณค่ะ',
                style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600))
          else ...[
            Text('${_bahtFmt.format(costPerMonth)} บาท/เดือน',
                style: const TextStyle(
                    fontSize: AppTypography.s24, fontWeight: FontWeight.w700, color: AppColors.primaryGreen)),
            const SizedBox(height: AppSpacing.v4),
            Text(
              '${_wattFmt.format(watt)} วัตต์ × ${_durationLabel(hours)} ÷ 1,000 = '
              '${kWhPerDay.toStringAsFixed(2)} หน่วยต่อวันที่ใช้ · ${_daysLabel(_selectedDays)}',
              style: TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade700),
            ),
            const SizedBox(height: AppSpacing.v10),
            Row(
              children: [
                Expanded(child: _estimateStat('ต่อวันที่ใช้', '${_bahtFmt.format(costPerDay)} บาท')),
                Expanded(child: _estimateStat('ต่อปี', '${_bahtFmt.format(costPerYear)} บาท')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _estimateStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
        Text(value,
            style: const TextStyle(
                fontSize: AppTypography.s14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
      ],
    );
  }
}
