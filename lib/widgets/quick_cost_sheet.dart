import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/dashboard/dashboard_styles.dart';
import '../utils/calculator.dart';
import '../utils/tariff_tables.dart';
import 'info_dialog.dart';
import 'ui/segmented_switch.dart';
import 'start_meter_fields.dart' show parseNumInput;

/// ===========================================================
/// ลองคิดค่าไฟ/ค่าน้ำ (bottom sheet)
/// ===========================================================
/// ใช้ได้ตั้งแต่วันแรกที่ยังไม่มีข้อมูลบิล — พิมพ์หน่วยแล้วเห็นยอดเงินแยกส่วนแบบในใบแจ้งหนี้
/// (ค่าพลังงาน, Ft, ค่าบริการ, VAT) หรือพิมพ์ยอดเงินแล้วเห็นว่าใช้ได้ประมาณกี่หน่วย
/// ด้วยสูตรเดียวกับที่แอปคิดบิลจริง (TariffTables)
/// เริ่มจากเขต ประเภทมิเตอร์ และประเภทอัตราของผู้ใช้ และเปลี่ยนได้ในชีตเพื่อคิดให้บ้านอื่น
/// (ค่าที่เปลี่ยนใช้แค่ในชีตนี้) ไม่บันทึกอะไรลงฐานข้อมูล
Future<void> showQuickCostSheet(
  BuildContext context, {
  required String area,
  required String meterType,
  required String tariff,
  Future<FtInfo> Function()? ftLoader,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuickCostSheet(area: area, meterType: meterType, tariff: tariff, ftLoader: ftLoader),
  );
}

class QuickCostSheet extends StatefulWidget {
  // ค่าเริ่มต้นของตัวเลือกในชีต (ของบ้านผู้ใช้)
  final String area; // 'bangkok' (กฟน./กปน.) หรือ 'province' (กฟภ./กปภ.)
  final String meterType; // 'normal' หรือ 'tou'
  final String tariff; // ประเภทอัตราของมิเตอร์ปกติ (UserModel.electricityTariff)
  // ตัวโหลดค่า Ft (ไม่ส่ง = EnergyCalculator.getFtInfo ตัวเดียวกับที่คิดบิลจริง)
  final Future<FtInfo> Function()? ftLoader;

  const QuickCostSheet({
    super.key,
    required this.area,
    required this.meterType,
    required this.tariff,
    this.ftLoader,
  });

  @override
  State<QuickCostSheet> createState() => _QuickCostSheetState();
}

class _QuickCostSheetState extends State<QuickCostSheet> {
  final _unitsCtrl = TextEditingController();
  final _peakCtrl = TextEditingController();
  final _offPeakCtrl = TextEditingController();
  final _bahtCtrl = TextEditingController();
  bool _water = false;
  bool _fromBaht = false; // true = กรอกยอดเงิน หาจำนวนหน่วย
  double? _ftRate; // null = ยังโหลดไม่เสร็จ
  late String _area = widget.area;
  late String _meterType = widget.meterType;
  late String _tariff = widget.tariff;

  bool get _isTou => _meterType == 'tou';
  bool get _bangkok => _area == 'bangkok';
  bool get _isOwnHome => _area == widget.area && _meterType == widget.meterType && _tariff == widget.tariff;

