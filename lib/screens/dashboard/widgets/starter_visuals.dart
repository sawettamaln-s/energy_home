import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/calculator.dart';
import '../../../utils/tariff_tables.dart';
import '../../../utils/thai_date_utils.dart';
import '../../../widgets/ui/app_card.dart';
import '../../../widgets/ui/icon_badge.dart';
import '../dashboard_styles.dart';

// =====================================================================
// ภาพประกอบสำหรับผู้ใช้ใหม่บนหน้าหลัก (แสดงคู่กับเช็คลิสต์ หายไปพร้อมกัน)
// ไม่มีตัวเลขสมมติ — SetupFlowStrip เป็นลำดับขั้นของระบบ (อยู่ในการ์ดเขียว) ส่วน
// TariffFactCard ใช้ตารางอัตราจริง (TariffTables) และค่า Ft งวดปัจจุบัน
// =====================================================================

/// ลำดับการทำงานของแอป 4 ขั้นสำหรับการ์ดเขียวตอนยังไม่มีข้อมูล (ไอคอนขาวบนพื้นเขียว):
/// ใบแจ้งหนี้ → จดมิเตอร์ → คิดเงินตามอัตราจริง → ดูแนวโน้ม
class SetupFlowStrip extends StatelessWidget {
  const SetupFlowStrip({super.key});

