part of 'analysis_screen.dart';

// =====================================================================
// กราฟเทรนด์ค่าใช้จ่าย/หน่วยที่ใช้ — ประกอบด้วย
//   1) _TrendChartCard   การ์ดในแท็บวิเคราะห์ โชว์ _cardMonths เดือนล่าสุด
//                        + แท่งประคาดการณ์ 3 เดือนข้างหน้าต่อท้ายในกราฟเดียว
//                        (กด "ดูทั้งหมด" เพื่อเปิดหน้าประวัติ)
//   2) _TrendBars        ตัววาดกราฟแท่ง ใช้ร่วมกันทั้งการ์ดและหน้าประวัติ
//   3) _TrendHistoryPage หน้าประวัติเต็ม เลือกดูรายปี (ดรอปดาวน์ ปีนี้/ปีย้อนหลัง)
//                        มีสรุปรวม/เฉลี่ย กราฟ 12 เดือน และรายการรายเดือน
// =====================================================================

// ไฮไลต์แท่งเดือนสูงสุด/ต่ำสุดด้วยสีต่างจากแท่งปกติ ช่วยให้กวาดตาเจอ
// เดือนผิดปกติได้ทันที เดือนต่ำสุดใช้สีเขียวหลักของแบรนด์ (ใช้น้อย = ดี)
// เดือนสูงสุดใช้ส้มอิฐ
const Color _trendPeakColor = AppColors.trendPeak;
const Color _trendLowColor = DashboardStyles.primaryGreen;

bool _trendHasVariation(List<double> values) {
  if (values.length < 2) return false;
  final maxVal = values.reduce((a, b) => a > b ? a : b);
  final minVal = values.reduce((a, b) => a < b ? a : b);
  return maxVal != minVal;
}

// ป้ายเดือนใต้แท่ง เช่น "ก.ย." — เดือนมกราคมต่อท้ายปี พ.ศ. 2 หลัก ("ม.ค. 69")
// ให้รู้ว่าข้ามปีแล้วโดยไม่ต้องเขียนปีทุกแท่ง
String _trendMonthLabel(int year, int month) {
  final name = thaiMonthsShort[month - 1];
  return month == 1 ? '$name${(year + 543) % 100}' : name;
}

Widget _trendLegendItem(Widget swatch, String label) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: AppSpacing.v4),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppTypography.s11, color: Colors.grey.shade600)),
      ),
    ],
  );
}

Widget _trendDot(Color color) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

// สวิตช์เลือกมุมมอง ค่าใช้จ่าย/หน่วย — ปุ่มสองช่องในกรอบมน ช่องที่เลือกเป็น
// พื้นขาวตัวหนังสือสีประจำยูทิลิตี้
class _ModeToggle extends StatelessWidget {
  final Color accent;
  final String unitLabel;
  final bool showCost;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.accent,
    required this.unitLabel,
    required this.showCost,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool value) {
      final selected = showCost == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.v7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm - 2),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.s12_5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.v3),
      decoration: BoxDecoration(
        color: DashboardStyles.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          option('ค่าใช้จ่าย (บาท)', true),
          option(unitLabel, false),
        ],
      ),
    );
  }
}

// สี่เหลี่ยมสีนำหน้าคำอธิบายกราฟ: ทึบ = เดือนจริง (แท่งทึบ), ประ = คาดการณ์ (แท่งประ)
class _LegendSwatch extends StatelessWidget {
  final Color color;
  final bool dashed;
  const _LegendSwatch({required this.color, required this.dashed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: dashed
          ? CustomPaint(painter: _DashedRRectPainter(color))
          : DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppSpacing.v3),
              ),
            ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  const _DashedRRectPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.7),
      const Radius.circular(AppSpacing.v3),
    );
    // พื้นจางเท่ากับแท่งคาดการณ์ในกราฟ (alpha 0.10) แล้วเส้นประทับบน
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.10));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = d + 2.5 > metric.length ? metric.length : d + 2.5;
        canvas.drawPath(metric.extractPath(d, end), stroke);
        d += 4.5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) => oldDelegate.color != color;
}