  @override
  void initState() {
    super.initState();
    (widget.ftLoader ?? EnergyCalculator.getFtInfo)().then((info) {
      if (mounted) setState(() => _ftRate = info.rate);
    });
  }

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _peakCtrl.dispose();
    _offPeakCtrl.dispose();
    _bahtCtrl.dispose();
    super.dispose();
  }

  // สูตรยอดแยกส่วนตามจำนวนหน่วยของน้ำ/ไฟมิเตอร์ปกติ — null = ยังไม่รู้ค่า Ft
  CostBreakdown Function(double units)? get _partsOf {
    if (_water) return _bangkok ? TariffTables.waterMwaParts : TariffTables.waterPwaParts;
    final ft = _ftRate;
    if (ft == null) return null;
    final small = _tariff == EnergyCalculator.tariffSmall;
    return (units) => TariffTables.electricityParts(units, ftRate: ft, small: small);
  }

  // ยอดแยกส่วนของหน่วยที่กรอก — null = ยังไม่ได้กรอก หรือยังไม่รู้ค่า Ft
  CostBreakdown? get _result {
    if (!_water && _isTou) {
      final ft = _ftRate;
      if (ft == null) return null;
      final peak = parseNumInput(_peakCtrl.text);
      final offPeak = parseNumInput(_offPeakCtrl.text);
      if (peak <= 0 && offPeak <= 0) return null;
      return TariffTables.electricityTouParts(peak, offPeak, ftRate: ft);
    }
    final partsOf = _partsOf;
    final units = parseNumInput(_unitsCtrl.text);
    if (partsOf == null || units <= 0) return null;
    return partsOf(units);
  }

  String get _unitName => _water ? 'ลบ.ม.' : 'หน่วย';

  Color get _accent => _water ? AppColors.waterBorder : AppColors.electricityBorder;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v10, AppSpacing.v20, AppSpacing.v24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(AppSpacing.v2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.v14),
            Row(
              children: [
                const Expanded(
                  child: Text('ลองคิดค่าไฟ/ค่าน้ำ',
                      style: TextStyle(
                          fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                ),
                IconButton(
                  tooltip: 'เครื่องคิดนี้ทำงานอย่างไร',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
                  onPressed: () => _showInfo(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.v2),
            Text('ใช้อัตราจริงชุดเดียวกับที่แอปคิดบิล ไม่บันทึกข้อมูลใดๆ ค่ะ',
                style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
            const SizedBox(height: AppSpacing.v16),
            _utilitySwitch(),
            const SizedBox(height: AppSpacing.v10),
            _rateCard(),
            const SizedBox(height: AppSpacing.v16),
            _inputHeader(),
            const SizedBox(height: AppSpacing.v8),
            if (_fromBaht)
              _field(_bahtCtrl, 'ยอดเงิน', 'บาท')
            else if (!_water && _isTou)
              Row(
                children: [
                  Expanded(child: _field(_peakCtrl, 'On-Peak', 'หน่วย')),
                  const SizedBox(width: AppSpacing.v10),
                  Expanded(child: _field(_offPeakCtrl, 'Off-Peak', 'หน่วย')),
                ],
              )
            else
              _field(_unitsCtrl, _water ? 'จำนวนน้ำที่ใช้' : 'จำนวนไฟที่ใช้', _unitName),
            const SizedBox(height: AppSpacing.v16),
            if (_fromBaht)
              _budgetResult()
            else if (result == null)
              _hint(!_water && _ftRate == null ? 'กำลังโหลดค่า Ft…' : 'พิมพ์จำนวนหน่วยเพื่อดูยอดเงินค่ะ')
            else
              _resultBox(result),
            const SizedBox(height: AppSpacing.v12),
            Text(_footnote(),
                style: TextStyle(fontSize: AppTypography.s11_5, height: 1.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _utilitySwitch() {
    return SegmentedSwitch<bool>(
      options: const [
        SegmentOption(value: false, label: 'ไฟฟ้า', icon: Icons.bolt_rounded, iconColor: AppColors.electricityBorder),
        SegmentOption(value: true, label: 'น้ำ', icon: Icons.water_drop_rounded, iconColor: AppColors.waterBorder),
      ],
      selected: _water,
      onChanged: (v) => setState(() => _water = v),
    );
  }

  // อัตราที่ใช้คิด เป็นแถวแบบหน้าตั้งค่า: ป้ายซ้าย ค่าปัจจุบันขวา กดแถวเพื่อเลือกค่าใหม่
  // (น้ำมีแค่เขต, TOU ไม่มีประเภทอัตรา ≤150/>150)
  Widget _rateCard() {
    final small = _tariff == EnergyCalculator.tariffSmall;
    final rows = <Widget>[
      _settingRow(
        label: 'เขต',
        value: _bangkok
            ? 'กทม.–ปริมณฑล (${_water ? 'กปน.' : 'กฟน.'})'
            : 'ต่างจังหวัด (${_water ? 'กปภ.' : 'กฟภ.'})',
        onTap: () => _pick<String>(
          title: 'เขต',
          selected: _area,
          options: [
            ('bangkok', 'กทม.–ปริมณฑล', 'กรุงเทพฯ นนทบุรี สมุทรปราการ · กฟน. / กปน.'),
            ('province', 'ต่างจังหวัด', 'จังหวัดอื่นทั้งหมด · กฟภ. / กปภ.'),
          ],
          onPicked: (v) => _area = v,
        ),
      ),
      if (!_water)
        _settingRow(
          label: 'มิเตอร์',
          value: _isTou ? 'TOU' : 'ปกติ',
          onTap: () => _pick<String>(
            title: 'ชนิดมิเตอร์',
            selected: _meterType,
            options: [
              ('normal', 'มิเตอร์ปกติ', 'ราคาเดียวทั้งวัน คิดแบบขั้นบันได'),
              ('tou', 'มิเตอร์ TOU', 'ราคาต่างกันช่วง On-Peak / Off-Peak'),
            ],
            onPicked: (v) => _meterType = v,
          ),
        ),
      if (!_water && !_isTou)
        _settingRow(
          label: 'อัตรา',
          value: small ? 'ไม่เกิน 150 หน่วย' : 'เกิน 150 หน่วย',
          onTap: () => _pick<String>(
            title: 'ประเภทอัตรา',
            selected: _tariff,
            options: [
              (
                EnergyCalculator.tariffStandard,
                'เกิน 150 หน่วย',
                'ประเภท ${EnergyCalculator.tariffCode(EnergyCalculator.tariffStandard, _area)} · บ้านส่วนใหญ่'
              ),
              (
                EnergyCalculator.tariffSmall,
                'ไม่เกิน 150 หน่วย',
                'ประเภท ${EnergyCalculator.tariffCode(EnergyCalculator.tariffSmall, _area)} · มิเตอร์ไม่เกิน 5 แอมแปร์'
              ),
            ],
            onPicked: (v) => _tariff = v,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_isOwnHome ? 'คิดตามอัตราของบ้านคุณ' : 'คิดให้บ้านอื่น',
                  style: TextStyle(fontSize: AppTypography.s12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            ),
            if (!_isOwnHome)
              TextButton.icon(
                onPressed: () => setState(() {
                  _area = widget.area;
                  _meterType = widget.meterType;
                  _tariff = widget.tariff;
                }),
                icon: const Icon(Icons.home_outlined, size: 16),
                label: const Text('ใช้ค่าของบ้านคุณ'),
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  textStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 30),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.v6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppColors.inputBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: AppSpacing.v14, color: Colors.grey.shade200),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingRow({required String label, required String value, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.v14, AppSpacing.v12, AppSpacing.v8, AppSpacing.v12),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade700)),
              const SizedBox(width: AppSpacing.v12),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // รายการให้เลือกค่าของแถว (ชื่อ + คำอธิบายสั้น) — ตัวที่ใช้อยู่มีเครื่องหมายถูก
  Future<void> _pick<T>({
    required String title,
    required T selected,
    required List<(T, String, String)> options,
    required void Function(T) onPicked,
  }) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v20, AppSpacing.v16, AppSpacing.v20, AppSpacing.v8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: AppTypography.s16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            ),
            for (final (value, label, detail) in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.v20),
                title: Text(label,
                    style: TextStyle(
                        fontSize: AppTypography.s14,
                        fontWeight: value == selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textDark)),
                subtitle: Text(detail, style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
                trailing: value == selected ? Icon(Icons.check_rounded, color: _accent) : null,
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: AppSpacing.v8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => onPicked(picked));
  }

  // หัวช่องกรอก: บอกว่ากำลังกรอกอะไร + ปุ่มสลับทิศ (หน่วย -> บาท / บาท -> หน่วย)
  Widget _inputHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(_fromBaht ? 'กรอกยอดเงิน' : 'กรอกจำนวน$_unitName',
              style: const TextStyle(fontSize: AppTypography.s13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _fromBaht = !_fromBaht),
          icon: const Icon(Icons.swap_vert_rounded, size: 18),
          label: Text(_fromBaht ? 'คิดจากหน่วย' : 'คิดจากยอดเงิน'),
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            textStyle: const TextStyle(
                fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _hint(String text) => Text(text,
      textAlign: TextAlign.center, style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600));

  // โหมดกรอกยอดเงิน: หน่วยเต็มที่มากที่สุดที่ยอดไม่เกินที่กรอก
  // TOU ราคาต่อหน่วยขึ้นกับช่วงเวลา จึงบอกเป็นช่วง ตั้งแต่ใช้ On-Peak ทั้งหมดถึง Off-Peak ทั้งหมด
  Widget _budgetResult() {
    if (!_water && _ftRate == null) return _hint('กำลังโหลดค่า Ft…');
    final baht = parseNumInput(_bahtCtrl.text);
    if (baht <= 0) return _hint('พิมพ์ยอดเงินเพื่อดูว่าใช้ได้ประมาณกี่$_unitNameค่ะ');
    final count = NumberFormat('#,##0');
    final money = NumberFormat('#,##0.00');

    if (!_water && _isTou) {
      final ft = _ftRate!;
      double touCost(double peak, double offPeak) => TariffTables.electricityTouParts(peak, offPeak, ftRate: ft).total;
      final peakOnly = TariffTables.unitsForBudget(baht, (u) => touCost(u, 0));
      final offPeakOnly = TariffTables.unitsForBudget(baht, (u) => touCost(0, u));
      if (peakOnly == null || offPeakOnly == null) return _belowMinimum(touCost(0, 0));
      return _box(
        label: 'ใช้ได้ประมาณ',
        headline: '${count.format(peakOnly)}–${count.format(offPeakOnly)} หน่วย',
        lines: [
          Text('ขึ้นกับว่าใช้ไฟช่วง On-Peak มากแค่ไหนค่ะ',
              style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
          _line('ถ้าใช้ช่วง On-Peak ทั้งหมด', '${count.format(peakOnly)} หน่วย'),
          _line('ถ้าใช้ช่วง Off-Peak ทั้งหมด', '${count.format(offPeakOnly)} หน่วย'),
        ],
      );
    }

    // มิเตอร์นับเป็นหน่วยเต็ม ยอดจึงตรงกับที่กรอกพอดีได้ยาก — บอกยอดของหน่วยที่ได้ (ไม่เกิน)
    // คู่กับยอดของหน่วยถัดไป (เกิน) ให้เห็นว่ายอดที่กรอกอยู่ระหว่างสองยอดนี้
    final partsOf = _partsOf!;
    final units = TariffTables.unitsForBudget(baht, (u) => partsOf(u).total);
    if (units == null) return _belowMinimum(partsOf(0).total);
    final r = partsOf(units.toDouble());
    final exact = money.format(r.total) == money.format(baht);
    final small = TextStyle(fontSize: AppTypography.s12, height: 1.45, color: Colors.grey.shade600);
    return _box(
      label: 'ใช้ได้ประมาณ',
      headline: '${count.format(units)} $_unitName',
      lines: [
        _line('${count.format(units)} $_unitName (ไม่เกินยอดที่กรอก)', '${money.format(r.total)} บาท'),
        if (!exact) ...[
          _line('${count.format(units + 1)} $_unitName (เกินยอดที่กรอก)',
              '${money.format(partsOf(units + 1.0).total)} บาท'),
          const SizedBox(height: AppSpacing.v4),
          Text('มิเตอร์นับเป็นหน่วยเต็ม ยอดจึงไม่ตรงกับที่กรอกพอดี แต่อยู่ระหว่างสองยอดนี้ค่ะ', style: small),
        ],
        const SizedBox(height: AppSpacing.v10),
        Text('ยอดแยกส่วนของ ${count.format(units)} $_unitName',
            style: const TextStyle(
                fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        ..._breakdownLines(r),
      ],
    );
  }

  // ยอดที่กรอกยังไม่ถึงค่าบริการรายเดือน + VAT ซึ่งต้องจ่ายแม้ใช้ 0 หน่วย
  Widget _belowMinimum(double minimum) => _hint(
      'ยอดนี้น้อยกว่าค่าบริการรายเดือนรวม VAT (${NumberFormat('#,##0.00').format(minimum)} บาท) '
      'ซึ่งต้องจ่ายแม้ไม่ได้ใช้เลยค่ะ');

  Widget _resultBox(CostBreakdown r) {
    return _box(
      label: _water ? 'ค่าน้ำประมาณ' : 'ค่าไฟประมาณ',
      headline: '${NumberFormat('#,##0.00').format(r.total)} บาท',
      lines: _breakdownLines(r),
    );
  }

  List<Widget> _breakdownLines(CostBreakdown r) {
    final money = NumberFormat('#,##0.00');
    String baht(double v) => '${money.format(v)} บาท';
    return [
      _line(_water ? 'ค่าน้ำตามขั้นบันได' : 'ค่าพลังงานไฟฟ้า', baht(r.energy)),
      if (!_water) _line('ค่า Ft', baht(r.ft)),
      _line('ค่าบริการรายเดือน', baht(r.service)),
      if (r.rawWater > 0) _line('ค่าน้ำดิบ', baht(r.rawWater)),
      _line('ภาษีมูลค่าเพิ่ม 7%', baht(r.vat)),
    ];
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.v4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700))),
            Text(value,
                style: const TextStyle(
                    fontSize: AppTypography.s12_5,
                    color: AppColors.textDark,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );

  Widget _box({required String label, required String headline, required List<Widget> lines}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.v14),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
          Text(headline,
              style: TextStyle(
                  fontSize: AppTypography.s24,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: AppSpacing.v6),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.v4),
          ...lines,
        ],
      ),
    );
  }

  // ปุ่ม ⓘ: อธิบายว่าเครื่องคิดทำอะไร คิดได้สองทาง คิดให้บ้านอื่น และทำไมยอดไม่ตรงพอดี
  void _showInfo(BuildContext context) {
    const body = TextStyle(fontSize: AppTypography.s13, height: 1.55, color: AppColors.textMuted);
    Widget section(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.primaryGreen),
                  const SizedBox(width: AppSpacing.v6),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: AppTypography.s13_5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.v2),
              Text(text, style: body),
            ],
          ),
        );

    showInfoDialog(
      context,
      title: 'เครื่องคิดนี้ทำงานอย่างไร?',
      contentBuilder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'ลองคิดค่าไฟ/ค่าน้ำด้วยอัตราจริงชุดเดียวกับที่แอปใช้คิดบิล ใช้คิดเล่นหรือคิดให้คนอื่นได้ '
              'ไม่บันทึกอะไรลงบัญชีค่ะ',
              style: body),
          section(Icons.swap_vert_rounded, 'คิดได้สองทาง',
              'กรอกจำนวนหน่วย ดูยอดเงินแยกส่วนแบบในใบแจ้งหนี้ หรือกด "คิดจากยอดเงิน" '
              'กรอกงบที่มี ดูว่าใช้ได้ประมาณกี่หน่วย'),
          section(Icons.tune_rounded, 'คิดให้บ้านอื่น',
              'กดแถวเขต มิเตอร์ หรืออัตรา เพื่อเลือกค่าของบ้านที่จะคิดให้ (กทม.–ปริมณฑล/ต่างจังหวัด ฯลฯ) '
              'ค่าที่เลือกใช้แค่ในหน้านี้ ไม่เปลี่ยนการตั้งค่าของบ้านคุณ'),
          section(Icons.straighten_rounded, 'ทำไมยอดไม่ตรงกับที่กรอกพอดี',
              'มิเตอร์นับเป็นหน่วยเต็มและราคาเป็นขั้นบันได แอปจึงบอกหน่วยเต็มที่มากที่สุดที่ยอดไม่เกินที่กรอก '
              'พร้อมยอดของหน่วยถัดไป เช่น กรอก 200 บาท จะเห็นยอดที่ต่ำกว่า 200 บาทเล็กน้อย '
              'คู่กับยอดของหน่วยถัดไปที่เกิน 200 บาท'),
          section(Icons.schedule_rounded, 'มิเตอร์ TOU',
              'ราคาต่อหน่วยช่วง On-Peak แพงกว่า Off-Peak เมื่อคิดจากยอดเงินจึงบอกเป็นช่วง '
              'ตั้งแต่ใช้ช่วง On-Peak ทั้งหมดถึงใช้ช่วง Off-Peak ทั้งหมด'),
          section(Icons.receipt_long_outlined, 'ยอดขั้นต่ำและความแม่นยำ',
              'ค่าบริการรายเดือนและ VAT ต้องจ่ายแม้ไม่ได้ใช้เลย ค่า Ft เปลี่ยนทุก 4 เดือน '
              'ยอดในหน้านี้เป็นยอดประมาณ อาจต่างจากใบแจ้งหนี้เล็กน้อยจากการปัดเศษค่ะ'),
        ],
      ),
    );
  }

  // อัตราที่ใช้คิด — รหัสประเภทต่างกันตามการไฟฟ้า จึงใช้ tariffCode/touCode เสมอ
  String _footnote() {
    if (_water) {
      return 'อัตราที่อยู่อาศัยของ${_bangkok ? 'การประปานครหลวง' : 'การประปาส่วนภูมิภาค (ตาราง 3)'} '
          'มาตรวัดน้ำ ½ นิ้ว · ยอดประมาณ อาจต่างจากใบแจ้งหนี้เล็กน้อย';
    }
    final code = _isTou ? EnergyCalculator.touCode(_area) : EnergyCalculator.tariffCode(_tariff, _area);
    final ft = _ftRate == null ? '' : ' · ค่า Ft งวดนี้ ${NumberFormat('0.##').format(_ftRate! * 100)} สตางค์/หน่วย';
    return 'อัตราประเภท $code ของ${_bangkok ? 'การไฟฟ้านครหลวง' : 'การไฟฟ้าส่วนภูมิภาค'}$ft · '
        'ยอดประมาณ อาจต่างจากใบแจ้งหนี้เล็กน้อย';
  }
}
