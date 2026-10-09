import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/dashboard/dashboard_styles.dart';
import '../utils/calculator.dart';
import '../utils/tariff_tables.dart';
import 'info_dialog.dart';
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
  bool _showRateOptions = false; // กางตัวเลือกเขต/มิเตอร์/ประเภทอัตราอยู่
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

  // สวิตช์ไฟฟ้า/น้ำแบบแถบเดียว ฝั่งที่เลือกเป็นพื้นขาวยกขึ้น
  Widget _utilitySwitch() {
    Widget segment(String label, IconData icon, Color color, bool water) {
      final selected = _water == water;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _water = water),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 38,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                boxShadow: selected
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: selected ? color : Colors.grey.shade500),
                  const SizedBox(width: AppSpacing.v4),
                  Text(label,
                      style: TextStyle(
                          fontSize: AppTypography.s13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? AppColors.textDark : Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v3),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm + AppSpacing.v3),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Row(
        children: [
          segment('ไฟฟ้า', Icons.bolt_rounded, AppColors.electricityBorder, false),
          segment('น้ำ', Icons.water_drop_rounded, AppColors.waterBorder, true),
        ],
      ),
    );
  }

  // อัตราที่ใช้คิด สรุปเป็นบรรทัดเดียว กด "เปลี่ยน" จึงกางตัวเลือกเขต/มิเตอร์/ประเภทอัตรา
  // (น้ำใช้แค่เขต, TOU ไม่มีประเภทอัตรา ≤150/>150)
  String get _rateSummary {
    if (_water) return _bangkok ? 'กปน. · กทม.–ปริมณฑล' : 'กปภ. · ต่างจังหวัด';
    final parts = [
      _bangkok ? 'กฟน.' : 'กฟภ.',
      _isTou ? 'มิเตอร์ TOU' : 'มิเตอร์ปกติ',
      if (!_isTou) _tariff == EnergyCalculator.tariffSmall ? 'ไม่เกิน 150 หน่วย' : 'เกิน 150 หน่วย',
    ];
    return parts.join(' · ');
  }

  Widget _rateCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _showRateOptions = !_showRateOptions),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v12, AppSpacing.v10, AppSpacing.v8, AppSpacing.v10),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: AppSpacing.v10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isOwnHome ? 'คิดตามอัตราของบ้านคุณ' : 'คิดให้บ้านอื่น',
                            style: TextStyle(fontSize: AppTypography.s11_5, color: Colors.grey.shade600)),
                        Text(_rateSummary,
                            style: const TextStyle(
                                fontSize: AppTypography.s13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      ],
                    ),
                  ),
                  Text(_showRateOptions ? 'เสร็จ' : 'เปลี่ยน',
                      style: TextStyle(fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600, color: _accent)),
                  Icon(_showRateOptions ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 20, color: _accent),
                ],
              ),
            ),
          ),
          if (_showRateOptions) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.v12, AppSpacing.v10, AppSpacing.v12, AppSpacing.v12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _choiceRow('เขต', [
                    ('bangkok', 'กทม.–ปริมณฑล'),
                    ('province', 'ต่างจังหวัด'),
                  ], _area, (v) => _area = v),
                  if (!_water) ...[
                    const SizedBox(height: AppSpacing.v6),
                    _choiceRow('มิเตอร์', [('normal', 'ปกติ'), ('tou', 'TOU')], _meterType, (v) => _meterType = v),
                    if (!_isTou) ...[
                      const SizedBox(height: AppSpacing.v6),
                      _choiceRow('อัตรา', [
                        (EnergyCalculator.tariffSmall, 'ไม่เกิน 150 หน่วย'),
                        (EnergyCalculator.tariffStandard, 'เกิน 150 หน่วย'),
                      ], _tariff, (v) => _tariff = v),
                    ],
                  ],
                  if (!_isOwnHome) ...[
                    const SizedBox(height: AppSpacing.v6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
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
                              fontFamily: AppTheme.fontFamily,
                              fontSize: AppTypography.s12_5,
                              fontWeight: FontWeight.w600),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
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

  Widget _choiceRow(String label, List<(String, String)> options, String value, void Function(String) onPick) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: TextStyle(fontSize: AppTypography.s12, color: Colors.grey.shade600)),
        ),
        for (final (key, text) in options) ...[
          if (key != options.first.$1) const SizedBox(width: AppSpacing.v6),
          Expanded(child: _choice(text, value == key, () => setState(() => onPick(key)))),
        ],
      ],
    );
  }

  Widget _choice(String text, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? _accent.withValues(alpha: 0.10) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: selected ? _accent.withValues(alpha: 0.55) : AppColors.inputBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v4, vertical: AppSpacing.v4),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppTypography.s12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _accent : Colors.grey.shade700)),
        ),
      ),
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
              'กด "เปลี่ยน" เพื่อเลือกเขต (กทม.–ปริมณฑล/ต่างจังหวัด) ชนิดมิเตอร์ และประเภทอัตรา '
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