// =====================================================================
// การ์ดกราฟเทรนด์ — สลับมุมมองระหว่าง "ค่าใช้จ่าย" กับ "หน่วยที่ใช้" ได้ใน
// การ์ดเดียว ต้องเป็น StatefulWidget แยกจาก _UtilityTab เพราะต้องจำมุมมองที่
// ผู้ใช้เลือกไว้ระหว่างที่ส่วนอื่นของหน้า rebuild
// =====================================================================
class _TrendChartCard extends StatefulWidget {
  final List<BillModel> bills;
  final String title; // 'ค่าไฟฟ้า' / 'ค่าน้ำ'
  final String unitLabel; // 'หน่วย' / 'ลบ.ม.' ใช้เป็น label ปุ่มฝั่งหน่วย
  final double Function(BillModel) costSelector;
  final double Function(BillModel) usedSelector;
  final Color accentColor;
  // สีแท่งกราฟ แยกตามโหมด "ค่าใช้จ่าย" กับ "หน่วย/ลบ.ม."
  final Color costColor;
  final Color unitColor;
  // TOU เท่านั้น — สี Off-Peak ของแท่งซ้อน ถ้าไม่ส่งมาจะใช้เฉดอ่อนของ unitColor
  final Color? touOffPeakColor;
  final bool isTou;
  final double Function(BillModel)? peakUsedSelector;
  final double Function(BillModel)? offPeakUsedSelector;
  // คาดการณ์ล่วงหน้า (ยอดรวมต่อเดือน) ต่อท้ายกราฟเป็นแท่งประ แยกตามโหมด
  // ค่าใช้จ่าย/หน่วย — list ว่าง = ไม่โชว์ส่วนคาดการณ์ (แท่งของรอบที่กำลังใช้
  // อยู่ใช้ยอดคาดการณ์สิ้นรอบ ดู _UtilityTab._withCurrentCycle)
  final List<double> costForecast;
  final List<double> usedForecast;
  // ข้อมูลน้อยกว่า 3 เดือน → ติดป้ายเตือน "ประมาณการเบื้องต้น"
  final bool forecastLowConfidence;
  // true = คาดการณ์ด้วยเส้นฤดูกาล (รู้ area+meterType) ใช้เลือกข้อความอธิบาย
  final bool usesSeasonalCurve;

  const _TrendChartCard({
    required this.bills,
    required this.title,
    required this.unitLabel,
    required this.costSelector,
    required this.usedSelector,
    required this.accentColor,
    required this.costColor,
    required this.unitColor,
    this.touOffPeakColor,
    this.isTou = false,
    this.peakUsedSelector,
    this.offPeakUsedSelector,
    this.costForecast = const [],
    this.usedForecast = const [],
    this.forecastLowConfidence = false,
    this.usesSeasonalCurve = false,
  });

  // ---- ตัวช่วยที่ใช้ร่วมกันระหว่างการ์ดกับหน้าประวัติ -------------------

  double Function(BillModel) selectorFor(bool showCost) => showCost ? costSelector : usedSelector;

  // TOU + มุมมอง "หน่วยที่ใช้" → แท่งซ้อน On-Peak/Off-Peak ฝั่งค่าใช้จ่ายไม่แยก
  // เพราะ electricityCost เก็บเป็นยอดเดียว ไม่มีราคาแยกตามช่วงเวลาให้ซ้อน
  bool showStackedFor(bool showCost) =>
      !showCost && isTou && peakUsedSelector != null && offPeakUsedSelector != null;

  Color get touPeakColor => unitColor;
  Color get touOffPeakColorResolved => touOffPeakColor ?? Color.lerp(unitColor, Colors.white, 0.3)!;

  // คำอธิบายสีแท่ง — แท่งซ้อน TOU โชว์ On-Peak/Off-Peak นอกนั้นโชว์สูงสุด/
  // ต่ำสุด (เฉพาะเมื่อมีความต่างระหว่างเดือนให้ไฮไลต์) [withForecast] เพิ่มคู่
  // จริง/คาดการณ์ไว้หน้าสุด (ใช้ในการ์ด ส่วนหน้าประวัติไม่มีแท่งคาดการณ์)
  List<Widget> legendItems(bool showCost, List<BillModel> bills, {bool withForecast = false}) {
    final accent = showCost ? costColor : unitColor;
    return [
      if (withForecast) ...[
        _trendLegendItem(_LegendSwatch(color: accent, dashed: false), 'จริง'),
        _trendLegendItem(_LegendSwatch(color: accent, dashed: true), 'คาดการณ์'),
      ],
      if (showStackedFor(showCost)) ...[
        _trendLegendItem(_trendDot(touPeakColor), 'On-Peak'),
        _trendLegendItem(_trendDot(touOffPeakColorResolved), 'Off-Peak'),
      ] else if (_trendHasVariation(bills.map(selectorFor(showCost)).toList())) ...[
        _trendLegendItem(_trendDot(_trendPeakColor), 'สูงสุด'),
        _trendLegendItem(_trendDot(_trendLowColor), 'ต่ำสุด'),
      ],
    ];
  }

