import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/dashboard/dashboard_styles.dart';
import '../utils/calculator.dart';
import '../utils/tariff_tables.dart';
import 'start_meter_fields.dart' show parseNumInput;

/// ===========================================================
/// ลองคิดค่าไฟ/ค่าน้ำจากจำนวนหน่วย (bottom sheet)
/// ===========================================================
/// ใช้ได้ตั้งแต่วันแรกที่ยังไม่มีข้อมูลบิล — พิมพ์หน่วยแล้วเห็นยอดเงินแยกส่วนแบบในใบแจ้งหนี้
/// (ค่าพลังงาน, Ft, ค่าบริการ, VAT) ด้วยสูตรเดียวกับที่แอปคิดบิลจริง (TariffTables)
/// ตามพื้นที่ ประเภทมิเตอร์ และประเภทอัตราของผู้ใช้ ไม่บันทึกอะไรลงฐานข้อมูล
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
  bool _water = false;
  double? _ftRate; // null = ยังโหลดไม่เสร็จ

  bool get _isTou => widget.meterType == 'tou';
  bool get _bangkok => widget.area == 'bangkok';

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
    super.dispose();
  }

  // ยอดแยกส่วนของสิ่งที่กรอก — null = ยังไม่ได้กรอก หรือยังไม่รู้ค่า Ft
  CostBreakdown? get _result {
    if (_water) {
      final units = parseNumInput(_unitsCtrl.text);
      if (units <= 0) return null;
      return _bangkok ? TariffTables.waterMwaParts(units) : TariffTables.waterPwaParts(units);
    }
    final ft = _ftRate;
    if (ft == null) return null;
    if (_isTou) {
      final peak = parseNumInput(_peakCtrl.text);
      final offPeak = parseNumInput(_offPeakCtrl.text);
      if (peak <= 0 && offPeak <= 0) return null;
      return TariffTables.electricityTouParts(peak, offPeak, ftRate: ft);
    }
    final units = parseNumInput(_unitsCtrl.text);
    if (units <= 0) return null;
    return TariffTables.electricityParts(units, ftRate: ft, small: widget.tariff == EnergyCalculator.tariffSmall);
  }

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
            const Text('ลองคิดค่าไฟ/ค่าน้ำจากหน่วย',
                style: TextStyle(fontSize: AppTypography.s17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: AppSpacing.v2),
            Text('ใช้อัตราจริงชุดเดียวกับที่แอปคิดบิล ไม่บันทึกข้อมูลใดๆ ค่ะ',
                style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade600)),
            const SizedBox(height: AppSpacing.v14),
            Row(
              children: [
                Expanded(child: _option('ไฟฟ้า', Icons.bolt_rounded, AppColors.electricityBorder, !_water, false)),
                const SizedBox(width: AppSpacing.v8),
                Expanded(child: _option('น้ำ', Icons.water_drop_rounded, AppColors.waterBorder, _water, true)),
              ],
            ),
            const SizedBox(height: AppSpacing.v14),
            if (!_water && _isTou)
              Row(
                children: [
                  Expanded(child: _field(_peakCtrl, 'On-Peak (หน่วย)')),
                  const SizedBox(width: AppSpacing.v10),
                  Expanded(child: _field(_offPeakCtrl, 'Off-Peak (หน่วย)')),
                ],
              )
            else
              _field(_unitsCtrl, _water ? 'จำนวนน้ำที่ใช้ (ลบ.ม.)' : 'จำนวนไฟที่ใช้ (หน่วย)'),
            const SizedBox(height: AppSpacing.v16),
            if (result == null)
              Text(
                !_water && _ftRate == null ? 'กำลังโหลดค่า Ft…' : 'พิมพ์จำนวนหน่วยเพื่อดูยอดเงินค่ะ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.s13, color: Colors.grey.shade600),
              )
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

  Widget _option(String label, IconData icon, Color color, bool selected, bool water) {
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : AppColors.inputFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: selected ? color.withValues(alpha: 0.55) : AppColors.inputBorder, width: selected ? 1.2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _water = water),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? Icons.check_rounded : icon, size: 16, color: selected ? color : color.withValues(alpha: 0.55)),
              const SizedBox(width: AppSpacing.v4),
              Text(label,
                  style: TextStyle(
                      fontSize: AppTypography.s13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? color : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _resultBox(CostBreakdown r) {
    final money = NumberFormat('#,##0.00');
    Widget line(String label, double value) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.v4),
          child: Row(
            children: [
              Expanded(
                  child: Text(label, style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700))),
              Text('${money.format(value)} บาท',
                  style: const TextStyle(
                      fontSize: AppTypography.s12_5,
                      color: AppColors.textDark,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        );

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
          Text(_water ? 'ค่าน้ำประมาณ' : 'ค่าไฟประมาณ',
              style: TextStyle(fontSize: AppTypography.s12_5, color: Colors.grey.shade700)),
          Text('${money.format(r.total)} บาท',
              style: TextStyle(
                  fontSize: AppTypography.s24,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: AppSpacing.v6),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.v4),
          line(_water ? 'ค่าน้ำตามขั้นบันได' : 'ค่าพลังงานไฟฟ้า', r.energy),
          if (!_water) line('ค่า Ft', r.ft),
          line('ค่าบริการรายเดือน', r.service),
          if (r.rawWater > 0) line('ค่าน้ำดิบ', r.rawWater),
          line('ภาษีมูลค่าเพิ่ม 7%', r.vat),
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
    final code = _isTou ? EnergyCalculator.touCode(widget.area) : EnergyCalculator.tariffCode(widget.tariff, widget.area);
    final ft = _ftRate == null ? '' : ' · ค่า Ft งวดนี้ ${NumberFormat('0.##').format(_ftRate! * 100)} สตางค์/หน่วย';
    return 'อัตราประเภท $code ของ${_bangkok ? 'การไฟฟ้านครหลวง' : 'การไฟฟ้าส่วนภูมิภาค'}$ft · '
        'ยอดประมาณ อาจต่างจากใบแจ้งหนี้เล็กน้อย';
  }
}