  static const _steps = [
    (Icons.receipt_long_outlined, 'ใบแจ้งหนี้'),
    (Icons.speed_rounded, 'จดมิเตอร์'),
    (Icons.calculate_outlined, 'คิดเงิน'),
    (Icons.insights_rounded, 'ดูแนวโน้ม'),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // เส้นเชื่อมระหว่างวงกลม (หลังไอคอน ระดับกึ่งกลางวงกลม)
        Positioned(
          left: 0,
          right: 0,
          top: 19,
          child: LayoutBuilder(
            builder: (context, c) => Padding(
              padding: EdgeInsets.symmetric(horizontal: c.maxWidth / _steps.length / 2),
              child: Container(height: 1.5, color: Colors.white.withValues(alpha: 0.25)),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // วงสุดท้ายสีขาวทึบ = ผลลัพธ์ที่ผู้ใช้จะได้
                        color: i == _steps.length - 1
                            ? Colors.white
                            : Color.alphaBlend(Colors.white.withValues(alpha: 0.16), AppColors.primaryGreen),
                      ),
                      child: Icon(_steps[i].$1,
                          size: 19, color: i == _steps.length - 1 ? AppColors.primaryGreen : Colors.white),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_steps[i].$2,
                          style: const TextStyle(
                              color: Colors.white, fontSize: AppTypography.s11_5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "รู้ไหม" — ราคาต่อหน่วยตามอัตราจริงของผู้ใช้เป็นขั้นบันได (TOU: On-Peak/Off-Peak)
/// พร้อมค่า Ft งวดปัจจุบัน ตัวเลขทั้งหมดมาจาก TariffTables และ app_config ไม่มีค่าสมมติ
class TariffFactCard extends StatefulWidget {
  final String area;
  final String meterType;
  final String tariff;
  // ลิงก์ใต้กราฟไปหน้าตารางอัตราทั้งหมด (มีเครื่องคิดค่าไฟจากหน่วยอยู่บนสุด)
  final VoidCallback onRates;
  // ตัวโหลดค่า Ft (ไม่ส่ง = EnergyCalculator.getFtInfo ตัวเดียวกับที่คิดบิลจริง)
  final Future<FtInfo> Function()? ftLoader;

  const TariffFactCard({
    super.key,
    required this.area,
    required this.meterType,
    required this.tariff,
    required this.onRates,
    this.ftLoader,
  });

  @override
  State<TariffFactCard> createState() => _TariffFactCardState();
}

class _TariffFactCardState extends State<TariffFactCard> {
  FtInfo? _ft;

  @override
  void initState() {
    super.initState();
    (widget.ftLoader ?? EnergyCalculator.getFtInfo)().then((info) {
      if (mounted) setState(() => _ft = info);
    });
  }

  bool get _isTou => widget.meterType == 'tou';

  // แท่งราคา: (ป้ายช่วงหน่วย, บาท/หน่วย)
  List<(String, double)> get _bars {
    if (_isTou) {
      return [('On-Peak', TariffTables.touPeakRate), ('Off-Peak', TariffTables.touOffPeakRate)];
    }
    final tiers = widget.tariff == EnergyCalculator.tariffSmall
        ? TariffTables.electricitySmall
        : TariffTables.electricityStandard;
    final fmt = NumberFormat('#,##0');
    final bars = <(String, double)>[];
    double lower = 0;
    for (final t in tiers) {
      final from = fmt.format(lower + 1);
      bars.add((t.upTo.isInfinite ? '$from+' : '$from–${fmt.format(t.upTo)}', t.rate));
      lower = t.upTo;
    }
    return bars;
  }

  String get _headline {
    if (_isTou) {
      const cheaper = (1 - TariffTables.touOffPeakRate / TariffTables.touPeakRate) * 100;
      return 'ใช้ไฟช่วง Off-Peak ถูกกว่า On-Peak ${cheaper.round()}%';
    }
    final tiers = widget.tariff == EnergyCalculator.tariffSmall
        ? TariffTables.electricitySmall
        : TariffTables.electricityStandard;
    final pricier = (tiers.last.rate / tiers.first.rate - 1) * 100;
    return 'ยิ่งใช้มาก หน่วยหลังๆ ยิ่งแพง ขั้นสุดท้ายแพงกว่าขั้นแรก ${pricier.round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final code = _isTou
        ? EnergyCalculator.touCode(widget.area)
        : EnergyCalculator.tariffCode(widget.tariff, widget.area);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.lightbulb_outline_rounded, color: AppColors.electricityBorder, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('รู้ไหม',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypography.s15)),
                    Text(_headline,
                        style: TextStyle(fontSize: AppTypography.s12, height: 1.4, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _chart(),
          const SizedBox(height: 10),
          Text(
            _isTou
                ? 'บาท/หน่วย อัตรา $code · On-Peak คือ จ.–ศ. 09:00–22:00 น. นอกนั้นรวมวันหยุดเป็น Off-Peak'
                : 'บาท/หน่วย อัตรา $code ตามช่วงหน่วยที่ใช้ในเดือน',
            style: TextStyle(fontSize: AppTypography.s11, height: 1.4, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          _ftRow(),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onRates,
              style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('ดูอัตราทั้งหมด'), Icon(Icons.chevron_right_rounded, size: 18)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart() {
    final bars = _bars;
    final maxRate = bars.map((b) => b.$2).reduce((a, b) => a > b ? a : b);
    final minRate = bars.map((b) => b.$2).reduce((a, b) => a < b ? a : b);
    const maxHeight = 72.0;
    final rateFmt = NumberFormat('0.00');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          if (i > 0) SizedBox(width: bars.length > 4 ? 4 : 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(rateFmt.format(bars[i].$2),
                      style: const TextStyle(
                          fontSize: AppTypography.s11_5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 4),
                Container(
                  height: maxHeight * bars[i].$2 / maxRate,
                  decoration: BoxDecoration(
                    // แท่งไล่เข้มขึ้นตามราคา
                    color: AppColors.electricityBorder.withValues(
                        alpha: maxRate == minRate ? 0.6 : 0.3 + 0.6 * (bars[i].$2 - minRate) / (maxRate - minRate)),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(bars[i].$1,
                      style: TextStyle(fontSize: AppTypography.s10_5, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _ftRow() {
    final ft = _ft;
    final String text;
    if (ft == null) {
      text = 'กำลังโหลดค่า Ft งวดนี้…';
    } else {
      final from = ft.effectiveFrom;
      final period = from == null ? '' : ' (เริ่ม ${from.day} ${thaiMonthsShort[from.month - 1]} ${(from.year + 543) % 100})';
      text = 'บวกค่า Ft งวดนี้ ${NumberFormat('0.##').format(ft.rate * 100)} สตางค์/หน่วย$period และ VAT 7%';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Text(text, style: const TextStyle(fontSize: AppTypography.s12, color: AppColors.textDark)),
    );
  }
}