  Widget buildBars({
    required List<BillModel?> slots,
    required List<String> labels,
    required bool showCost,
    required double barWidth,
    double labelFontSize = 10,
    List<double> forecasts = const [],
    List<String> forecastLabels = const [],
  }) {
    return _TrendBars(
      slots: slots,
      labels: labels,
      forecastValues: forecasts,
      forecastLabels: forecastLabels,
      selector: selectorFor(showCost),
      modeAccent: showCost ? costColor : unitColor,
      showStacked: showStackedFor(showCost),
      peakUsedSelector: peakUsedSelector,
      offPeakUsedSelector: offPeakUsedSelector,
      touPeakColor: touPeakColor,
      touOffPeakColor: touOffPeakColorResolved,
      isCost: showCost,
      unitLabel: unitLabel,
      barWidth: barWidth,
      labelFontSize: labelFontSize,
    );
  }

  @override
  State<_TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<_TrendChartCard> {
  // true = กราฟค่าใช้จ่าย (บาท), false = กราฟหน่วยที่ใช้ — เริ่มที่ค่าใช้จ่าย
  // เพราะมีครบทุกเดือนแน่นอนกว่า (หน่วยอาจเป็น 0 ในเดือนแรกสุดที่ไม่มี
  // record ก่อนหน้าให้คำนวณ delta)
  bool _showCost = true;

  // จำนวนเดือนที่โชว์ในการ์ด — ข้อมูลย้อนหลังหลายปีถ้าโชว์ทั้งหมดในการ์ดแคบๆ
  // แท่งจะเบียดกัน ดูย้อนหลังทั้งหมดได้ที่หน้าประวัติ
  static const int _cardMonths = 6;

  String _emptyMessage(String subject) {
    if (widget.bills.isEmpty) {
      return 'ยังไม่มีข้อมูลบิลของ$subject\nเพิ่มบิลย้อนหลังที่หน้าตั้งค่า เพื่อเริ่มเห็นกราฟค่ะ';
    }
    final needed = 2 - widget.bills.length;
    return 'มีข้อมูลแล้ว ${widget.bills.length} เดือน\nอีก $needed เดือน จะเริ่มเห็นกราฟแนวโน้มค่ะ';
  }

  void _openHistoryPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TrendHistoryPage(config: widget, initialShowCost: _showCost),
      ),
    );
  }

  void _showForecastInfo() {
    final seasonal = widget.usesSeasonalCurve;
    final touNote = widget.showStackedFor(_showCost);
    final method = seasonal
        ? 'แท่งประคือยอดคาดการณ์ 3 เดือนข้างหน้า ใช้วิธีเดียวกับส่วน "รอบถัดไป" '
            'ในการ์ดคาดการณ์ คือปรับค่าเฉลี่ยล่าสุดของคุณตามรูปแบบฤดูกาลของแต่ละเดือน\n\n'
            'ยิ่งคาดการณ์ไกลจากปัจจุบัน ความไม่แน่นอนยิ่งสูงขึ้น แต่จะแม่นกว่าการไม่ปรับตามฤดูกาลเลย'
        : 'แท่งประคือยอดคาดการณ์ 3 เดือนข้างหน้า ลากต่อจากเส้นแนวโน้มของยอดย้อนหลัง\n\n'
            'ยิ่งคาดการณ์ไกลจากปัจจุบัน ความไม่แน่นอนยิ่งสูงขึ้น เหมาะสำหรับดูแนวโน้มคร่าวๆ';
    const currentCycleNote = 'แท่งของบิลรอบที่กำลังใช้อยู่ ใช้ตัวเลขเดียวกับส่วน "รอบนี้" '
        'ในการ์ดคาดการณ์ (คำนวณจากบันทึกมิเตอร์จริงของรอบนี้) เมื่อบันทึกมิเตอร์ในรอบนี้แล้ว';
    const touText = 'แท่งประเป็นยอดรวมทั้งเดือน ไม่แยก On-Peak/Off-Peak '
        'เพราะรูปแบบฤดูกาลสร้างจากยอดหน่วยไฟรวม ยังไม่มีข้อมูลแยกรายช่วงเวลา';
    showInfoDialog(
      context,
      title: 'กราฟนี้อ่านอย่างไร?',
      message: [method, currentCycleNote, if (touNote) touText].join('\n\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBills = widget.bills;
    final canExpand = allBills.length > _cardMonths;
    final bills = canExpand ? allBills.sublist(allBills.length - _cardMonths) : allBills;

    // กราฟโชว์เมื่อมีบิล >= 2 เดือน — ส่วนคาดการณ์ต่อท้ายตามนั้น
    final hasChart = bills.length >= 2;
    final forecasts = !hasChart ? const <double>[] : (_showCost ? widget.costForecast : widget.usedForecast);
    final forecastLabels = <String>[
      for (var i = 0; i < forecasts.length; i++)
        () {
          final d = DateTime(bills.last.year, bills.last.month + i + 1, 1);
          return _trendMonthLabel(d.year, d.month);
        }(),
    ];

    final emptyMessage =
        _showCost ? _emptyMessage(widget.title) : _emptyMessage('${widget.unitLabel}ที่ใช้${widget.title}');
    final legend = hasChart ? widget.legendItems(_showCost, bills, withForecast: forecasts.isNotEmpty) : <Widget>[];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.v16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: Icons.bar_chart_rounded, color: widget.accentColor, size: 34),
              const SizedBox(width: AppSpacing.v10),
              Expanded(
                child: Text('ประวัติและแนวโน้ม${widget.title}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: AppTypography.s15, color: AppColors.textDark)),
              ),
              if (forecasts.isNotEmpty) _InfoButton(onTap: _showForecastInfo),
            ],
          ),
          const SizedBox(height: AppSpacing.v12),
          _ModeToggle(
            accent: widget.accentColor,
            unitLabel: widget.unitLabel,
            showCost: _showCost,
            onChanged: (v) => setState(() => _showCost = v),
          ),
          const SizedBox(height: AppSpacing.v16),
          SizedBox(
            height: 190,
            child: !hasChart
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: BarChart(
                            BarChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              barTouchData: BarTouchData(enabled: false),
                              maxY: 8,
                              barGroups: List.generate(6, (i) {
                                const demo = [3.0, 5.0, 3.5, 6.0, 4.5, 6.5];
                                return BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: demo[i],
                                    color: Colors.grey.shade200,
                                    width: 18,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.v6)),
                                  ),
                                ]);
                              }),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v16, vertical: AppSpacing.v10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(AppSpacing.v10),
                          ),
                          child: Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: AppTypography.s12_5, height: 1.5, color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    ],
                  )
                : widget.buildBars(
                    slots: bills,
                    labels: [for (final b in bills) _trendMonthLabel(b.year, b.month)],
                    showCost: _showCost,
                    // 6 + 3 = 9 แท่งในการ์ดแคบ ลดความกว้างแท่งเมื่อมีส่วนคาดการณ์
                    barWidth: forecasts.isEmpty ? 24 : 18,
                    forecasts: forecasts,
                    forecastLabels: forecastLabels,
                  ),
          ),
          if (legend.isNotEmpty || canExpand) ...[
            const SizedBox(height: AppSpacing.v12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(spacing: AppSpacing.v12, runSpacing: AppSpacing.v6, children: legend),
                ),
                if (canExpand)
                  TextButton(
                    onPressed: _openHistoryPage,
                    style: TextButton.styleFrom(
                      foregroundColor: widget.accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.v6),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontFamily: AppTheme.fontFamily, fontSize: AppTypography.s12_5, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('ดูทั้งหมด'),
                  ),
              ],
            ),
          ],
          if (forecasts.isNotEmpty && widget.forecastLowConfidence) ...[
            const SizedBox(height: AppSpacing.v10),
            Text(
              'ประมาณการเบื้องต้น (มีบิล ${widget.bills.length} เดือน) ยิ่งเดือนไกลยิ่งไม่แน่นอน',
              style: const TextStyle(fontSize: AppTypography.s11_5, color: AppColors.warningText),
            ),
          ],
        ],
      ),
    );
  }
}
